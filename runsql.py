#!/home/red/anaconda2/bin/python

import psycopg2
import argparse

parser = argparse.ArgumentParser(description='Run the specified SQL code')
parser.add_argument('--file', nargs=1, required=True, help='the name of the file to process')
parser.add_argument('--store', action='count', help='store the result in <file>.result')
parser.add_argument('--nolimit', action='count', help='do not limit results returned -- BE CAREFUL')

args = parser.parse_args()

inFile = args.file[0]
store = args.store > 0
limit = args.nolimit is None
outFile = None

if store:
    outFile = open(inFile + '.result', 'w')

commandFile = open(inFile, 'r')
command = ''

for line in commandFile:
    command += line

commandFile.close()

conn = psycopg2.connect("dbname=bdbt"
            +" user=red"
            +" password=PzZwvgDNHVGV"
            +" port=3389"
            +" host=redshift-test-03-redshiftcluster-13pffhtt8kqg9.cswu2qd2etx1.us-west-2.redshift.amazonaws.com")
cur = conn.cursor()

cur.execute(command)
colnames = [desc[0] for desc in cur.description]
header = '|'.join(colnames)

print header
if store:
    outFile.write(header + '\n')

index = 0

for result in cur:
    outLine = '|'.join(str(x) for x in result)
    print outLine
    if store:
        outFile.write(outLine + '\n')
    index += 1
    if (index > 1000 and limit == True):
        break

cur.close()
conn.commit()
conn.close()

if store:
    outFile.close()

