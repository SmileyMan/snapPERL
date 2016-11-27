#!/usr/bin/perl
#############################################################################################
#
# Snapraid helper script written in PERL. Enables automation using cron for your Array Syncs
#
# Please see README.md
#
#############################################################################################

#############################################################################################
#
# Created by Steve Miles (SmileyMan). https://github.com/SmileyMan
#                                     http://snapperl.stevemiles.me.uk/
#                                     http://stevemiles.me.uk/
#
# Email Support                       snapperl@stevemiles.me.uk
# (Please note: Free script so will help where I can)
#
#############################################################################################

package snapPERL;

# Pragmas
use 5.010;
use strict;
use warnings;

# Modules
use Module::Load;        # Perl core module for on demand loading of optional modules
use File::Spec;          # Used to read absolute path
use LWP::UserAgent;      # Send Post/Get (For messaging support)
use JSON::PP;            # Encode data to JSON for storage
use Getopt::Long;        # Get command line options
use Data::Dumper;        # Debug use - Dump hashes used

# Work started on v0.4.0
our $VERSION = '0.3.1';

# Todo: More updates to log when running explaining whats going on for interactive use!

############################## Script only from here ########################################

# Get os name from perl inbuilt variable
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

# Define custom commands file
my $customCmdsFile = $scriptPath . 'custom-cmds';

# Get file locations from command line if given
my %argv;
#Getops object
my $cmdLineOpts = Getopt::Long::Parser->new;
#Configure to accept short -? type commandline options
$cmdLineOpts->configure( qw(gnu_getopt) );
#get Options
$cmdLineOpts->getoptions (
  "conf|c=s"          => \$optionsFile,
  "custom-cmds|x=s"   => \$customCmdsFile,
  "message-level|m=i" => \$argv{messageLevel},
  "log-level|l=i"     => \$argv{logLevel},
  "stdout!"           => \$argv{logStdout},
  "check!"            => \$argv{checkSuspectDisks},
  "scrub!"            => \$argv{scrubEnable},
  "email!"            => \$argv{emailSend},
  "custom!"           => \$argv{useCustomCmds},
  "pushover!"         => \$argv{pushOverSend},
  "smart!"            => \$argv{smartLog},
  "pool!"             => \$argv{pool},
  "spindown!"         => \$argv{spinDown},
  "help|h"            => \$argv{help},
  "version|v"         => \$argv{version},
);

# Display Help or Version and exit;
if ( $argv{version} or $argv{help} ) { show_cmdline_help(); }

# Croak if no conf file to load
if ( !-e $optionsFile ) { say "snapPERL conf file: $optionsFile not found - Critical error"; exit(1); }

# Define package variables (Lexical to package)
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

# Auto mount and unmount parity - Will leave to custom-cmds options - To be removed!
#if ( %opt{autoMountParity} ) { mount_parity(); }

# Check conf hash
check_conf();

# Get current state.
snap_status();
snap_diff();

# Sync needed?
if ( $diffHash{sync} ) {

  # Check set limitsn here - Tagged to investigate
  # Todo: Somthing funky going o
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

# Use scrubEnforceMinDays option to enforce minimum days between scrubs
if ( $opt{scrubEnforceMinDays} ) {
  # Location of json file
  my $jsonFile = $opt{jsonFileLocation} . $slashType .  'scrublast.json'; 
   
  # Save json and end warning if failed to save
  my $scrubLastRef = load_json( $jsonFile );
  
  # Get time
  my $timeNow = time();
  
  # Check if enougth time as passed
  if ( $scrubLastRef->{lastScrubTime} and $scrubLastRef->{lastScrubTime} > $timeNow - ($opt{scrubEnforceMinDays} * 86400) ) {
    $opt{scrubMinDaysEnforced} = 1;
  } 
}

# Stop scrub if scrubEnforceMinDays in effect and min days not passed
if ( not $opt{scrubMinDaysEnforced} and $opt{scrubEnable} ) {
  
  # Scrub needed? If sync is run daily with 'scrub -p new' $opt{scrubNewDays} will always be 0.
  # So second check on oldest scrubbed block is made and scrub called if needed.
  if ( $opt{scrubNewDays} >= $opt{scrubNewest} or $opt{scrubOldDays} >= $opt{scrubOldest} ) {
  
    # Do not scrub un sync'ed array!
    if ($opt{syncSuccess} or not $diffHash{sync} ) {
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
}
elsif ( not $opt{scrubEnable} ) {
  # Log that all scrub activity is disabled
  logit(  text    => "No Scrub: All scrub activity disabled in configuration",
          message => 'No Scrub. All scrub activity disabled',
          level   => 3,
        );
}
else {
  # Log that scrubEnforceMinDays not passed
  logit(  text    => "No Scrub: Days since last scrub does not exceed min setting of: $opt{scrubEnforceMinDays} days",
          message => 'No Scrub. Enforce Min Days in effect',
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

logit(  text    => 'Script Completed',
        message => '',
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

  # Define call return vars
  my ($output, $exitCode, $snapLog);

  # Get snapraid version (cmd => 'version' not needed but snapraid ignores it so stndout/stderr files get right name)
  ( $output, $exitCode ) = snap_run( opt => '--version', cmd => 'version' );
  ( $opt{snapVersion} ) = $output =~ m/snapraid\s+?v(\d+?.\d+?)/i;
  
  # Not using a current version of snapraid..
  if ( $opt{snapVersion} < 10.0 and not $opt{noVersionWarnings} ) {
    logit(  text    => 'Info: snapPERL tested and works best on snapraid v10.0+',
            message => 'Info: snapPERL works best on snapraid v10.0+',
            level   => 3,
          );
  }
  # Very old version - Can not ensure support
  elsif ( $opt{snapVersion} < 9.0 and not $opt{noVersionWarnings} ) {
    logit(  text    => 'Info: Snapraid < 9.0 not recomended - Please visit http://www.snapraid.it/download for latest version',
            message => 'Info: Snapraid < 9.0 not recomended',
            level   => 3,
          );
  }

  # Run snapraid status
  ( $output, $exitCode, $snapLog ) = snap_run( opt => '', cmd => 'status', snaplog => 1);

  # Critical error. Status shows errors detected.
  if ( $output !~ m/No\s+?error\s+?detected/i ) { 
    logit(  text    => 'Critical: Status shows errors detected',
            message => 'Crit: Status shows errors detected',
            level   => 1,
            abort   => 1,
          );
  }

  # Critical error. Sync currently in progress.
  # Todo: Handle this much better - Snapraid reports this when a sync has not completed not when an active sync in progress!
  if ( $output !~ m/No\s+?sync\s+?is\s+?in\s+?progress/i ) { 
    logit(  text    => 'Abort: Sync currently in progress',
            message => 'Abort: Sync currently in progress',
            level   => 2,
            abort   => 1,
          ); 
  }
  
  # Abort if log shows and DANGER warnings !
  if ( $snapLog =~ m/DANGER/ ) {
    logit(  text    => 'Critical: Snapraid log reports DANGER - Script aborting - Please check logs ASAP!',
            message => 'Crit: Snapraid log reports DANGER ',
            level   => 1,
            abort   => 1,
          ); 
  }

  # Check for zero sub-second timestamps and correct.
  if ( $output =~ m/You\s+?have\s+?(?<timeStamps>\d+?)\s+?files/i ) {

    # Grab match so I don't clobber it later with new match
    my $timeStamps = $+{timeStamps};

    # Reset enabled in config and snapraid supports?
    if ( $opt{resetTimeStamps} && $opt{snapVersion} >= 10.0 ) {

      # Run snapraid touch
      my ( $touch, $exitCode ) = snap_run( opt => '', cmd => 'touch' );
      foreach my $line ( split(/\n/, $touch) ) {

        # Log files where time stamps where changed.
        if ( $line =~ m/touch/i ) {

          # Remove word 'touch' before logging
          $line =~ s/touch\s//i;
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
  ( $opt{scrubNewDays} ) = $output =~ m/the\s+?newest\s+?(\d+?)./i;

  # Get the age of the oldest scrubbed block (Used when $opt{useScrubNew} in effect)
  ( $opt{scrubOldDays} ) = $output =~ m/scrubbed\s+?(\d+?)\s+?days\s+?ago/i;

  return;
}

##
# sub snap_diff();
# Runs diff command and scrapes values into a hash and sets 'sync' value to true if differences detected.
# usage snap_diff();
# return void
sub snap_diff {

  # Run snapraid diff
  my ( $output, $exitCode, $snapLog ) = snap_run( opt => '', cmd => 'diff', snaplog => 1 );

  # Abort if log shows and DANGER warnings !
  if ( $snapLog =~ m/DANGER/ ) {
    logit(  text    => 'Critical: Snapraid log reports DANGER - Script aborting - Please check logs ASAP!',
            message => 'Crit: Snapraid log reports DANGER ',
            level   => 1,
            abort   => 1,
          ); 
  }

  # Add each diff value to %diffHash
  # Todo: Extract from log file rather than scrape.
  foreach my $diffKey (qw( equal added removed updated moved copied restored )) {
    if ( $output =~ m/(?<diffValue>\d+?)\s+?$diffKey/i ) {
      $diffHash{$diffKey} = $+{diffValue};
    }
    else {
      # Opps we did not get a value? Abort!
      logit(  text    => "Warning: Missing value \'$diffKey\' during diff command!",
              message => 'Abort: Diff values missing',
              level   => 2,
              abort   => 1,
            );
    }
  }

  # Sync needed?
  $diffHash{sync} = $output =~ m/There\s+?are\s+?differences/i ? 1 : 0;
  #$diffHash{sync} = $exitCode;
  
  # Log diff output
  my $diffLogTxt;
  foreach my $key ( sort(keys %diffHash) ) { $diffLogTxt .= "-> " . $key . ' = ' . $diffHash{$key} . " "; }
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

  # Lexical's
  my $excludedCount = 0;
  my ( $dataProcessed, $fullLog );
  
  my ( $output, $exitCode, $snapLog );
  # Use pre-hash on sync? Snapraid version must be 10.0+
  if ( $opt{preHashOnSync} and $opt{snapVersion} >= 10.0 ) { 
    # Run snapraid sync command with pre-hash - Recommended on v10.0
    ( $output, $exitCode, $snapLog ) = snap_run( opt => '-h', cmd => 'sync', snaplog => 1 );    
  }
  else {
    # Run snapraid sync command no pre-hash
    ( $output, $exitCode, $snapLog ) = snap_run( opt => '', cmd => 'sync', snaplog => 1 );  
  }

  # Abort if log shows and DANGER warnings !
  if ( $snapLog =~ m/DANGER/ ) {
    logit(  text    => 'Critical: Snapraid log reports DANGER - Script aborting - Please check logs ASAP!',
            message => 'Crit: Snapraid log reports DANGER ',
            level   => 1,
            abort   => 1,
          ); 
  }

  # Process output
  foreach my $line ( split(/\n/, $output) ) {

    # Match for excluded files
    if ( $line =~ m/Excluding\s+?file/i ) {
      $excludedCount++;
    }
    else {
      $fullLog .= $line . "\n";
    }

    # Get size of data processed
    if ( $line =~ m/completed/i ) { ( $dataProcessed ) = $output =~ m/completed,?\s+?(\d+?)\s+?MB\s+?processed/i; }

    # Was it a success?
    if ( $line =~ m/Everything\s+?OK/i or $line =~ m/Nothing\s+?to\s+?do/i ) { $opt{syncSuccess} = 1; }

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
    logit(  text    => "Abort: Sync failed!\n$fullLog",
            message => 'Abort: Sync failed',
            level   => 2,
            abort   => 1,
          );
  }

  # New in snapraid. Verify new data from sync.
  if ( $opt{useScrubNew} and $opt{scrubEnable} ) {

    # Check its a compatible version of snapraid.
    if ( $opt{snapVersion} >= 9.0 ) {
      logit(  text    => 'ScrubNew option set. Scrubing latest sync data',
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
  elsif ( not $opt{scrubEnable} ) {
    # Log that all scrub activity is disabled
    logit(  text    => "No Scrub: All scrub activity disabled in configuration",
            message => 'No Scrub. All scrub activity disabled',
            level   => 3,
          );
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
  
  if ( $cmdArgs{plan} eq 'new' ) { $cmdArgs{planNew} = 1; }
  
  if ( $cmdArgs{plan} ) { $cmdArgs{plan} = "-p $cmdArgs{plan}"; }
  if ( $cmdArgs{age} )  { $cmdArgs{age}  = "-o $cmdArgs{age}";  }

  my ( $output, $exitCode, $snapLog ) = snap_run( opt => "$cmdArgs{plan} $cmdArgs{age}", cmd => 'scrub', snaplog => 1 );

  # Abort if log shows and DANGER warnings !
  if ( $snapLog =~ m/DANGER/ ) {
    logit(  text    => 'Critical: Snapraid log reports DANGER - Script aborting - Please check logs ASAP!',
            message => 'Crit: Snapraid log reports DANGER ',
            level   => 1,
            abort   => 1,
          ); 
  }

  #Get size of data processed
  if ( $output =~ m/completed/i ) { ( $dataProcessed ) = $output =~ m/completed,?\s+?(\d+?)\s+?MB processed/i; }

  # Was it a success?
  if ( $output =~ m/Everything\s+?OK/i ) {
    
    # Output scrub time to json
    if ( $opt{scrubEnforceMinDays} and not $cmdArgs{planNew} ) {
  
      my $timeNow = time();
      my $scrubTime = { lastScrubTime => $timeNow };
    
      # Location of json file
      my $jsonFile = $opt{jsonFileLocation} . $slashType .  'scrublast.json'; 
     
      # Save json and end warning if failed to save
      if ( !save_json( $jsonFile, $scrubTime ) ) {
        logit(  text    => "Warning: Unable to write to: $opt{jsonFileLocation}",
                message => 'Warn: Unable to write to json dir',
                level   => 2,
              );
      }
    }  
    # Log details from scrub.
    logit(  text    => "Snapraid scrub completed: $dataProcessed MB processed",
            message => "Snapraid scrub comp: $dataProcessed MB",
            level   => 3,
          );
  }
  elsif ( $output =~ m/Nothing\s+?to\s+?do/i ) {
    logit(  text    => 'Snapraid scrub completed: Nothing to do',
            message => 'Snapraid scrub comp: Nothing to do',
            level   => 3,
          );   
  }
  else {
    # Stop script.
    logit(  text    => "Abort: Scrub failed! - Please review run logs in $opt{snapRaidTmpLocation}",
            message => 'Abort: Scrub failed! - Please see main log',
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
sub snap_smart {

  # Run snapraid smart
  my ( $output, $exitCode ) = snap_run( opt => '', cmd => 'smart' );

  # Holds disk data to be written out
  my %smartDisk;
  
  my %checkDisks;

  # Counters
  my $totalErrors   = 0; 
  my $aggregateTemp = 0; 
  my $driveNum      = 0;

  # Process Output
  foreach my $line ( split(/\n/, $output) ) {

    # Match snapraid log for disk info
    # Todo: Not happy with this. Works fine but messy and unreadable... To re-visit
    if ( $line =~ m/\s+?\d+?\s+?\d+?\s+?\d+?\s+?\d+?%\s+?\d\.\d\s+?[A-Za-z0-9-]+?\s+?[\/a-z]+?\s+?\w+/i ) {

      # Get params
      my ( $temp, $days, $error, $fp, $size, $serial, $device, $disk ) = $line =~ m/\s+?(\d+?)\s+?(\d+?)\s+?(\d+?)\s+?(\d+?)%\s+?(\d\.\d)\s+?([A-Za-z0-9-]+?)\s+?([\/a-z]+?)\s+?(\w+)/i;

      # Perl grabs these as strings and I want nums to be compared and go into json string
      $temp   = int($temp);
      $error  = int($error);
      $fp     = int($fp);

      # Counters
      $driveNum++;
      $totalErrors    += $error;
      $aggregateTemp  += $temp;

      # Add data to hash
      $smartDisk{$serial}->{temp}   = $temp;
      $smartDisk{$serial}->{error}  = $error;
      $smartDisk{$serial}->{fp}     = $fp;
      $smartDisk{$serial}->{disk}   = $disk;

      $fp = sprintf( "%02d", $fp );
    
      logit(  text    => "Device: $device     Temp: $temp     Error Count: $error     Fail Percentage: $fp%     Power on days: $days", 
              message => "Drive $device temp:- $temp",
              level   => 3,
          );

      # Warn if Fail Percentage exceeds limit sit in config
      if ( $fp > $opt{smartDiskWarn} ) {
        $smartDisk{$serial}->{fpwarn} = 1;
        logit(  text    => "Warning: Fail percentage for $serial has exceeded warning level",
                message => 'Warn: Fail % for $device > warning level',
                level   => 2,
              );
      }
      else { $smartDisk{$serial}->{fpwarn} = 0; }
    
      # Warn for disk temp
      if ( $temp > $opt{smartMaxDriveTemp} ) {
        $smartDisk{$serial}->{tempwarn} = 1; 
        logit(  text    => "Warning: Device:- $device Serial:- $serial : Temp:- $temp exceeds limit set in config!", 
                message => "Warn: $device Temp:- $temp > warning level",
                level   => 2,
              );
      }
      else { $smartDisk{$serial}->{tempwarn} = 0; }

      # Warn for disk errors
      if ( $error >= $opt{smartDiskErrorsWarn} ) {
        $smartDisk{$serial}->{errorwarn} = 1; 
        logit(  text    => "Warning: Device:- $device Serial:- $serial : Errors exceeds limit set in config!", 
                message => "Warn: $device errors > warning level",
                level   => 2,
             );
      }
      else { $smartDisk{$serial}->{errorwarn} = 0; }

      # If disk exceeds settings for running a check add it to the checkDisks hash for processing - FP at 100% forces past checkOnlyAfterIncrease
      if ( ($opt{checkSuspectDisks} and (not $opt{checkOnlyAfterIncrease} or $fp == 100)) and $fp > $opt{checkDiskFailPercentage} ) {
        # Add $fp to send to check_disks();
        $checkDisks{$disk} = $fp;
      }

    }
    elsif ( $line =~ m/next\s+?year\s+?is/i ) {

      if ( $driveNum != 0 ) {
        # Get FP for array
        my ( $arrayFail ) = $line =~ m/next\s+?year\s+?is\s+?(\d+?)%/i;
        $smartDisk{ARRAY}->{fp} = $arrayFail;
        logit(  text    => "Calculated chance of at least one drive failing in the next year is $arrayFail%",
                message => "Drive fail within year: $arrayFail%",
                level   => 3,
              );
              
        $smartDisk{ARRAY}->{temp}       = $aggregateTemp / $driveNum;
        $smartDisk{ARRAY}->{error}      = $totalErrors;
        $smartDisk{ARRAY}->{fp}         = int($arrayFail);
        $smartDisk{ARRAY}->{tempwarn}   = 0;
        $smartDisk{ARRAY}->{errorwarn}  = 0;
        $smartDisk{ARRAY}->{disk}       = 'All';
  
        # Warn if Fail Percentage for Array exceeds limit sit in config
        if ( $arrayFail > $opt{smartWarn} ) {
          $smartDisk{ARRAY}->{fpwarn} = 1;
          logit(  text    => 'Warning: Chance of disk in array failing within the next year has exceeded warning level',
                  message => 'Warn: Drive fail withing year > warning level',
                  level   => 2,
                );
        } 
        else { $smartDisk{ARRAY}->{fpwarn} = 0; }
      }
      else {
        logit(  text    => 'No drive information was detected - Are you using VHD mounts?',
                message => 'No drive info - Using VHD?',
                level   => 3,
              );
      }
    }
  }
  
  # Location of Json file for smart data
  my $jsonSmartFile = $opt{jsonFileLocation} . $slashType .  'smartout.json';

  # Load json as a data reference
  my $smartDiskInRef = load_json($jsonSmartFile);

  # Data from last run
  if ( $smartDiskInRef ) {
    foreach my $key (keys %{$smartDiskInRef} ) {
      # Valid key in new hash to compare
      if ( exists $smartDisk{$key} ) {
        # Temp increased since last run and warn sent
        if ( ($smartDisk{$key}->{temp} > $smartDiskInRef->{$key}{temp}) and $smartDisk{$key}->{tempwarn} ) {
          logit(  text    => "Warning: Temp of drive: $key increased since last run",
                  message => "Warn: Temp increased for drive: $key",
                  level   => 2,
                );
          
        } 
        # Fail percentage increased since last run
        if ( $smartDisk{$key}->{fp} > $smartDiskInRef->{$key}{fp} ) {
          logit(  text    => "Warning: Fail Percentage of drive: $key increased since last run",
                  message => "Warn: FP increased for drive: $key",
                  level   => 2,
                );
          # If disk exceeds settings for running a check add it to the checkDisks hash for processing
          if ( $opt{checkSuspectDisks}  and $smartDisk{$key}->{fp} > $opt{checkDiskFailPercentage} ) {
            # Add $fp to send to check_disks();
            $checkDisks{$smartDisk{$key}->{disk}} = $smartDisk{$key}->{fp};
          }
        } 
        # Errors increased since last run
        if ( $smartDisk{$key}->{error} > $smartDiskInRef->{$key}{error} ) {
          logit(  text    => "Warning: Errors of drive: $key increased since last run",
                  message => "Warn: Errors increased for drive: $key",
                  level   => 2,
                );
          
        } 
      }
    }
  }
  
  # Save json and end warning if failed to save
  if ( !save_json( $jsonSmartFile, \%smartDisk ) ) {
    logit(  text    => "Warning: Unable to write to: $opt{jsonFileLocation}",
            message => 'Warn: Unable to write to json dir',
            level   => 2,
          );
  }

  # Disks added to %checkDisks hash? Well lets process them           
  if ( %checkDisks ) {
    #Send ref to this has to check_disks();
    snap_check( \%checkDisks );
  }                   
  return;
}

# sub snap_check
# Runs snapraid check command on suspect disks with high Fail Percentages
# usage snap_check( \%hash );
# return void
sub snap_check {

  # Get reference to passed hash
  my $disksToProcess = shift;
  
  # Nothing sent then stright back
  return unless ( %{$disksToProcess} );
    
  # Location of Json file for smart data
  my $jsonCheckFile = $opt{jsonFileLocation} . $slashType .  'checkfile.json';

  # Load json as a data reference
  my $checkInRef = load_json($jsonCheckFile);
  
  # Get current time
  my $timeNow = time();
  
  # Process sent disks
  foreach my $disk ( keys(%{$disksToProcess}) ) {
    
    # Dont run check if one has been run within checkMinTimeBetweenChecks days
    if ( $checkInRef->{$disk} < $timeNow - ($opt{checkMinTimeBetweenChecks} * 86400) ) {
  
      # Var for options
      my $options;
      
      # Var for check log per disk
      my $filesDamaged;
      
      # Logit
      logit(  text    => "Starting snapraid check on disk: $disk - Fail Percentage: $disksToProcess->{$disk}% - This proccess will take some time", 
              message => "Starting snapraid check on disk: $disk",
              level   => 3,
           );
            
      # Build options
      $options = "-d $disk";
      
      # Add audit only tag
      if ( $opt{checkAuditOnly} ) { $options .= ' -a'}
  
      my ( $output, $exitCode ) = snap_run( opt => $options, cmd => 'check' );
      
      # Process output
      foreach my $line ( split(/\n/, $output) ) {
        
        if ( $line =~ m/\bdamaged|\brecoverable/i ) {
  
          # Remove word 'damaged' or 'recoverable' before logging
          $line =~ s/damaged|recoverable//i;
          # Remove whitespace
          $line =~ s/^\s+|\s+$//g;
          
          # Add to check log
          $filesDamaged .= "Damaged: $line";
          # Logit @ Lv4
          logit(  text    => "Damaged: $line",
                  message => "Damaged file found on check for disk $disk - Check log",
                  level   => 4,
          );
          
          if ( !$opt{checkAutoFix} ) {
            # Add snapraid repair command to check log
            $filesDamaged .= "Run: snapraid -f '$line' fix - To correct";
            # Logit @ Lv4
            logit(  text    => "Run: snapraid -f '$line' fix - To correct",
                    message => '',
                    level   => 4,
            );
          } 
          else {          
            # Call snapraid to fix - snap_fix sub needed! - Hum... How safe? - Maybe DANGEROUS option
          }
  
        }
        elsif ( $line =~ m/(?<megs>\d+?)\s+?MB\s+?processed/i ) {
          logit(  text    => "Check completed: Disk: $disk - $+{megs} MB processed",
                  message => "Check completed: Disk: $disk - $+{megs} MB processed",
                  level   => 3,
          );
        } 
        elsif ( $line =~ m/(?<errors>\d+?)\s+?errors/i ) {
          if ( $+{errors} > 0 ) {
            logit(  text    => "Warning: Check on disk $disk shows $+{errors} errors",
                    message => "Warn: Check on disk $disk shows $+{errors} errors",
                    level   => 2,
                  );
          }
        }
        elsif ( $line =~ m/(?<unrerrors>\d+?)\s+?unrecoverable/i ) {
          if ( $+{unrerrors} > 0 ) {
          logit(  text    => "Critical: Check on disk $disk shows $+{unrerrors} unrecoverable errors",
                  message => "Crit: Check on disk $disk shows $+{unrerrors} unrecoverable errors",
                  level   => 1,
                );
          }
        }
      }
      
      # Damaged files found so lets log them
      if ( $filesDamaged ) {
        # Writeout check log if need (Writes files names found damaged)
        my $checkLogFile = $opt{logFileLocation} . $slashType . "snapraidCheck-$disk.log";
        # Write file 
        my $fileWritten = write_file( filename  => $checkLogFile,
                                      contents  => \$filesDamaged,
                                    );
        # Logit if file did not write out
        if ( !$fileWritten ) {
          logit(  text    => "Warning: Unable to write check log - Please check $opt{logFileLocation} is writable", 
                  message => 'Warn: Unable to write check log',
                  level   => 2,
                );
        }
        else {
          logit(  text    => "Warning: Damaged files checking $disk - Please check log: $checkLogFile", 
                  message => "Warn: Damaged files checking $disk - Please check log: $checkLogFile",
                  level   => 2,
                );      
        }
      }
    }
    else {
      # Logit
      logit(  text    => "Check disk: $disk - Fail Percentage: $disksToProcess->{$disk}% - Checked within $opt{checkMinTimeBetweenChecks} days", 
              message => "Check disk: $disk - No check done min time not elapsed",
              level   => 3,
           );
    }
    # Change fp to time for storage in json file
    $disksToProcess->{$disk} = $timeNow;
  }
  
  # Save json and end warning if failed to save
  if ( !save_json( $jsonCheckFile, $disksToProcess ) ) {
    logit(  text    => "Warning: Unable to write to: $opt{jsonFileLocation}",
            message => 'Warn: Unable to write to json dir',
            level   => 2,
          );
  }
  
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
# Create pool if valid config option exists
# usage snap_pool();
# return void
sub snap_pool {

  # Check for pool entry in snapraid config and it exists
  if ( $conf{pool} and -d $conf{pool} ) {

    # Run snapraid pool command
    my ( $output, $exitCode ) = snap_run( opt => '', cmd => 'pool' );

    # Get number of links created
    my ( $links ) = $output =~ m/(\d+?)\s+?links/i;
    if ( $links ) {
      logit(  text    => "Pool command run and $links links created in $conf{pool}", 
              message => "Pool run and $links links created",
              level   => 3,
            );
    }
    else {
      logit(  text    => "Warning: Pool command failed for location $conf{pool}", 
              message => "Warn: Pool command failed",
              level   => 2,
            );    
    }
  }
  # Not a valid directory?
  elsif ( not -d $conf{pool} ) {
    logit(  text    => "Warning: Unable to pool location if config file not a valid directory - Value: $conf{pool}", 
            message => "Warn: Pool setting in conf file not valid",
            level   => 2,
          );
  }
  # No value for pool parsed from snapraid.conf 
  else {
    logit(  text    => 'Warning: Pool option set but no entry in snapraid conf file', 
            message => 'Warn: No pool location in snapraid conf',
            level   => 2,
          );
  }
  return;
}

##
# sub snap_run
# Run a snapraid command
# usage snap_run( opt => 'options', cmd => 'command', snaplog => 0|1, stderr => 0|1 );
# returns stdout, exitcode, *opt snaplog, *opt stderr (Will return all four but opt will be undef if not called for)
sub snap_run {

  # Get passed args
  my %cmdArgs    = @_;
  
  # Define file names - sndout/stderr/log are all saved for each command between runs - Any issues lots of logs to check back on
  my $snapLogFile = $opt{logFileLocation}     . $slashType . "snapraid-$cmdArgs{cmd}.log";
  my $stderrFile  = $opt{snapRaidTmpLocation} . $slashType . "snapraid-$cmdArgs{cmd}-stderr.tmp";
  my $stdoutFile  = $opt{snapRaidTmpLocation} . $slashType . "snapraid-$cmdArgs{cmd}-stdout.tmp";

  # Build command
  my $snapCmd     = "$opt{snapRaidBin} -c $opt{snapRaidConf} -l $snapLogFile -v $cmdArgs{opt} $cmdArgs{cmd} 1\>$stdoutFile 2\>$stderrFile";
  my $snapCmdLog  = "$opt{snapRaidBin} -c $opt{snapRaidConf} -l $snapLogFile -v $cmdArgs{opt} $cmdArgs{cmd}";

  # Log command to be run
  logit(  text    => "Running: $snapCmdLog",
          message => '',
          level   => 4,
        );
        
  my $exitCode;
  # OS Base?
  if ( $osName eq 'MSWin32' ) {
    $exitCode = system($snapCmd);
  }
  else {
    # Expand path for snapraid.exe call to smartctl
    local $ENV{PATH} = "$ENV{PATH}:/usr/sbin"; 
    # Run command
    $exitCode = system($snapCmd);
  }

  # Slurp in stndout/stderr/log from last call
  my $cmdStdout   = slurp_file($stdoutFile);
  # Slurp in only if requested by caller;
  my $cmdLogData;
  if ( $cmdArgs{snaplog} ) { $cmdLogData = slurp_file($snapLogFile); }
  # Slurp in only if requested by caller;
  my $cmdStderr;
  if ( $cmdArgs{stderr} ) { $cmdStderr = slurp_file($stderrFile); }
  
  # Check we have the information needed to proceed
  if ( not defined $cmdStdout and $cmdArgs{stderr} ) {
    logit(  text    => "Abort: Unable to read stndout file:- $stdoutFile - Please check $opt{snapRaidTmpLocation} is writable",
            message => 'Abort: Unable to read stndout file',
            level   => 2,
            abort   => 1,
          );
  }
  elsif ( not defined $cmdLogData  and $cmdArgs{snaplog} ) {
    logit(  text    => "Abort: Unable to read log file:- $snapLogFile - Please check $opt{logFileLocation} is writable",
            message => 'Abort: Unable to read log file',
            level   => 2,
            abort   => 1,
          );
  }
  
  
  # Get file size of stderr file
  my @stderrStat = stat $stderrFile;

  # stderr file is NOT empty indicating snapraid wrote to stderr
  if ( $stderrStat[7] > 0 and $cmdArgs{snaplog} ) {
    # Snaprard wrote to stderr. Add this to log for further investigation
    # I did abort here but found out snapraid writes to stderr for none fatal warnings
    # Can not trust that Exit Code:0 only means OK so pass back to caller for some checking
    $cmdLogData .= "msg:status:snderr:size:$stderrStat[7]";
  }
  else {
    # stnderr empty :P
    $cmdLogData .= 'msg:status:snderr:size:0';
  }

  # Pass stdout / exitcode / log / stderr back to caller
  return ( $cmdStdout, $exitCode, $cmdLogData, $cmdStderr );

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

      # Process parity - Snapraid v11.0 added multi parity files per parity level. Modified to collect these! (\A forces an anchor and strips main parity entry)
      if ( $key =~ m/\Aparity/i ) { 
        my @parityFiles = split(/\,/, $value );
        foreach my $parityFile ( @parityFiles ) {
          $parityFile =~ s/^\s+|\s+$//g; 
          $conf{$key}[ $#{ $conf{$key} } + 1 ] = $parityFile;
        }
        next;
      }
      
      # Process extra parity - Snapraid v11.0 added multi parity files per parity level. Modified to collect these!
      if ( $key =~ m/.+?parity/i ) { 
        my @parityFiles = split(/\,/, $value );
        foreach my $parityFile ( @parityFiles ) {
          $parityFile =~ s/^\s+|\s+$//g; 
          $conf{xparity}->{$key}[ $#{ $conf{xparity}{$key} } + 1 ] = $parityFile;
        }
        next;
      }

      # Process other options and add to hash-array
      elsif ( $key =~ m/content|exclude|share/i ) { 
        $conf{$key}->[ $#{ $conf{$key} } + 1 ] = $value; 
        next;
      }

      # Process data disks
      elsif ( $key =~ m/disk|data/i ) {
        my ( $drive, $path ) = split(/\s/, $value, 2);
        $drive  =~ s/^\s+|\s+$//g;
        $path   =~ s/^\s+|\s+$//g;
        $conf{data}->{$drive} = $path;
        next;
      }

      # Process smart options
      elsif ( $key =~ m/smartctl/i ) {
        my ( $drive, $smartCmd ) = split(/\s/, $value, 2);
        $drive      =~ s/^\s+|\s+$//g;
        $smartCmd   =~ s/^\s+|\s+$//g;
        $conf{$key}->{$drive} = $smartCmd;
        next;
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

  # Load json as a data reference
  my $preConfRef = load_json($jsonConfFile);
     
  # Conf file changed? 
  if ( !compare_data_structure(\%conf, $preConfRef) ) {
    logit(  text    => "Warning: $opt{snapRaidConf} file changed since last run. If this is expected please ignore",
            message => 'Warn: Snapraid conf file changed!',
            level   => 2,
          );
  }
 
  # Save json and end warning if failed to save
  if ( !save_json( $jsonConfFile, \%conf ) ) {
    logit(  text    => "Warning: Unable to write to: $opt{jsonFileLocation}",
            message => 'Warn: Unable to write to json dir',
            level   => 2,
          );
  }
  
  return;
}

##
# sub check_conf
# Check to values loaded from conf file for sanity. Abort if critical issue found
# usage check_conf();
# return void
sub check_conf {

  # Set to 1 to abort
  my $invalidConf = 0;
 
  # Check parity - Does not support checking extra files in v11.0. Don't know yet if snapraid creates these files before it uses them!
  if ( not defined $conf{parity}[0] or not -e $conf{parity}[0] ) { 
    # No parity file - Set flag to abort
    $invalidConf = 1;
    # Prevents undefined warning if not loaded from config!
    my $parity = defined $conf{parity}[0] ? $conf{parity}[0] : 'Not loaded from config';
    
    logit(  text    => "Warning: Missing parity file: $parity",
            message => "Warn: Missing parity file: $parity",
            level   => 2,
          );
    logit(  text    => 'Warning: Parity not mounted or not built?',
            message => 'Warn: Parity not mounted or not built?',
            level   => 2,
          );
  }
  
  # Check all data locations exist
  foreach my $confKey ( sort(keys %{ $conf{data} }) ) { 
    if ( not -d $conf{data}->{$confKey} ) { 
      # Missing data location - Set flag to abort
      $invalidConf = 1;
      logit(  text    => "Warning: Missing data drive: $conf{data}->{$confKey}",
              message => "Warn: Missing data drive: $conf{data}->{$confKey}",
              level   => 2,
            );
    }
  }

  # Check each content file listed exists
  my $anyValidContent = 0;
  for ( my $i = 0 ; $i <= $#{ $conf{content} } ; $i++ ) {
    if ( not -e $conf{content}->[$i] ) { 
      logit(  text    => "Warning: Missing content file: $conf{content}->[$i]",
              message => "Warn: Missing content file: $conf{content}->[$i]",
              level   => 2,
            );
    } 
    else { 
      # At least one valid content file exist. So we don't abort and let snapraid handle it
      $anyValidContent = 1; 
    } 
  }
  # No valid content file - Set flag to abort
  if ( not $anyValidContent ) { $invalidConf = 1; }
  
  # Check each extra parity exists - Does not support checking extra files in v11.0. Don't know yet if snapraid creates these files before it uses them!
  foreach my $xparity ( keys %{$conf{xparity}} ) {
      if ( not defined $conf{xparity}->{$xparity} or not -e $conf{xparity}->{$xparity}[0] ) { 
        # Missing extra parity file - Set flag to abort
        $invalidConf = 1;
        # Prevents undefined warning if not loaded from config!
        my $parity = defined $conf{xparity}->{$xparity}[0] ? $conf{xparity}->{$xparity}[0] : 'Not loaded from config';
        logit(  text    => "Warning: Missing parity file: $conf{xparity}->{$xparity}[0]",
                message => "Warn: Missing parity file: $conf{xparity}->{$xparity}[0]",
                level   => 2,
              );
        logit(  text    => 'Warning: Parity not mounted or not built?',
                message => 'Warn: Parity not mounted or not built?',
                level   => 2,
              );
      }
  }
  
  if ( $invalidConf ) {
    logit(  text    => 'Critical: Invalid snapraid conf file - Aborting',
            message => 'Crit: Invalid snapraid conf - Abort',
            level   => 1,
            abort   => 1,
          );
  }
  
  return;
}

##
# sub get_opt_hash
# Build option hash from options in optionsfile into package wide hash %opt;
# usage get_opt_hash();
# return void
sub get_opt_hash {

  # Hold value of lowest LogLevel reached
  $opt{minLogLevel} = 5;
  
  # Options hash
  my $options;

  # Slurp the options file :P
  $options = slurp_file($optionsFile);

  # Cycle though options and build hash
  foreach my $optin ( split(/\n/, $options) ) {

    # Ignore lines without options in them
    if ( $optin =~ m/=/ ) {

      # Lexical s
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
  
  # Call to validate loaded conf file
  my $valid = validate_conf();
  
  # Invalid conf file?
  if ( not $valid ) {
    # Don't use logit(); Missing values in conf file. Abort
    say 'Abort: Loaded conf file not valid - Please check your file against snapPERL.conf.example';
    say 'This can happen when upgrading to a new versions with changed or added options';
    say 'See list of missing options given by script';
    # Exit
    exit(1);
  }
  
  # Get hostname
  $opt{hostname} = qx{hostname};
  # Remove vertical whitespace from hostname (Email issue)
  $opt{hostname} = uc($opt{hostname});
  chomp($opt{hostname});
    
  # If not defined in config file (Normal situation)
  if ( !$opt{snapRaidTmpLocation} ) { $opt{snapRaidTmpLocation} = $scriptPath . 'tmp'; }
  
  # If not defined in config file (Normal situation)
  if ( !$opt{logFileLocation} ) { $opt{logFileLocation} = $scriptPath . 'log'; }
  
  # Define location for script json files (Files that hold information about previous runs)
  $opt{jsonFileLocation} = $scriptPath . 'json';
  
  # Set options to command line overrides - If not sent on command line then they use values from conf
  foreach my $option (keys %argv) {
    # Value taken from command line
    if ( defined $argv{$option} ) {
      # Replace value read from conf file in %opt hash
      $opt{$option} = $argv{$option};
    }
  }
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
  if ( $opt{logFile} and $scriptLog ) { 
    my $logOutFile = $opt{logFileLocation} . $slashType . $opt{logFile};
    my $fileWritten = write_file( filename  => $logOutFile,
                                  contents  => \$scriptLog,
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
  
  if ( $opt{useCustomCmds} ) {

    # Run post commands
    custom_cmds('post');
  }
  
  return;
}

##
# sub email_send
# Send the scriptLog out via email;
# usage email_send();
# return 0 if unable load modules else undef
sub email_send {
  
  # Add alert to subject line if warnings or errors encountered.
  my $subjectAlert;
  if ( $opt{minLogLevel} < 3 ) {
    $subjectAlert = $opt{minLogLevel} < 2 ? 'Critical' : 'Warning';
  }
  else {
    $subjectAlert = '';
  }

  # Use email.
  if ( $opt{emailSend} ) {

    # Load on demand need modules for email sending
    my $loadFail;
    eval { autoload Email::Send };            if ($@) { $loadFail += 'Email::Send '; }
    eval { autoload Email::Simple::Creator }; if ($@) { $loadFail += 'Email::Simple::Creator '; }
    
    # Modules did not load
    if ( $loadFail ) {
      logit(  text    => "Warning: Failed to load modules for Email: $loadFail",
              message => 'Warn: Failed to load modules for Email',
              level   => 2,
            );
      # Return to caller with false boolean
      return 0;
    }

    if ( $opt{emailUseSendmail} ) {
      # Create mail object
      my $sender = Email::Send->new();
      # Is sendmail avalible?
      if ( $sender->mailer_available('Sendmail') ) {
        # Set mailer
        $sender->mailer('Sendmail');
        # Create the email!
        my $email = Email::Simple->create(
          header => [
                      From  => $opt{emailFromAddress}, 
                      To    => $opt{emailToAddress}, 
                      Subject => "$subjectAlert \[$opt{hostname}\] - snapPERL Log. Please see message body",
                    ],
          body => $scriptLog,
        );
        # Send email
        my $return = eval { $sender->send($email) };
        if ($@) { 
        logit(  text    => "Warning: Sendmail send failed:-  $@",
                message => 'Warn: Sendmail send failed',
                level   => 2,
              );
        }
        elsif ( $return !~ m/Message\ssent/i or $return != 1 ) {
          logit(  text    => "Warning: Sendmail send failed: $return",
                  message => 'Warn: Sendmail send failed',
                  level   => 2,
                );
        }
      }
      else {
        logit(  text    => 'Warning: Email::Send::Sendmail not found. Please install Cpan module Email::Send::Sendmail',
                message => 'Warn: Email::Send::Sendmail not found',
                level   => 2,
              );        
      }
    }
    
    if ( $opt{emailUseGmail} ) {
      # Create mail object
      my $sender = Email::Send->new();
      # Is sendmail avalible?
      if ( $sender->mailer_available('Gmail') ) {
        # Set mailer
        $sender->mailer('Gmail');
        # Set args
        $sender->mailer_args(
          [
            username => $opt{emailGmailUser},
            password => $opt{emailGmailPass},
          ]
        );
        # Create the email!    
        my $email = Email::Simple->create(
          header => [
                      From  => $opt{emailGmailUser}, 
                      To    => $opt{emailGmailToAddress}, 
                      Subject => "$subjectAlert \[$opt{hostname}\] - snapPERL Log. Please see message body",
                    ],
          body => $scriptLog,
        );
        # Send email
        my $return = eval { $sender->send($email) };
        if ($@) { 
        logit(  text    => "Warning: Gmail send failed:  $@",
                message => 'Warn: Gmail send failed',
                level   => 2,
              );
        }
        elsif ( $return != 1 ) {
          logit(  text    => "Warning: Gmail send failed: $return",
                  message => 'Warn: Gmail send failed',
                  level   => 2,
                );
        }
      }
      else {
        logit(  text    => 'Warning: Email::Send::Gmail not found. Please install Cpan module Email::Send::Gmail',
                message => 'Warn: Email::Send::Gmail not found',
                level   => 2,
              );        
      }
    }
    
    if ( $opt{emailUseSmtp} ) {
      # Create mail object
      my $sender = Email::Send->new();
      # Is sendmail avalible?
      if ( $sender->mailer_available('SMTP') ) {
        # Set mailer
        $sender->mailer('SMTP');
        # Set args
        $sender->mailer_args(
          [
            Host      => $opt{emailSmtpAddress},
            Port      => $opt{emailSmtpPort},
            username  => $opt{emailSmtpUser},
            password  => $opt{emailSmtpPass},
            ssl       => $opt{emailSmtpSSL},
          ]
        );
        # Create the email!    
        my $email = Email::Simple->create(
          header => [
                      From  => $opt{emailSmtpFromAddress}, 
                      To    => $opt{emailSmtpToAddress}, 
                      Subject => "$subjectAlert \[$opt{hostname}\] - snapPERL Log. Please see message body",
                    ],
          body => $scriptLog,
        );
        # Send email
        my $return = eval { $sender->send($email) };
        if ($@) { 
        logit(  text    => "Warning: SMTP send failed:-  $@",
                message => 'Warn: SMTP send failed',
                level   => 2,
              );
        }
        elsif ( $return !~ m/Message\ssent/i or $return != 1 ) {
          logit(  text    => "Warning: SMTP send failed: $return",
                  message => 'Warn: SMTP send failed',
                  level   => 2,
                );
        }
      }
      else {
        logit(  text    => 'Warning: Email::Send::SMTP not found. Please install Cpan module Email::Send::SMTP',
                message => 'Warn: Email::Send::SMTP not found',
                level   => 2,
              );        
      }
    }
  }
  return;
}

##
# sub send_message_po();
# Sends message to Pushover API 
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

  # Priority 2 can only be used with expire and retry
  if ( (not defined $optHash{expire} or not defined $optHash{retry}) and $optHash{poPriority} == 2) { $optHash{poPriority} = 1; }

  # Make sure expire setting is no less then 30 or more than 86400 seconds
  if ( defined $optHash{expire} ) { 
    $optHash{expire} = $optHash{expire} < 30 ? 30 : $optHash{expire}; 
    $optHash{expire} = $optHash{expire} < 86400 ? 86400 : $optHash{expire};
  }
  
  # Make sure expire setting is no less then 30 seconds
  if ( defined $optHash{expire} ) { 
    $optHash{retry} = $optHash{retry} < 30 ? 30 : $optHash{retry}; 
  }

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

  # File exists?
  if ( -e $customCmdsFile ) {
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
  }
  else {
    logit(  text    => "Warning: Custom Commands file: $customCmdsFile not found",
            message => 'Warn: custom-cmds file not found',
            level   => 2,
          );
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
      logit(  text    => "Running custom $type command: $customCmds{$type}->[$i]",
              message => '',
              level   => 3,
            );
      eval { system( $customCmds{$type}->[$i] ) };
      if ($@) { 
      logit(  text    => "Warning: Custom-cmd: $customCmds{$type}->[$i] failed... $@",
              message => 'Warn: Custom-cmd: $customCmds{$type}->[$i] failed',
              level   => 2,
            );
      }
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
      local $/ = undef;       # Don't clobber global version. Normally holds 'newline' and reads one line at a time
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
# returns formatted timestamp
sub time_stamp {

  # Define month names
  my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

  # Define day names
  my @days = qw( Sun Mon Tue Wed Thu Fri Sat Sun );

  # Get current time
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();

  # Convert to full 4 digit year
  my $fullYear = $year + 1900;

  # Return formatted timestamp
  return sprintf( "%02d:%02d:%02d %d %s %d", $hour, $min, $sec, $mday, $months[$mon], $fullYear );

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
  
  # Check incoming hash
  if ( not $logIn{level} or $logIn{level} < 0 or $logIn{level} > 5 ) { $logIn{level} = 3; }
  if ( not $logIn{text} and not $logIn{message} ) { 
    $logIn{text} = 'DEBUG: No message sent to logit'; 
    $logIn{level} = 5;
  }

  # Variable holds lowest log level reached. 1 for Critical, 2 for Warning and 3 for Normal
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
 
    # Log before killing script (Recursive call) - Already aborting so abort tag not needed and would create an infinite loop
    logit(  text    => 'Fatal issue encountered. Please see logs',
            message => 'Fatal issue encountered. Please see logs',
            level   => 3,
            abort   => 0, # Never change to 1 (Infinite Loop)
          ); 
   
    # Cleanup
    script_comp();
    
    # Add debug information to log
    if ( $opt{logLevel} >= 5 ) { debug_log(); }

    # Kill script - Return 1 indicating fatal exit
    exit(1);
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
    print {$fh} ${ $fileParams{contents} };
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

##
# sub save_json();
# Encode and write json data to file
# usage load_json( filename, \%@data );
# returns 1 if success and 0 if not
sub save_json {
  
  # Get incomming data
  my $jsonFileName  = shift;
  my $dataRef       = shift;
  
  # Json object
  my $json = JSON::PP->new;
  $json = $json->canonical(1);
  
  # Encode incomming data to json
  my $jsonOut = $json->encode($dataRef);

  # Write out to json directory
  my $fileWritten = write_file( filename  => $jsonFileName,
                                contents  => \$jsonOut,
                               );
  # File written OK?
  if ( !$fileWritten ) {
    # Return fail
    return 0;
  }
  else {
    # Success return 1
    return 1;
  }
  return;
}

##
# sub load_json();
# Read json data from file and decode
# usage load_json( filename );
# returns json data ref if success and undef if not
sub load_json {
  
  # Get json file name
  my $jsonFileName = shift;
   
  # Create Json object
  my $json = JSON::PP->new;
  $json = $json->canonical(1);
 
  # Load json file 
  my $jsonIn = slurp_file($jsonFileName);
 
  # Decode and return json
  if ( $jsonIn ) {
    # Decode json
    my $jsonRef = $json->decode($jsonIn);
    # Return ref to json data
    return $jsonRef;      
  }
  else {
    # Invalid then return undef;
    return;
  }   
  return;
}

##
# sub comp_data_structure();
# Compare two data structures you expect to be identical
# Recursive self calling. Will follow down no mater how many levels or types
# usage comp_data_structure( \%|@refData1, \%|@refData2 );
# returns 1 if data structures match perfect and 0 if not
sub compare_data_structure {
  
  my ($dataRef1, $dataRef2) = @_;
  
  # Sent hash refs?
  if ( ref $dataRef1 eq 'HASH' and ref $dataRef2 eq 'HASH' ) {
    foreach my $key ( keys %{$dataRef1} ) {
      #Check keys
      if ( not exists $dataRef2->{$key} ) {
        # Return false
        return 0;
      }
      # Check values
      if ( $dataRef1->{$key} ne $dataRef2->{$key} ) {
        if ( (ref $dataRef1->{$key} eq 'HASH' and ref $dataRef2->{$key} eq 'HASH') or (ref $dataRef1->{$key} eq 'ARRAY' and ref $dataRef2->{$key} eq 'ARRAY') ) {
          # Recursive call on self 
          if ( !compare_data_structure($dataRef1->{$key}, $dataRef2->{$key}) ) { return 0; }
        }
        else { 
          # Return false
          return 0;
        }
      }
    }
  }
  # Sent Array refs?
  elsif ( ref $dataRef1 eq 'ARRAY' and ref $dataRef2 eq 'ARRAY' ) {
    for ( my $i = 0; $i <= $#{ $dataRef1 }; $i++ ) {
      if ( $dataRef1->[$i] ne $dataRef2->[$i] ) {
        if ( (ref $dataRef1->[$i] eq 'HASH' and ref $dataRef2->[$i] eq 'HASH') or (ref $dataRef1->[$i] eq 'ARRAY' and ref $dataRef2->[$i] eq 'ARRAY') ) {
          # Recursive call on self
          if ( !compare_data_structure($dataRef1->[$i], $dataRef2->[$i]) ) { return 0; }
        }
        else { 
          # Return false
          return 0;
        }
      }
    }
  }
  else {
    # Sent mixed refs?
    return 0;
  }
  # Gets here then it all matched! - Return true
  return 1; 
}

##
# sub debug_log
# Called if logLevel set to 5 (Debug).
# Dumps the contents of the main scrip hashes
# usage debug_log();
# return void
sub debug_log {

  # Dump contents of hashes to stdout 
  say Data::Dumper->Dump( [ \%argv        ],  [ qw(*argv)       ] );
  say Data::Dumper->Dump( [ \%opt         ],  [ qw(*opt)        ] );
  say Data::Dumper->Dump( [ \%conf        ],  [ qw(*conf)       ] );
  say Data::Dumper->Dump( [ \%customCmds  ],  [ qw(*customCmds) ] );
  say Data::Dumper->Dump( [ \%diffHash    ],  [ qw(*diffHash)   ] );

  return;
}

##
# Sub validate_conf
# Called to validate conf file and check it contains all required options - Carps to sndout
# Will add and change values here as I add and change in options snapPERL.conf.example
# usage validate_conf();
# return 1 if valid and 0 if not
sub validate_conf {

  # Conf is valid unless found to be otherwise
  my $isValid = 1;
  
  # Anonymous hash containing values that should exisit in conf file
  my $validate = { 
    syncOptions       => [ qw( deletedFiles changedFiles )                                                                                                            ],
    scrubOptions      => [ qw( scrubEnable scrubNewest scrubOldest scrubAge scrubPercentage useScrubNew scrubEnforceMinDays )                                         ],
    smartOptions      => [ qw( smartLog smartWarn smartDiskWarn smartMaxDriveTemp smartDiskErrorsWarn)                                                                ],
    checkOptions      => [ qw( checkSuspectDisks checkAuditOnly checkOnlyAfterIncrease checkDiskFailPercentage checkMinTimeBetweenChecks checkAutoFix)                ],
    snapOptions       => [ qw( snapRaidBin snapRaidConf preHashOnSync resetTimeStamps spinDown pool)                                                                  ],
    otherOptions      => [ qw( logFile messageLevel logStdout useCustomCmds noVersionWarnings )                                                                       ],
    emailOptions      => [ qw( emailSend emailUseSendmail emailFromAddress emailToAddress )                                                                           ],
    smtpOptions       => [ qw( emailUseSmtp emailSmtpFromAddress emailSmtpToAddress emailSmtpAddress emailSmtpPort emailSmtpSSL emailSmtpUser emailSmtpPass )         ],
    gmailOptions      => [ qw( emailUseGmail emailGmailToAddress emailGmailUser emailGmailPass )                                                                      ],
    pushoverOptions   => [ qw( pushOverSend pushOverKey pushOverToken pushOverUrl pushDefaultPriority pushWarningPriority pushCriticalPriority pushSound pushDevice ) ],
    #nmaOptions        => [ qw( nmaSend ) ],
    #pushbulletOptions => [ qw( pushBulletSend ) ],
  }; 
  
  # Cycle though $validate and confirm all options listed loaded from conf file (Check conf updated with new options)
  foreach my $optionGroup ( keys %{$validate} ) {
    foreach my $option ( @{$validate->{$optionGroup}} ) {
      # Check for missing option
      if ( not exists $opt{$option} ) {
        # Carp to stdout and set flag
        say "snapPERL conf file missing option :: Group: $optionGroup -> Option: $option=";
        $isValid = 0;
      }
    }
  }
  
  return $isValid;
}

##
# sub show_cmdline_help
# Called to display help when called from command line
# usage show_cmdline_help();
# return exit(0)
sub show_cmdline_help {

  # Show Version
  say "snapPERL v$VERSION by Steve Miles (2016) - snapperl.stevemiles.me.uk";
  
  # Show help
  if ( $argv{help} ) {
    # Build help
    my $help = q(
    snapPERL.pl [ -c  --conf CONFIG         { Full path to conf file        } ]
                [ -x  --custom-cmds FILE    { Full path to custom-cmds file } ]
                [ -m  --message-level 1-3   { Set message level             } ]
                [ -l  --log-level 1-5       { Set log level                 } ]
                [ --stdout    --nostdout    { Toggle log to stdout          } ]
                [ --check     --nocheck     { Toggle check option enable    } ]
                [ --scrub     --noscrub     { Toggle scrub option enable    } ]
                [ --email     --noemail     { Toggle email send             } ]
                [ --custom    --nocustom    { Toggle custom cmds            } ]
                [ --pushover  --nopushover  { Toggle Pushover send          } ]
                [ --smart     --nosmart     { Toggle smart logging          } ]
                [ --pool      --nopool      { Toggle snapraid pool          } ]
                [ --spindown  --nospindown  { Toggle spindown disks         } ]
                [ -h  --Help                { This Help                     } ]
                [ -v  --version             { Display Version               } ]
    );
    
    # Display help
    say $help;
  }
  
  # Exit script - version and help cause end of script!
  exit (0);
}

#-------- Subroutines End --------#

# Return true at end of script
1;

__END__
