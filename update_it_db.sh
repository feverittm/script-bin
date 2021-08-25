#!/bin/sh
# $Header:$
#
# This script wraps some perl functions to update the itinfo database and
#   manage the passwords.
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

msg()
{
  echo "$@"
  logger -t SYSCONF "$*"
}

hostname=$(hostname)
host=$(echo $hostname | sed 's/\..*//')  # Just the short name.

if ! $quiet; then
   echo "$0: "
fi

###############################################################################
#

original="/com0/it/master/sysconf/itinfo/itinfo.db"
path=`dirname $original`

save=`pwd`

tmpdir="/tmp/itinfo.$$~"

mkdir $tmpdir
if [ $? -ne 0 ]
then
   exit 1
fi

cd $tmpdir

/com0/it/master/sysconf/itinfo/update_db_passwd.pl -f ${original}
if [ $? -eq 1 ]
then
   exit 1
fi

diffs=`diff new.db $original | wc -l`
if [ $diffs -gt 0 ]
then
  echo "$diffs Changes found in database"

  cvs co sysconf/itinfo/itinfo.db
  if [ $? -ne 0 ]
  then
     exit 1
  fi

  diff new.db sysconf/itinfo/itinfo.db

  mv new.db sysconf/itinfo/itinfo.db

  cvs ci -m "Password update" sysconf/itinfo/itinfo.db
fi

cd $save

rm -rf /tmp/itinfo.$$~

exit 0

