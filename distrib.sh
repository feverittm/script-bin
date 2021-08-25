#!/bin/bash

# This file should have one account per line
acct_list="$HOME/bin/accounts"

# Files to copy
copy_files='.profile .kshrc .bashrc .bash_profile .emacs'

# Go to our home directory
cd ~

do_account() {
   # $1 contains string "user@host"
   echo "  ** $1 **"

   # Create ~/.ssh (if necessary), copy authorized_keys file
   ssh -T "$1" \
      'umask 077; mkdir -p ~/.ssh; cat > ~/.ssh/authorized_keys' \
      < ~/.ssh/authorized_keys || {
      echo "Failed to create authorized_keys file on $1!" >&2
      return 1
   }

   # Now, copy other files over
   #scp $copy_files "$1:~/" || {
   #   echo "Failed to copy files to $1!" >&2
   #   return 1
   #}
}

for account in `cat "$acct_list"` ; do
   if [ -z "$*" ] ; then
      # No arguments specified, so do every host
      do_account $account
   else
      for arg ; do
         if [ "$arg" = "${account#*@}" ] ; then
            # Host was specified on command line
            do_account $account
         fi
      done
   fi
done
