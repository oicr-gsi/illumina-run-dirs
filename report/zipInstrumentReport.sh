#!/bin/bash

filePrefix=$1
fileSuffix=$2
outputDir=$3
emailUser="$4"
dateStamp=$5

module load sharutils/4.13.5;

cd $outputDir; 
zip ${filePrefix}instrument_report.zip $filePrefix*$fileSuffix; 
#  $ (cat mailtext; uuencode surfing.jpeg surfing.jpeg) | mail -s "subject" timothy.beck@oicr.on.ca
( cat mailtext.txt; uuencode ${filePrefix}instrument_report.zip ${filePrefix}instrument_report.zip ) | mail -s "$dateStamp wideInstrumentReport" ${emailUser};
