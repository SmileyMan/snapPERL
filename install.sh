#!/bin/bash

#v0.2 install script! - Linux only

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

SCRIPT=snapPERL.pl
CONF=snapPERL.conf
CCMD=custom-cmds

if [ ! -f "$SCRIPT" ]
then
    echo "Must be run in snapPERL script directory"
    exit 1
fi

if [ ! -f "$CONF" ]
then
    echo "Creating snapPERL.conf"
    cp snapPERL.conf.example snapPERL.conf
fi

if [ ! -f "$CCMD" ]
then
    echo "Creating custom-cmds"
    cp custom-cmds.example custom-cmds
fi

echo "Setting access attributes"
chmod +x snapPERL.pl
chmod 600 snapPERL.conf
chmod 640 custom-cmds
chmod 740 json/
chmod 740 tmp/
chmod 740 log/
echo "Attributes set"

echo "Install optional modules."

echo -n "Are you going to use email? [y/n]"
read -n 1 email

if  [ "$email" == "y" ]; then
  echo ""
  echo "Installing MIME::Lite"
  cpan install MIME::Lite
elif [ "$email" == "n" ]; then
  echo ""
  echo "Email module not installed"
else
  echo ""
  echo "Invalid option please run script again!"
fi

echo -n "Are you going to use gmail? [y/n]"
read -n 1 gmail

if  [ "$gmail" == "y" ]; then
  echo ""
  echo "Installing Email::Send::Gmail"
  cpan install Email::Send::Gmail
elif [ "$gmail" == "n" ]; then
  echo ""
  echo "Gmail modules not installed"
else
  echo ""
  echo "Invalid option please run script again!"
fi

echo ""
echo "INSTALL COMPLETED. snapPERL Script should be run as ROOT so snapraid.exe is called as ROOT"
echo ""
echo "Please now edit snapPERL.conf and custom-cmds to your needs"
echo ""
