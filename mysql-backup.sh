#/bin/bash
user="root"
pass="js-iwnly"
export d=$(date +'%Y-%m-%d')
export dest="/disc/extras/mysql/backup"
mkdir -p $dest/$d
for db in `echo "show databases" | mysql -u $user -p$pass $db | sed '1d'`;
do
   mkdir -p $dest/$d/$db
   echo "Backing up database: $db"
   for table in `echo "show tables" | mysql -u $user -p$pass $db|grep -v Tables_in_`;
   do
     date
     echo "   ... table: $table"
     mysqldump --add-drop-table --allow-keywords -q -a -c -u $user -p$pass $db $table > $dest/$d/$db/$table.sql
     rm -f $dest/$d/$db/$table.sql.gz
     gzip $dest/$d/$db/$table.sql
   done
done
