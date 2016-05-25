# Install Instructions Windows

### Required Perl Modules - These will autoload on demand
~~~
Email::Send (If using email)              ->  command: ppm install Email::Send            - (Normaly installed by default)
Email::Send::SMTP (If using SMTP)         ->  command: ppm install Email::Send::SMTP      - (Normaly installed by default)
Email::Send::Sendmail (If using Sendmail) ->  command: ppm install Email::Send::Sendmail  - (Normaly installed by default)
Email::Send::Gmail (If using gmail)       ->  command: ppm install Email::Send::Gmail
* commands listed are for ActivePerl in elevated command prompt
~~~ 

##Windows: 

You need Perl installed on windows. Options are:
* ActivePerl       - http://www.activestate.com/activeperl - Version I test on
* Strawberry Perl  - http://strawberryperl.com/
* DWIM Perl        - http://dwimperl.com/

~~~ Windows
1. Download http://snapperl.stevemiles.me.uk/downloads/latest/snapPERL-latest.zip
2. Extract to hard drive. Good place is C:\snapraid\snapPERL
3. Edit and rename snapPERL.conf.example to snapPERL.conf
4. Rename custom-cmds.example custom-cmds
5. Edit snapPERL.conf taking great care to enable Windows paths to conf and snapraid binary with correct full paths
6. See notes about email before trying to enable sendmail
7. Use PPM with ActivePerl to install needed modules (Or other Perl Package Manager installed)
8. From elevated command prompt run snapPERL.pl
~~~

#### Automation

~~~
Run Task Scheduler : Start Menu -> All Programs -> Accessories -> System tools -> Task Scheduler
                     Start Menu -> Administrative Tools -> Task Scheduler
                     Start menu -> Run -> C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Task Scheduler.lnk

Click 'Create Basic Task'

Enter Name: snapPERL
Enter Description: Snapraid automation wrapper
Click 'Next'

Set to Daily 
Click 'Next'

Set date and Time (Tomorrow @ 02:00:00) - Should have 1 in the Recur box
Click 'Next'

Select 'Start a Program'
Click 'Next'

Enter loction of script -Example C:\snapraid\snapPERL\snapPERL.pl
Add any command line arguments (Normaly none)
Click 'Next'

Click on 'Open the Properties dialog for this task when I click Finish'

Click 'Finish'

Click 'Change User or Group'
Enter 'Local' in box and click 'Check Names'
Select 'LOCAL SERVICE'

Click on 'Run with highest privileges (Snapraid needs to be elevated)

Under 'Settings' tab change max run time to '1 day'

Click 'OK'

Done!
~~~

WOW and GUI's make things more easy? :P
