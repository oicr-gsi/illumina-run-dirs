#!/usr/bin/perl

use strict;
use warnings;
use JSON;

my @jsonFiles = @ARGV;

my $emailUser = "ltimms";
my $outputDir = "/oicr/data/archive/web/wideInstrumentReport/";
my %instSkipList = qw(h393 1 I1551 1 m146 1 m753 1);

my %jsonHash;

my $line;
my $file;

for $file (@jsonFiles)
{
	if (open (FILE, $file))
	{

	if ($line = <FILE>)
	{
		$jsonHash{$file} = decode_json($line);
	}
	else
	{
		warn "No data found in $file!\n";
	}
	close FILE;
	}
	else
	{
		warn "Couldn't open $file!\n";
	}

}

my $rawReads;
my $rawYield;
my $mapRate;

my $qOver30;
my $qTotal;

my $sum;
my $count;

my $cycleCount;

my $best;
my $worst;
my $worstCycle;

my $errorRate;

my $onTargetRate;
my $estimatedYield;
my $estimatedCoverage;

my $inst;
my %instFH;

my $filePrefix = `date +%y%m%d`;
chomp $filePrefix;
$filePrefix .= "_";
my $fileSuffix = "_report.csv";

my $fileName;

my $R1errorRate;
my $R2errorRate;
my $R1softClipRate;
my $R2softClipRate;

# for illumina numbers:
my $l;
my $xmlPath;
my $lane;

my $totalClusters;
my $PFrate;
my $R1phasing;
my $R2phasing;
my $R1prephasing;
my $R2prephasing;
my $R1phixErrorRate;
my $R2phixErrorRate;
my $R1phixErrorRateSD;
my $R2phixErrorRateSD;

my $i;

for my $j (reverse sort keys %jsonHash)
{
	$inst = $jsonHash{$j}{"instrument"};
	$inst =~ s/SN/h/;
	$fileName = $filePrefix . $inst . $fileSuffix;

	unless (exists $instSkipList{$inst})
	{
		unless (exists $instFH{$inst})
		{
			open (FILE, ">${outputDir}/$fileName") or die "Couldn't open ${outputDir}/$fileName for write.\n";
			$instFH{$inst} = \*FILE;
	
			print { $instFH{$inst} } "Run,Lane,Barcode,Library,Insert Mean,Insert Stdev,Read Length,R1 Phasing, R1 Prephasing, R2 Phasing, R2 Prephasing, R1 PhiX Error %, R2 PhiX Error %, # Raw Clusters, PF %, Uniquely Mapped %,R1 % >= q30,R2 % >= q30,R1 Error %,R2 Error %,R1 Soft Clip %,R2 Soft Clip %, Est Reads/SP,% on Target,Est Yield,Est Coverage,Coverage Target,Comments\n";
		}
	
	
		print { $instFH{$inst} } $jsonHash{$j}{"run name"} . ",";
		print { $instFH{$inst} } $jsonHash{$j}{"lane"} . ",";
		if (exists $jsonHash{$j}{"barcode"})
		{
			print { $instFH{$inst} } $jsonHash{$j}{"barcode"} . ",";
		}
		else
		{
			print { $instFH{$inst} } "noIndex,";
		}
		print { $instFH{$inst} } $jsonHash{$j}{"library"} . ",";
	
		if ($jsonHash{$j}{"number of ends"} eq "paired end")
		{
			printf { $instFH{$inst} } "%.2f,", $jsonHash{$j}{"insert mean"};
			printf { $instFH{$inst} } "%.2f,", $jsonHash{$j}{"insert stdev"};
			print { $instFH{$inst} } $jsonHash{$j}{"read 1 average length"} . "/" . $jsonHash{$j}{"read 2 average length"} . ",";
		}
		else
		{
			print { $instFH{$inst} } "n/a,n/a,";
			printf { $instFH{$inst} } "%.2f,", $jsonHash{$j}{"read ? average length"};
	
		}
	
	
		# parsing and printing illumina xml stuff here
	
		if ($j =~ /\/oicr\/data\/archive\/(.*?)\/(.*?)\/jsonReport/)
		{
			$xmlPath = "/oicr/data/archive/$1/$2/Data/reports/Summary/";
		}
		else
		{
			die "Couldn't parse $j for xml path.\n";
		}
	
		$totalClusters = "n/a";
		$R1phasing = "n/a";
		$R1prephasing = "n/a";
		$R1phixErrorRate = "n/a";
		$R1phixErrorRateSD = "n/a";
	
		if (open (XMLFILE, "$xmlPath/read1.xml"))
		{
			while ($l = <XMLFILE>)      # should just be one line...
			{
				$lane = $jsonHash{$j}{"lane"};
				if ($l =~ /<Lane key="$lane".*?TileCount="(.*?)".*?ClustersRaw="(.*?)".*?PrcPFClusters="(.*?)".*?Phasing="(.*?)" Prephasing="(.*?)".*?ErrRatePhiX="(.*?)" ErrRatePhiXSD="(.*?)"/)
				{
					$totalClusters = $1 * $2;
					$PFrate = $3;
					$R1phasing = $4;
					$R1prephasing = $5;
					$R1phixErrorRate = $6;
					$R1phixErrorRateSD = $7;
				}
			}
			close XMLFILE;
		}
		else
		{
			warn "Couldn't open [$xmlPath/read1.xml]\n";
		}
	
		$R2phasing = "n/a";
		$R2prephasing = "n/a";
		$R2phixErrorRate = "n/a";
		$R2phixErrorRateSD = "n/a";
	
		$i = 2;			# open read files until you find the last one (which is hopefully read 2)
		while (open (XMLFILE, "$xmlPath/read$i.xml"))
		{
			while ($l = <XMLFILE>)      # should just be one line...
			{
				if ($l =~ /<Lane key="$lane".*?TileCount="(.*?)".*?ClustersRaw="(.*?)".*?PrcPFClusters="(.*?)".*?Phasing="(.*?)" Prephasing="(.*?)".*?ErrRatePhiX="(.*?)" ErrRatePhiXSD="(.*?)"/)
				{
					$R2phasing = $4;
					$R2prephasing = $5;
					$R2phixErrorRate = $6;
					$R2phixErrorRateSD = $7;
				}
			}
			close XMLFILE;
			$i++;
		}
	
	
		print { $instFH{$inst} } "$R1phasing,$R1prephasing,$R2phasing,$R2prephasing,";
		print { $instFH{$inst} } "$R1phixErrorRate,$R2phixErrorRate,";
		print { $instFH{$inst} } "$totalClusters, $PFrate,";
	
		$rawReads = $jsonHash{$j}{"mapped reads"} + $jsonHash{$j}{"unmapped reads"} + $jsonHash{$j}{"qual fail reads"};
	
		if ($rawReads > 0)
		{
			$mapRate = ($jsonHash{$j}{"mapped reads"} / $rawReads);
			print { $instFH{$inst} } $mapRate . ",";
		}
		else
		{
			print { $instFH{$inst} } "0,";
		}
	
		# quality calculations
		$qOver30 = 0;
		$qTotal = 0;
		# count first in pair and unpaired reads as read 1
		for my $q (keys %{ $jsonHash{$j}{"read 1 quality histogram"} })
		{
			if ($q >= 30)
			{
				$qOver30 += $jsonHash{$j}{"read 1 quality histogram"}{$q};
			}
			$qTotal += $jsonHash{$j}{"read 1 quality histogram"}{$q};
		}
		for my $q (keys %{ $jsonHash{$j}{"read ? quality histogram"} })
		{
			if ($q >= 30)
			{
				$qOver30 += $jsonHash{$j}{"read ? quality histogram"}{$q};
			}
			$qTotal += $jsonHash{$j}{"read ? quality histogram"}{$q};
		}
		
		if ($qTotal > 0)
		{
			print { $instFH{$inst} } $qOver30 / $qTotal . ",";
		}
		else
		{
			print { $instFH{$inst} } "n/a,";
		}
	
		$qOver30 = 0;
		$qTotal = 0;
		for my $q (keys %{ $jsonHash{$j}{"read 2 quality histogram"} })
		{
			if ($q >= 30)
			{
				$qOver30 += $jsonHash{$j}{"read 2 quality histogram"}{$q};
			}
			$qTotal += $jsonHash{$j}{"read 2 quality histogram"}{$q};
		}
	
		if ($qTotal > 0)
		{
			print { $instFH{$inst} } $qOver30 / $qTotal . ",";
		}
		else
		{
			print { $instFH{$inst} } "n/a,";
		}
	
	
		# mismatch errors
		if (byCycleToCount($jsonHash{$j}{"read 1 aligned by cycle"}) > 0)
		{
			$R1errorRate = ((byCycleToCount($jsonHash{$j}{"read 1 mismatch by cycle"}) + byCycleToCount($jsonHash{$j}{"read 1 insertion by cycle"}) + byCycleToCount($jsonHash{$j}{"read 1 deletion by cycle"})) / byCycleToCount($jsonHash{$j}{"read 1 aligned by cycle"})) * 100;
		}
		else
		{
			$R1errorRate = "n/a";
		}
	
		if (byCycleToCount($jsonHash{$j}{"read 2 aligned by cycle"}) > 0)
		{
			$R2errorRate = ((byCycleToCount($jsonHash{$j}{"read 2 mismatch by cycle"}) + byCycleToCount($jsonHash{$j}{"read 2 insertion by cycle"}) + byCycleToCount($jsonHash{$j}{"read 2 deletion by cycle"})) / byCycleToCount($jsonHash{$j}{"read 2 aligned by cycle"})) * 100;
		}
		else
		{
			$R2errorRate = "n/a";
		}
	
		print { $instFH{$inst} } $R1errorRate . "," . $R2errorRate . ",";
	
		# soft clip errors
		if ((byCycleToCount($jsonHash{$j}{"read 1 aligned by cycle"}) + byCycleToCount($jsonHash{$j}{"read 1 soft clip by cycle"})) > 0)
		{
			$R1softClipRate = byCycleToCount($jsonHash{$j}{"read 1 soft clip by cycle"}) / ( byCycleToCount($jsonHash{$j}{"read 1 aligned by cycle"}) + byCycleToCount($jsonHash{$j}{"read 1 soft clip by cycle"})) * 100;
		}
		else
		{
			$R1softClipRate = "n/a";
		}
	
		if (( byCycleToCount($jsonHash{$j}{"read 2 aligned by cycle"}) + byCycleToCount($jsonHash{$j}{"read 2 soft clip by cycle"})) > 0)
		{
			$R2softClipRate = byCycleToCount($jsonHash{$j}{"read 2 soft clip by cycle"}) / ( byCycleToCount($jsonHash{$j}{"read 2 aligned by cycle"}) + byCycleToCount($jsonHash{$j}{"read 2 soft clip by cycle"})) * 100;
		}
		else
		{
			$R2softClipRate = "n/a";
		}
	
		print { $instFH{$inst} } $R1softClipRate . "," . $R2softClipRate . ",";
	
		print { $instFH{$inst} } $jsonHash{$j}{"reads per start point"} . ",";
	
		if ($jsonHash{$j}{"mapped reads"} > 0)
		{
			$onTargetRate = ($jsonHash{$j}{"reads on target"} / $jsonHash{$j}{"mapped reads"});
		}
		else
		{
			$onTargetRate = "n/a,";
		}
		if (($jsonHash{$j}{"reads per start point"} > 0) and ($onTargetRate ne "n/a,"))
		{
			$estimatedYield = int(($jsonHash{$j}{"aligned bases"} * $onTargetRate) / $jsonHash{$j}{"reads per start point"});
		}
		else
		{
			$estimatedYield = "n/a,";
		}
		if ($estimatedYield ne "n/a,")
		{
			$estimatedCoverage = $estimatedYield / $jsonHash{$j}{"target size"};
		}
		else
		{
			$estimatedCoverage = "n/a,";
		}
	
		print { $instFH{$inst} } $onTargetRate . ",";
		print { $instFH{$inst} } $estimatedYield . ",";
		print { $instFH{$inst} } $estimatedCoverage . ",";
	
		print { $instFH{$inst} } $jsonHash{$j}{"target file"} . ",";
	
	
		print { $instFH{$inst} } "\n";
	}
}




# zip and mail
`cd ${outputDir}; tar -cvzf ${filePrefix}instrument_report.tgz $filePrefix*$fileSuffix; uuencode ${filePrefix}instrument_report.tgz ${filePrefix}instrument_report.tgz | mail -s "${filePrefix}instrument_report.tgz" ${emailUser}\@oicr.on.ca; chmod g+rwx ${filePrefix}*; cd -`;








sub byCycleToCount
{
    my $histRef = $_[0];

    my $sum = 0;
    for my $i (keys %{$histRef})
    {
        $sum += $histRef->{$i};
    }

    return $sum;
}

