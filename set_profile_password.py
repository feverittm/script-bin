#!/usr/bin/python3
# https://github.azc.ext.hp.com/cirrostratus/redshift_utils/blob/master/redshift-get-credentials.py
# This script was originally developed by Phani Lanka (CyberSecurity) and this is a modified version of the script
# to work with PingFederate. The script here can be used as a generic
# script to call any AWS Service after receiving the
# SAML token from AWS STS. We are calling the redshift get-cluster-credential to retrieve temporary password to authenticate
# with our Redshift Database.
#
# If you are trying to use this script on git/bash and are having terminal issues with imputting your password then you need
# to add:
#      alias python='winpty -Xallow-non-tty python.exe'
# to your .bashrc.  This should fix the issue and still allow file redirects.
#


import sys
import boto3
import requests
import getpass
import argparse
import urllib3
import base64
import logging
import xml.etree.ElementTree as ET
import re
from bs4 import BeautifulSoup
from os.path import expanduser
import yaml
from shutil import copyfile
try:
    from urllib.parse import urlparse
except ImportError:
    # Backward compatibility for Python 2.7
    from urlparse import urlparse

# Get details and more from a secrets.py file
try:
    from secrets import sec_list
except ImportError:
    print("Can't open the secrets file with the sec_list")
    raise

urllib3.disable_warnings()
# SSL certificate verification: Whether or not strict certificate
# verification is done, False should only be used for dev/test
sslverification = True

# idpentryurl: The initial url that starts the authentication process.
idpentryurl_dev = 'https://login-itg.external.hp.com/idp/startSSO.ping?PartnerSpId=AWS_redshift'
idpentryurl_itg = 'https://login-itg.external.hp.com/idp/startSSO.ping?PartnerSpId=AWS_redshift_dataos_prod'

##########################################################################
# The program options and help file
parser = argparse.ArgumentParser(description="Securely connect to Redshift", prog='RedshiftAuth')
parser.add_argument('--region', help='AWS Region', default='us-west-2')
parser.add_argument('--cluster', help='Redshift Cluster'
                    , choices=['dev', 'itg', 'prod-02', 'prod-04']
                    , default='dev')
parser.add_argument('--duration', type=int, help='Redshift Connection Duration', default=3600)
parser.add_argument('--dbt_profile', help='name of DBT profile to set')
parser.add_argument('--dbt_target', help='name of DBT target to set')
parser.add_argument('--debug', action='store_true', help='enable debug logging')
args = parser.parse_args()

cluster_map = {
    'dev': 'redshift-test-03-redshiftcluster-13pffhtt8kqg9'
    , 'itg': 'redshift-itg-02'
    , 'prod-02': 'redshift-prod-02'
    , 'prod-04': 'redshift-prod-04'
}

idpentryurl = idpentryurl_dev if args.cluster == 'dev' else idpentryurl_itg

logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO)

##########################################################################
# Get the federated credentials from the user
# Backwards compatibility for Python2.7.
# https://docs.python.org/3/whatsnew/3.0.html#builtins
# PEP 3111: raw_input() was renamed to input(). That is, the new input() function reads a line
# from sys.stdin and returns it with the trailing newline stripped.
# It raises EOFError if the input is terminated prematurely.
# To get the old behavior of input(), use eval(input()).
if 'username' in sec_list:
    username = sec_list['username']
else:
    try:
        username = input('Please enter your HP email address: ')
    except Exception:
        username = raw_input('Please enter your HP email address: ')

if 'password' in sec_list:
    password = sec_list['password']
else:
    password = getpass.getpass('Password (wont be echoed on screen): ')

# Initiate session handler
session = requests.Session()

# Programmatically get the SAML assertion
# Opens the initial IdP url and follows all of the HTTP302 redirects, and
# gets the resulting login page
formresponse = session.get(idpentryurl, verify=False)
# Capture the idpauthformsubmiturl, which is the final url after all the 302s
idpauthformsubmiturl = formresponse.url

# Parse the response and extract all the necessary values
# in order to build a dictionary of all of the form values the IdP expects
formsoup = BeautifulSoup(formresponse.text, "html.parser")
payload = {}

# Some IdPs don't explicitly set a form action, but if one is set we should
# build the idpauthformsubmiturl by combining the scheme and hostname
# from the entry url with the form action target
# If the action tag doesn't exist, we just stick with the
# idpauthformsubmiturl above
for inputtag in formsoup.find_all(re.compile('(FORM|form)')):
    action = inputtag.get('action')
    if action:
        parsedurl = urlparse(idpentryurl)
        idpauthformsubmiturl = parsedurl.scheme + "://" + parsedurl.netloc + action

# Performs the submission of the IdP login form with the above post data
response = session.post(idpauthformsubmiturl, data=payload, verify=sslverification)

# Decode the response and extract the SAML assertion
soup = BeautifulSoup(response.text, "html.parser")
for inputtag in soup.find_all(re.compile('(INPUT|input)')):
    name = inputtag.get('name', '')
    value = inputtag.get('value', '')
    if "username" in name.lower():
        # Make an educated guess that this is the right field for the username
        payload[name] = username
    elif "pass" in name.lower():
        # Some IdPs also label the username field as 'email'
        payload[name] = password
    else:
        # Simply populate the parameter with the existing value (picks up hidden fields in the login form)
        payload[name] = value

# This will print out sensitive information like plaintext password.
logging.debug("Payload is: {}".format(payload))
resp = session.post(idpauthformsubmiturl, data=payload, verify=sslverification)
assertion_soup = BeautifulSoup(resp.text, "html.parser")

assertion = ''
# Look for the SAMLResponse attribute of the input tag (determined by
# analyzing the debug print lines above)
for inputtag in assertion_soup.find_all('input'):
    if inputtag.get('name') == 'SAMLResponse':
        logging.debug(inputtag.get('value'))
        assertion = inputtag.get('value')

if assertion == '':
    logging.error('Response did not contain a valid SAML assertion')
    sys.exit(1)

logging.debug(base64.b64decode(assertion))

# Parse the returned assertion and extract the authorized roles
awsroles = []
root = ET.fromstring(base64.b64decode(assertion))
for saml2attribute in root.iter('{urn:oasis:names:tc:SAML:2.0:assertion}Attribute'):
    if saml2attribute.get('Name') == 'https://aws.amazon.com/SAML/Attributes/Role':
        for saml2attributevalue in saml2attribute.iter('{urn:oasis:names:tc:SAML:2.0:assertion}AttributeValue'):
            awsroles.append(saml2attributevalue.text)

# Note the format of the attribute value should be role_arn,principal_arn
# but lots of blogs list it as principal_arn, role_arn so let's reverse
# them if needed
for awsrole in awsroles:
    chunks = awsrole.split(',')
    role_arn = chunks[0]
    principal_arn = chunks[1]

# Use the assertion to get an AWS STS token using Assume Role with SAML
# conn = boto.sts.connect_to_region(args.region)
conn = boto3.client('sts', region_name=args.region)
token = conn.assume_role_with_saml(
    RoleArn=role_arn,
    PrincipalArn=principal_arn,
    SAMLAssertion=assertion,
    DurationSeconds=args.duration,
)
client = boto3.client('redshift',
                      region_name=args.region,
                      aws_access_key_id=token['Credentials']['AccessKeyId'],
                      aws_secret_access_key=token['Credentials']['SecretAccessKey'],
                      aws_session_token=token['Credentials']['SessionToken']
                      )

response = client.get_cluster_credentials(
    DbUser=token['AssumedRoleUser']['AssumedRoleId'].split(':')[1],
    DbName="bdbt",
    ClusterIdentifier=cluster_map[args.cluster],
    DurationSeconds=args.duration,
)
# delete environment variable
del username
del password

home = expanduser("~")
profile_path = f'{home}/.dbt/profiles.yml'
with open(profile_path) as file:
    profiles = yaml.load(file, Loader=yaml.FullLoader)

profile_name = args.dbt_profile if args.dbt_profile else 'default'
target_name = args.dbt_target if args.dbt_target else profiles[profile_name]['target']

profiles[profile_name]['outputs'][target_name]['user'] = response['DbUser']
profiles[profile_name]['outputs'][target_name]['pass'] = response['DbPassword']

copyfile(profile_path, profile_path + ".bck")

with open(profile_path, 'w') as file:
    yaml.dump(profiles, file)

logging.info("Done!")
