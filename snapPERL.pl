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
use Carp qw(croak);   # Croak to abort script
use Module::Load;     # Perl core module for on demand loading of optional modules
use File::Spec;       # Used to read absolute path
use LWP::UserAgent;   # Send Post/Get (For messaging support)
use JSON::PP;         # Encode data to JSON for storage

our $VERSION = 0.2.0;

############################## Script only from here ########################################

# Get os name from perl inbuilt varible
my $osName = $^O;
my $slashType;

# Configure for Win32 / Unix bases
if ( $osName eq 'MSWin32' ) {
  $slashType = '\\';
}
else {
  $slashType = '/';
}

# Get script absolute location
my $absLocation = File::Spec->rel2abs(__FILE__);
my ( $scriptPath, $scriptName ) = $absLocation =~ m/(.+[\/\\])(.+)$/;

# Define options file
my $optionsFile = $scriptPath . 'snapPERL.conf';

# Defind custom commands file
my $customCmdsFile = $scriptPath . 'custom-cmds';

# Define package varibles (Lexical to package)
my ( $scriptLog, $scriptMessage );
my ( %diffHash, %opt, %conf, %customCmds );

#-------- Script Start --------#

# Build options hash
get_opt_hash();

logit(  text    => 'Script Started', 
        message => '',
        level   => 3,
      );

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
    logit(  text    => 'There are differences. Sync running', 
            message => 'Sync running',
            level   => 3,
          );
    snap_sync();

  }
  else {
    logit(  text    => 'Warning: Deleted or Changed files exceed limits set. Sync not completed', 
            message => 'Warn: Deleted / Changed files exceed limits',
            level   => 2,
          );  
  }
}
else {
  logit(  text    => 'No differences. Sync not needed', 
          message => 'No differences',
          level   => 3,
        );
}

# Scrub needed? If sync is run daily with 'scrub -p new' $opt{scrubNewDays} will allways be 0.
# So second check on oldest scrubbed block is made and scrub called if needed.
if ( $opt{scrubNewDays} >= $opt{scrubDays} or $opt{scrubOldDays} >= $opt{scrubOldest} ) {

  # Do not scrub un sync'ed array!
  if ($opt{syncSuccess}) {
    logit(  text    => "Running scrub - Days since last scrub:- $opt{scrubNewDays} - Oldest scrubbed block:- $opt{scrubOldDays}", 
            message => "Running scrub - Last: $opt{scrubNewDays} - Oldest: $opt{scrubOldDays}",
            level   => 3,
          );
    snap_scrub( plan => "$opt{scrubPercentage}", age => "$opt{scrubAge}" );
  
  }
  else {
    logit(  text    => 'Sync was not run. Scrub only performed after successful sync', 
            message => 'No sync so Scrub not performed}',
            level   => 3,
          );  
  }
}
else {
  logit(  text    => "No Scrub needed - Days since last scrub:- $opt{scrubNewDays} - Oldest scrubbed block:- $opt{scrubOldDays}",
          message => 'No post sync scrub needed',
          level   => 3,
        );
}

# Create symbolic link pool
if ( $opt{pool} ) { 
  snap_pool(); 
}

# Log smart details?
if ( $opt{smartLog} ) { 
  snap_smart(); 
}

# Spindown?
if ( $opt{spinDown} ) { 
  snap_spindown(); 
}

if ( $opt{useCustomCmds} ) {

  # Run post commands
  custom_cmds('post');
}

logit(  text    => 'Script Completed',
        message => 'Script Completed',
        level   => 3,
      );
          
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
# return void
sub snap_status {

  # Get snapraid version
  my ( $output, $exitCode ) = snap_run( opt => '--version', cmd => '' );
  ( $opt{snapVersion} ) = $output =~ m/snapraid\s+v(\d+.\d+)/;

  # Run snapraid status
  ( $output, $exitCode ) = snap_run( opt => '', cmd => 'status' );

  # Critical error. Status shows errors detected.
  if ( $output !~ m/No\s+error\s+detected/ ) { 
    logit(  text    => 'Critical: Status shows errors detected',
            message => 'Crit: Status shows errors detected',
            level   => 1,
            abort   => 1,
          );
  }

  # Critical error. Sync currently in progress.
  if ( $output !~ m/No\s+sync\s+is\s+in\s+progress/ ) { 
    logit(  text    => 'Abort: Sync currently in progress',
            message => 'Abort: Sync currently in progress',
            level   => 2,
            abort   => 1,
          ); 
  }

  # Check for zero sub-second timestamps and correct.
  if ( $output =~ m/You have\s+(\d+)\s+files/ ) {

    # Grab match so I don't clobber it later with new code
    my $timeStamps = $1;

    # Reset enabled in config and snapraid supports?
    if ( $opt{resetTimeStamps} && $opt{snapVersion} >= 10.0 ) {

      # Run snapraid touch
      my ( $touch, $exitCode ) = snap_run( opt => '', cmd => 'touch' );
      foreach my $line ( split(/\n/, $touch) ) {

        # Log files where time stamps where changed.
        if ( $line =~ m/touch/ ) {

          # Remove word 'touch' before logging
          $line =~ s/touch\s//;
          logit(  text    => "Zero sub-second timestamp reset on :- $line",
                  message => '',
                  level   => 4,
          );
        }
      }
      logit(  text    => "$timeStamps files with zero sub-second timestamps, Snapraid touch command was run",
              message => "ZSS Timestamps reset on $timeStamps files",
              level   => 3,
            );
    }
    else {
      logit(  text    => "$timeStamps files with zero sub-second timestamps, No action taken",
              message => "$timeStamps files with ZSS timestamps",
              level   => 3,
            );
    }
  }
  else {
    logit(  text    => 'No zero sub-second timestamps detected',
            message => 'No ZSS timestamps detected',
            level   => 3,
          );
  }

  # Get number of days since last scrub
  ( $opt{scrubNewDays} ) = $output =~ m/the\s+newest\s+(\d+)./;

  # Get the age of the oldest scrubbed block (Used when $opt{useScrubNew} in effect)
  ( $opt{scrubOldDays} ) = $output =~ m/scrubbed\s+(\d+)\s+days\s+ago/;

  return;
}

##
# sub snap_diff();
# Runs diff command and scrapes values into a hash and sets 'sync' value to true if differences detected.
# usage snap_diff();
# return void
sub snap_diff {

  # Lexicals
  my ( $diffLogTxt, $missingValues );

  # Run snapraid diff
  my ( $output, $exitCode ) = snap_run( opt => '', cmd => 'diff' );

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
      logit(  text    => "Warning: Missing value \'$diffKey\' during diff command!",
              message => '',
              level   => 2,
            );
      $missingValues = 1;
      
    }
  }

  # Missing values?
  if ( $missingValues ) { 
    logit(  text    => 'Abort: Values missing from snapraid diff',
            message => 'Abort: Diff values missing',
            level   => 2,
            abort   => 1,
          );
  }

  # Sync needed?
  $diffHash{sync} = $output =~ m/There\s+are\s+differences/ ? 1 : 0;
  
  # Log diff output
  foreach my $key ( sort(keys %diffHash) ) {
    $diffLogTxt .= "-> " . $key . ' = ' . $diffHash{$key} . " ";
  }
  logit(  text    => $diffLogTxt,
          message => '',
          level   => 3,
        );

  return;
}

##
# sub snap_sync
# Runs a sync command and logs details
# usage snap_sync();
# return void
sub snap_sync {

  # Lexicals
  my $excludedCount = 0;
  my ( $dataProcessed, $fullLog );

  # Run snapraid sync command
  my ( $output, $exitCode ) = snap_run( opt => '', cmd => 'sync' );

  # Process output
  foreach my $line ( split(/\n/, $output) ) {

    # Match for excluded files
    if ( $line =~ m/Excluding\s+file/ ) {
      $excludedCount++;
    }
    else {
      $fullLog .= $line . "\n";
    }

    # Get size of data processed
    if ( $line =~ m/completed/ ) { ( $dataProcessed ) = $output =~ m/completed,\s+(\d+)\s+MB processed/; }

    # Was it a success?
    if ( $line =~ m/Everything\s+OK/ ) { $opt{syncSuccess} = 1; }

  }

  if ( $opt{syncSuccess} ) {

    # Log details from sync.
    logit(  text    => "Snapraid sync completed: $dataProcessed MB processed and $excludedCount files excluded", 
            message => "Snapraid sync comp: $dataProcessed MB",
            level   => 3,
          );
  }
  else {
    # Stop script.
    logit(  text    => 'Abort: Sync failed!\n$fullLog',
            message => 'Abort: Sync failed',
            level   => 2,
            abort   => 1,
          );
  }

  # New in snapraid. Verify new data from sync.
  if ( $opt{useScrubNew} ) {

    # Check its a compatible version of snapraid.
    if ( $opt{snapVersion} >= 9.0 ) {
      logit(  text    => 'ScrubNew option set. Scrubing lastest sync data',
              message => 'Scrubbing latest sync data',
              level   => 3,
          );
      snap_scrub( plan => 'new', age => '' );
      
    }
    else {
      logit(  text    => 'Warning: ScrubNew is set but snapraid version must be 9.0 or higher!',
              message => 'Warn: ScrubNew -> Snapraid 9.0+',
              level   => 2,
            );
    }
  }
  return;
}

##
# sub snap_scrub
# Perform a scrub on array
# usage snap_scrub( plan => 'plan', age => 'age' );
# return void
sub snap_scrub {

  # Grab first to elements of passed array.
  my %cmdArgs = @_;
  my $dataProcessed;
  
  if ( $cmdArgs{plan} ) { $cmdArgs{plan} = "-p $cmdArgs{plan}"; }
  if ( $cmdArgs{age} )  { $cmdArgs{age}  = "-o $cmdArgs{age}";  }

  my ( $output, $exitCode ) = snap_run( opt => "$cmdArgs{plan} $cmdArgs{age}", cmd => 'scrub' );

  #Get size of data processed
  if ( $output =~ m/completed/ ) { ( $dataProcessed ) = $output =~ m/completed,\s+(\d+)\s+MB processed/; }

  # Was it a success?
  if ( $output =~ m/Everything\s+OK/ ) {
    # Log details from scrub.
    logit(  text    => "Snapraid scrub completed: $dataProcessed MB processed",
            message => "Snapraid scrub comp: $dataProcessed MB",
            level   => 3,
          );
  }
  else {
    # Stop script.
    logit(  text    => 'Abort: Scrub failed!\n$fullLog',
            message => 'Abort: Scrub failed!',
            level   => 2,
            abort   => 1,
          ); 
  }
  return;
}

##
# sub snap_smart
# Log smart details and warn if requited
# usage snap_smart();
# return void
sub snap_smart { #TODO: Use run dir to log data from last run

  # Run snapraid smart
  my ( $output, $exitCode ) = snap_run( opt => '', cmd => 'smart' );

  # Holds disk data to be written out
  my %smartDisk;

  # Process Output
  foreach my $line ( split(/\n/, $output) ) {

    # Match snapraid log for disk info
    # Todo: Not happy with this. Works fine but messy and unreadble... To re-visit
    if ( $line =~ m/\s+\d+\s+\d+\s+\d+\s+\d+%\s+\d\.\d\s+[A-Za-z0-9-]+\s+[\/a-z]+\s+\w+/ ) {

      # Get params
      my ( $temp, $days, $error, $fp, $size, $serial, $device, $disk ) = $line =~ m/\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(\d\.\d)\s+([A-Za-z0-9-]+)\s+([\/a-z]+)\s+(\w+)/;
      $fp = sprintf( "%02d", $fp );
      
      # Add data to hash
      $smartDisk{$serial}->{temp}   = $temp;
      $smartDisk{$serial}->{error}  = $error;
      $smartDisk{$serial}->{fp}     = $fp;
      
      logit(  text    => "Device: $device     Temp: $temp     Error Count: $error     Fail Percentage: $fp%     Power on days: $days", 
              message => '',
              level   => 3,
          );

      # Warn if Fail Percentage exceeds limit sit in config
      if ( $fp > $opt{smartDiskWarn} ) {
        logit(  text    => "Warning: Fail percentage for $serial has exceded warning level",
                message => 'Warn: Fail % for $device > warning level',
                level   => 2,
              );
      }
    
      # Warn for disk temp
      if ( $temp > $opt{smartMaxDriveTemp} ) { 
        logit(  text    => "Warning: Device:- $device Serial:- $serial : Temp:- $temp exceeds limit set in config!", 
                message => "Warn: $device Temp:- $temp > warning level",
                level   => 2,
              );
      }

      # Warn for disk errors
      if ( $error >= $opt{smartDiskErrorsWarn} ) { 
        logit(  text    => "Warning: Device:- $device Serial:- $serial : Errors exceeds limit set in config!", 
                message => "Warn: $device errors > warning level",
                level   => 2,
             );
      }

    }
    elsif ( $line =~ m/next\s+year\s+is/ ) {

      # Get FP for array
      my ( $arrayFail ) = $line =~ m/next\s+year\s+is\s+(\d+)%/;
      logit(  text    => "Calculated chance of at least one drive failing in the next year is $arrayFail%",
              message => "Drive fail withing year: $arrayFail%",
              level   => 3,
            );

      # Warn if Fail Percentage for Array exceeds limit sit in config
      if ( $arrayFail > $opt{smartWarn} ) {
        logit(  text    => 'Warning: Chance of disk in array failing within the next year has exceded warning level',
                message => 'Warn: Drive fail withing year > warning level',
                level   => 2,
              );
      }
    }
  }
  
  # Encode smartdata to json
  my $smartDiskOut = encode_json \%smartDisk;
  
  # Write out to json directory (Used to chack for changes since last run)
  my $jsonSmartOut = $opt{jsonFileLocation} . $slashType .  'smartout.json';
  my $fileWritten = write_file( filename  => $jsonSmartOut,
                                contents  => \$smartDiskOut,
                               );
                                
  return;
}

##
# sub snap_spindown
# Spin down disks (Plan to add options for selecting which disks to spin down)
# usage snap_spindown();
# return void
sub snap_spindown {

  # Run snapraid down
  my ( $output, $exitCode ) = snap_run( opt => '', cmd => 'down' );

  #Log output
  foreach my $disk ( split(/\n/, $output) ) {
    logit(  text    => $disk, 
            message => '',
            level   => 4,
          );
  }

  logit(  text    => 'Array spundown', 
          message => 'Array spundown',
          level   => 3,
        );
  
  return;
}

##
# sub snap_pool
# Creat pool if valid config option exists
# usage snap_pool();
# return void
sub snap_pool {

  # Check for pool entry in snapraid config
  if ( $conf{pool} ) {

    # Run snapraid pool command
    my ( $output, $exitCode ) = snap_run( opt => '', cmd => 'pool' );

    # Get number of links created
    my ( $links ) = $output =~ m/(\d+)\s+links/;
    logit(  text    => "Pool command run and $links links created in $conf{pool}", 
            message => "Pool run and $links links created",
            level   => 3,
          );
  }
  return;
}

##
# sub snap_run
# Run a snapraid command
# usage snap_run( opt => 'options', cmd => 'command', stderr => '0|1' );
# returns stdout, exitcode, *opt stderr
sub snap_run {

  # Get passed args
  my %cmdArgs    = @_;
  my $stderrFile = $opt{snapRaidTmpLocation} . $slashType . 'snapPERLcmd-stderr.tmp';
  my $stdoutFile = $opt{snapRaidTmpLocation} . $slashType . 'snapPERLcmd-stdout.tmp';

  # Build command
  my $snapCmd     = "$opt{snapRaidBin} -c $opt{snapRaidConf} -v $cmdArgs{opt} $cmdArgs{cmd} 1\>$stdoutFile 2\>$stderrFile";
  my $snapCmdLog  = "$opt{snapRaidBin} -c $opt{snapRaidConf} -v $cmdArgs{opt} $cmdArgs{cmd}";

  # Log command to be run
  logit(  text    => "Running: $snapCmdLog",
          message => '',
          level   => 4,
        );
        
  my $exitCode;
  # OS Base?
  if ( $osName eq 'MSWin32' ) {
    # TODO
  }
  else {
    # Expand path for snapraid.exe call to smartctl
    local $ENV{PATH} = "$ENV{PATH}:/usr/sbin"; 
    # Run command
    $exitCode = system($snapCmd);
  }

  # Slurp in stndout/stderr from last call
  my $cmdStderr = slurp_file($stderrFile);
  my $cmdStdout = slurp_file($stdoutFile);
  
  if ( defined $cmdStderr ) {

    # Get file size of stderr file
    my @stderrStat = stat $stderrFile;

    # stderr file is NOT empty indicating snapraid wrote to stderr
    if ( $stderrStat[7] > 0 ) {

      # Write it to log
      my $logOutFile = $opt{logFileLocation} . $slashType . 'Stnderr' . $cmdArgs{cmd} . '.log';
      my $fileWritten = write_file( filename  => $logOutFile,
                                    contents  => \$cmdStderr,
                                    UTF8      => 0,
                                   );

      if ( !$fileWritten ) {
        logit(  text    => "Warning: Unable to write log - Please check $opt{logFileLocation} is writable", 
                message => "Warn: Unable to write log Stderr",
                level   => 2,
              );
      }
      
      # Abort script and request user to investigate if critical call
      if ( $cmdArgs{cmd} =~ /sync|scrub|status|diff/ ) {
        logit(  text    => "Critical: stderr file size: $stderrStat[7] -- Exit code: $exitCode", 
                message => "Crit: Snapraid error -- Exit code: $exitCode",
                level   => 1,
            );
        logit(  text    => "Abort: Snapraid $cmdArgs{cmd} reports errors. Please check snapraid stderr file:- $stderrFile",
                message => 'Abort: Snapraid $cmdArgs{cmd} reports errors',
                level   => 2,
                abort   => 1,
          ); 
      } 
      else { 
        # Logit for investigation
        logit(  text    => "Warning: Snapraid issues with cmd: $cmdArgs{cmd} - Please see log: $logOutFile",
                message => "Warn: Check log: $logOutFile",
                level   => 2,
              );
      }
    }
  }
  else {
    logit(  text    => "Warning: unable to read stderr file: $stderrFile - Please check $opt{snapRaidTmpLocation} is writable",
            message => 'Warn: unable to read stderr file',
            level   => 2,
          );
  }

  if ( defined $cmdStdout ) {
    #Pass stdout / exitcode back to caller
    if ( $cmdArgs{stderr} ) {
      return ( $cmdStdout, $exitCode, $cmdStderr );
    }
    else {
      return ( $cmdStdout, $exitCode );
    }
  }
  else {
    logit(  text    => "Abort: Unable to read stndout file:- $stdoutFile - Please check $opt{snapRaidTmpLocation} is writable",
            message => 'Abort: Unable to read stndout file',
            level   => 2,
            abort   => 1,
          );
  }

  return;
}

##
# sub parse_conf
# Parse the snapraid conf file into a package wide 2 dimension hash->hash/array %conf
# usage parse_conf();
# return void
sub parse_conf {

  # Define local slurp scalar
  my $confData;

  # Slurp the conf file :P
  $confData = slurp_file( $opt{snapRaidConf} );

  # Process slurped conf file.
  foreach my $confIn ( split(/\n/, $confData) ) {

    # Remove leading whitespace
    $confIn =~ s/^\s+//g;

    # If not commented out or empty line
    if ( $confIn !~ m/^#/ && $confIn =~ m/^\w+/ ) {
      my ( $key, $value ) = split(/\s/, $confIn, 2);

      # Stop uninitialized warnings if there is no whitespace after key only option https://github.com/SmileyMan/snapPERL/issues/1
      if ( !defined $value ) { $value = ''; }
      $key    =~ s/^\s+|\s+$//g;      # Remove leading and trailing whitespace
      $value  =~ s/^\s+|\s+$//g;      # Remove leading and trailing whitespace

      # Process extra parity
      if ( $key =~ m/\d-parity/ ) { $conf{xparity}->[ $#{ $conf{xparity} } + 1 ] = $value; }

      # Process other options and add to hash-array
      elsif ( $key =~ m/content|exclude|share|smartctl/ ) { $conf{$key}->[ $#{ $conf{$key} } + 1 ] = $value; }

      # Process data disks
      elsif ( $key =~ m/disk|data/ ) {
        my ( $drive, $path ) = split(/\s/, $value, 2);
        $drive  =~ s/^\s+|\s+$//g;    # Remove leading and trailing whitespace
        $path   =~ s/^\s+|\s+$//g;    # Remove leading and trailing whitespace
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
  
  # Location of json conf file
  my $jsonConfFile = $opt{jsonFileLocation} . $slashType .  'confout.json'; 
 
  # Load conf from last run 
  my $preConfIn = slurp_file($jsonConfFile);
  my %preConf   = decode_json \$preConfIn;
  
  # Compare the conf (Just a little santiy check)
  # comp_conf(\%conf, \%preConf);
  
  # Encode current snapraid conf to json and write out
  my $confOut     = encode_json \%conf;
  my $fileWritten = write_file( filename  => $jsonConfFile,
                                contents  => \$confOut,
                               );
  
  return;
}

##
# sub get_opt_hash
# Build option hash from options in optionsfile into package wide hash %opt;
# usage get_opt_hash();
# return void
sub get_opt_hash {

  my $options;

  # Slurp the options file :P
  $options = slurp_file($optionsFile);

  # Cycle though options and build hash
  foreach my $optin ( split(/\n/, $options) ) {

    # Ignore lines without options in them
    if ( $optin =~ m/=/ ) {

      # Lexicals
      my ( $key, $value, $comment, $valueC );

      # Split keys
      ( $key, $valueC ) = split(/=/, $optin);

      # Don't add commented out keys
      if ( $key !~ /#/ ) {

        # Split Values
        if ( $valueC =~ m/#/ ) {
          ( $value, $comment ) = split(/#/, $valueC);
        }
        else {
          $value = $valueC;
        }

        # Clean up keys/values
        $key    =~ s/^\s+|\s+$//g;
        $value  =~ s/^\s+|\s+$//g;

        #Add key,value pairs
        $opt{$key} = $value;
      }
    }
  }
  
  # Get hostname
  $opt{hostname} = qx{hostname};
  # Remove vertical whitespace from hostname (Email issue)
  chop $opt{hostname};
    
  # If not defined in config file (Normal situation)
  if ( !$opt{snapRaidTmpLocation} ) { $opt{snapRaidTmpLocation} = $scriptPath . 'tmp'; }
  
  # If not defined in config file (Normal situation)
  if ( !$opt{logFileLocation} ) { $opt{logFileLocation} = $scriptPath . 'log'; }
  
  # Define location for script json files (Files that hold information about previous runs)
  $opt{jsonFileLocation} = $scriptPath . 'json';
  
  # Hold value of lowest LogLevel reached
  $opt{minLogLevel} = 5;
  
  return;
}

##
# sub script_comp
# Called at end of script. Basic clean up tasks.
# usage script_comp();
# return void
sub script_comp {

  # Send email if enabled
  if ( $opt{emailSend} ) { email_send(); }

  # Write log to location in $opt{logFile}
  if ( $opt{logFile} ) { 
    my $logOutFile = $opt{logFileLocation} . $slashType . $opt{logFile};
    my $fileWritten = write_file( filename  => $logOutFile,
                                  contents  => \$scriptLog,
                                  UTF8      => 0,
                                 );
    
    if ( !$fileWritten ) {
      logit(  text    => "Warning: Unable to write log - Please check $opt{logFileLocation} is writable",
              message => "Warn: Unable to write log: $logOutFile",
              level   => 2,
            );
    } 
  }
  
  # Send pushover message?
  if ( $opt{pushOverSend} and $scriptMessage ) {

    my $messageTitle;
    my $poMessagePriority = $opt{pushDefaultPriority};
    
    # Modify for Warnings or Critical
    if ( $opt{minLogLevel} < 3 ) {
      $messageTitle       = $opt{minLogLevel} < 2 ? 'Critical' : 'Warning';
      $poMessagePriority  = $opt{minLogLevel} < 2 ? $opt{pushCriticalPriority} : $opt{pushWarningPriority};
    } 
        
    # Build title
    $messageTitle .=  " $opt{hostname} snapPERL";
    
    # Send message
    send_message_po (       
      poPriority  => $poMessagePriority,
      poDevice    => $opt{pushDevice},
      poTitle     => $messageTitle,
      poSound     => $opt{pushSound},
      message     => $scriptMessage, 
    );

  }
  
  return;
}

##
# sub email_send
# Send the scriptLog out via email;
# usage email_send();
# return void
sub email_send {

  my $subjectAlert;

  # Add alert to subject line if warnings or errors encountered.
  if ( $opt{minLogLevel} < 3 ) {
    $subjectAlert = $opt{minLogLevel} < 2 ? 'Critical' : 'Warning';
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
        Subject => "$subjectAlert \[$opt{hostname}\] - snapPERL Log. Please see message body",
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
    if ($@) { 
      logit(  text    => "Warning: Gmail SMTP email send failed... $@",
              message => 'Warn: Gmail SMTP email send failed...',
              level   => 2,
            );
    }

  }
  else {

    # Load on demand needed modules for Email send
    autoload MIME::Lite;

    # Send email via localy configured sendmail server.
    my $msg = MIME::Lite->new(
      From    => $opt{emailSendAddress},
      To      => $opt{emailAddress},
      Subject => "\[$opt{hostname}\] - snapPERL Log. Please see message body",
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
  return;
}

##
# sub send_message();
# Sends message to various messaging API's 
# usage send_message( %options_hash );
# return void
sub send_message_po {
  
  # Get passed options
  my %optHash = @_;

  # Valid Pushover sounds
  my @poSounds = qw{  
    pushover bike bugle cashregister classical cosmic falling gamelan incoming intermission 
    magic mechanical pianobar siren spacealarm tugboat alien climb persistent echo updown none
  };

  # Check sound valid and if not assign default
  if ( !grep { $_ =~ /^$optHash{poSound}$/ } @poSounds ) {
    $optHash{poSound} = 'pushover';
  }

  # Add default title if needed
  if ( !defined $optHash{poTitle} ) { $optHash{poTitle} = "$opt{hostname} snapPERL"; }

  # Priority must be between -2 and 2
  if ( !defined $optHash{poPriority} || $optHash{poPriority} > 2 || $optHash{poPriority} < -2 ) { $optHash{poPriority} = 0; }

  # Priority 2 can only be used with device name
  if ( !defined $optHash{poDevice} && $optHash{poPriority} == 2) { $optHash{poPriority} = 1; }

  # Get LWP Agent
  my $userAgent = LWP::UserAgent->new;
  
  # Post request to pushover API
  my $response = $userAgent->post( $opt{pushOverUrl}, 
    [ 
      token     => $opt{pushOverToken},
      user      => $opt{pushOverKey},
      priority  => $optHash{poPriority},
      device    => $optHash{poDevice},
      title     => $optHash{poTitle},
      sound     => $optHash{poSound},
      message   => $optHash{message}, 
    ]
  );
  
  # Did the post fail?
  if ( !$response->is_success ) {
    # Log the fail!
    logit(  text    => "Warning: Pushover message failed:-  $response->status_line",
            message => 'Warn: Pushover message failed',
            level   => 2,
          );
  }
  else {
    # Log the success
      logit(  text    => 'Pushover message sent',
              message => '',
              level   => 3,
          );
  }

  return;
}

##
# sub load_custom_cmds();
# Loads custom commands from file into hash/array
# usage load_custom_cmds();
# return void
sub load_custom_cmds {

  my $customCmdsIn;

  # Slurp the custom commands file :P
  $customCmdsIn = slurp_file($customCmdsFile);

  foreach my $line ( split(/\n/, $customCmdsIn) ) {

    # Remove any leading whitespace
    $line =~ s/^\s+//g;

    #Ignore comments and empty lines
    if ( $line !~ m/^#/ && $line =~ m/=/ ) {

      #Split on '='
      my ( $type, $cmd ) = split(/=/, $line);

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
# return void
sub custom_cmds {

  # Get type of operation
  my $type = shift;

  # Check it's valid
  if ( $type !~ m/pre|post/ ) {
    logit(  text    => 'Warning: Custom commands called with incorrect option',
            message => '',
            level   => 2,
          );
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
# return contents of slurp or undef if failed
sub slurp_file {

  # Get file to slurp
  my $file = shift;

  # mmm Slurp
  my $slushPuppie;

  # File exists?
  if ( -e $file ) {
    if ( open my $fh, '<:encoding(UTF-8)', $file ) {
      local $/ = undef;       # Don't clobber global version. Normaly holds 'newline' and reads one line at a time
      $slushPuppie = <$fh>;   # My favorite slurp
      close $fh;              # Will auto close once once out of scope regardless
    }
    else {
      logit(  text    => "Warning: Unable to open file: $file",
              message => "Warn: Unable to open file: $file",
              level   => 2,
            );
    }
  }
  else {
    # File don't exist - Send to log @ debug level
    logit(  text    => "Call to slurp_file() with none existing file: $file",
            message => '',
            level   => 5,
          );
  }

  # Return the Slurpie (If file not read returns undef)
  return $slushPuppie;
}

##
# sub time_stamp();
# Create a timestamp for the log.
# usage $stamp = time_stamp();
# returns formated timestamp
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
# Create a log - Build a message.
# usage logit(  text    => 'Text',
#               message => 'Message',
#               level   => level,
#               abort   => 0|1,
#             );
# return void
sub logit {
  
  # Get hash
  my %logIn = @_;
  
  # Check incomming hash
  if ( not $logIn{level} or $logIn{level} < 0 or $logIn{level} > 5 ) { $logIn{level} = 3; }
  if ( not $logIn{text} and not $logIn{message} ) { 
    $logIn{text} = 'DEBUG: No message sent to logit'; 
    $logIn{level} = 5;
  }

  # Varible holds lowest log level reached. 1 for Critical, 2 for Warning and 3 for Normal
  $opt{minLogLevel} = $logIn{level} < $opt{minLogLevel} ? $logIn{level} : $opt{minLogLevel};
  
  # (1=Critical, 2=Warning, 3=Info, 4=All, 5=Debug)
  if ( $logIn{level} <= $opt{logLevel} or $logIn{level} == 1 ) {
    
    # Add text to logfile
    if ( $logIn{text} ) {
      # Get current timestamp
      my $timeStamp = time_stamp();
      
      if ( $opt{logStdout} == 1 ) {
        # Send to stdout
        say( $timeStamp . " : " . $logIn{text} );
      }

      # Add to log string
      $scriptLog .= $timeStamp . " : " . $logIn{text} . "\n";
    }
    
    if ( $logIn{message} and $logIn{level} < 4 ) {
     
      # (1=Critical, 2=Warning, 3=Normal)
      if ( $logIn{level} <= $opt{messageLevel} or $logIn{level} == 1 ) {
        # Add to message string
        $scriptMessage .= $logIn{message} . "\n";
      }
    }
  }
  
  if ( $logIn{abort} ) {
    
    # Cleanup
    script_comp();

    # Kill script
    croak "Fatal issue encountered. Please see logs";
    
  }
  
  return;
}


##
# sub write_file();
# Write the file to disk.
# usage write_file( filename  => '',
#                   contents  => \scalar-ref,
#                  );
# returns 1 if success and 0 if not
sub write_file {

  # Write log to file
  my %fileParams = @_;
  
  if ( open my $fh, '>:encoding(UTF-8)', $fileParams{filename} ) {
    say {$fh} ${ $fileParams{contents} };
    close $fh;
    return 1;
  }
  else {
    logit(  text    => "Warning: Unable to write $fileParams{filename} . Please check config",
            message => "Warn: Unable to write $fileParams{filename}",
            level   => 2,
          );
    return 0;
  } 
}

sub comp_hash {
  
  my ($hashRef1, $hashRef2) = @_;
  my $hashMatch = 1;
  my @diffs;

  foreach my $key ( keys %{$hashRef1} ) {
    unless ( exists ${$hashRef2}{$key} ) {
      push @diffs, "Hash1 Key \'$key\' missing in hash2";
      $hashMatch = 0;
      next;
    }

    if ( ${$hashRef1}{$key} ne ${$hashRef2}{$key} ) {
      push @diffs, "Values for Hash1 don't match Hash2";
      $hashMatch = 1;
    }
  }
  return wantarray ? @diffs : $hashMatch; 
}

##
# sub debug_log
# Called if logLevel set to 5 (Debug).
# Cycles over multi dimension hash created from config file.
# usage debug_log();
# return void
sub debug_log {

  # May just use Data::Dumper for this

  # Debug -> Log Options!
  logit(  text    => '-------- Options --------',
          message => '',
          level   => 5,
        );
  foreach ( sort( keys %opt ) ) {
    logit(  text    => "Option :: $_ -> $opt{$_}",
            message => '',
            level   => 5,
          );
  }
  logit(  text    => '-------- Options End --------',
          message => '',
          level   => 5,
        );

  # Debug -> Log Config!
  logit(  text    => '-------- Config --------',
          message => '',
          level   => 5,
        );
  foreach my $confKey ( sort(keys %conf) ) {
    if ( ref($conf{$confKey}) eq "HASH" ) {
      foreach my $diskKey ( keys %{ $conf{$confKey} } ) {
        logit(  text    => "Config : $confKey -> $diskKey -> $conf{$confKey}->{$diskKey}",
                message => '',
                level   => 5,
          );
      }
    }
    elsif ( ref($conf{$confKey}) eq "ARRAY" ) {
      for ( my $i = 0 ; $i <= $#{ $conf{$confKey} } ; $i++ ) {
        logit(  text    => "Config : $confKey -> $i -> $conf{$confKey}->[$i]",
                message => '',
                level   => 5,
              );
      }
    }
    else {
      logit(  text    => "Config : $confKey -> $conf{$confKey}",
              message => '',
              level   => 5,
          );
    }
  }
  logit(  text    => '-------- Config End--------',
          message => '',
          level   => 5,
        );

  return;
}


#-------- Subroutines End --------#

# Return true at end of script
1;

__END__

