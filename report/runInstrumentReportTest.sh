#!/bin/bash
# TAB 201408 - You can use this tool to quickly test cronning and report generation and delivery pathways for wideinstrumentreport

shopt -s extglob
declare -a instruments

instruments=/oicr/data/archive/@([A-Z][0-9])*
outputDir=/oicr/data/archive/web/wideInstrumentReport
runDir=~seqprodbio/seq_prod_bio/pipeline/wideInstrumentReport

#zipRecipients="Lee.Timms@oicr.on.ca, Kristen.Geras@oicr.on.ca, Karolina.Czajka@oicr.on.ca, Jeremy.Johns@oicr.on.ca, timothy.beck@oicr.on.ca"
zipRecipients="timothy.beck@oicr.on.ca"
logRecipients="timothy.beck@oicr.on.ca"

ymd="`date "+%y%m%d"`"
hm="`date "+%R"`"
day="`date "+%a"`"
zone="`date "+%Z"`"
timeStamp="\"$ymd $hm $day $zone\""
#filePrefix="${ymd}_${hm}_"
#fileSuffix="_report.csv"
filePrefix="*error"
fileSuffix=".log"

echo -e "Please find the current wideInstrumentReport generated $timeStamp attached.\nPlease email seqprodbio@lists.oicr.on.ca if you have any questions about this report." > $outputDir/mailtext.txt

qsub -cwd -b y -N ZipReports -m beas -M $logRecipients -e $outputDir/qsubZip.log -o $outputDir/qsubZip.log -l h_vmem=4g "$runDir/zipInstrumentReport.sh $filePrefix $fileSuffix $outputDir "$zipRecipients" $timeStamp > $outputDir/error_outZip.log 2>&1"

