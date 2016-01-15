# illumina-run-dirs

##Introduction

Illumina is a company that manufactures instruments used to sequence DNA including HiSeq and MiSeq. These sequencer runs produce large amounts of data that must be converted into human readable metrics for interpretation and analysis.
The wideInstrumentReport.pl can take in JSON files produced for each run. If there is not a JSON report associated with the run, wideInstrumentReport.pl can also take in the RunInfo.xml file for brief run report detials.
Another input that the wideInstrumentReport.pl can interpret is the file provenance report in the format of seqware_files_report_<date>(.gz) as it will extract the location of JSON files associated with each run and return it to the report.

##How to Use through Command Prompt

Ensure you have access wideInstrumentReport.pl script path as well as the json file directory and run the command with your desired input variables:
```
$ qsub -cwd -b y -N [fileName] -e [errorFile] -o [outputFile] -l h_vmem=4g "export PERL5LIB=/oicr/local/analysis/lib/perl/pipe/lib/perl5; OICR_PERL_BIN=/oicr/local/analysis/lib/perl/pipe/bin; 
export PATH=$PATH:$OICR_PERL_BIN; [wideInstrumentReport.pl path] $timeStamp $filePrefix $fileSuffix [outputDir] [instrument files] >> error.log 2>&1"
```
Here is a template for the timeStamp, filePrefix, and fileSuffix input parameters:
```
ymd="`date "+%y%m%d"`"
hm="`date "+%R"`"
day="`date "+%a"`"
zone="`date "+%Z"`"
timeStamp="\"$ymd $hm $day $zone\""
filePrefix="${ymd}_${hm}_"
fileSuffix="_report.csv"
```
If you want to receive an email with run details (when it begins, ends, aborts or suspends), add "-m beas -M [your email]" into the arguments

Example:
```
$ ymd="`date "+%y%m%d"`"
$ hm="`date "+%R"`"
$ day="`date "+%a"`"
$ zone="`date "+%Z"`"
$ timeStamp="\"$ymd $hm $day $zone\""
$ filePrefix="${ymd}_${hm}_"
$ fileSuffix="_report.csv"
$ qsub -cwd -b y -N TestReport -m beas -M "test@test.com" -e error.log -o output.log -l h_vmem=4g "export PERL5LIB=/oicr/local/analysis/lib/perl/pipe/lib/perl5; OICR_PERL_BIN=/oicr/local/analysis/lib/perl/pipe/bin;
export PATH=$PATH:$OICR_PERL_BIN; /u/test/wideInstrumentReport.pl $timeStamp $filePrefix $fileSuffix /u/test/output /.mounts/labs/PDE/data/testdata/runs/150602_D00355_0086_BC6UA2ANXX/jsonReport/test.annotated.bam.BamQC.json > error.log 2>&1"
```

##Expected Output
Navigate to the output directory. There should be a .csv file that contains report data. 
Example:
```
$ cat 160112_15\:27_D00355_report.csv 
Run,Lane,Barcode,Library,Insert Mean,Insert Stdev,Read Length,R1 Phasing, R1 Prephasing, R2 Phasing, R2 Prephasing, R1 PhiX Error %, R2 PhiX Error %, # Raw Clusters, PF %, Uniquely Mapped %,R1 % >= q30,R2 % >= q30,R1 Error %,R2 Error %,R1 Soft Clip %,R2 Soft Clip %, Est Reads/SP,% on Target,Est Yield,Est Coverage,Coverage Target,Source,Comments
150602_D00355_0086_BC6UA2ANXX,8,CGACTGGA,HALT_1651_Bm_R_PE_379_EX,202.63,72.10,126/126,0.275,0.239,0.127,0.111,0.25,0.24,270006964,95.32,0.967670556844631,0.948054604673045,0.940096214382176,150.141752016891,224.918369416632,41.6815753237864,43.744198822454,1.26825765688761,0.872094257036948,5682850244,111.016330477386,/.mounts/labs/PDE/data/TargetedSequencingQC/Agilent.SureSelect.All.Exon.V4/SureSelect_All_Exon_V4_Covered_Sorted.bed,Binary, - 
```
If the instrument file input was the file provenance report, a new data file for each instrument will be created in the output directory.
