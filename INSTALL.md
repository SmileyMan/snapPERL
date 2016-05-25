# Install Instructions

### Required Perl Modules - These will autoload on demand
~~~
Email::Send (If using email)              ->  command: sudo cpan install Email::Send            - (Normaly installed by default)
Email::Send::SMTP (If using SMTP)         ->  command: sudo cpan install Email::Send::SMTP      - (Normaly installed by default)
Email::Send::Sendmail (If using Sendmail) ->  command: sudo cpan install Email::Send::Sendmail  - (Normaly installed by default)
Email::Send::Gmail (If using gmail)       ->  command: sudo cpan install Email::Send::Gmail
~~~ 
## Linux:

#### This script does not write or manipulate any Array Data. It is a wrapper for snapraid http://www.snapraid.it/

#### Feel free to test. All data manipulation is done by snapraid http://www.snapraid.it/

##### Install


Install Script:

~~~BASH
1. wget http://snapperl.stevemiles.me.uk/downloads/latest/snapPERL-latest.zip
2. tar -zxvf snapPERL-latest.zip
3. mv snapPERL-latest snapPERL
4. cd snapPERL
5. ./install.sh
6. Change settings in snapPERL.conf to suit
7. Change settings in custom-cmds to suit (Optional)
8. ./snapPERL.pl to run
~~~

Manual:

~~~BASH
1.  wget http://snapperl.stevemiles.me.uk/downloads/latest/snapPERL-latest.zip
2.  tar -zxvf snapPERL-latest.zip
3.  mv snapPERL-latest snapPERL
4.  cd snapPERL
5.  cp snapPERL.conf.example snapPERL.conf
6.  cp custom-cmds.example custom-cmds
7.  Change settings in snapPERL.conf to suit
8.  Change settings in custom-cmds to suit (Optional)
9.  Change attributes of files to suite (chmod 600 on snapPERL.conf highly recommended)
10. Install modules if needed (See top of this file)
11. ./snapPERL.pl to run
~~~

### Using git (This will pull latest master commit.. Not a release)

~~~
1. sudo apt-get install git
2. git clone https://github.com/SmileyMan/snapPERL.git
3. Follow from number 4 above 
~~~
Update git

In snapPERL location on drive type
~~~
git pull
~~~
This will not clobber your conf file but be sure to check for any new options

Bleeding edge Dev version
~~~
git pull
pit merge origin/Dev
~~~
Test first on a new clone - I do break it now and again (I write on machines with no testing enviroment and commit to check when I get home)

##### You can of course run as a root crontab. Be happy it does what you need first. 
~~~
sudo crontab -e
~~~
Add
~~~
0 2 * * * ~/scripts/snapPERL/snapPERL.pl > /dev/null 2>&1
~~~
This will run every moring at 2am (Location can be anywhere this is just mine)

##### SystemD instructions - Instead of Cron

Timer file
~~~
sudo nano /etc/systemd/system/snapPERL.timer
~~~
Enter
~~~
[Unit]
Description="SnapPERL a SnapRAID automation wrapper"

[Timer]
OnCalendar=02:00
Unit=snapPERL.service

[Install]
WantedBy=multi-user.target
~~~

Service file
~~~
sudo nano /etc/systemd/system/snapPERL.service
~~~
Enter
~~~
[Unit]
Description="SnapRAID Wrapper Script for sync/scrub and much more"

[Service]
Type=simple
ExecStart=
ExecStart=/root/scripts/snapPERL/snapPERL.pl
~~~

To enable the timer
~~~
sudo systemctl enable snapPERL.timer
~~~
