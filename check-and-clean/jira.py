#!/usr/bin/python
from __future__ import print_function
import sys
import json
import argparse
import urllib2,ssl,base64
import re
import os,stat

oicrurl="https://jira.oicr.on.ca"
CLEAN=0
CONTINUE=100
NO_CLEAN=1

def main(args):
    if args.url is not None:
        url=args.url
    else:
        url=oicrurl

    if args.json is None:
        tickets=get_sequencer_runs(args.run,url=url)
    else: 
        tickets=json.load(args.json)

    return decisions(tickets,verbose=args.verbose)


def get_jira_personal_token():
    if "JIRA_AUTH" in os.environ:
        passfile=os.environ['JIRA_AUTH']
    else:
        passfile=os.environ['HOME']+"/.jira"
    if not os.path.exists(passfile):
        raise IOError("JIRA auth file not found. Set JIRA_AUTH or ~/.jira")
    if os.stat(passfile).st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise IOError("JIRA auth file should have permissions 700: "+passfile)
    with open(passfile) as jfile:
        for l in jfile:
            return l.strip()

def get_sequencer_runs(rname,url=oicrurl):
    """
    Gets all of the tickets that talk about rname using creds from personal token (see README)
    """
    request_url=url+"/rest/api/latest/search?jql=text~"+rname
    request = urllib2.Request(request_url)
    request.add_header("Authorization", "Bearer %s" % get_jira_personal_token())   
    request.add_header("Content-Type","application/json")
    try:
        result = urllib2.urlopen(request)
        tickets=json.load(result)
    except urllib2.HTTPError, e:
        print("HTTP error: %d" % e.code, file=sys.stderr)
    except urllib2.URLError, e:
        print("Network error: %s" % e.reason.args[1], file=sys.stderr)
    return tickets


def decisions(tickets, verbose=False):
    anyopen=False
    keys=[]
    patt_comp=re.compile("Closed|Resolved|Won't Fix|Done|Fixed")
    for t in tickets['issues']:
        if verbose:
            print_verbose(t)
        if not patt_comp.match(t['fields']['status']['name']):
            keys.append(t['key'])
            anyopen=True
    if keys:
        import time
        print(time.strftime("%d/%m/%Y %H:%M:%S"),"Open JIRA tickets", keys, file=sys.stderr)
    return what_is_your_will(anyopen)

def print_verbose(ticket):
    print("Key\t",ticket['key'], file=sys.stderr)
    print("Status\t",ticket['fields']['status']['name'], file=sys.stderr)
    print("Summary:\t", ticket['fields']['summary'], file=sys.stderr)
    print("Reporter:\t",ticket['fields']['reporter']['name'], file=sys.stderr)
    print("Updated:\t",ticket['fields']['updated'],"\n", file=sys.stderr)

def what_is_your_will(anyopen):
    if anyopen:
        print("JIRA: Stop; do not clean", file=sys.stderr)
        return NO_CLEAN
    else:
        #print("JIRA: Continue; possibly clean")
        return CONTINUE



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Searches for and reports the status of issues in JIRA")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--json", "-j", help="The sequencer run JSON file to search")
    parser.add_argument("--url", help="the JIRA URL. Default: https://jira.oicr.on.ca")
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    args=parser.parse_args()
    sys.exit(main(args))
