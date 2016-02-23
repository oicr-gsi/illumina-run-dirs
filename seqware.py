#!/usr/bin/python
from __future__ import print_function
import sys
import re,csv
import argparse
import gzip
import os
oicrfpr="/.mounts/labs/seqprodbio/private/backups/sqwprod-db.hpc.oicr.on.ca/seqware_files_report_latest.gz"

NO_CLEAN=1
CLEAN=0
CONTINUE=100

def main(args):
    if args.fpr is not None:
        fastqs=get_sequencer_run(args.run, fpr=args.fpr)
    else:
        fastqs=get_sequencer_run(args.run)
    return decisions(fastqs, verbose=args.verbose)

def get_sequencer_run(rname,filetype="chemical/seq-na-fastq-gzip",wfilter="Xenome",fpr=oicrfpr):
    """
    Parse the file provenance report, search for sequencer runs called "rname", 
    locate files of a particular type "filetype", filtering out those from workflows named "wfilter".
    By default, looks for fastqs that are not from Xenome.

    Lane Number{} 
          - IUS Tag{}
                - count
                - library
                - details{}
                    - File SWID{}
                          - sw_size	: the size according to seqware
                          - fs_size	: the size on the filesystem
                          - path	: the path of the file
    """
    lanes={}
    with gzip.open(fpr) as tsv:
        #match fastqs from specific runs that are not from Xenome
        fastq_matcher=re.compile(filetype)
        run_matcher=re.compile(rname.strip())
        filter_matcher=re.compile(wfilter)

	#parse the report into a map
	for line in csv.DictReader(tsv, delimiter="\t"):
            if not fastq_matcher.match(line['File Meta-Type']):
                continue
            if not run_matcher.match(line['Sequencer Run Name'].strip()):
                continue
            if filter_matcher.search(line['Workflow Name']):
                continue
            lane=lanes.setdefault(line['Lane Number'],{})
            barcode=lane.setdefault(line['IUS Tag'],{})
            numfiles=barcode.setdefault('count',0)
            barcode['count']=(numfiles+1)
            barcode['library']=line['Sample Name']
            details=barcode.setdefault('details',{})
            swid=details.setdefault(line['File SWID'],{})
            filepath=line['File Path']
            if line['File Size'].strip()=="":
                swid['sw_size']=0
            else:
                swid['sw_size']=abs(long(line['File Size']))
            if os.path.exists(filepath):
                swid['fs_size']=abs(long(os.path.getsize(filepath)))
            else:
                swid['fs_size']=0
            swid['path']=filepath
    return lanes

def print_verbose(lane, ius, count, library, swid):
    return [lane, ius, library,str(count), str(swid['sw_size']), str(swid['fs_size']), swid['path'][:100]+"..."]

def details(lane,ius,library,problem):
    return "\t".join([lane, ius, library, problem])

def pretty_print(header, table):
    row_format=""
    for t in table[0]:
        row_format+="{:<"+str(len(t)+5)+"}"
    print(row_format.format(*header),file=sys.stderr)
    for row in table:
       print(row_format.format(*row), file=sys.stderr)

def decisions(fastqs,verbose=False):
    morethantwo=False
    lessthantwo=False
    mismatchfilesize=False
    smallfile=False
    problems=[]
    lanes=fastqs.keys()
    lanes.sort()
    if verbose:
        verbose_out=[]
        #verbose_out.append("\t".join(["Lane","Barcode","Library","Count","SW Size", "FS Size", "Path"]))
    #Iterate through each lane
    for lane in lanes:
        iuses=fastqs[lane].keys()
        iuses.sort()
        size=0
        for ius in iuses:
            count=fastqs[lane][ius]['count']
            library=fastqs[lane][ius]['library']
            #Test if there are more than 2 files per IUS
            if count > 2:
                morethantwo=True
                problems.append(details(lane,ius,library,"Has too many files: "+str(count)))
            #Test if there are less than 2 files per IUS
            elif count < 2:
                lessthantwo=True
                problems.append(details(lane,ius,library,"Only "+str(count)+" file"))
            swids=fastqs[lane][ius]['details']
            for swid in swids:
                sw=swids[swid]['sw_size']
                fs=swids[swid]['fs_size']
                #Test if the seqware and filesystem sizes match
                if sw != fs:
                    mismatchfilesize=True
                    problems.append(details(lane,ius,library, "Filesize doesn't match -"+str(sw) + " vs "+str(fs)))
                #Test if the size on disk is too small (>1MB)
                if fs<1e6:
                    smallfile=True
                    problems.append(details(lane,ius,library,"File very small = "+str(fs)+" bytes"))
                size=size+fs
                if verbose:
                    verbose_out.append(print_verbose(lane, ius,count,fastqs[lane][ius]['library'],swids[swid]))

        #Test to see if the lane size is less than 20G
        if verbose:
            print("Lane "+lane+" size:"+str(size/1e9)+"G", file=sys.stderr)
        if size/1e9 < 20:
            smallfile=True
            problems.insert(0,"\t".join(["Lane",lane,"size is <20G:",str(size/1e9)]))
    if verbose:
        pretty_print(["Lane","Barcode","Library","Count","SW Size", "FS Size", "Path"],verbose_out)
    
    if problems:
        import time
        print(time.strftime("%d/%m/%Y %H:%M:%S"),"SeqWare issues detected",len(problems), file=sys.stderr)
    for p in problems:
        print(p, file=sys.stderr)
    return what_is_your_will(morethantwo,lessthantwo,mismatchfilesize,smallfile)

def what_is_your_will(morethantwo,lessthantwo,mismatchfilesize,smallfile):
   if smallfile:
       print("SeqWare: Do not clean. Make JIRA ticket: diagnose small data problem", file=sys.stderr)
       return NO_CLEAN
   if lessthantwo:
       print("SeqWare: Do not clean. Make JIRA ticket: locate or regenerate data.", file=sys.stderr)
       return NO_CLEAN
   if morethantwo:
       print("SeqWare: More than two fastqs. Clean. Make JIRA ticket.", file=sys.stderr)
       return CONTINUE
   if mismatchfilesize:
#       print("SeqWare: Continue; possibly clean")
       return CONTINUE

def test_decisions():
    fastqs={}
    fastqs['1']={}
    test_decisions_make_ius(fastqs['1'],"OneFastq",1,"LA",1e10,1e10,"path")
    test_decisions_make_ius(fastqs['1'],"ThreeFastq",3,"LA",1e10,1e10,"path")
    test_decisions_make_ius(fastqs['1'],"FsMismatch",2,"LA",1e11,1e10,"path")
    test_decisions_make_ius(fastqs['1'],"FsSmall",2,"LA",1e5,1e5,"path")
    fastqs['2']={}
    decisions(fastqs)

def test_decisions_make_ius(fmap, tag, count, library, sw_size, fs_size, path):
    fmap[tag]={}
    fmap[tag]['count']=count
    fmap[tag]['library']=library
    fmap[tag]['details']={}
    fmap[tag]['details']['1']={}
    fmap[tag]['details']['1']['sw_size']=sw_size
    fmap[tag]['details']['1']['fs_size']=fs_size
    fmap[tag]['details']['1']['path']=path



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Searches for and reports the status of fastqs in SeqWare according to sequencer run name")
    parser.add_argument("--run", "-r", help="the name of the sequencer run, e.g. 111130_h801_0064_AC043YACXX", required=True)
    parser.add_argument("--fpr", "-f", help="The SeqWare file provenance report to search")
    parser.add_argument("--verbose","-v", help="Verbose logging",action="store_true")
    args=parser.parse_args()
    sys.exit(main(args))
