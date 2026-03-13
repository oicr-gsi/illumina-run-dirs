#!/usr/bin/python
import pinery,fpr,jira,cardea
import argparse
import time

def main(args):
    base_pinery_url = args.pinery_url
    base_cardea_url = args.cardea_url

    if args.verbose:
        print(time.strftime("%d/%m/%Y %H:%M:%S"), args.run, file=sys.stderr)
        print("------------------------\nCardea\n------------------------", file=sys.stderr)

    cardea_sequencer_run_case_statuses = cardea.get_sequencer_run_case_statuses(args.run, base_cardea_url, verbose=args.verbose)
    cardea_decision = cardea.decisions(cardea_sequencer_run_case_statuses, args.run, verbose=args.verbose)

    if args.verbose:
        print(f"Cardea decision for {args.run} = {cardea_decision}", file=sys.stderr)
        print(time.strftime("%d/%m/%Y %H:%M:%S"),args.run, file=sys.stderr)
        print("------------------------\nCardea done\n------------------------", file=sys.stderr)


    result=[args.run]
    decision="Clean"
    pveto=False
    
    prun = pinery.get_pinery_obj(base_pinery_url+"/sequencerrun?name="+args.run)
    
    presult = pinery.decisions(prun, base_pinery_url, verbose=args.verbose)
    pskippedlanes=pinery.get_skipped_lanes(prun)
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
    elif presult==pinery.NO_QCS and cardea_decision==cardea.CLEAN:
        # special situation where we allow Cardea case statuses override Pinery signoff statuses
        if args.verbose:
            print(f"Warning: {args.run} Pinery signoffs are not complete, but Cardea case signoffs are - proceeding with cleaning", file=sys.stderr)
        decision="Clean"
    elif presult==pinery.NO_QCS and args.fpr is None:
        result.append("Pinery: Signoffs not complete")
        decision="No Clean"

    #Pinery overrules everything else. If it vetos continuing, no point in running expensive API queries
    if pveto:
        if args.verbose:
            for k,v in list(pskippedlanes.items()):
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

    jruns_summary = jira.get_sequencer_runs_by_summary(args.run)
    jruns_text = jira.get_sequencer_runs_by_text(args.run)
    jruns = jruns_summary.copy()
    jruns.update(jruns_text)

    jresult_summary = jira.decisions(jruns,verbose=args.verbose)

    if jresult_summary==jira.NO_CLEAN:
        result.append("JIRA: Open tickets (by summary and text)")
        jveto=True
        decision="No Clean"

    sresult="Disabled"
    # searching the FPR does not happen unless it is provided
    if args.fpr is not None:
        anfpr=args.fpr        

        if args.verbose:
            print("------------------------\nFPR\n------------------------", file=sys.stderr)
        sruns = fpr.get_sequencer_run(args.run,pskippedlanes,fpr=anfpr)
        sresult = fpr.decisions(sruns,expected_lanes=pinery.get_positions(prun),verbose=args.verbose)
        if sresult==fpr.NO_CLEAN:
            result.append("FPR:No Clean")
            decision="No Clean"
        elif sresult==fpr.CONTINUE:
            result.append("FPR: issues detected")
            if not jveto:
                decision="Clean"
    if args.verbose:
        for k,v in list(pskippedlanes.items()):
            if v==True:
                print("Lane ",k," is skipped:",v,file=sys.stderr)

    print("------------------------\n"+args.run+" FINAL \n------------------------", file=sys.stderr)
    print("Pinery", str(presult), "\nJIRA summary", str(jresult_summary), "\nFPR", str(sresult), file=sys.stderr)


    result.insert(1,decision)
    print("\t".join(result))


if __name__ == "__main__":
    import sys
    parser = argparse.ArgumentParser(description="Checks a sequencer run to see if it can be cleaned")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--fpr", "-f", help="enable searching the FPR by providing path to the file provenance report. Increases time substantially and toggles off QC checking.")
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    parser.add_argument("--pinery-url", help="The Pinery URL", default="http://pinery.gsi.oicr.on.ca")
    parser.add_argument("--cardea-url", help="The Cardea URL", default="https://cardea.gsi.oicr.on.ca")
    args=parser.parse_args()
    main(args)
