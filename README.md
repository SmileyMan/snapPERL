# snapPERL v0.2.2

### Windows Compatible
#### Tested on Windows 10 - Snapraid x64 v10.0 and Latest ActivePerl 

Helper script for snapraid created in PERL

 Snapraid helper script written in PERL. Enables automation using cron for your Array Syncs

 Runs sync commands and verifys data using scrub command. Sends alerts when are issues found
 and aborts where needed. Tested with snapraid 10.0
 
#####Script is expected to be run as root so calls snapraid as root

 1.  Parses the $options scalar and builds %opt hash from this. These options are used
     thoughout the script. Built this was to make the option more human readable.

 2.  Parses the snapraid config file and puts the options into the %conf hash.

 3.  Runs snapraid status and checks for reported errors. If there is a sync in progress.
     Number of days since last scrub and finaly any sub-second timestamps. It will correct
     timestamp issues before moving on. Snapraid verion is logged.

 4.  Runs snapraid diff and puts all counts into %diff hash. Aborts if data not parsed.
     Sets diff{sync} if sync is required.

 5.  If diff shows sync need and changed/deleted files do not exceed limits set in $options
     a snapraid sync is run. If set the data if verified using the '-p new' option from
     snapraid 9.0 on. Script will abort if snapraid does not confirm Everything Ok!

 6.  If needed array is scrubbed using settings from $options. Scrub will not run unless a
     successfull sync has run. Scrub if run when age of newest scrubbed block exceeds limit
     set uing 'scrubDays' option of $options. If '-p new' option of snapraid 9.0+ is used then
     the check will be against the oldest scrub block against 'scrubOldest'

 7.  If active in $options snapraid pool command is run. This will be checked against valid
     option for snapraid conf file before running.

 8.  If active in $options snapraid smart is run and details parsed from output and logged
     warning will be sent based on Fail Percentage / Temp and Errors set in $options.

 9.  If active in $options snapraid down is run and array is spun down. Details are logged.

 10. Log file wrote to disk and any warnings/errors are sent out via email. This subrutine is 
     also called if the script aborts so messages are sent and log saved. $option 'logStdout'
     will also send the log to the screen as the script runs. Useful for debugging. Turn of
     off when run via a cron job. (Debug info sent to log if 'logLevel >= 5')

 11. Runs custom commands before and after script runs from custom-cmds file. See example for syntax



#Created by Steve Miles (SmileyMan). 

https://github.com/SmileyMan

Inspired by bash script http://zackreed.me/articles/83-updated-snapraid-sync-script 
by Zack Reed (http://zackreed.me)

Why PERL. Perl is cleaner. More powerfull and I can use HASH'es. Been over 10 years since
I worked with PERL and now remember why I loved it. Did not get on with BASH syntax!

#Work in Progress.

This is just a wrapper for snapraid.exe
and only ever calls snapraid (diff/status/sync/scrub/smart/down) so data should always be safe
(only snapraid.exe manipulates the data)

####Script passes Perl::Critic - Severity: Stern

###__This script does not write or manipulate and Array Data. It is a wrapper for snapraid http://www.snapraid.it/__

#Disclaimer

This SOFTWARE PRODUCT is provided by THE PROVIDER "as is" and "with all faults." 
THE PROVIDER makes no representations or warranties of any kind concerning the safety, 
suitability, lack of viruses, inaccuracies, typographical errors, or other harmful 
components of this SOFTWARE PRODUCT. There are inherent dangers in the use of any software,
and you are solely responsible for determining whether this SOFTWARE PRODUCT is compatible
with your equipment and other software installed on your equipment. You are also solely
responsible for the protection of your equipment and backup of your data, and THE PROVIDER
will not be liable for any damages you may suffer in connection with using, modifying, or 
distributing this SOFTWARE PRODUCT. 

