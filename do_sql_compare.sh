#!/bin/bash
source="/home/red/projects/idst/dbt_idst/idst"
target="/home/red/projects/idst/idst_test_env/idst_dbttest/idst"
let cnt=0
for file in `find target/compiled/idst/models/ -name "*.sql" | grep -v '.yml' | cut -d/ -f4-`
do
		echo "${cnt}: ${file}"
		diff -q ${source}/${file} ${target}/${file}
		if [ $? -ne 0 ]
		then
				echo "Failed compare"
				exit
		fi
		let cnt=${cnt}+1
		#if [ $cnt -gt 50 ]
		#then
		#	exit 1
		#fi
done


