#!/usr/bin/python3
from __future__ import print_function

import psycopg2
import sys
import os
from os.path import expanduser
import yaml
import argparse
import pandas as pd


parser = argparse.ArgumentParser(description='Run the specified SQL code')
parser.add_argument('--file', nargs=1, required=True, help='the name of the file to process')
parser.add_argument('--env', help='Database Environment: dev, itg, prod, dev_std_raw', choices=['dev', 'itg', 'prod', 'prod04'], default='dev')
parser.add_argument('--nolimit', action='count', help='do not limit results returned -- BE CAREFUL')

args = parser.parse_args()

inFile = args.file[0]
limit = args.nolimit is None
outFile = None

home = expanduser("~")
profile_path = f'{home}/.dbt/profiles.yml'
with open(profile_path) as file:
    profiles = yaml.load(file, Loader=yaml.FullLoader)

profile_name = 'default'
target_name = args.env

dbname="bdbt"
port=profiles[profile_name]['outputs'][target_name]['port']
host=profiles[profile_name]['outputs'][target_name]['host']
user=profiles[profile_name]['outputs'][target_name]['user']
password=profiles[profile_name]['outputs'][target_name]['pass']

if args.env:
    inEnv = args.env[0]
    #print("running in environment ",inEnv)

commandFile = open(inFile, 'r')
command = ''

for line in commandFile:
    command += line

commandFile.close()

conarg="dbname="+dbname \
        + " user="+user \
        + " password="+password \
        + " port="+str(port) \
        + " host="+host

print (conarg)

try:
    conn = psycopg2.connect(conarg, sslmode='require')
except psycopg2.OperationalError as e:
    print('Unable to connect!\n{0}').format(e)
    sys.exit()

cur = conn.cursor()

#print(command)

try:
    cur.execute(command)
except psycopg2.Error as e:
    print("Unable to execute command!")
    print (e.pgerror)
    print (e.diag.message_detail)
    sys.exit()

print ("The number of rows: ", cur.rowcount)
pd.options.display.width=0
if cur.rowcount > 0:
    results_table = pd.DataFrame(cur.fetchall())
    #Renaming columns from integers to columns names
    results_table.columns = [desc[0] for desc in cur.description]

    results_table.to_csv('results.csv', index=False)
    print(results_table)

cur.close()
conn.commit()
conn.close()


