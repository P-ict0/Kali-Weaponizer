#!/bin/bash

##
## extract-hashes-responder
## ------------------------
## Extracts one hash per user from a Responder-Session.log file for easy
## cracking with hashcat.
##
## Usage: ./extract-hashes-responder </opt/Responder/Responder-Session.log> [Result number]
##
## Credit: https://github.com/Wh1t3Rh1n0/pentest-scripts/blob/master/extract-hashes-responder
##

if [ "$1" == "" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ] ; then
    /usr/bin/grep -E '^## ?' "$0" | /usr/bin/sed -E 's/^## ?//g'
    exit
fi

if [ "$2" == "" ] ; then
  RESULTS=1
else
  RESULTS=$2
fi

for user in $(/usr/bin/grep -ioE "complete[^:]+:[^:]+:" "$1" | /usr/bin/sort -u | /usr/bin/grep -ioE ":[^:]+:") ; do 
    /usr/bin/grep -m $RESULTS "$user" "$1" | /usr/bin/grep -ioE "[^:]+::.+$" | /usr/bin/tail -n 1
done
