#!/bin/bash
export PATH=$PATH:/home/red/bin
export ftp_proxy=http://web-proxy.cv.hp.com:8088/
export http_proxy=http://web-proxy.cv.hp.com:8088/

echo "Dailystrips running"

echo "Start $0: `date`"

ds=`date +%Y.%m.%d`

echo "Date Stamp = $ds"

COMICS="/var/www/html/comics"

cd ${COMICS}

if [ $# -eq 0 ]
then
   if [ ! -r "dailystrips-${ds}.html" ]
   then
      /home/red/bin/dailystrips -a --nospaces --basedir ${COMICS} --local @floyds
   else
      echo "not re-fetching today's comics"
   fi
else
   idate="\"$1\""
   echo "Fetch date: $idate"
   eval dailystrips -a --nospaces -date $idate --basedir ${COMICS} --local @floyds
fi

for strip in Garfield UserFriendly
do
    last=`ls -lrt ${strip}-* | tail -1 | awk '{print $NF}'`

    EXT=`echo $last | awk -F. '{print $NF}'`

    echo "Strip $strip: Type=$EXT, Last = $last"

    if [ -r ${strip}.${EXT} ]
    then
       rm -f ${strip}.${EXT}
    fi

    ln -s "${last}" ${strip}.${EXT}
done
