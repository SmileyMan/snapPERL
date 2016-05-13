# Install Instructions

### Required Perl Modules - These will autoload on demand
~~~
**Email::Send::Gmail** (If using gmail)  ->  command: sudo cpan install Email::Send::Gmail
**MIME::Lite**         (if using email)  ->  command: sudo cpan install MIME:Lite

Windows: 
(Basic first version of instuctions)
~~~ Windows
1. Download and extract zip. 
2. Edit and rename snapPERL.conf.example to snapPERL.conf
3. Rename custom-cmds.example custom-cmds
4. Use PPM with ActivePerl to install needed modules (Or other Perl Package Manager installed)
5. From elevated command prompt run snapPERL.pl
~~~

## Linux:

### This script does not write or manipulate any Array Data. It is a wrapper for snapraid http://www.snapraid.it/

### Feel free to test. All data manipulation is done by snapraid http://www.snapraid.it/

#### Install


Install Script:

~~~BASH
1. wget https://github.com/SmileyMan/snapPERL/archive/snapPERL-v0.2.1.tar.gz
2. tar -zxvf snapPERL-v0.2.2.tar.gz
3. mv snapPERL-v0.2.2 snapPERL
4. cd snapPERL
5. ./install.sh
6. Change settings in snapPERL.conf to suit
7. Change settings in custom-cmds to suit (Optional)
8. ./snapPERL.pl to run
~~~

Manual:

~~~BASH
1.  wget https://github.com/SmileyMan/snapPERL/archive/snapPERL-v0.2.1.tar.gz
2.  tar -zxvf snapPERL-v0.2.2.tar.gz
3.  mv snapPERL-v0.2.2 snapPERL
4.  cd snapPERL
5.  cp snapPERL.conf.example snapPERL.conf
6.  cp custom-cmds.example custom-cmds
7.  Change settings in snapPERL.conf to suit
8.  Change settings in custom-cmds to suit (Optional)
9.  Change attributes of files to suite (chmod 600 on snapPERL.conf highly recommended)
10. Install modules if needed (See top of this file)
11. ./snapPERL.pl to run
~~~

#### You can of course run as a root crontab. Be happy it does what you need first. 


Using git (This will pull latest master commit.. Not a release)

~~~BASH
1. sudo apt-get install git
2. git clone https://github.com/SmileyMan/snapPERL.git
3. Follow from number 4 above 
~~~
Update git

In snapPERL location on drive type
~~~BASH
git pull
~~~
This will not clobber your conf file but be sure to check for any new options

