#!/usr/bin/python
from __future__ import print_function

import pinery,seqware
import argparse


def main(args):
    if args.verbose:
        import time
        print(time.strftime("%d/%m/%Y %H:%M:%S"),args.run, file=sys.stderr)
        print("------------------------\nPinery\n------------------------", file=sys.stderr)
    if args.pineryjson:
         pruns = pinery.open_json(args.pineryjson,args.run)
    elif args.offline:
        print("If running in offline mode, supply a Pinery JSON file.")
        exit(1)
    else:
        pruns = [pinery.get_pinery_obj(pineryurl+"/sequencerrun?name="+args.run)]
    presult = pinery.decisions(pruns, verbose=args.verbose, offline=args.offline)
    if args.verbose:
        print("------------------------\nSeqWare\n------------------------", file=sys.stderr)
    if args.fpr:
         sruns = seqware.get_sequencer_run(args.run, fpr=args.fpr)
    else:
        sruns = seqware.get_sequencer_run(args.run)
    sresult = seqware.decisions(sruns,expected_lanes=pinery.get_positions(pruns),verbose=args.verbose)
    if args.verbose:
        print("------------------------\n"+args.run+" FINAL \n------------------------", file=sys.stderr)
        print("Pinery", str(presult), "\nSeqWare", str(sresult), file=sys.stderr)


    result=[args.run]
    decision="Clean"
    pveto=False

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

    if sresult==seqware.NO_CLEAN:
        result.append("SeqWare:No Clean")
        if not pveto:
            decision="No Clean"
    elif sresult==seqware.CONTINUE:
        result.append("SeqWare: issues detected")
        decision="Clean"
    result.insert(1,decision)
    print("\t".join(result))


if __name__ == "__main__":
    import sys
    parser = argparse.ArgumentParser(description="Searches for and reports the status of runs in Pinery and FPR")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    parser.add_argument("--pineryjson","-j", help="Location of the Pinery sequencerrun JSON file for offline mode")
    parser.add_argument("--offline","-o", help="Offline mode. Don't attempt to contact Pinery", action="store_true")
    parser.add_argument("--fpr","-f", help="Alternative file provenance report, TSV format with header, zipped.")
    args=parser.parse_args()
    main(args)
