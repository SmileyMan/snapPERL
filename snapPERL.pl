#!/usr/bin/perl
#############################################################################################
#
# Snapraid helper script written in PERL. Enables automation using cron for your Array Syncs
#
# Please see README.md
#
#############################################################################################

#############################################################################################
# Created by Steve Miles (SmileyMan). https://github.com/SmileyMan
#
# Why PERL. Perl is cleaner. More powerfull and I can use HASH'es. Been over 10 years since
# I worked with PERL and now remember why I loved it. Did not get on with BASH syntax!
#
#############################################################################################

package snapPERL;

# Pragmas
use 5.010;
use strict;
use warnings;

# Modules
use Carp;            # To replace die calls.. Not yet implemented
use Module::Load;    # Perl core module for on demand loading of optional modules
use File::Spec;      # Used to read absolute path

our $VERSION = 0.2.0;

############################## Script only from here ########################################

# Get script absolute location
my $absLocation = File::Spec->rel2abs(__FILE__);
my ( $scriptPath, $ScriptName ) = $absLocation =~ m/(.+[\/\\])(.+)$/;

# Define options file
my $optionsFile = $scriptPath . 'snapPERL.conf';

# Defind custom commands file
my $customCmdsFile = $scriptPath . 'custom-cmds';

# Define Script Varibles
my $hostname = qx{hostname};

# Remove vertical whitespace from hostname (Email issue)
chop $hostname;

my ( $scriptLog, $scrubNew, $scrubOld, $syncSuccess, $snapVersion );
my ( %diffHash, %opt, %conf, %customCmds );
my $minLogLevel = 5;

#-------- Script Start --------#

# Build options hash
get_opt_hash();

logit( 'Script Started', 3 );

# using optional feature 'custom commands'?
if ( $opt{useCustomCmds} ) {

    # Load from file 'custom-cmds'
    load_custom_cmds();

    # Run pre commands
    custom_cmds('pre');
}

# Parse snapraid conf file
parse_conf();

# Get current state.
snap_status();
snap_diff();

# Sync needed?
if ( $diffHash{sync} ) {

    # Check set limits
    if ( $diffHash{removed} <= $opt{deletedFiles} && $diffHash{updated} <= $opt{changedFiles} ) {
        logit( "There are differnces. Sync running", 3 );
        snap_sync();
    }
    else {
        logit( 'Warning: Deleted or Changed files exceed limits set. Sync not completed', 2 );
    }
}
else {
    logit( 'No differnces. Sync not needed', 3 );
}

# Scrub needed? If sync is run daily with 'scrub -p new' $scrubNew will allways be 0.
# So second check on oldest scrubbed block is made and scrub called if needed.
if ( $scrubNew >= $opt{scrubDays} or $scrubOld >= $opt{scrubOldest} ) {

    # Do not scrub un sync'ed array!
    if ($syncSuccess) {
        logit( "Running scrub - Days since last scrub:- $scrubNew - Oldest scrubbed block:- $scrubOld", 3 );
        snap_scrub( "-p $opt{scrubPercentage}", "-o $opt{scrubAge}" );
    }
    else {
        logit( 'Sync was not run. Scrub only performed after successful sync.', 3 );
    }
}
else {
    logit( "No Scrub needed - Days since last scrub:- $scrubNew - Oldest scrubbed block:- $scrubOld", 3 );
}

# Create symbolic link pool
if ( $opt{pool} ) { snap_pool(); }

# Log smart details?
if ( $opt{smartLog} ) { snap_smart(); }

# Spindown?
if ( $opt{spinDown} ) { snap_spindown(); }

if ( $opt{useCustomCmds} ) {

    # Run post commands
    custom_cmds('post');
}

logit( 'Script Completed', 3 );

# Add debug information to log
if ( $opt{logLevel} >= 5 ) { debug_log(); }

# Log/Email cleanup.
script_comp();

#-------- Script End --------#

#-------- Subroutines --------#

##
# sub snap_status()
# Calls snapraid status and does a few checks. Sets days since last scrub. Corrects sub second timestamps when detected.
# usage snap_status();
sub snap_status {

    # Get snapraid version
    my ( $output, $exitCode ) = snap_run('snapraid --version');
    ($snapVersion) = $output =~ m/snapraid\s+v(\d+.\d+)/;

    # Run snapraid status
    ( $output, $exitCode ) = snap_run('status');

    # Critical error. Status shows errors detected.
    if ( $output !~ m/No\s+error\s+detected/ ) { error_die("Critical error: Status shows errors detected"); }

    # Critical error. Sync currently in progress.
    if ( $output !~ m/No\s+sync\s+is\s+in\s+progress/ ) { error_die("Critical error: Sync currently in progress"); }

    # Check for zero sub-second timestamps and correct.
    if ( $output =~ m/You have\s+(\d+)\s+files/ ) {

        # Grab match so I don't clobber it later with new code
        my $timeStamps = $1;

        # Reset enabled in config and snapraid supports?
        if ( $opt{resetTimeStamps} && $snapVersion >= 10.0 ) {

            # Run snapraid touch
            my ( $touch, $exitCode ) = snap_run('touch');
            foreach ( split /\n/, $touch ) {

                # Log files where time stamps where changed.
                if (m/touch/) {

                    # Remove word 'touch' before logging
                    s/touch\s//;
                    logit( "Zero sub-second timestamp reset on :- $_", 4 );
                }
            }
            logit( "$timeStamps files with zero sub-second timestamps, Snapraid touch command was run", 3 );
        }
        else {
            logit( "$timeStamps files with zero sub-second timestamps, No action taken", 3 );
        }
    }
    else {
        logit( 'No zero sub-second timestamps detected', 3 );
    }

    # Get number of days since last scrub
    ($scrubNew) = $output =~ m/the\s+newest\s+(\d+)./;

    # Get the age of the oldest scrubbed block (Used when $opt{useScrubNew} in effect)
    ($scrubOld) = $output =~ m/scrubbed\s+(\d+)\s+days\s+ago/;

    return 1;
}

##
# sub snap_diff();
# Runs diff command and scrapes values into a hash and sets 'sync' value to true if differences detected.
# usage snap_diff();
sub snap_diff {

    # Lexicals
    my ( $diffLogTxt, $missingValues );

    # Run snapraid diff
    my ( $output, $exitCode ) = snap_run('diff');

    # Assign values to hash
    ( $diffHash{equal} )    = $output =~ m/(\d+)\s+equal/;
    ( $diffHash{added} )    = $output =~ m/(\d+)\s+added/;
    ( $diffHash{removed} )  = $output =~ m/(\d+)\s+removed/;
    ( $diffHash{updated} )  = $output =~ m/(\d+)\s+updated/;
    ( $diffHash{moved} )    = $output =~ m/(\d+)\s+moved/;
    ( $diffHash{copied} )   = $output =~ m/(\d+)\s+copied/;
    ( $diffHash{restored} ) = $output =~ m/(\d+)\s+restored/;

    # If any of the diff values missing stop script.
    foreach my $diffKey (qw( equal added removed updated moved copied restored )) {
        if ( !defined $diffHash{$diffKey} ) {
            logit( "Warning: Missing value \'$diffKey\' during diff command!", 2 );
            $missingValues = 1;
        }
    }

    # Missing values?
    if ($missingValues) { error_die('Critical error: Values missing from snapraid diff.'); }

    # Sync needed?
    $diffHash{sync} = $output =~ m/There\s+are\s+differences/ ? 1 : 0;

    # Log diff output
    foreach my $key ( sort( keys %diffHash ) ) {
        $diffLogTxt .= "-> " . $key . ' = ' . $diffHash{$key} . " ";
    }
    logit( $diffLogTxt, 3 );

    return 1;
}

##
# sub snap_sync
# Runs a sync command and logs details
# usage snap_sync();
sub snap_sync {

    # Lexicals
    my $excludedCount = 0;
    my ( $dataProcessed, $fullLog );

    # Run snapraid sync command
    my ( $output, $exitCode ) = snap_run('sync');

    # Process output
    foreach ( split /\n/, $output ) {

        # Match for excluded files
        if (m/Excluding\s+file/) {
            $excludedCount++;
        }
        else {
            $fullLog .= $_ . "\n";
        }

        # Get size of data processed
        if (m/completed/) { ($dataProcessed) = $output =~ m/completed,\s+(\d+)\s+MB processed/; }

        # Was it a success?
        if (m/Everything\s+OK/) { $syncSuccess = 1; }

    }

    if ($syncSuccess) {

        # Log details from sync.
        logit( "Snapraid sync completed: $dataProcessed MB processed and $excludedCount files excluded", 3 );
    }
    else {
        # Stop script.
        error_die("Critical error: Sync failed! \n$fullLog");    # todo
    }

    # New in snapraid. Verify new data from sync.
    if ( $opt{useScrubNew} ) {

        # Check its a compatible version of snapraid.
        if ( $snapVersion >= 9.0 ) {
            logit( 'ScrubNew option set. Scrubing lastest sync data', 3 );
            snap_scrub('-p new');
        }
        else {
            logit( 'Warning: ScrubNew is set but snapraid version must be 9.0 or higher!', 2 );
        }
    }
    return 1;
}

##
# sub snap_scrub
# Perform a scrub on array
# usage snap_scrub('Plan to use staring with -p', 'Min age to scrub starting with -o');
sub snap_scrub {

    # Grab first to elements of passed array.
    my $plan = shift;
    my $age  = shift // '';
    my ( $dataProcessed, $success );

    my ( $output, $exitCode ) = snap_run( $plan, $age, 'scrub' );

    #Get size of data processed
    if ( $output =~ m/completed/ ) { ($dataProcessed) = $output =~ m/completed,\s+(\d+)\s+MB processed/; }

    # Was it a success?
    if ( $output =~ m/Everything\s+OK/ ) { $success = 1; }

    if ($success) {

        # Log details from scrub.
        logit( "Snapraid scrub completed: $dataProcessed MB processed", 3 );
    }
    else {
        # Stop script.
        error_die("Critical error: Scrub failed!\n$output");    # todo
    }
    return 1;
}

##
# sub snap_smart
# Log smart details and warn if requited
# usage snap_smart();
sub snap_smart {

    # Run snapraid smart
    my ( $output, $exitCode ) = snap_run('smart');

    # Process Output
    foreach ( split /\n/, $output ) {

        # Match snapraid log for disk info
        # Todo: Not happy with this. Works fine but messy and unreadble... To re-visit
        if (m/\s+\d+\s+\d+\s+\d+\s+\d+%\s+\d\.\d\s+[A-Za-z0-9-]+\s+[\/a-z]+\s+\w+/) {

            # Get params
            my ( $temp, $days, $error, $fp, $size, $serial, $device, $disk ) = m/\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(\d\.\d)\s+([A-Za-z0-9-]+)\s+([\/a-z]+)\s+(\w+)/;
            $fp = sprintf( "%02d", $fp );
            logit( "Device: $device     Temp: $temp     Error Count: $error     Fail Percentage: $fp%     Power on days: $days", 3 );

            # Warn if needed
            if ( $fp > $opt{smartDiskWarn} ) { logit( "Warning: Fail percentage for $serial has exceded warning level", 2 ); }

        }
        elsif (m/next\s+year\s+is/) {

            # Get FP for array
            my ($arrayFail) = m/next\s+year\s+is\s+(\d+)%/;
            logit( "Calculated chance of at least one drive failing in the next year is $arrayFail%", 3 );

            # Warn if needed
            if ( $arrayFail > $opt{smartWarn} ) { logit( 'Warning: Chance of disk in array failing within the next year has exceded warning level', 2 ); }

        }
    }
    return 1;
}

##
# sub snap_spindown
# Spin down disks (Plan to add options for selecting which disks to spin down)
# usage snap_spindown();
sub snap_spindown {

    # Run snapraid down
    my ( $output, $exitCode ) = snap_run('down');

    #Log output
    foreach my $disk ( split /\n/, $output ) {
        logit( $disk, 4 );
    }

    logit( 'Array spundown', 3 );

    return 1;
}

##
# sub snap_pool
# Creat pool if valid config option exists
# usage snap_pool();
sub snap_pool {

    # Check for pool entry in snapraid config
    if ( $conf{pool} ) {

        # Run snapraid pool command
        my ( $output, $exitCode ) = snap_run('pool');

        # Get number of links created
        my ($links) = $output =~ m/(\d+)\s+links/;
        logit( "Pool command run and $links links created in $conf{pool}", 3 );
    }
    return 1;
}

##
# sub snap_run
# Run a snapraid command
# usage snap_run(command);
# returns stdout, exitcode
sub snap_run {

    # Get passed args
    my @cmdArgs    = @_;
    my $stderrFile = "$opt{snapRaidTmpLocation}/snapPERLcmd-stderr.tmp";
    my $stdoutFile = "$opt{snapRaidTmpLocation}/snapPERLcmd-stdout.tmp";

    # Build command
    my $snapCmd = "$opt{snapRaidBin} -c $opt{snapRaidConf} -v @cmdArgs 1\>$stdoutFile 2\>$stderrFile";

    # Log command to be run
    logit( "Running: $snapCmd", 4 );

    # Run command
    my $exitCode = system($snapCmd);

    #my $cmdStderr = slurp_file($stderrFile);
    my $cmdStdout = slurp_file($stdoutFile);

    # Get file size of stderr file
    my @stderrStat = stat $stderrFile;

    # stderr file is NOT empty indicating snapraid wrote to stderr
    # abort script and request user to investigate
    if ( $stderrStat[7] > 0 ) {
        logit( "Critical error. stderr file size: (stat $stderrStat[7] -- Exit code: $exitCode", 1 );
        error_die("Critical error: Snapraid reports errors. Please check snapraid stderr file:- $opt{snapRaidTmpLocation}/snapPERLcmd-stderr.tmp");
    }

    # Pass stdout / exitcode back to caller
    else {
        return ( $cmdStdout, $exitCode );
    }

    return 1;
}

##
# sub parse_conf
# Parse the snapraid conf file into a 2 dimension hash->hash/array
# usage parse_conf();
sub parse_conf {

    # Define local slurp scalar
    my $confData;

    # Slurp the conf file :P
    $confData = slurp_file( $opt{snapRaidConf} );

    # Process slurped conf file.
    foreach ( split /\n/, $confData ) {
        
        # Remove leading whitespace
        s/^\s+//g;
        
        # If not commented out or empty line
        if ( !m/^#/ && m/^\w+/ ) {
            my ( $key, $value ) = split /\s/, $_, 2;

            # Stop uninitialized warnings if there is no whitespace after key only option https://github.com/SmileyMan/snapPERL/issues/1
            if ( !defined $value ) { $value = ''; }
            $key   =~ s/^\s+|\s+$//g;    # Remove leading and trailing whitespace
            $value =~ s/^\s+|\s+$//g;    # Remove leading and trailing whitespace
            
            # Process extra parity
            if ( $key =~ m/\d-parity/ ) { $conf{xparity}->[ $#{ $conf{xparity} } + 1 ] = $value; }

            # Process other options and add to hash-array
            elsif ( $key =~ m/content|exclude|share|smartctl/ ) { $conf{$key}->[ $#{ $conf{$key} } + 1 ] = $value; }

            # Process data disks
            elsif ( $key =~ m/disk|data/ ) {
                my ( $drive, $path ) = split /\s/, $value, 2;
                $drive =~ s/^\s+|\s+$//g;    # Remove leading and trailing whitespace
                $path  =~ s/^\s+|\s+$//g;    # Remove leading and trailing whitespace
                $conf{$key}->{$drive} = $path;
            }

            # Values left are singular. Add to hash
            else {
                if ( $value =~ /\w+/ ) {
                    $conf{$key} = $value;
                }

                # Has no value so assign boolean
                else {
                    $conf{$key} = 1;
                }
            }
        }
    }
    return 1;
}

##
# sub get_opt_hash
# Build option hash from $options at start of script;
# usage get_opt_hash();
sub get_opt_hash {

    my $options;

    # Slurp the options file :P
    $options = slurp_file($optionsFile);

    # Cycle though options and build hash
    foreach ( split /\n/, $options ) {

        # Ignore lines without options in them
        if (m/=/) {
            
            # Lexicals
            my ( $key, $value, $comment, $valueC );

            # Split keys
            ( $key, $valueC ) = split /=/;

            # Don't add commented out keys
            if ( $key !~ /#/ ) {

                # Split Values
                if ( $valueC =~ m/#/ ) {
                    ( $value, $comment ) = split /#/, $valueC;
                }
                else {
                    $value = $valueC;
                }

                # Clean up keys/values
                $key   =~ s/^\s+|\s+$//g;
                $value =~ s/^\s+|\s+$//g;

                #Add key,value pairs
                $opt{$key} = $value;
            }
        }
    }
    return 1;
}

##
# sub script_comp
# Called at end of script. Basic clean up tasks.
# usage script_comp();
sub script_comp {

    # Send email if enabled
    if ( $opt{emailSend} ) { email_send(); }

    # Write log to location in $opt{logFile}
    if ( $opt{logFile} ) { write_log(); }

    return 1;
}

##
# sub email_send
# Send the scriptLog out via email;
# usage email_send();
sub email_send {

    my $subjectAlert;

    # Add alert to subject line if warnings or errors encountered.
    if ( $minLogLevel < 3 ) {
        $subjectAlert = $minLogLevel < 2 ? 'Critical' : 'Warning';
    }
    else {
        $subjectAlert = '';
    }

    # Use gmail SMTP to send the email.. System I use.
    if ( $opt{useGmail} ) {

        # Load on demand need modules for Gmail send
        autoload Email::Send;
        autoload Email::Send::Gmail;
        autoload Email::Simple::Creator;

        # Create gmail email
        my $email = Email::Simple->create(
            header => [
                From    => $opt{emailSendAddress},
                To      => $opt{emailAddress},
                Subject => "$subjectAlert \[$hostname\] - snapPERL Log. Please see message body",
            ],
            body => $scriptLog,
        );

        # Account details for gmail
        my $sender = Email::Send->new(
            {
                mailer      => 'Gmail',
                mailer_args => [
                    username => $opt{emailAddress},
                    password => $opt{gmailPass},
                ]
            }
        );

        # Send using gmail SMTP
        eval { $sender->send($email) };
        if ($@) { logit("Warning: Gmail SMTP email send failed... $@"); }

    }
    else {

        # Load on demand needed modules for Email send
        autoload MIME::Lite;

        # Send email via localy configured sendmail server.
        my $msg = MIME::Lite->new(
            From    => $opt{emailSendAddress},
            To      => $opt{emailAddress},
            Subject => "\[$hostname\] - snapPERL Log. Please see message body",
            Data    => $scriptLog,
        );

        # Send.
        if ( $opt{emailUseSmtp} ) {
            $msg->send( 'smtp', $opt{emailSmtpAddress}, Timeout => 60 );
        }
        else {
            $msg->send;
        }
    }
    return 1;
}

##
# sub load_custom_cmds();
# Loads custom commands from file into hash/array
# usage load_custom_cmds());
sub load_custom_cmds {

    my $customCmdsIn;

    # Slurp the custom commands file :P
    $customCmdsIn = slurp_file($customCmdsFile);

    foreach my $line ( split /\n/, $customCmdsIn ) {

        # Remove any leading whitespace
        $line =~ s/^\s+//g;

        #Ignore comments and empty lines
        if ( $line !~ m/^#/ && $line =~ m/=/ ) {

            #Split on '='
            my ( $type, $cmd ) = split /=/, $line;

            # Ignore lines without pre or post commands
            if ( $type =~ m/pre|post/ ) {

                # Add to Hash/Array
                $customCmds{$type}->[ $#{ $customCmds{$type} } + 1 ] = $cmd;
            }
        }
    }
    return 1;
}

##
# sub custom_cmds();
# Runs custom pre and post commands defined in custom-cmds file.
# usage custom_cmds('pre|post');
sub custom_cmds {

    # Get type of operation
    my $type = shift;

    # Check it's valid
    if ( $type !~ m/pre|post/ ) {
        logit( "Warning: Custom commands called with incorrect option", 2 );
        return;
    }

    # Prevent working on undefined hash if no commands loaded
    if ( defined $customCmds{$type} ) {

        # For each array element in hash
        for ( my $i = 0 ; $i <= $#{ $customCmds{$type} } ; $i++ ) {

            # Run command
            system( $customCmds{$type}->[$i] );
        }
    }
    return 1;
}

##
# sub slurp_file();
# Slurp the contents of a file and return a scalar
# usage $contents = slurp_file(filename);
sub slurp_file {

    # Get file to slurp
    my $file = shift;

    # mmm Slurp
    my $slushPuppie;

    # File exists?
    if ( -e $file ) {
        open my $fh, '<', $file or error_die("Critical error: Unable to open $file.");
        local $/ = undef;        # Don't clobber global version. Normaly holds 'newline' and reads one line at a time
        $slushPuppie = <$fh>;    # My favorite slurp
        close $fh;               # Will auto close once once out of scope regardless
    }
    else {
        # File don't exist - Send to log @ debug level
        logit( "Warning: call to slurp_file() with none existing file: $file", 5 );
    }

    # Return the Slurpie
    return $slushPuppie;
}

##
# sub time_stamp();
# Create a timestamp for the log.
# usage $stamp = time_stamp();
sub time_stamp {

    # Define month names
    my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

    # Define day names
    my @days = qw( Sun Mon Tue Wed Thu Fri Sat Sun );

    # Get current time
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();

    # Convert to full 4 digit year
    my $fullYear = $year + 1900;

    # Return formated timestamp
    return sprintf( "%02d:%02d:%02d - %s %d %s %d", $hour, $min, $sec, $days[$wday], $mday, $months[$mon], $fullYear );

}

##
# sub logit()
# Create a log.
# usage logit('Text', Level);
sub logit {

    # Get text and loglevel
    my ( $logText, $logLevel ) = @_;

    # Varible holds lowest log level reached. 1 for Critical, 2 for Warning and 3 for Normal
    $minLogLevel = $logLevel < $minLogLevel ? $logLevel : $minLogLevel;

    # Get current timestamp
    my $timeStamp = time_stamp();

    # (1=Critical, 2=Warning, 3=Info, 4=Everything, 5=Debug)
    if ( $logLevel <= $opt{logLevel} or $logLevel == 1 ) {
        if ( $opt{logStdout} == 1 ) {

            # Send to stdout
            say( $timeStamp . " : " . $logText );
        }

        # Add to log string
        $scriptLog .= $timeStamp . " : " . $logText . "\n";

    }
    return 1;
}

##
# sub write_log();
# Write the logfile to disk or stdout.
# usage write_log();
sub write_log {

    # Write log to file
    # Todo: Try and Catch instead of killing script
    open my $fh, '>', $opt{logFile} or die("Critical error: Unable to open logfile file. Please check config");
    say {$fh} $scriptLog;
    close $fh;

    return 1;
}

##
# sub debug_log
# Called if logLevel set to 5 (Debug).
# Cycles over multi dimension hash created from config file.
# usage debug_log();
sub debug_log {

    # May just use Data::Dumper for this

    # Debug -> Log Options!
    logit( '-------- Options --------', 5 );
    foreach ( sort( keys %opt ) ) {
        logit( "Option :: $_ -> $opt{$_}", 5 );
    }
    logit( '-------- Options End --------', 5 );

    # Debug -> Log Config!
    logit( '-------- Config --------', 5 );
    foreach my $confKey ( sort( keys %conf ) ) {
        if ( ref( $conf{$confKey} ) eq "HASH" ) {
            foreach my $diskKey ( keys %{ $conf{$confKey} } ) {
                logit( "Config : $confKey -> $diskKey -> $conf{$confKey}->{$diskKey}", 5 );
            }
        }
        elsif ( ref( $conf{$confKey} ) eq "ARRAY" ) {
            for ( my $i = 0 ; $i <= $#{ $conf{$confKey} } ; $i++ ) {
                logit( "Config : $confKey -> $i -> $conf{$confKey}->[$i]", 5 );
            }
        }
        else {
            logit( "Config : $confKey -> $conf{$confKey}", 5 );
        }
    }
    logit( '-------- Config End--------', 5 );

    return 1;
}

##
# sub error_die()
# Wrapper for PERL die command.
# usage error_die("Error Text");
sub error_die {

    # Get message (list context gets first item in array only)
    my ($message) = @_;

    # Log error message
    logit( $message, 1 );

    # Cleanup
    script_comp();

    # Kill script
    die;    # Wipe yourself off. You're dead.

}

#-------- Subroutines End --------#

# Return true at end of script
1;

__END__

