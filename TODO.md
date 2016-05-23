
#Todo

           Once a drive is past warning level for Fail Percentage start weekly snapraid check on it audit-only (In Process v0.3)
           Snapraid sends WARNING! messages to stderr. Need to catch these. Currently script aborts for none fatals (v0.3)
           Add catches for snapraid DANGER! and Warning! messages (Plan v0.3)
           
           Scrape Log Files and STDOUT for command output processing (Plan v0.4)
           Move Logit messages to external file en_GB.lang to allow translations (Plan v0.4)

           Keep x amount of logs (Plan v0.5)
           Improve custom commands especialy regarding output and error checks (Plan v0.5)
           Limited command line options that overide conf settings (Plan v0.5)

           Add NMA support (Plan v0.6)
           Add Pushbullet support (Plan v0.6)
           Add email TLS support - Change to Email::Sender::SMTPS (Plan v0.6)

           Allow spindown setting per disk (Plan v0.7)
           Add dup command and report number of duplicates and disk space consumed (Plan v0.7)
  
           Go over code and clean (Ongoing)
           Drink beer! (Ongoing)

#Done
           
           Config data in external file (Done in v0.1)
           Custom commands at start and completion of script (rubylaser) (Done in v0.1)

           Catch snapraid.exe stderr and action/log it (Done in v0.2)
           Add pushover support and messages (Done v0.2)
           Warn for high disk temp (Done v0.2)
           Warn for logged errors on disk (Done v0.2)
           Make self contained for future growth (Done v0.2)
           Re-write log code to a single function (Done v0.2)
           Use carp for errors and warnings (Done v0.2)
           Code review (Done v0.2)
           Warn for disks with increasing values (Done 0.2)

           Portablity (Work with windows) (Done v0.2.2)

           Check and confirm conf file when loaded (Done v0.3)
           Send warning if conf file changed since last run (Done v0.3)
           Check data and parity disks are present (Done v0.3)
           Options to ignore disks not in array or not smart capable (Done v0.3)
           Add Pre-Hash option to config and script - Snapraid v10.0+ only (Done v0.3)
           Add email support and messages (All working v0.3))
           
#Removed
           Allow smart data per disk (Plan v0.4) - No snapraid support
           Add option to delete duplicates and re-sync (Adding symbolic refs if wanted) (Plan v0.4) - Breaks underlying rule to not touch data
           Big one - Check and auto update snapraid binary if enabled (Plan v1.0) - Potentialy dangerous and breaks underlying rule to not touch data
