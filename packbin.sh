#!/bin/bash
# Name:     packbin
# Version:  $HeadURL: svn+ssh://lxcvifem.cv.hp.com/var/lib/svn/repository/projects/red-bin/trunk/packbin.sh $
# Date:     Mon Apr  4 15:20:24 PDT 2011
# Author:   Floyd Moore
#
# Synopsis:
#    Make a release copy of my linux 'bin' directory so that I can pack
#    them away for home or move them to another machine.
#
# Usage:    ./packbin
#####################################
#

echo "Packing up script directory for backup/transport..."

cd ~/bin

INFO=`svn info . > /dev/null 2>&1`
if [ $? -ne 0 ]
then
   echo "Bad return from 'svn info' on bin directory.  Not in repository"
   exit 1
fi

# update the svn data...
svn update $TARGET 

ROOT=`svn info . | grep Root | awk '{print $3}' -`
echo "Root = $ROOT"
if [ -z "$ROOT" ]
then
   echo "Bad root location! Cannot continue"
   exit 1
fi
# get the revision of the whole svn repository
REPO_REV=`svn info . | grep Revision | awk '{print $2}' -`
RREV=`svn info . | grep "Last Changed Rev:" | cut -d: -f 2 | awk '{print $1}'`
let RREV=$RREV+0

# try to convert file: methods in svn to use ssh

METHOD=`echo $ROOT | cut -d: -f1`
if [ $METHOD = "file" ]
then
   echo "try to translate file: methods to svn+ssh methods..."
   myroot=`echo $ROOT | sed -e 's/file:\/\//svn+ssh:\/\/lxcvifem.cv.hp.com/'`
   echo "   ... translated: $myroot"
   TESTPATH=`svn info $myroot > /dev/null 2>&1`
   if [ $? -ne 0 ]
   then
      echo "Bad return from svn on translated path $myroot,  Not in svn repository"
      echo "   ... falling back to file: method"
   else
      echo "   ... Success.  New file path is: $myroot"
      ROOT=$myroot
   fi
fi

# validate there are no uncommitted changes in the target
CHECK=`svn status --ignore-externals . | egrep -v "^X" | wc -l`
#echo "STATUS check $CHECK"
if [ $CHECK -ne 0 ]
then
   echo "The directory has uncommitted changes!  Please commit them before trying"
   echo "  to release."
   svn status
   exit 1
fi

# check the structure of the repository to make sure it is in the 'known' format
for tag in trunk tags branches
do
   svn list $ROOT/$tag > /dev/null 2>&1
   if [ $? -ne 0 ]
   then
      echo "This repository does not have a standard '$tag' directory.  This needs to be fixed"
      exit 1
   fi
done

REPO=`echo $ROOT | awk -F/ '{print $NF}'`
LEN=`echo $REPO | wc -c`
let LEN=$LEN+1

# find out the latest released version in the TAGS repository and then the version of the target
# file that is in that repository.  If the versions match then we don't need to make a new version
# of release/tag and we can just check that we have the latest file from that version installed.
DIR=`svn list $ROOT/tags | sort -n -k1.${LEN} | tail -1`
TREV=`svn info $ROOT/tags/$DIR | grep "Last Changed Rev:" | cut -d: -f2 | awk '{print $1}'`
let TREV=$TREV+0

# Report some of the information:
echo
echo "##########################"
echo "  Root: $ROOT"
echo "  Main Repository Revision: $REPO_REV"
echo "  Local Last Changed Rev: $RREV"
echo "  Released Last Changed Rev: $TREV" 
echo 
echo "  Release Repository Project: $REPO"
echo "  Latest Release Directory is $DIR"
echo "##########################"

svn diff --summarize --old=$ROOT/tags/$DIR
CHECK=`svn diff --summarize --old=$ROOT/tags/$DIR | wc -l | awk '{print $1}'`

if [ $RREV -eq $TREV ]
then
   echo "File revision and Release revision are the same.  No Repository update needed"
else	
   echo "Mismatch: $RREV is not the same as $TREV"
   # To get a list of the release log.  Use the command:
   #svn log file://$REPOS/branches 

   # The order of the copy command here is important.  If we mess up the
   #    names, then we could get a bad/invalid branch created.
   #    It is also best to check the tree afterwards to make sure.
   echo "copy to a release branch: RB-${RREV}..."
   svn ls $ROOT/branches/RB-${RREV} > /dev/null 2>&1
   if [ $? -eq 0 ]
   then
      echo "branches repository for RB-${RREV} already exists!"
      exit 1
   fi
   svn copy -m "Tag Branch $RREV for release" \
      $ROOT/trunk \
      $ROOT/branches/RB-${RREV}

   echo "Release is: $ROOT/tags/${REPO}-${RREV}"
   DIR="${REPO}-${RREV}"
   svn ls $ROOT/tags/${DIR} > /dev/null 2>&1
   if [ $? -eq 0 ]
   then
      echo "release ${DIR} already exists!"
      exit 1
   fi
   svn copy -m "Release $RREV" \
      $ROOT/branches/RB-${RREV} \
      $ROOT/tags/${REPO}-${RREV}


   # check out a copy of the branch to modify library paths
   release_name="${REPO}-${RREV}"
   rm -f /home/red/priv/${REPO}-*.tar.gz
   svn export $ROOT/tags/${release_name} ${release_name}
   tar cf ${release_name}.tar ${release_name}
   gzip ${release_name}.tar
   mv ${release_name}.tar.gz /home/red/priv
   rm -r ${release_name:?}
fi
exit 0
