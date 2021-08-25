#!/bin/sh
# $Header:$
#
# This script handles normal maintance chores for the MySQL database engine and the
# 'licenses' database that it currently hosts.
#

# PATH to contain only well known and well controlled directories.
# In particular /usr/local/bin is avoided since a user might install
# something there that would cause us to break.
PATH=/opt/local/bin:/usr/bin:/usr/sbin:/sbin:$PATH
PATH=/var/opt/sysconf/scripts:$PATH
PATH=$(dirname $0):$(dirname $0)/../bin:$PATH

trap 'rm -f /tmp/*.tmp.$$~ /tmp/*.tmp.$$~.d/*' 0

usage()
{
   echo "   Usage: $0 [-vxqp]"
   echo "   -v) Verbose"
   echo "   -x) Trace on"
   echo "   -p) preview"
   echo "   -q) Quiet"
   exit -1
}

trace=false
quiet=false
preview=false
verbose=false

set - `getopt qxpvh? $*`
if [ $? != 0 ]
then
  echo $*
  usage  
fi       
for I in $*
do         
  case "x$I" in
    x-q) quiet=true ; shift;;
    x-x) trace=true ; shift;;
    x-p) preview=true ; shift;;
    x-v) verbose=true ; shift;;
    x-h) usage ;;
  esac  
done    

hostname=$(hostname)
host=$(echo $hostname | sed 's/\..*//')  # Just the short name.

if ! $quiet; then
   echo "$0: Type=$machine-$os, Server=$server"
fi

if [ `id -u` -ne 0 ]
then
   echo "This script should only be ran by root!"
   exit 1
fi

###############################################################################
#

#
# Chores to do:
# 1 - check and clean tables
# 2 - re-optimize the flexlm_usage table
# 3 - get the counts to how many records are in the database, first and last 
#     dates.
# 4 - Backup database.

myisamchk --fast --silent /var/lib/mysql/*/*.MYI

# Optimize the main tables
#echo "OPTIMIZE TABLE flexlm_events" | mysql --silent -u lic_user --password=newpass licenses
#echo "OPTIMIZE TABLE license_usage" | mysql --silent -u lic_user --password=newpass licenses

#
# Backup Database
#
DEST=/disc/extras/mysql

#mysqlhotcopy --allowold -u root --flushlog --password=js-iwnly licenses $DEST
