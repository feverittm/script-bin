if [ -d $HOME/.keychain ]
then
   #echo "keychain directory found..."
   if [ -f "$HOME/.keychain/`uname -n`-sh" ]
   then
      #echo "source keychain files..."
      if [ -z "$ENV" ]
      then
         source $HOME/.keychain/`uname -n`-sh > /dev/null
      else
         . $HOME/.keychain/`uname -n`-sh > /dev/null
      fi
   fi
fi
