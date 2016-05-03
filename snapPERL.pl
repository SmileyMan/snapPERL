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
# Based on a bash script http://zackreed.me/articles/83-updated-snapraid-sync-script by 
# Zack Read (http://zackreed.me) - Extended and converted to PERL
#
# Why PERL. Perl is cleaner. More powerfull and I can use HASH'es. Been over 10 years since
# I worked with PERL and now remember why I loved it. Did not get on with BASH syntax!
#
# CHANGELOG
# ---------
# 01/05/2016 Uploaded to Git-Hub. Working script with logfile. No messages/emails or alerts yet.
#
#############################################################################################

package snapRAID;

# Pragmas 
use 5.010;
use strict;
use warnings;

# Modules
use MIME::Lite;
use Email::Send;
use Email::Send::Gmail;
use Email::Simple::Creator;

############################## Define User Variables ########################################

# todo: remove and load from external file
# Sub is called to build option hash. Makes it more readable (1. Only use = when entering options for hash) (2. Every option should be followed with a comment)
my $options = q{
  
  ## Email Options
  emailSend=0                                                   #Send email?
  emailAddress=#########@#######.com                            #Email address
  useGmail=1                                                    #Use Gmail to send mail
  gmailPass="****************"                                  #Gmail password to use... Recomend using app passwords on 2 factor auth -> https://security.google.com/settings/security/apppasswords
                                                                #If not please please please chmod 600 to root on config file.. PLEASE!
  
  ## Pushover Options
  pushOverSend=0                                                #Send pushover alerts?
  pushOverKey=################################                  #Pushover user key
  pushOverToken=##############################                  #Pushover app token
  pushOverUrl=https://api.pushover.net/1/messages.json          #Pushover url to send messages
  
  ## Sync and Scrub options
  deletedFiles=50                                               #Max amount of deleted files to auto sync
  changedFiles=500                                              #Max amount of changed files to auto sync
  scrubDays=7                                                   #Number of days before scrub is run 
  scrubOldest=30                                                #Max oldest block before scrub is run if using 'new' plan on sync (v9.0 on)
  scrubAge=10                                                   #Data older than days
  scrubPercentage=8                                             #Percentage of array to scrub
  useScrubNew=1                                                 #Scrub new data from sync and verify. (Supported in latest versions of snapraid).
  
  ## Smart options
  smartLog=1                                                    #Check and log Smart data. 
  smartWarn=70                                                  #Chance of fail percentage (whole array) to send warnings
  smartDiskWarn=50                                              #Chance of fail percentage (disk) to send warnings
  
  ## Snapraid options
  snapRaidConf=/etc/snapraid.conf                               #Location of snapraid conf file
  
  ## Binary locations
  snapRaidBin=/usr/local/bin/snapraid                           #Snapriad binary location
  mailBin=/usr/bin/mutt                                         #Email binary location
  curlBin=/usr/bin/curl                                         #Curl binary location
  ## Other Options
  spinDown=0                                                    #Spindown array once script completed?
  pool=0                                                        #Run pool command if valid config option found?
  logFile=/tmp/script-snapRAID.log                              #Logfile location
  logLevel=4                                                    #Level of logging (1=Critical, 2=Warning, 3=Info, 4=Everything, 5=Debug)
  logStdout=1                                                   #If set to 1 sends log file to stdout (Not very useful when run via cron :P).
};

############################## Script only from here ########################################

# Define Script Varibles
my $hostname = qx/hostname/;
my ($scriptLog, $scrubNew, $scrubOld, $syncSuccess, $snapVersion);
my (%diffHash, %opt, %conf);

#-------- Script Start --------#

# Build options hash
get_opt_hash();

logit('Script Started', 3);

# Parse snapraid conf file
parse_conf();

# Get current state.
snap_status();
snap_diff();

# Sync needed?
if ( $diffHash{sync} ) {
  # Check set limits
  if ( $diffHash{removed} <= $opt{deletedFiles} && $diffHash{updated} <= $opt{changedFiles} ) {
    logit("There are differnces. Sync running", 3);
    snap_sync();
  } 
  else {
    logit('Warning: Deleted or Changed files exceed limits set. Sync not completed', 2)
  }
} 
else {
  logit('No differnces. Sync not needed', 3);
}

# Scrub needed? If sync is run daily with 'scrub -p new' $scrubNew will allways be 0.
# So second check on oldest scrubbed block is made and scrub called if needed.
if ( $scrubNew >= $opt{scrubDays} or $scrubOld >= $opt{scrubOldest} ) {
  # Do not scrub un sync'ed array!
  if ( $syncSuccess ) {
    logit("Running scrub - Days since last scrub:- $scrubNew - Oldest scrubbed block:- $scrubOld", 3);
    snap_scrub("-p $opt{scrubPercentage}", "-o $opt{scrubAge}");
  } 
  else {
    logit('Sync was not run. Scrub only performed after successful sync.', 3)
  }
} 
else {
  logit("No Scrub needed - Days since last scrub:- $scrubNew - Oldest scrubbed block:- $scrubOld", 3);
}

# Create symbolic link pool
if ( $opt{pool} ) { snap_pool(); } 

# Log smart details?
if ( $opt{smartLog} ) { snap_smart(); }

# Spindown?
if ( $opt{spinDown} ) { snap_spindown(); }

logit('Script Completed', 3);

# Add debug information to log.
if ( $opt{logLevel} >= 5 ) { debug_log(); }

write_log();

#-------- Script End --------#


#-------- Subroutines --------#

##
# sub snap_diff();
# Runs diff command and scrapes values into a hash and sets 'sync' value to true if differences detected.
# usage snap_diff();
sub snap_diff {
  
  # Define local variables
  my ($diffLogTxt, $missingValues);
  
  # Run snapraid diff
  my $output = snap_run('diff');
  
  # Assign values to hash
  ($diffHash{equal})    = $output =~ m/(\d+)\s+equal/;
  ($diffHash{added})    = $output =~ m/(\d+)\s+added/;
  ($diffHash{removed})  = $output =~ m/(\d+)\s+removed/;
  ($diffHash{updated})  = $output =~ m/(\d+)\s+updated/;
  ($diffHash{moved})    = $output =~ m/(\d+)\s+moved/;
  ($diffHash{copied})   = $output =~ m/(\d+)\s+copied/;
  ($diffHash{restored}) = $output =~ m/(\d+)\s+restored/;
  
  # If any of the diff values missing stop script.
  foreach my $diffKey (qw( equal added removed updated moved copied restored )) {
    if ( !defined $diffHash{$diffKey} ) {
      logit("Warning: Missing value \'$diffKey\' during diff command!", 2);
      $missingValues = 1;
    }
  }
  
  if ( $missingValues ) { error_die('Critical error: Values missing from snapraid diff.'); }
  
  # Sync needed?
  $diffHash{sync} = $output =~ m/There\s+are\s+differences/ ? 1 : 0;
  
  # Log diff output
  foreach my $key ( sort(keys %diffHash) ) {
    $diffLogTxt .= "-> " . $key . ' = ' . $diffHash{$key} . " ";
  }
  logit($diffLogTxt, 3);

  return 1;
}

##
# sub snap_status()
# Calls snapraid status and does a few checks. Sets days since last scrub. Corrects sub second timestamps when detected.
# usage snap_status();
sub snap_status {
  
  # Run snapraid status
  my $output = snap_run('status');
  
  # Critical error. Status shows errors detected.
  if ( $output !~ m/No\s+error\s+detected/ ) { error_die("Critical error: Status shows errors detected"); };
  
  # Critical error. Sync currently in progress.
  if ( $output !~ m/No\s+sync\s+is\s+in\s+progress/ ) { error_die("Critical error: Sync currently in progress"); };
  
  # Check for sub-second timestamps and correct.
  if ( $output =~ m/You have\s+(\d+)\s+files/ ) {
    # Run snapraid touch
    my $touch = snap_run('touch');
    foreach ( split /\n/, $touch ) {
      # Log files where time stamps where changed.
      if ( m/touch/ ) { 
      	# Remove word 'touch' before logging
      	s/touch\s//;
      	logit("Sub-second timestamp reset on :- $_", 4); 
      }
    }
    logit("$1 files with sub-second timestamps, Snapraid touch command was run", 3);
  } 
  else {
    logit('No sub-second timestamps detected', 3);
  };
  
  # Get number of days since last scrub
  ($scrubNew) = $output =~ m/the\s+newest\s+(\d+)./;
  
  # Get the age of the oldest scrubbed block (Used when $opt{useScrubNew} in effect)
  ($scrubOld) = $output =~ m/scrubbed\s+(\d+)\s+days\s+ago/;
  
  # Get snapraid version
  $output = snap_run('snapraid --version');
  ($snapVersion) = $output =~ m/snapraid\s+v(\d+.\d+)/;

  return 1;
}

##
# sub snap_sync
# Runs a sync command and logs details
# usage snap_sync();
sub snap_sync {
  
  my $excludedCount = 0;
  my ($dataProcessed, $fullLog);
  
  # Run snapraid sync command
  my $output = snap_run('sync');
  
  # Process output
  foreach ( split /\n/, $output ) {
    
    # Match for excluded files
    if ( m/Excluding\s+file/ ) { 
      $excludedCount++; 
    } 
    else { 
      $fullLog .= $_ . "\n"; 
    }
    # Get size of data processed
    if ( m/completed/ ) { ($dataProcessed) = $output =~ m/completed,\s+(\d+)\s+MB processed/; }
    
    # Was it a success?
    if ( m/Everything\s+OK/ ) { $syncSuccess = 1; }
  
  }
  
  if ( $syncSuccess ) {
    # Log details from sync. 
    logit("Snapraid sync completed: $dataProcessed MB processed and $excludedCount files excluded", 3);
  } 
  else {
    # Stop script.
    error_die("Critical error: Sync failed! \n$fullLog"); # todo
  }
  
  # New in snapraid. Verify new data from sync.
  if ( $opt{useScrubNew} ) {
    # Check its a compatible version of snapraid.
    if ( $snapVersion >= 9.0 ) {
      logit('ScrubNew option set. Scrubing lastest sync data', 3);
      snap_scrub('-p new');
    } 
    else {
      logit('Warning: ScrubNew is set but snapraid version must be 9.0 or higher!', 2)
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
  my ($dataProcessed, $success);
    
  my $output = snap_run($plan, $age, 'scrub');

  #Get size of data processed
  if ( $output =~ m/completed/ ) { ($dataProcessed) = $output =~ m/completed,\s+(\d+)\s+MB processed/; }
  
  # Was it a success?
  if ( $output =~ m/Everything\s+OK/ ) { $success = 1; }
  
  if ( $success ) {
    # Log details from sync.
    logit("Snapraid sync completed: $dataProcessed MB processed", 3);
  } 
  else {
    # Stop script.
    error_die("Critical error: Scrub failed!\n$output"); # todo
  }
  return 1;
}

##
# sub snap_smart
# Log smart details and warn if requited
# usage snap_smart();
sub snap_smart {
  
  # Run snapraid smart
  my $output = snap_run('smart');
  
  # Process Output
  foreach ( split /\n/, $output ) {
  
    # Match snapraid log for disk info
    # Todo: Not happy with this. Works fine but messy and unreadble... To re-visit
    if ( m/\s+\d+\s+\d+\s+\d+\s+\d+%\s+\d\.\d\s+[A-Za-z0-9-]+\s+[\/a-z]+\s+\w+/ ) {
      
      # Get params
      my ($temp, $days, $error, $fp, $size, $serial, $device, $disk) = m/\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(\d\.\d)\s+([A-Za-z0-9-]+)\s+([\/a-z]+)\s+(\w+)/;
      $fp = sprintf("%02d", $fp);    
      logit("Device: $device     Temp: $temp     Error Count: $error     Fail Percentage: $fp%     Power on days: $days", 3);
      
      # Warn if needed
      if ( $fp > $opt{smartDiskWarn} ) { logit("Warning: Fail percentage for $serial has exceded warning level", 2); } 
    
    } 
    elsif ( m/next\s+year\s+is/ ) {
      
      # Get FP for array
      my ($arrayFail) = m/next\s+year\s+is\s+(\d+)%/;
      logit("Calculated chance of at least one drive failing in the next year is $arrayFail%", 3);
      
      # Warn if needed
      if ( $arrayFail > $opt{smartWarn} ) { logit('Warning: Chance of disk in array failing within the next year has exceded warning level', 2); } 
    
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
  my $output = snap_run('down');
  
  #Log output
  foreach my $disk ( split /\n/, $output ) {
    logit($disk, 4);  
  }
    
  logit('Array spundown', 3);
  
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
    my $output = snap_run('pool');
    
    # Get number of links created
    my ($links) = $output =~ m/(\d+)\s+links/;
    logit("Pool command run and $links links created in $conf{pool}", 3);
  }
  return 1;
}

##
# sub snap_run
# Run a snapraid command
# usage snap_run(options, command);
sub snap_run {

  my $snapCmd = "$opt{snapRaidBin} -c $opt{snapRaidConf} -v @_";
  logit("Running snapraid command: $snapCmd", 4);
  
  # Run command and return output to caller.
  # Todo: Try catch to be implemented...
  return qx/$snapCmd/;

}

##
# sub parse_conf
# Parse the snapraid conf file into a 2 dimension hash->hash/array
# usage parse_conf();
sub parse_conf {
  
  # Define local slurp scalar
  my $confData;
  
  # Slurp the conf file :P
  {
    open my $fh, '<', $opt{snapRaidConf} or error_die("Critical error: Unable to open conf file. Please check config");
    local $/ = undef;   # Don't clober gobal version.
    $confData = <$fh>;
    close $fh;
  }

  # Process slurped conf file.
  foreach ( split /\n/, $confData ) {
    s/^\s+//g;             # Remove leading whitespace
    # If not commented out or empty line
    if ( !m/^#/ && m/^\w+/ ) {
      my ($key, $value) = split /\s/, $_, 2;
      $key   =~ s/^\s+|\s+$//g;   # Remove leading and trailing whitespace
      $value =~ s/^\s+|\s+$//g;   # Remove leading and trailing whitespace
      # Process extra parity
      if ( $key =~ m/\d-parity/ ) { $conf{xparity}->[ $#{$conf{xparity}}+1 ] = $value; }
      # Process other options and add to hash-array
      elsif ( $key =~ m/content|exclude|share|smartctl/ ) { $conf{$key}->[ $#{$conf{$key}}+1 ] = $value; }
      # Process data disks
      elsif ( $key =~ m/disk|data/ ) { 
        my ($drive, $path) = split /\s/, $value, 2;
        $drive =~ s/^\s+|\s+$//g;   # Remove leading and trailing whitespace
        $path  =~ s/^\s+|\s+$//g;   # Remove leading and trailing whitespace
        $conf{$key}->{$drive} = $path;
      }
      # Values left are singular. Add to hash
      else { 
        if ( $value =~ /\w+/ ) {
          $conf{$key} = $value; 
        # Has no value so assign boolen
        } 
        else {
          $conf{$key} = "Yes";
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
  
  # Cycle though options and build hash
  foreach ( split /\n/, $options ) {
    # Ignore lines without options in them
    if ( m/=/ ) {    
      my ($key, $value, $comment, $valueC);
      # Split keys
      ($key, $valueC) = split /=/;
      # Don't add commented out keys
      if ( $key !~ /#/ ) {
        # Split Values
        if ( $valueC =~ m/#/ ) {
          ($value, $comment) = split /#/, $valueC;
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

sub email_send {
	
  if ( $opt{useGmail} ) {
    
    # Great gmail email
    my $email = Email::Simple->create(
      header => [
        From    => $opt{emailAddress},
        To      => $opt{emailAddress},
        Subject => "[$hostname] - snapPERL Log. Please see message body",
      ],
      body => $scriptLog,
    );

    # Account details for gmail
    my $sender = Email::Send->new(
      {   mailer      => 'Gmail',
          mailer_args => [
            username => $opt{emailAddress},
            password => $opt{gmailPass},
          ]
      }
    );
  
    # Send using gmail SMTP
    eval { $sender->send($email) };
    #die "Error sending email: $@" if $@;
  
  }
  else {
 
    # Send email via localy configured email server. 
    my $msg = MIME::Lite->new(
                                From     => $opt{emailAddress},
                                To       => $opt{emailAddress},
                                Subject  => "[$hostname] - snapPERL Log. Please see message body",
                                Data     => $scriptLog,
                              );
    
    # Send.             
    $msg->send;
    
  }
  return 1;
}

##
# sub time_stamp();
# Create a timestamp for the log.
# usage $stamp = time_stamp();
sub time_stamp {
  
  # Define month names
  my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
  # Define day names
  my @days   = qw( Sun Mon Tue Wed Thu Fri Sat Sun );
  # Get current time
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
  # Convert to full 4 digit year
  my $fullYear = $year + 1900;
  # Return formated timestamp
  return sprintf("%02d:%02d:%02d - %s %d %s %d", $hour, $min, $sec, $days[$wday], $mday, $months[$mon], $fullYear);

}

##
# sub logit()
# Create a log.
# usage logit('Text', Level);
sub logit {

  # Get text and loglevel
  my ($logText, $logLevel) = @_;
 
  # Get current timestamp
  my $timeStamp = time_stamp();
  
  # (1=Critical, 2=Warning, 3=Info, 4=Everything, 5=Debug)
  if ( $logLevel <= $opt{logLevel} or $logLevel == 1) {
    if ( $opt{logStdout} == 1 ) {
      # Send to stdout
      say ($timeStamp . " : " . $logText);
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
  
  # Debug -> Log Options!
  logit('-------- Options --------', 5);
  foreach ( sort(keys %opt) ) {
    logit("Option :: $_ -> $opt{$_}", 5);
  }
  logit('-------- Options End --------', 5);
  
  # Debug -> Log Config!
  logit('-------- Config --------', 5);
  foreach my $confKey( sort(keys %conf) ) {
    if ( ref($conf{$confKey}) eq "HASH" ) {
      foreach my $diskKey ( keys %{$conf{$confKey}} ) {
        logit("Config : $confKey -> $diskKey -> $conf{$confKey}->{$diskKey}", 5);
      }
    } 
    elsif ( ref($conf{$confKey}) eq "ARRAY" ) {
      for ( my $i=0; $i <= $#{$conf{$confKey}}; $i++ )  {
        logit("Config : $confKey -> $i -> $conf{$confKey}->[$i]", 5);
      }
    } 
    else {
      logit("Config : $confKey -> $conf{$confKey}", 5);
    }
  }
  logit('-------- Config End--------', 5);
  
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
  logit($message, 1);

  # Write log to file
  write_log();

  # Kill script
  die;          # Wipe yourself off. You're dead.

}

#-------- Subroutines End --------#

# Return true at end of script
1;

__END__

