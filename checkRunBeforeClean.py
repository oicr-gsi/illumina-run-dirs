#!/usr/bin/python
from __future__ import print_function

import pinery,seqware,jira
import argparse


def main(args):
    if args.verbose:
        import time
        print(time.strftime("%d/%m/%Y %H:%M:%S"),args.run)
        print("------------------------\nPinery\n------------------------")
    pruns = pinery.get_sequencer_runs(args.run)
    presult = pinery.decisions(pruns, verbose=args.verbose)

    if args.verbose:
        print("------------------------\nJIRA\n------------------------")
    jruns = jira.get_sequencer_runs(args.run,args.username)
    jresult = jira.decisions(jruns,verbose=args.verbose)
    if args.verbose:
        print("------------------------\nSeqWare\n------------------------")
    sruns = seqware.get_sequencer_run(args.run)
    sresult = seqware.decisions(sruns,verbose=args.verbose)
    if args.verbose:
        print("------------------------\nFINAL\n------------------------")
        print("Pinery", str(presult), "\nJIRA", str(jresult), "\nSeqWare", str(sresult))
    if presult==pinery.CLEAN:
        print(args.run, "Pinery", "Clean")
    elif presult==pinery.NO_CLEAN:
        print(args.run, "Pinery", "No Clean")
    elif jresult==jira.NO_CLEAN:
        print(args.run, "JIRA","No Clean")
    elif sresult==seqware.NO_CLEAN:
        print(args.run, "SeqWare","No Clean")
    else:
        print(args.run, "Everyone" "Clean")



if __name__ == "__main__":
    import sys
    parser = argparse.ArgumentParser(description="Searches for and reports the status of issues in JIRA")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    parser.add_argument("--username","-u", help="The username to use for JIRA",required=True)
    args=parser.parse_args()
    main(args)
