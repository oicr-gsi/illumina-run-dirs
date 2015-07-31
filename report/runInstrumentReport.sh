#!/bin/bash

shopt -s extglob
declare -a instruments

instruments=/oicr/data/archive/@([A-Z][0-9])*
outputDir=/oicr/data/archive/web/wideInstrumentReport
runDir=~seqprodbio/illumina-run-dirs/report

zipRecipients="lee.timms@oicr.on.ca,kristen.geras@oicr.on.ca,karolina.czajka@oicr.on.ca,jeremy.johns@oicr.on.ca,morgan.taschuk@oicr.on.ca"
logRecipients="tbeck@oicr.on.ca"

ymd="`date "+%y%m%d"`"
hm="`date "+%R"`"
day="`date "+%a"`"
zone="`date "+%Z"`"
timeStamp="\"$ymd $hm $day $zone\""
filePrefix="${ymd}_${hm}_"
fileSuffix="_report.csv"

firstloop="true"

for i in $instruments
do
	instrument=`basename $i`

	qsub -cwd -b y -N ${instrument}Report -m beas -M $logRecipients -e $outputDir/qsub_${instrument}.log -o $outputDir/qsub_${instrument}.log -l h_vmem=4g "export PERL5LIB=/oicr/local/analysis/lib/perl/pipe/lib/perl5; OICR_PERL_BIN=/oicr/local/analysis/lib/perl/pipe/bin; export PATH=$PATH:$OICR_PERL_BIN; $runDir/wideInstrumentReport.pl $timeStamp $filePrefix $fileSuffix $outputDir /oicr/data/archive/$instrument/*/jsonReport/*.json >> $outputDir/${instrument}_error.log 2>&1"
	
	if $firstloop == "true"
		then
			jidList="${instrument}Report,"
	else
		jidList="$jidList${instrument}Report,"
	fi
	firstloop="false"
done;

# Create report email boilerplate text
echo -e "Please find the current wideInstrumentReport generated $timeStamp attached.\nPlease email seqprodbio@lists.oicr.on.ca if you have any questions about this report." > $outputDir/mailtext.txt

qsub -cwd -b y -N ZipReports -hold_jid $jidList -m beas -M $logRecipients -e $outputDir/qsubZip.log -o $outputDir/qsubZip.log -l h_vmem=4g "$runDir/zipInstrumentReport.sh $filePrefix $fileSuffix $outputDir "$zipRecipients" $timeStamp > $outputDir/error_outZip.log 2>&1"

