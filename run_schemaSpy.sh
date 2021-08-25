#!/bin/sh
#Start SchemaSpyGUI
TMPDIR=`mktemp -d /tmp/schemaspy.XXXXX ` || exit 1
cd $TMPDIR

echo "Running in $TMPDIR"

#To get TNS working you need to set the following variables in the 
#environment:
#
#reference:
#   http://www.oracle.com/technology/docs/tech/sql_plus/10103/readme_ic.htm
unset TNS_ADMIN
unset CLASSPATH
unset SQLPATH

#MY_ORACLE_HOME=/apps/oracle/instantclient_10_2/linux
MY_ORACLE_HOME=/home/red/bin/instantclient_11_2
# to find the shared libraries for oracle
export LD_LIBRARY_PATH=$MY_ORACLE_HOME
# to find the glogin.sql file used during login
export SQLPATH=$MY_ORACLE_HOME
# to set up the oracle naming service (like DNS for Oracle)
# there should be a tnsnames.ora file in this location
export TNS_ADMIN=/home/red/bin/instantclient_10_2/network/admin
#
# add the java class path to point to the ODBC connector
export CLASSPATH=/apps/perl5/2.6x86_64/ext/oracle/lib

# set the path so we can find sqlplus and friends
export PATH=$MY_ORACLE_HOME:$PATH

cmd="java -jar /home/red/bin/schemaSpy_5.0.0.jar -dp $MY_ORACLE_HOME/ojdbc6.jar -t ora -db MDAP -s MDA -host gvu0134.houston.hp.com -port 1525 -u floyd_moore -p new4mdadb! -o $TMPDIR"

echo "Running $cmd"

$cmd
