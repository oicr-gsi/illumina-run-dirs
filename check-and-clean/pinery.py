#!/usr/bin/python
from __future__ import print_function
import sys
import json
import argparse
import urllib2,ssl
import re

oicrurl="http://pinery.gsi.oicr.on.ca"

DELETE=-1
CLEAN=0
NO_CLEAN=1
CONTINUE=100

def main(args):
    if args.url is not None:
        url=args.url
    if args.json is None and not args.offline:
        runs = get_sequencer_runs(args.run,url=url)
    else: 
        runs = open_json(args.json,args.run)
    return(decisions(runs,verbose=args.verbose,offline=args.offline))


def get_sequencer_run(runs_obj, rname):
    """
    Gets all of the sequencer runs that match rname
    from runs, which is a .read()-supporting file-like object
    """
    runs=[]
    allruns=json.load(runs_obj)
    for i in allruns:
        if re.search(rname,i['name'], re.IGNORECASE):
            runs.append(i)
    return runs

def get_sequencer_runs(rname,url=oicrurl):
    """
    Gets all of the sequencer runs that match rname from pinery webservice.
    """
    runs=[]
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    url=url+"/sequencerruns"
    try:
        rstr = urllib2.urlopen(url, context=ctx)
        runs=get_sequencer_run(rstr,rname)
    except urllib2.HTTPError, e:
        print("Pinery HTTP error: %d" % e.code, file=sys.stderr)
        sys.exit(e.code)
    except urllib2.URLError, e:
        print("Pinery Network error: %s" % e.reason.args[1], file=sys.stderr)
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
       

def get_pinery_obj(url):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        sam = urllib2.urlopen(url, context=ctx)
        sample=json.load(sam)
    except urllib2.HTTPError, e:
        print("Pinery HTTP error: %d" % e.code, file=sys.stderr)
        sys.exit(e.code)
    except urllib2.URLError, e:
        print("Pinery Network error: %s" % e.reason.args[1], file=sys.stderr)
        sys.exit(2)
    return sample


def decisions(runs, verbose=False, offline=False):
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
                 if 'samples' in p:
                     pos['num_samples']=len(p['samples'])
                     pos['exsample_url']=p['samples'][0]['url'].replace("http://localhost:8080",oicrurl)
                 else:
                     pos['num_samples']="Unknown"
                     pos['exsample_url']="Unknown"
                 positions.append(pos)
                 if verbose:
                     print_verbose_position(pos,offline)
        elif patt_run.match(r['state']):
            inprogress=True
    if verbose:
        print("Run exists: ", exists, "\nRun succeeded: ", succeeded, "\nRun in progress: ", inprogress, file=sys.stderr)
    return(what_is_your_will(exists,inprogress,succeeded))

def print_verbose(run):
    print("name:\t",run['name'], file=sys.stderr)
    print("state:\t",run['state'], file=sys.stderr)
    print("date:\t",run['created_date'],"\n", file=sys.stderr)

def print_verbose_position(pos,offline=False):
    if pos['exsample_url'] == "Unknown" or offline:
        print("Lane:",pos['lane'],"\tNum Libraries:",pos['num_samples'],file=sys.stderr)
    else:
        print("Lane:",pos['lane'],"\tNum Libraries:",pos['num_samples'],"\tExample: ", get_pinery_obj(pos['exsample_url'])['name'], file=sys.stderr)

def what_is_your_will(exists,inprogress,succeeded):
    if not exists:
        print("Pinery: Delete folder; Add to JIRA ticket GP-596", file=sys.stderr)
        return DELETE
    if inprogress:
        print("Pinery: Stop; do not clean", file=sys.stderr)
        return NO_CLEAN
    if succeeded:
        #print("Pinery: Continue; possibly clean")
        return CONTINUE
    else:
        print("Pinery: Run failed. Clean run", file=sys.stderr)
        return CLEAN

def get_positions(runs):
    positions=0
    patt_comp=re.compile("Completed")
    patt_run=re.compile("Running")
    for r in runs:
        if patt_comp.match(r['state']):
            succeeded=True
            positions=len(r['positions'])
    return positions

if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description="Searches for and reports the status of sequencer runs in Pinery")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--json", "-j", help="The sequencer run JSON file to search")
    parser.add_argument("--url", help=" ".join(["the pinery URL. Default: ",oicrurl]))
    parser.add_argument("--offline", "-o", help="Run in offline mode (don't attempt to contact Pinery). Should be used in combination with --json option.", action="store_true");
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    args=parser.parse_args()
    sys.exit(main(args))
