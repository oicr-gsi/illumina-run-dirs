#!/bin/bash
set -eo pipefail

module load python

# Usage: script.sh runlist.txt sequencerruns.json fpr.tsv.gz
### runlist.txt is each run name on a new line
### sequencerruns.json is downloaded from pinery/sequencerruns
### fpr.tsv.gz is the file provenance report with header, gzipped


RUNLIST="${1}"
JSON="${2}"
FPR="${3}"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
if [[ ! -f "$RUNLIST" ]]; then
    echo "Runlist file doesn't exist: '$RUNLIST'"
    exit 1
fi
if [[ ! -f "$JSON" ]]; then
    echo "JSON file doesn't exist: '$JSON'"
    exit 1
fi
if [[ ! -f "$FPR" ]]; then
    echo "FPR doesn't exist: '$FPR'"
    exit 2
fi

for i in `cat $1`
do 
    echo "${i}"; 
    name=$(basename $i)
    CMD="python ${HOME}/git/illumina-run-dirs/check-and-clean/checkRunForPineryFPR.py \
        --run ${name} \
        --verbose  \
        --pineryjson ${JSON} \
        --offline \
        --fpr ${FPR} \
        2> ${name}.checkRun \
        >> verdicts.tsv"
#    qsub -cwd -b y -N "checkFP_${i}" "${CMD}"
    eval $CMD
done
