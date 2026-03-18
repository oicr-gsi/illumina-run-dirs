#!/usr/bin/python
import argparse
import json
import sys
from urllib.request import urlopen

DELETE = -1
CLEAN = 0
NO_CLEAN = 1
NO_QCS = 2
CONTINUE = 100


def main(args):
    run_case_statuses = get_sequencer_run_case_statuses(args.run, args.cardea_url, verbose=args.verbose)
    decision = decisions(run_case_statuses, args.run, verbose=args.verbose)
    return decision


def get_sequencer_run_case_statuses(run, base_cardea_url, verbose=False):
    url = "/".join([base_cardea_url, "case-statuses", run])
    if verbose:
        print(f"Cardea URL: {url}", file=sys.stderr)
    return json.loads(urlopen(url).read().decode('utf-8'))


def decisions(run_case_statuses, run, verbose=False):
    if (run_case_statuses is None
            or type(run_case_statuses) is not dict
            or run_case_statuses.keys() != {'activeCases', 'completedCases', 'stoppedCases'}):
        if verbose:
            print(f"Cardea run case-statuses output:\n{run_case_statuses}", file=sys.stderr)
        raise Exception("Unable to parse Cardea case statuses response")

    active_case_count = len(run_case_statuses['activeCases']) + len(run_case_statuses['stoppedCases'])
    completed_case_count = len(run_case_statuses['completedCases'])
    total_case_count = active_case_count + completed_case_count

    if total_case_count == 0:
        if verbose:
            print(f"No cases for {run} found in Cardea", file=sys.stderr)
        return CONTINUE
    if active_case_count == 0:
        if verbose:
            print(f"All {total_case_count} cases for {run} are complete in Cardea", file=sys.stderr)
        return CLEAN
    if active_case_count > 0:
        if verbose:
            print(f"{active_case_count} of {total_case_count} cases for {run} are active in Cardea", file=sys.stderr)
        return NO_CLEAN

    raise Exception("Unexpected state while determining Cardea case-statuses decision")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Searches for a sequencer run's case statuses in Cardea")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--cardea-url", help="The Cardea URL", default="https://cardea.gsi.oicr.on.ca")
    parser.add_argument("--verbose", "-v", help="Verbose logging", action="store_true")
    args = parser.parse_args()
    sys.exit(main(args))
