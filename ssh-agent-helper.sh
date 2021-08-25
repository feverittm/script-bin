#!/bin/sh
# Name:     ssh-agent-helper
# Version:  $Id: ssh-agent-helper.sh 2 2008-04-28 19:07:25Z red $
# Date:     Fri Mar 10 08:12:58 PST 2006
# Author:   Floyd Moore (floyd.moore@hp.com)
#
# Synopsis: A helper script to wrap both ssh-agen and the gentoo keychain
#           programs and make it easier and more secure to manage ssh keys
#           in a system.
#          
#           Primary use is to launch and kill the ssh-agent.
#
# Usage:    ssh-agent-helper.sh [stop|start]
#
#####################################
#

version_string='Version: \$Revision:\$'
 
usage()
{
   echo "Usage: $0 {options...} <blockname>"
   echo $version_string
   echo
   exit 1
}

clean_exit()
{
   rm -f /tmp/ssh-helper.sem
}

trace=false
quiet=false
preview=false
verbose=false

trap "clean_exit" QUIT
trap "clean_exit" HUP
trap "clean_exit" TERM
trap "clean_exit" INT

if [ $# -eq 0 ] 
then
   usage
   exit 1
fi

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

if [ -z "$1" ]
then
   echo "No command specifid"
   usage
else
   if [ $1 == "--" ]
   then
      shift;
   fi
   if [ -z "$1" ]
   then
      echo "No command specified"
      usage
   fi
   echo command=$1
fi

user=`whoami`
hostname=$(hostname)
host=$(echo $hostname | sed 's/\..*//')  # Just the short name.

echo "User=$user"
running=`ps -u $user | egrep -v "sge_execd"`


case "$1" in
   start)
      ! $quiet && echo "ssh-agent starting..."
      ;;
   stop)
      rc=`ps -u $user | egrep "ssh-agent" | wc -l`
      if [ $rc -eq 0 ]
      then
         ! $quiet && echo "   ... No agent running"
         exit
      fi
      if [ -z "$SSH_AGENT_PID" ]
      then
         ! $quiet && echo "  ... agent not exported to this environment"
         if [ -f $HOME/.keychain/${hostname}-sh ]
         then
            . $HOME/.keychain/${hostname}-sh
         else
            echo "No keychain found for user $user on machine $hostname"
            exit
         fi
      fi
      ! $quiet && echo "stopping ssh-agent $SSH_AGENT_PID..."
      ! $preview && ssh-agent -k
      ;;
   *)
      echo "Command $1 not recognized!"
      usage
      ;;
esac
