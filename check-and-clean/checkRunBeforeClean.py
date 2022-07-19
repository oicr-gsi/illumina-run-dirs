#!/usr/bin/python
from __future__ import print_function

import pinery,seqware,jira
import argparse

pineryurl="http://pinery.gsi.oicr.on.ca"
fpr="/.mounts/labs/seqprodbio/private/backups/seqware_files_report_latest.tsv.gz"
def main(args):
    if args.verbose:
        import time
        print(time.strftime("%d/%m/%Y %H:%M:%S"),args.run, file=sys.stderr)
        print("------------------------\nPinery\n------------------------", file=sys.stderr)
    # I put this in an array now because I was doing it in a very roundabout and terrible way before
    # and I don't feel like fixing it right now -MT
    pruns = [pinery.get_pinery_obj(pineryurl+"/sequencerrun?name="+args.run)]
    #pruns = pinery.get_sequencer_runs(args.run)
    #pruns = pinery.open_json("/u/mtaschuk/run_dir_clean/sequencerruns.json",args.run)
    presult = pinery.decisions(pruns, verbose=args.verbose)
    if args.verbose:
        print("------------------------\nPinery done\n------------------------", file=sys.stderr)  
        print("------------------------\nJIRA\n------------------------", file=sys.stderr)
    jruns = jira.get_sequencer_runs(args.run)
    jresult = jira.decisions(jruns,verbose=args.verbose)
    if args.verbose:
        print("------------------------\nSeqWare\n------------------------", file=sys.stderr)
    sruns = seqware.get_sequencer_run(args.run,fpr=fpr)
    sresult = seqware.decisions(sruns,expected_lanes=pinery.get_positions(pruns),verbose=args.verbose)
    if args.verbose:
        print("------------------------\n"+args.run+" FINAL \n------------------------", file=sys.stderr)
        print("Pinery", str(presult), "\nJIRA", str(jresult), "\nSeqWare", str(sresult), file=sys.stderr)


    result=[args.run]
    decision="Clean"
    pveto=False
    jveto=False

    if presult==pinery.CLEAN:
        result.append("Pinery: Failed run")
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

    if jresult==jira.NO_CLEAN:
        result.append("JIRA: Open tickets")
        jveto=True
        if not pveto:
            decision="No Clean"

    if sresult==seqware.NO_CLEAN:
        result.append("SeqWare:No Clean")
        if not pveto:
            decision="No Clean"
    elif sresult==seqware.CONTINUE:
        result.append("SeqWare: issues detected")
        if not pveto and not jveto:
            decision="Clean"
    result.insert(1,decision)
    print("\t".join(result))


if __name__ == "__main__":
    import sys
    parser = argparse.ArgumentParser(description="Searches for and reports the status of issues in JIRA")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    args=parser.parse_args()
    main(args)
