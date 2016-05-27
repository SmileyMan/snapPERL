# _*snapPERL v0.3.0*_

#####Automation script for Snapraid created in PERL

 Snapraid wrapper script written in **PERL**. Enables automation using cron for your Array Syncs

 Runs sync commands and verifys data using scrub command. Sends alerts when are issues found
 and aborts where needed. Plus much more see: _snapPERL.conf.example_

## Website: [snapPERL](http://snapperl.stevemiles.me.uk/ "snapPERL")

---

## Linux Compatible
##### Tested on Ubuntu 16.04LTS - Snapraid x64 v10.0

## Windows Compatible 
#### _Requires a PERL distribution to be installed_
##### Tested on Windows 10 - Snapraid x64 v10.0 and Latest ActivePerl 
 
--- 
 
#####Script is expected to be run as root so it calls snapraid as root

#### _Please Read!_

* CHANGELOG
* INSTALL.md
* INSTALL-WINDOWS.md
* LICENSE
* _And the extensive comments for the options in: snapPERL.conf.example_

---

#Created by Steve Miles (SmileyMan). 

[snapPERL Website](http://snapperl.stevemiles.me.uk/ "snapPERL Website")

[snapPERL Github](https://github.com/SmileyMan/snapPERL/ "snapPERL Github")


Inspired by this bash script: [SnapRAID Sync Script](http://zackreed.me/articles/83-updated-snapraid-sync-script) 
-_Zack Reed (http://zackreed.me)_

Which in turn was a modified version of this bash script: [SnapRAID Helper](https://gist.github.com/bfg100k/87a1bbccf4f15d963ff7) 
-_Sidney Chong first created in 2011_

---

#Work in Progress.

**This is just a wrapper for snapraid.exe**

It only ever calls snapraid (diff/status/sync/scrub/check/smart/down)

_(only Snapraid manipulates the data)_

####Script passes Perl::Critic - Severity: Stern

---

#### Important

__This script does not write to or manipulate any Array Data__

---

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

---

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

