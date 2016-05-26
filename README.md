# snapPERL v0.3.0

#####Helper script for snapraid created in PERL

 Snapraid wrapper script written in PERL. Enables automation using cron for your Array Syncs

 Runs sync commands and verifys data using scrub command. Sends alerts when are issues found
 and aborts where needed. Tested with snapraid v10.0

## Website: http://snapperl.stevemiles.me.uk

### Linux Compatible
#### Tested on Ubuntu 16.04LTS

### Windows Compatible
#### Tested on Windows 10 - Snapraid x64 v10.0 and Latest ActivePerl 
 
#####Script is expected to be run as root so calls snapraid as root

#### _Please Read!_

CHANGELOG
INSTALL.md
INSTALL-WINDOWS.md
LICENSE

_And the extensive comments for the options in: snapPERL.conf.example_


#Created by Steve Miles (SmileyMan). 

https://github.com/SmileyMan

Inspired by bash script http://zackreed.me/articles/83-updated-snapraid-sync-script 
- Zack Reed (http://zackreed.me)

Which in turn was a modified version of https://gist.github.com/bfg100k/87a1bbccf4f15d963ff7 
- Sidney Chong first created in 2011


#Work in Progress.

This is just a wrapper for snapraid.exe
and only ever calls snapraid (diff/status/sync/scrub/smart/down) so data should always be safe
(only snapraid.exe manipulates the data)

####Script passes Perl::Critic - Severity: Stern

###__This script does not write or manipulate and Array Data. It is a wrapper for snapraid http://www.snapraid.it/__

#### Command Line Options
##### Only for overrides set all permanent options in snapPERL.conf

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

