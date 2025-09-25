# run-dir-cleanup
Scripts for checking and cleaning Illumina instrument run directories.

There are two components to cleaning run folders.

1. checking for problems
2. cleaning the run 

The most time-consuming process for the user is checking for problems. It involves examining the output of the checkRunBeforeClean script, looking it over, doing an initial diagnosis on the problems if they exist, making tickets and flagging the run on the filesystem, and then sending it for cleaning. Cleaning also takes a long time but it's hands-off once it is launched.

The two main scripts are checkRunBeforeClean.py and cleanRun. All other scripts in this directory are called by those.

## Dependencies

* A clone of [illlumina-run-dirs](https://github.com/oicr-gsi/illumina-run-dirs)
* For checking: Python 3 with module [argparse](https://docs.python.org/3/library/argparse.html)
* For cleaning: bash on Debian/Ubuntu
* Pinery webservice
* JIRA (by default, points to jira.oicr.on.ca)
  * JIRA configuration file: ~/.jira or set under JIRA_AUTH_FILE with private permissions. The file should consist of one line that is your JIRA personal access token (https://jira.oicr.on.ca/secure/ViewProfile.jspa?selectedTab=com.atlassian.pats.pats-plugin:jira-user-personal-access-tokens)
* FPR file provenance report

Each service is contacted in its own python module: pinery.py, fpr.py, and jira.py. Each module has a method get_sequencer_run(s) that retrieves the data, and decisions which returns a 100 or 0 if the run checks out okay, or another number if an error occurred or the run can't be cleaned automatically.

# Primary scripts

## checkRunBeforeClean.py

The primary script for checking whether run folders can be cleaned is illumina-run-dirs/check-and-clean/checkRunBeforeClean.py.

It uses the name of the sequencer run directory to query OICR services to determine whether the run can be cleaned.

* Checks
  * whether sequencing is complete;
  * LIMS (Pinery)
    * if this run is marked 'failed'
    * if the run appears in LIMS at all
    * if the run has had all QC signed off (for the run and run-libraries)
  * JIRA
    * If there are any open tickets that mention the run by name
  * Optionally: FPR
    * if there are exactly two fastqs per library
    * if there are at least two fastqs per lane
    * if the fastq files exist on disk and are larger than 1MB
    * if the total size of the lane is less than 15G
* Works from any filesystem location
* Does not prompt for passwords; passwords are not hardcoded in the scripts.
* Prints results to standard out
* Does NOT take any cleaning action

Because of the requirement to authenticate in JIRA, this script should be run as yourself and not an instrument user (e.g. sbsuser).

If you must run using an insecure account, set the JIRA\_AUTH environment variable (and make sure that bash history immediately forgets about it).

    history -d $((HISTCMD-1)) && export JIRA_AUTH='YOUR_GITHUB_PERSONAL_ACCESS_TOKEN'



```
usage: checkRunBeforeClean.py [-h] --run RUN [--fpr FPR] [--verbose]

Searches for and reports the status of issues in JIRA

options:
  -h, --help         show this help message and exit
  --run RUN, -r RUN  the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX
  --fpr FPR, -f FPR  enable searching the FPR by providing path to the file provenance report. Increases time substantially.
  --verbose, -v      Verbose logging
```

Example command line:

```
python3 checkRunBeforeClean.py --run 180320_A00469_0007_AHCHTWDMXX
```



### Output
The script prints a single line (in non-verbose mode) to standard out with the following columns:

* Name of instrument run
* Decision (i.e. Clean/No Clean/Delete)
* Optional columns: if one or more services had a warning or rejected cleaning, briefly explain why. In the format SERVICE: Reason

Example:

```
110915_h239_0128_BC055RACXX     Clean
110927_h239_0130_AC0476ACXX     Clean   FPR: issues detected
111107_h239_0131_AC087PACXX     Clean
111118_h239_0132_AD080LACXX     Delete  Pinery: Not in lims; Delete, add to GP-596
111118_h239_0133_AD080LACXX     Delete  Pinery: Not in lims; Delete, add to GP-596
111124_h239_0134_BC06GFACXX     No Clean        FPR:No Clean
111209_h239_0135_BD0GRMACXX     No Clean        JIRA: Open tickets      FPR:No Clean
111216_h239_0136_AD0E6RACXX     Delete  Pinery: Not in lims; Delete, add to GP-596
111222_h239_0137_AD0DDNACXX     Clean   Pinery: Failed run
```

## cleanRun
Removes all of the large data from a run directory

* Check whether the name of the directory matches an Illumina sequencer name
* Removes:
  * sgeLogs
  * ReadPrep1/2/Images
  * AnalysisLogs
  * Calibration*
  * finchResults / finch_results
  * Cleans contents of directories named: postProcessing; GERALD*; BaseCalls; Intensities; Bustard*; *Firecrest*; Data
* Reports the total size of the directory after cleaning and any files larger than 1GB in size

## checkAllClean
This script is intended to be run from an instrument directory that contains many run directories. For example,

    sbsuser@hn3:/.mounts/labs/prod/archive/m753

This will quickly list run directories that contain the CLEANED.TIM file (produced by `cleanRun`), indicating the run dir has been cleaned, or without CLEANED.TIM indicating the run dir needs to be cleaned.

# Support scripts

## cleanBasecalls

Removes sequentially:

* L00[1-8]
* Matrix
* Phasing
* SignalMeans

Expects to be in directory: Data/Intensities/BaseCalls and will fail if not there.

Logs commands, output and timestamp into cleanBaseCalls.txt in current working directory

## cleanBustard

Removes the large files from the Bustard directory in an Illumina run directory. Bustard was previously used for base calling before Illumina added it to their runs.

Expects to be in directory: Data/Intensities/Bustard and will fail if not there.

Removes sequentially:

* dirs: L00[1-8]
* dir: Matrix
* dir: Phasing
* dir: SignalMeans
* dir: Temp
* *qseq.txt
* *finished.txt
* matrix[1-9].txt
* *pngs.txt
* *Means.txt
* support.txt
* *sig2.txt
* *seq.txt
* *prb.txt
* *qhg.txt
* tiles.txt
* warning.txt
* stdout
* stderr

Logs commands, output and timestamp into cleanBustard.txt in current working directory

## cleanData

Removes log files from the Illumina Data directory.

Expects to be in directory: <rundir>/Data

Removes sequentially:

* CopyLog.txt
* ErrorLog.txt
* Log.txt
* ./TileStatus

Logs commands, output and timestamp into cleanData.txt in cwd

## cleanFirecrest

Expects files to be below a directory that matches the Firecrest formats (i.e.  C1-[0-9]{2,3}_Firecrest[0-9.a]{5,7}_[0-9]{2}-[0-9]{2}-[0-9]{4}_[a-zA-Z]{2,8}  )

Logs commands, output and timestamp into cleanFirecrest.txt

## cleanGerald


Expects to be in GERALD_* directory

* *qval.txt.gz
* *results.tim
* -f *eland_extended.txt
* -f *eland_query.txt
* -f *eland_multi.txt
* -f *eland_result.txt
* *anomaly.txt
* *frag.txt
* *qraw.txt
* *sorted.txt
* *score.txt
* *rescore.txt
* *qcal.txt
* *qref.txt
* *qval_file_pair.txt
* *filt.txt
* *anomraw.txt
* *saf.txt
* *seqpre.txt
* *qtable.txt
* *qreport.txt
* -f *export.txt
* *prealign.txt
* *realign.txt
* *rescore.txt
* *align.txt
* *qcalreport.txt
* dir: Temp
* dir: Stats

 Logs commands, output and timestamp into cleanGERALD.txt in cwd


## cleanIntensities

Expects to be in Intensities directory

Removes sequentially:

* L001 L002 L003 L004 L005 L006 L007 L008

Logs commands, output and timestamp into cleanBaseCalls.txt (sic).
run-dir-cleanup/cleanIPAR

Expects to be in IPAR_* directory

* Removes sequentially:
* rm -rf *_nse.txt.p.gz
* rm -rf *_int.txt.p.gz
* rm -rf Matrix
* rm -rf Firecrest

Logs commands, output and timestamp into cleanIPAR.txt.


## cleanOICR

Expects to be in directory postProcessing

Removes sequentially:

* rm -rf ./bwa
* rm -rf ./bowtie
* rm -rf ./samtools
* rm -rf ./maq
* rm -rf ./enrichment
* rm -rf ./dcc
* rm -rf ./novoalign
* find ./insertsizeplot -name '*stats.txt' | xargs truncate -s0
* find ./blast -name '*count' | xargs rm
* find ./blast -name 'tmp' -type d | xargs rm -rf
* find ./blast -name '*.blastoutput' -type f | xargs rm -rf
* find ./blast -name 'seq_positions' -type f | xargs rm -rf
* find ./blast -name '*seq_positions.txt' -type f | xargs rm -rf
* find ./bwa -name '*.ba[mi]' -type f | xargs truncate -s0
* find ./bwa -name '*.modified.gz' -type f | xargs truncate -s0
* find ./bwa -name '*sequence.txt.gz' -type f | xargs truncate -s0
* find ./bwa -name '*.ba[mi]' -type f | xargs truncate -s0
* find ./novoalign* \( -name '*.bam' -o -name '*.sam' -o -name '*.err' -o -name '*.out' \) -type f | xargs truncate -s0
* find . -regextype posix-extended -regex '.*\.(e|o)[0-9]{7}$' -type f | xargs rm -rf   # Catch all SGE logs


## cleaned

This is the last script that is run in the process. It generates a 'CLEANED.TIM' file (or appends to an existing one) that describes the size footprint of what remains. This is useful for older run dirs where someone may have created temporary files that don't fit the cleaning pattern and remain to be cleaned.


## jira.py

Searches for and reports the status of issues in JIRA using the name of an instrument run. This module requires a password file ~/.jira or set under JIRA_AUTH_FILE with private permissions. The file should consist of one line in the format username:password. It will check to ensure the file has no read permissions by anyone other than owner.

```
usage: jira.py [-h] --run RUN [--json JSON] [--url URL] [--verbose]
            [--username USERNAME]

Searches for and reports the status of issues in JIRA

optional arguments:
  -h, --help            show this help message and exit
  --run RUN, -r RUN     the name of the sequencer run, e.g.
                        111130_h801_0064_AC043YACXX
  --json JSON, -j JSON  The sequencer run JSON file to search
  --url URL             the JIRA URL. Default: https://jira.oicr.on.ca
  --verbose, -v         Verbose logging
  --username USERNAME, -u USERNAME
                        The username to use for JIRA
```

**API**

`get_sequencer_runs(rname,username [,url="https://jira.oicr.on.ca"])`

Gets all of the tickets that talk about rname using creds from username

* Params:
  * rname : name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX
  * username : JIRA username for authentication purposes
  * url : path to the JIRA webservice
* Returns:
  * Dict of tickets from JIRA json

`decisions(tickets, verbose=False)`

makes a decision whether or not the run clean be cleaned

* Params:
  * tickets : Dict of tickets from JIRA json (probably from get_sequencer_runs)
  * verbose : whether to print more information to stderr
* Returns:
  * 100 : continue, perhaps clean the run based on other checks
  * 1 : do not clean the run


## pinery.py

Searches for and reports the status of sequencer runs in Pinery.

```
usage: pinery.py [-h] --run RUN [--json JSON] [--url URL] [--verbose]

Searches for and reports the status of sequencer runs in Pinery

optional arguments:
  -h, --help            show this help message and exit
  --run RUN, -r RUN     the name of the sequencer run, e.g.
                        111130_h801_0064_AC043YACXX
  --json JSON, -j JSON  The sequencer run JSON file to search
  --url URL             the pinery URL. Default:
                        https://pinery.hpc.oicr.on.ca:8443
  --verbose, -v         Verbose logging
```

**API:**

`get_sequencer_runs(rname [,url="https://pinery.hpc.oicr.on.ca:8443"])`

Gets all of the sequencer runs that match rname from pinery webservice

* Params:
  * rname : name of the sequencer run, e.g 111130_h801_0064_AC043YACXX
  * url : path to the pinery webservice
* Returns
  * List of run objects from Pinery sequencer run JSON

`decisions(runs [, verbose=False])`

Makes a decision whether or not the run can be cleaned

* Params:
  * runs: the List of run objects from Pinery sequencer run JSON (probably from get_sequencer_runs)
  * verbose : whether to print more information to stderr
* Returns:
  * 0 : clean the run immediately
  * 100 : continue, perhaps clean the run based on other checks
  * 1 : do not clean the run


##fpr.py

Searches for and reports the status of fastqs in FPR according to
sequencer run name


```
usage: fpr.py [-h] --run RUN [--fpr FPR] [--verbose]
Searches for and reports the status of fastqs in FPR according to
sequencer run name
optional arguments:
  -h, --help         show this help message and exit
  --run RUN, -r RUN  the name of the sequencer run, e.g.
                     111130_h801_0064_AC043YACXX
  --fpr FPR, -f FPR  The FPR file provenance report to search
  --verbose, -v      Verbose logging
```

**API**

`get_sequencer_run(rname [,filetype="chemical/seq-na-fastq-gzip", wfilter="Xenome", fpr="/.mounts/labs/seqprodbio/private/backups/sqwprod-db.hpc.oicr.on.ca/seqware_files_report_latest.gz" ])`

Parse the file provenance report, search for sequencer runs called "rname", locate files of a particular type "filetype", filtering out those from workflows named "wfilter"

* Params:
  * rname : name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX
  * filetype: metatype to look for in the file provenance report
  * wfilter : workflow filter keyword to remove from the results
  * fpr : path to the file provenance report
* Returns:
  * Dict of file details about the sequencer run

`decisions(runs [, verbose=False])`

Makes a decision whether or not the run can be cleaned

* Params
  * runs: Dict of file details about the sequencer run (probably from get_sequencer_run 
  * verbose : whether to print more information to stderr
* Returns:
  * 0 : clean the run
  * 100 : continue, perhaps clean the run based on other checks
  * 1 : do not clean the run


# Attribution

Written by Genome Sequence Informatics for Ontario Institute for Cancer Research. For questions, email gsi@oicr.on.ca .
