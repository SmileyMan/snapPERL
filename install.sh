#!/bin/bash

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
chmod 644 custom-cmds
chmod 766 run/
chmod 766 tmp/
chmod 766 log/
echo "Attributes set"
