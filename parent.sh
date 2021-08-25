#!/bin/sh
# To find the parent processes of the pid given.
# name: parent
# Gregor Weertman

if [ -z "$1" ] ;then
    echo 'usage parent pid <pid2> <pid3> .....'
    exit
fi

for pid
do
    ps -ef |awk -vpd=$pid '
    function parent( fpid, ff){
        for( ii[ ff] = 1; ii[ ff] <= TNR; ii[ ff]++){
            if( pid[ ii[ ff]] == fpid) {
                print psln[ ii[ ff]]
                pd1  = ppid[ ii[ ff]]
                ppd1 = pid[ ii[ ff]]
                if( pid[ ii[ ff]] == ppid[ ii[ ff]]) return 3
                ret=parent( pd1, ff+1)
                return 2
            }
            if( ret == 3) return 1
        }
        return 0
    }
    {
        pid[  NR] = $2
        ppid[ NR] = $3
        psln[ NR] = $0
        if( pid[ NR] == pd) pd1 = pid[ NR]
        TNR = NR
    }
    END{
        if( pd == 0) exit
        parent( pd, 1)
    }'
    echo "\n"
done
