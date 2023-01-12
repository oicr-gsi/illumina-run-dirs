#!/usr/bin/python
from __future__ import print_function

import pinery,fpr,jira
import argparse

def main(args):
    pineryurl="http://pinery.gsi.oicr.on.ca"
    anfpr="/.mounts/labs/seqprodbio/private/backups/seqware_files_report_latest.tsv.gz"
    if args.verbose:
        import time
        print(time.strftime("%d/%m/%Y %H:%M:%S"),args.run, file=sys.stderr)
        print("------------------------\nPinery\n------------------------", file=sys.stderr)


    if args.fpr is not None:
        anfpr=args.fpr        

    result=[args.run]
    decision="Clean"
    pveto=False
    
    # I put this in an array now because I was doing it in a very roundabout and terrible way before
    # and I don't feel like fixing it right now -MT
    pruns = [pinery.get_pinery_obj(pineryurl+"/sequencerrun?name="+args.run)]
    #pruns = pinery.get_sequencer_runs(args.run)
    #pruns = pinery.open_json("/u/mtaschuk/run_dir_clean/sequencerruns.json",args.run)
    presult = pinery.decisions(pruns, verbose=args.verbose)
    pskippedlanes=pinery.get_skipped_lanes(pruns)
    if args.verbose:
        print("------------------------\nPinery done\n------------------------", file=sys.stderr)  

    if presult==pinery.CLEAN:
        result.append("Pinery: Failed or skipped run")
        decision="Clean"
        pveto=True
    elif presult==pinery.DELETE:
        result.append("Pinery: Not in lims; Delete, add to GP-596")
        decision="Delete"
        pveto=True
    elif presult==pinery.NO_CLEAN:
        result.append("Pinery: In progress run")
        decision="No Clean"
        pveto=True

    #Pinery overrules everything else. If it vetos continuing, no point in running expensive API queries
    if pveto:
        if args.verbose:
            for k,v in pskippedlanes.items():
                if v==True:
                    print("Lane ",k," is skipped:",v)
            print("------------------------\n"+args.run+" FINAL \n------------------------", file=sys.stderr)
            print("Pinery", str(presult), "\nJIRA Not run\nFPR Not run", file=sys.stderr)
        result.insert(1,decision)
        print("\t".join(result))
        return
    
    jveto=False

    if args.verbose:
        print("------------------------\nJIRA\n------------------------", file=sys.stderr)
    jruns = jira.get_sequencer_runs(args.run)
    jresult = jira.decisions(jruns,verbose=args.verbose)

    if jresult==jira.NO_CLEAN:
        result.append("JIRA: Open tickets")
        jveto=True
        decision="No Clean"

    if args.verbose:
        print("------------------------\nFPR\n------------------------", file=sys.stderr)
    sruns = fpr.get_sequencer_run(args.run,pskippedlanes,fpr=anfpr)
    sresult = fpr.decisions(sruns,expected_lanes=pinery.get_positions(pruns),verbose=args.verbose)
    if sresult==fpr.NO_CLEAN:
        result.append("FPR:No Clean")
        decision="No Clean"
    elif sresult==fpr.CONTINUE:
        result.append("FPR: issues detected")
        if not jveto:
            decision="Clean"

    if args.verbose:
        for k,v in pskippedlanes.items():
            if v==True:
                print("Lane ",k," is skipped:",v)
        print("------------------------\n"+args.run+" FINAL \n------------------------", file=sys.stderr)
        print("Pinery", str(presult), "\nJIRA", str(jresult), "\nFPR", str(sresult), file=sys.stderr)


    result.insert(1,decision)
    print("\t".join(result))


if __name__ == "__main__":
    import sys
    parser = argparse.ArgumentParser(description="Searches for and reports the status of issues in JIRA")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--fpr", "-f", help="path to the file provenance report")
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    args=parser.parse_args()
    main(args)
