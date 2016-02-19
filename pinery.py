#!/usr/bin/python
from __future__ import print_function

import json
import argparse
import urllib2,ssl
import re


def get_sequencer_run(runs_obj, rname):
    """
    Gets all of the sequencer runs that match rname
    from runs, which is a .read()-supporting file-like object
    """
    runs=[]
    allruns=json.load(runs_obj)
    for i in allruns:
        if re.search(rname,i['name']):
            runs.append(i)
    return runs

def pinery_sequencer_runs(url,rname):
    """
    Gets all of the sequencer runs that match rname from pinery webservice.
    """
    runs=[]
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    url=url+"/pinery/sequencerruns"
    try:
        rstr = urllib2.urlopen(url, context=ctx)
        runs=get_sequencer_run(rstr,rname)
    except urllib2.HTTPError, e:
        print("HTTP error: %d" % e.code)
        sys.exit(e.code)
    except urllib2.URLError, e:
        print("Network error: %s" % e.reason.args[1])
        sys.exit(2)
    return runs

def open_json(filename,rname):
    """
    Gets all of the sequencer runs that match rname from JSON file
    """
    runs=[]
    with open(filename) as rstr:
        runs=get_sequencer_run(rstr,rname)
    return runs
       

def main(args):
    if args.url is None:
        url="https://pinery.hpc.oicr.on.ca:8443"
    else:
        url=args.url

    if args.json is None:
        runs = pinery_sequencer_runs(url,args.run)
    else: 
        runs = open_json(args.json,args.run)
    decisions(runs,verbose=args.verbose)


def decisions(runs, verbose=False):
    succeeded=False
    inprogress=False
    exists=False
    positions=[]
    #check if at least one matching run exists
    if runs:
        exists=True

    patt_comp=re.compile("Completed")
    patt_run=re.compile("Running")
    for r in runs:
        if verbose:
            print_verbose(r)
        if patt_comp.match(r['state']):
            succeeded=True
            for p in r['positions']:
                 pos={}
                 pos['lane']=p['position']
                 pos['num_samples']=len(p['samples'])
                 positions.append(pos)
        elif patt_run.match(r['state']):
            inprogress=True
    if verbose:        
        print("Exists: ", exists, "; succeeded: ", succeeded, "; Run in progress: ", inprogress)
    print("Decision: ", what_is_your_will(exists,inprogress,succeeded))

def print_verbose(run):
    print("name:\t",run['name'])
    print("state:\t",run['state'])
    print("date:\t",run['created_date'],"\n")

def what_is_your_will(exists,inprogress,succeeded):
    if not exists:
        return "Delete folder; Add to JIRA ticket GP-596"
    if inprogress:
        return "Stop; do not clean"
    if succeeded:
        return "Continue; possibly clean"
    else:
        return "Clean run"




if __name__ == "__main__":
    import sys
    parser = argparse.ArgumentParser(description="Searches for and reports the status of sequencer runs in Pinery")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--json", "-j", help="The sequencer run JSON file to search")
    parser.add_argument("--url", help="the pinery URL. Default: https://pinery.hpc.oicr.on.ca:8443")
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    args=parser.parse_args()
    main(args)
