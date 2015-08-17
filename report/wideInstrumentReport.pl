#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use Data::Dumper;
use Cwd;
use POSIX qw/strftime/;

my @jsonFiles = @ARGV;

my %jsonHash;
my $outputDir;
my $line;
my $file;

my $timeStamp=""; 
my $filePrefix="";
my $fileSuffix="";
my $logtime=strftime('%Y-%m-%d',localtime);

# Loops through input arguments and sorts filenames from variables
# If input is a JSON file, file is decoded into perl hash 
for $file (@jsonFiles)
{
	if($file =~ /\d{6} \d{2}\:\d{2} \w{3} \w{3}/)
	{
		$timeStamp = $file;
	
		# prints time stamp to error log
		select((select(STDOUT), $|=1)[0]);
		print STDOUT "Time Stamp: $timeStamp\n";
	}
	elsif($file =~ /\d{6}_\d{2}\:\d{2}_/)
	{
		$filePrefix = $file;
	} 
	elsif($file =~ /.csv/)
	{
		$fileSuffix = $file;
	}
	elsif($file =~ /.json/)
	{
		if (open (FILE, $file))
                {
                        if ($line = <FILE>)
                        {
                                $jsonHash{$file} = decode_json($line);
                        }
                        else
                        {
                                warn "No data found in $file\n";
                        }
                        close FILE;
                }
		elsif($file =~ /\*/)
		{
			warn "No JSON Reports Found in $file\n";
		}
                else
                {
                        warn "Couldn't open $file\n";
                }
	}
	else
	{
		$outputDir = $file;
		print "Output Dir: $outputDir\n";
	}	
}

# time stamp for log files are printed

printTimeStamp($outputDir, "xml_missing.txt", $timeStamp);
printTimeStamp($outputDir, "xml_present.txt", $timeStamp);
printTimeStamp($outputDir, "binary_missing.txt", $timeStamp);
printTimeStamp($outputDir, "binaryxml_missing.txt", $timeStamp);

# current list of reported fields
my $reportFields = "Run,Lane,Barcode,Library,Insert Mean,Insert Stdev,Read Length,R1 Phasing, R1 Prephasing, R2 Phasing, R2 Prephasing, R1 PhiX Error %, R2 PhiX Error %, # Raw Clusters, PF %, Uniquely Mapped %,R1 % >= q30,R2 % >= q30,R1 Error %,R2 Error %,R1 Soft Clip %,R2 Soft Clip %, Est Reads/SP,% on Target,Est Yield,Est Coverage,Coverage Target,Source,Comments";

my @fieldOrder = split(/,\s+|,/, $reportFields);
my %reportHash;

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

my $fileName;

my $R1errorRate;
my $R2errorRate;
my $R1softClipRate;
my $R2softClipRate;

# for illumina numbers:

=pod
####  Tile Metric Code Legend ####   

code 100: cluster density (k/mm2)
code 101: cluster density passing filters (k/mm2)
code 102: number of clusters
code 103: number of clusters passing filters
code (200 + (N – 1) * 2): phasing for read N
code (201 + (N – 1) * 2): prephasing for read N
code (300 + N – 1): percent aligned for read N
code 400: control lane
=cut

my $l;
my $i;
my $xmlPath;
my $xmlpathPrev = "n/a";
my $lane;

my $runxmlPath;
my $runPrev = "n/a";
my $read1;
my $read2;
my $metricHashref;
my $errorHashref;

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
my @sourceFile = ("XML","BIN","NIL"); # Illumina data comes from read XML or Binary files
my $Source;

for my $j (sort keys %jsonHash)
{
	%reportHash = ();

	$inst = $jsonHash{$j}{"instrument"}; 

	if(defined $inst)
	{
		$inst =~ s/SN/h/;
	}
	else
	{
		$inst = "InstrumentMissing";
	}

	$fileName = $filePrefix . $inst . $fileSuffix;
	unless (exists $instFH{$inst})
	{
		open (FILE, ">$outputDir/$fileName") or die "Couldn't open $fileName for write.\n";	
		$instFH{$inst} = \*FILE;

		print { $instFH{$inst} } $reportFields . "\n";
	}

	$reportHash{"Run"} = $jsonHash{$j}{"run name"}; 
	
	# lane is determined from file name or file contents (conventions vary)
	if(exists $jsonHash{$j}{"lane"})
	{	
		($lane, $reportHash{"Lane"}) = determineLane($j, $jsonHash{$j}{"lane"}, $outputDir);
	}
	else
	{
        	open (MissingLane, ">$outputDir/missing_lane.txt");
        	print MissingLane "$logtime Lane not defined in $j\n";
        	close MissingLane;
        	die "Lane not defined in $j\n";
        }
	
	if (exists $jsonHash{$j}{"barcode"})
	{
		$reportHash{"Barcode"} = $jsonHash{$j}{"barcode"};
	}
	else
	{
		$reportHash{"Barcode"} = "noIndex";
	}
	
	$reportHash{"Library"} =  $jsonHash{$j}{"library"};

	if ($jsonHash{$j}{"number of ends"} eq "paired end")
	{
		$reportHash{"Insert Mean"} = $jsonHash{$j}{"insert mean"};
		$reportHash{"Insert Stdev"} = $jsonHash{$j}{"insert stdev"};
		$reportHash{"Read Length"} = $jsonHash{$j}{"read 1 average length"} . "/" . $jsonHash{$j}{"read 2 average length"};
	}
	else
	{
		$reportHash{"Insert Mean"} = "n/a";
		$reportHash{"Insert Stdev"} = "n/a";
		$reportHash{"Read Length"} = $jsonHash{$j}{"read ? average length"};
	}


	# parsing illumina InterOp/SAV stuff here
	if ($j =~ /\/oicr\/data\/archive\/(.*?)\/(.*?)\/jsonReport/)
	{
		$xmlPath = "/oicr/data/archive/$1/$2/Data/reports/Summary";
		$runxmlPath = "/oicr/data/archive/$1/$2";
	}
	else
	{
		die "Input string $j doesn't match /oicr/data/archive/*/*/jsonReport during parsing for xml path.\n";
	}
	
	# read XML are parsed if available
	if(-d "$xmlPath")
	{
		# read1.xml is checked for existence, opened, and parsed
		# error messages are output accordingly 
		if (-e "$xmlPath/read1.xml" or -e "$xmlPath/read1.xml.gz")
		{
		        if (not open (XMLFILE, "$xmlPath/read1.xml"))
	        	{
	                	if (not open (XMLFILE,"gzip -dc $xmlPath/read1.xml.gz|"))
		                {
		                        print ("$logtime Missing $xmlPath/read1.xml or read1.xml.gz");
				}
		        }
	
			while ($l = <XMLFILE>)      # should just be one line...
			{
				if ($l =~ /<Lane key="$lane".*?TileCount="(.*?)".*?ClustersRaw="(.*?)".*?PrcPFClusters="(.*?)".*?Phasing="(.*?)" Prephasing="(.*?)".*?ErrRatePhiX="(.*?)" ErrRatePhiXSD="(.*?)"/)
				{
					# data is classified as XML
					$reportHash{"XML"}{"# Raw Clusters"} = $1 * $2;
					$reportHash{"XML"}{"PF %"} = $3;
					$reportHash{"XML"}{"R1 Phasing"} = $4;
					$reportHash{"XML"}{"R1 Prephasing"} = $5;
					$reportHash{"XML"}{"R1 PhiX Error %"} = $6;
					$reportHash{"XML"}{"R1phixErrorRateSD"} = $7;
				}
			}
			close XMLFILE;
			open(XMLPATH, ">>$outputDir/xml_present.txt");
			print XMLPATH "$logtime $xmlPath/read1.xml\n";
			close XMLPATH;
		}
		elsif($xmlpathPrev ne $xmlPath)
		{
			open(NOXMLPATH, ">>$outputDir/xml_missing.txt");
                	print NOXMLPATH "$logtime Couldn't Find [$xmlPath/read1.xml]\n";
			print NOXMLPATH "$logtime $xmlpathPrev\n";
			close NOXMLPATH;
		}
		$i = 2;			# open read files until you find the last one (which is hopefully read 2)
		# Opens and parses read2.xml if it exists
		# read number is incremented - the highest read XML will contain the values for read2 
		while(-e "$xmlPath/read$i.xml" or -e "$xmlPath/read$i.xml.gz")
		{
			if (not open(XMLFILE, "$xmlPath/read$i.xml"))
			{
				if (not open (XMLFILE, "gzip -dc $xmlPath/read$i.xml.gz|"))
				{
					print("$logtime Missing $xmlPath/read$i.xml or read$i.xml.gz");
					# assigns 'n/a' in place of missing data if read2.xml doesn't exist
					$reportHash{"XML"}{"R2 Phasing"} = "n/a";
					$reportHash{"XML"}{"R2 Prephasing"} = "n/a";
				        $reportHash{"XML"}{"R2 PhiX Error %"} = "n/a";
				        $reportHash{"XML"}{"R2phixErrorRateSD"} = "n/a";
				}
			}
			
			while ($l = <XMLFILE>)      # should just be one line...
			{
				while ($l =~ /<Lane key="$lane".*?TileCount="(.*?)".*?ClustersRaw="(.*?)".*?PrcPFClusters="(.*?)".*?Phasing="(.*?)" Prephasing="(.*?)".*?ErrRatePhiX="(.*?)" ErrRatePhiXSD="(.*?)".*>/g)
				{
					# data is classified as XML
					$reportHash{"XML"}{"R2 Phasing"} = $4;
					$reportHash{"XML"}{"R2 Prephasing"} = $5;
					$reportHash{"XML"}{"R2 PhiX Error %"} = $6;
					$reportHash{"XML"}{"R2phixErrorRateSD"} = $7;
				}
			}
			close XMLFILE;
			
			open(XMLPATH, ">>$outputDir/xml_present.txt");
                        print XMLPATH "$xmlPath/read$i.xml\n";
                        close XMLPATH;
			
			$i++;
		}
		
		if($i == 2)
		{
			warn "Couldn't open [$xmlPath/read2.xml]\n";
			# assigns 'n/a' in place of missing data if read2.xml doesn't exist
			$reportHash{"XML"}{"R2 Phasing"} = "n/a";
	                $reportHash{"XML"}{"R2 Prephasing"} = "n/a";
	                $reportHash{"XML"}{"R2 PhiX Error %"} = "n/a";
	                $reportHash{"XML"}{"R2phixErrorRateSD"} = "n/a";
		
			open(NOXMLPATH, ">>$outputDir/xml_missing.txt");
			print NOXMLPATH "$logtime Couldn't Find [$xmlPath/read2.xml]\n";
			
			print NOXMLPATH "$logtime $xmlpathPrev\n";
			close NOXMLPATH;
	       	}
		
		$reportHash{"XML"}{"Source"} = "Read XML";	
	}#end if XML
	elsif($xmlpathPrev ne $xmlPath)
	{
		open(NOXMLPATH, ">>$outputDir/xml_missing.txt");
                print NOXMLPATH "$logtime Couldn't Find [$xmlPath/read1.xml]\n";
		print NOXMLPATH "$logtime Couldn't Find [$xmlPath/read2.xml]\n";
		close NOXMLPATH;
	}
	
	# InterOp/SAV binary files are parsed if available
	# Both TileMetricOut and ErrorMetricOut must exist for a full dataset 
	if(-e "$runxmlPath/InterOp/TileMetricsOut.bin" && -e "$runxmlPath/InterOp/ErrorMetricsOut.bin")
	{	
		
		# Retrieves binary data for each different run
		if($runPrev ne $jsonHash{$j}{"run name"})
		{
			# checks for and creates any missing InterOp/SAV JSON data
			if(!-d "$runxmlPath/InterOp/JSON")
			{
				# if file system is read-only creates temp directory for JSON output
				#$outDir = determineJsonOutDir($runxmlPath, $reportHash{"Run"});
				# Target outDir for JSON files no longer supported - if create JSON below fails, error logged
				
				# creates JSON directory
				`oicr_illuminaSAV_bin_to_json.pl --runDir $runxmlPath`;
			}
			elsif(!-e "$runxmlPath/InterOp/JSON/TileMetricsOut.bin.json" && !-e "$runxmlPath/InterOp/JSON/ErrorMetricsOut.bin.json")
			{
				# if file system is read-only creates temp directory for JSON output
				#$outDir = determineJsonOutDir($runxmlPath, $reportHash{"Run"});
				# Target outDir for JSON files no longer supported - if create JSON below fails, error logged
				
				# creates necessary JSON files if they don't exist in JSON directory
				`oicr_illuminaSAV_bin_to_json.pl --runDir $runxmlPath`;
			}
			elsif((-e "$runxmlPath/InterOp/JSON/TileMetricsOut.bin.json") != (-e "$runxmlPath/InterOp/JSON/ErrorMetricsOut.bin.json"))
			{ 
				# if file system is read-only creates temp directory for JSON output
				#$outDir = determineJsonOutDir($runxmlPath, $reportHash{"Run"});
				# Target outDir for JSON files no longer supported - if create JSON below fails, error logged
				
				# removes JSON dir and recreates JSON dir contents of one JSON doesn't exist
				`rm -r $runxmlPath/InterOp/JSON;`;
				`oicr_illuminaSAV_bin_to_json.pl --runDir $runxmlPath`;
			}
			
			# retrieves data from InterOp/SAV files and read information
			($read1, $read2, $metricHashref, $errorHashref) = getBinaryData($runxmlPath);
			
		}
		
		# assigns retrieved data to the report hash classified as BIN data
		# metric codes correspond to different metric values based on the value of read1 and read2
		# More info - refer to Tile Metric Code Legend above or illumina's RTA Theory of Operations documentation
		$reportHash{"BIN"}{"R1 Phasing"} = $metricHashref->{$lane}{(200+($read1-1)*2)}{value};
		$reportHash{"BIN"}{"R1 Prephasing"} = $metricHashref->{$lane}{(201+($read1-1)*2)}{value};
		$reportHash{"BIN"}{"R1 PhiX Error %"} = $errorHashref->{$lane}{$read1}{value};

		$reportHash{"BIN"}{"R2 Phasing"} = $metricHashref->{$lane}{(200+($read2-1)*2)}{value};	
		$reportHash{"BIN"}{"R2 Prephasing"} = $metricHashref->{$lane}{(201+($read2-1)*2)}{value};
		$reportHash{"BIN"}{"R2 PhiX Error %"} = $errorHashref->{$lane}{$read2}{value};
			
		$reportHash{"BIN"}{"# Raw Clusters"} = $metricHashref->{$lane}{102}{value};

		# PF % = (# clusters passing filters) / (total cluster) * 100
		$reportHash{"BIN"}{"PF %"} = ($metricHashref->{$lane}{103}{value}/$metricHashref->{$lane}{102}{value})*100 if $metricHashref->{$lane}{102}{value};
		
		$reportHash{"BIN"}{"Source"} = "Binary";
		
		# reports instances of 'not a number' values in comments
		$reportHash{"Comments"} = checkNAN($metricHashref) .  " - " . checkNAN($errorHashref);
		
	}
	elsif($runPrev ne $jsonHash{$j}{"run name"})
	{		
		# every run any missing InterOp/SAV files are printed to log files
		# note: only one set of InterOp/SAV files per run	
		if(!-e "$runxmlPath/InterOp/TileMetricsOut.bin")
		{
			open(NOBIN, ">>$outputDir/binary_missing.txt");
			print NOBIN "$logtime Couldn't Find [$runxmlPath/InterOp/TileMetricsOut.bin]\n";
			close NOBIN;
		}
		
		if(!-e "$runxmlPath/InterOp/ErrorMetricsOut.bin")
		{
			open(NOBIN, ">>$outputDir/binary_missing.txt");
			print NOBIN "$logtime Couldn't Find [$runxmlPath/InterOp/ErrorMetricsOut.bin]\n";
			close NOBIN;
		}
	}
	
	# determines current status of illumina metric value source files	
	my $missingBothBin = "true" if (!-e "$runxmlPath/InterOp/TileMetricsOut.bin") && (!-e "$runxmlPath/InterOp/TileMetricsOut.bin");
	my $missingOneBin = "true" if (!-e "$runxmlPath/InterOp/TileMetricsOut.bin") != (!-e "$runxmlPath/InterOp/ErrorMetricsOut.bin");
	my $missingXML = "true" if (!-d "$xmlPath");
	my $missingInterOp = "true" if (!-d "$runxmlPath/InterOp");
	
	# If read XML and one or more InterOp/SAV binaries do not exist
	# errors are reported and reportHash values set to 'n/a'  
	if($missingXML && ($missingOneBin || $missingBothBin))
	{
		if($missingInterOp)
		{
			open(NOBINorXML, ">>$outputDir/binaryxml_missing.txt");
                        if($runPrev ne $jsonHash{$j}{"run name"})
                        {
                                print NOBINorXML "$logtime Couldn't Find [$xmlPath]\n";
                                print NOBINorXML "$logtime Couldn't Find [$runxmlPath/InterOp]\n";
                        }
                        close NOBINorXML;
		}
		elsif($missingBothBin)
		{
			open(NOBINorXML, ">>$outputDir/binaryxml_missing.txt");
                        if($runPrev ne $jsonHash{$j}{"run name"})
                        {
                                print NOBINorXML "$logtime Couldn't Find [$xmlPath]\n";
                                print NOBINorXML "$logtime Couldn't Find [$runxmlPath/InterOp/TileMetricsOut.bin]\n";
                                print NOBINorXML "$logtime Couldn't Find [$runxmlPath/InterOp/ErrorMetricsOut.bin]\n";
                        }
                        close NOBINorXML;
		}
		elsif($missingOneBin)
		{
			open(NOBINorXML, ">>$outputDir/binaryxml_missing.txt");
                        if($runPrev ne $jsonHash{$j}{"run name"})
                        {
                                print NOBINorXML "$logtime Couldn't Find [$xmlPath]\n";

                                if(-e "$runxmlPath/InterOp/TileMetricsOut.bin")
                                {
                                        print NOBINorXML "$logtime Couldn't Find [$runxmlPath/InterOp/ErrorMetricsOut.bin]\n";
                                }
                                else
                                {
                                        print NOBINorXML "$logtime Couldn't Find [$runxmlPath/InterOp/TileMetricsOut.bin]\n";
                                }
                        }
                        close NOBINorXML;
		}
		
		# assigns 'n/a' in place of missing data and classifies as NIL 
		$reportHash{"NIL"}{"R1 Phasing"} = "n/a";
		$reportHash{"NIL"}{"R1 Prephasing"} = "n/a";
		$reportHash{"NIL"}{"R1 PhiX Error %"} = "n/a";

		$reportHash{"NIL"}{"R2 Phasing"} = "n/a";
		$reportHash{"NIL"}{"R2 Prephasing"} = "n/a";
		$reportHash{"NIL"}{"R2 PhiX Error %"} = "n/a";

		$reportHash{"NIL"}{"# Raw Clusters"} = "n/a";
		$reportHash{"NIL"}{"PF %"} = "n/a";

		$reportHash{"NIL"}{"Source"} = "Nil";
	}
	
	# sets previous xml path and run
	$xmlpathPrev = $xmlPath; 
	$runPrev = $jsonHash{$j}{"run name"};
	
	$rawReads = $jsonHash{$j}{"mapped reads"} + $jsonHash{$j}{"unmapped reads"} + $jsonHash{$j}{"qual fail reads"};

	if ($rawReads > 0)
	{
		$mapRate = ($jsonHash{$j}{"mapped reads"} / $rawReads);
		$reportHash{"Uniquely Mapped %"} =  $mapRate;
	}
	else
	{
		$reportHash{"Uniquely Mapped %"} = "0";
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
		$reportHash{"R1 % >= q30"} = $qOver30 / $qTotal;
	}
	else
	{
		$reportHash{"R1 % >= q30"} = "n/a";
	}

	$qOver30 = 0;
	$qTotal = 0;
	for my $q (keys %{ $jsonHash{$j}{"read 2 quality histogram"} })
	{
		if ($q >= 30)
		{
			$qOver30 += $jsonHash{$j}{"read 2 quality histogram"}{$q};
		}
		$qTotal += $jsonHash{$j}{"read 2 quality histogram"}{$q}
	}

	if ($qTotal > 0)
	{
		$reportHash{"R2 % >= q30"} = $qOver30 / $qTotal;
	}
	else
	{
		$reportHash{"R2 % >= q30"} = "n/a";
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

	$reportHash{"R1 Error %"} = $R1errorRate;
	$reportHash{"R2 Error %"} = $R2errorRate;

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

	$reportHash{"R1 Soft Clip %"} = $R1softClipRate;
	$reportHash{"R2 Soft Clip %"} = $R2softClipRate;

	$reportHash{"Est Reads/SP"} = $jsonHash{$j}{"reads per start point"};

	if ($jsonHash{$j}{"mapped reads"} > 0)
	{
		$onTargetRate = ($jsonHash{$j}{"reads on target"} / $jsonHash{$j}{"mapped reads"});
	}
	else
	{
		$onTargetRate = "n/a";
	}
	if (($jsonHash{$j}{"reads per start point"} > 0) and ($onTargetRate ne "n/a"))
	{
		$estimatedYield = int(($jsonHash{$j}{"aligned bases"} * $onTargetRate) / $jsonHash{$j}{"reads per start point"});
	}
	else
	{
		$estimatedYield = "n/a";
	}
	if ($estimatedYield ne "n/a")
	{
		$estimatedCoverage = $estimatedYield / $jsonHash{$j}{"target size"};
	}
	else
	{
		$estimatedCoverage = "n/a";
	}

	$reportHash{"% on Target"} = $onTargetRate;
	$reportHash{"Est Yield"} = $estimatedYield;
	$reportHash{"Est Coverage"} = $estimatedCoverage;

	$reportHash{"Coverage Target"} =  $jsonHash{$j}{"target file"};

	iterateReportHash($instFH{$inst}, \%reportHash, \@sourceFile);

}

# SUBROUTINES

# Determines lane based on JSON file naming convention or content
sub determineLane
{
	my ($j, $jsonHashLane, $outputDir) = @_;
	my $reportHashLane;                      # lane value that will be printed in the report
	my $lane;                                # lane value used in parsing InterOp/SAV files

	# currently two file formats that specify lane in the filename
	if($j =~ /(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_L0{2}(\d)_(.*?)/ )
	{
		$reportHashLane = $13;
		$lane = $13;
	}
	else
        {
                $reportHashLane = $jsonHashLane;
                $lane = $jsonHashLane;
        }

	if($j =~ /(.*?)_(.*?)_(.*?)_(.*?)_(\d)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)_(.*?)\.json/)
        {
                #lane in InterOp/SAV files doesn't match this files of this naming convention
		if($5 . "_" . $6 eq $jsonHashLane)
                {          
			$reportHashLane = $5 . "_" . $6; 
			$lane = $5;
                }
		else
		{
			$reportHashLane = $jsonHashLane;
			$lane = $jsonHashLane;
		}
        }
	
	return ($lane, $reportHashLane);
}

sub byCycleToCount
{
	my $histRef = $_[0];

	for my $i (keys %{$histRef})
	{
		$sum += $histRef->{$i};
	}

	return $sum;
}

sub printTimeStamp
{
	my ($outputDir, $targetFile, $timeStamp) = @_;
	open(FILEHANDLE, ">>$outputDir/$targetFile");
	select((select(FILEHANDLE), $|=1)[0]);  # Flushes FileHandle buffer
	print FILEHANDLE "$timeStamp\n";
	close FILEHANDLE;
}

# checks for write permissions within a run directory
# if it is a read-only file system, assigns and returns a 
# temporary JSON output directory within the user's current 
# working directory
sub determineJsonOutDir
{
	my ($runxmlPath, $reportHashRun) = @_;
	my $outDir = $runxmlPath;
	
	unless(`touch $runxmlPath/writable.txt`)
	{
		$outDir = getcwd() . "/" . $reportHash{"Run"};  # unique/run specific temp directory
	}
	else
	{
		`rm $runxmlPath/writable.txt`;  # removes writable file if it was created
	}
	return $outDir;
}


# parses RunInfo.xml for NumCycles, IsIndexedRead, read1, and read2
sub readRunInfoXML
{
	my $runxmlPath = shift;
	my %readHash; # Stores data for each read

	my $read1;
	my $read2;
	my $firstRead = 1; 
	
	my $l;
	
	if (not open (XML, "$runxmlPath/RunInfo.xml")) 
	{
		if (not open (XML,"gzip -dc $runxmlPath/RunInfo.xml.gz|"))
		{
			print ("$logtime Missing $runxmlPath/RunInfo.xml or RunInfo.xml.gz");
		}
	}
	
	while($l = <XML>)
	{
		my $readNum;
		if($l =~ /<Read.* Number="(.*?)".*>/)
                {
			$readNum=$1;
			if($l =~ /<Read.* NumCycles="(.*?)".*>/)
			{
				$readHash{$readNum}{NumCycles} = $1;
			}

			if($l =~ /<Read.* IsIndexedRead="(.*?)".*>/)
			{
				$readHash{$readNum}{IsIndexedRead} = $1;
			}
			if($readHash{$readNum}{IsIndexedRead} eq 'N')
			{
				if($firstRead) # The first non-indexed read is read1
				{
					$read1 = $readNum;
					$firstRead = 0;
				}
				#read2 will be the last non-indexed read
				else 
				{
					$read2 = $readNum;
				}
			}
		}
	}

	if (not defined $read1 or not defined $read2)
	{
		print("$logtime Missing Read Number, NumCycles and IsIndexedRead in RunInfo.xml at $runxmlPath\n");
	}
        close XML;
	
	return ($read1, $read2, \%readHash);
}

# decodes JSON InterOp/SAV files and pushes contents to tile metric and error metric arrays
sub decodeJSON
{	
	my $runxmlPath = shift;
	my @interopFiles = ("$runxmlPath/InterOp/JSON/TileMetricsOut.bin.json", "$runxmlPath/InterOp/JSON/ErrorMetricsOut.bin.json");
	
	my $line;
	my $file;
	my @tileArray;
	my @errorArray;

	for $file (@interopFiles)
	{
		$line = "";
		if (open (INTEROP, $file))
		{
			while (<INTEROP>)
			{
				$_ =~ s/-nan/"nan"/; 	# replaces any 'not a number' values with a JSON readable string
				$line .= $_;	 	# file contents appended to a single string
			}

			if ($file =~ /TileMetricsOut.bin.json/)
			{		
				push @tileArray, @{decode_json($line)}; # push and dereference, array reference returned by decode_json()
			}
			elsif ($file =~ /ErrorMetricsOut.bin.json/)
			{
				push @errorArray, @{decode_json($line)};
			}

			close INTEROP;
		}
		else
		{
			warn "Couldn't open $file\n";
		}

	}
	return (\@tileArray, \@errorArray);
}

# Parses ErrorMetric data, stores/associates values by lane and read
sub getErrorData
{
	my ($read1, $read2, $errorArrayRef, $readHashRef, $tileHashRef, $laneHashRef) = @_;
	my @errorArray = @$errorArrayRef;  # Array of hashes containing error data
	my %readHash = %$readHashRef;
	my %tileHash = %$tileHashRef;
	my %laneHash = %$laneHashRef;
	
	my %errorHash; # stores error metric data
		
	my $num_tiles = keys %tileHash;
	
	# calculates number of errors per read
	# errors per read = 1 error per tile * total tiles per cycle * number of cycles per read
	my $num_err_read1 = $num_tiles * $readHash{$read1}{NumCycles};
	my $num_err_read2 = $num_tiles * $readHash{$read2}{NumCycles};
	
	# associates and assigns each error value with a lane, read, and data type (value/nan)
	# loops through every array entry, of every cycle, of every read, of every lane 
	foreach my $lane (sort{$a <=> $b} keys %laneHash)
	{
		my $cycleStart = 0;
		my $cycleEnd = 0;
		for my $read (keys %readHash)
		{
			# determines which range of cycles corresponds to each read
			# ie. read1 consisted of cycles 1-101, read2 was cycles 102-203
			if ($read == 1)
			{
				$cycleStart = 1;
			}
			else
			{
				$cycleStart += $readHash{$read-1}{NumCycles};  
			}
			$cycleEnd = $cycleStart + $readHash{$read}{NumCycles};
			
			if ($read == $read1 || $read == $read2)	# only data from read1 and read2 will be stored
			{		
				for my $cycle ($cycleStart .. $cycleEnd) # a read is a specific range of cycles
				{
					for my $index (@errorArray)      # loops through every error data entry from ErrorMetricOut.bin.json
					{
						if($index->{cycle} == $cycle && $index->{lane} == $lane)
						{
							if($index->{err_rate} eq "nan")		# stores occurence of 'not a number' values
                                        		{
                                                		$errorHash{$lane}{$read}{nan} = "true";
                                        		}
                                        		else
                                        		{
                                                		# err_rate is summed to calculate an average per lane
								$errorHash{$lane}{$read}{value} += $index->{err_rate};
                                        		}
						}
					}
				}
			}
		}
		
		# calculates average error rate for read1
		if(exists $errorHash{$lane}{$read1}{value})
		{
			$errorHash{$lane}{$read1}{value} /= $num_err_read1;
		}
		else
		{
			$errorHash{$lane}{$read1}{value} = "n/a";
		}
		
		# calculates averages error rate for read2
		if(exists $errorHash{$lane}{$read2}{value})
		{	
                        $errorHash{$lane}{$read2}{value} /= $num_err_read2;
		}
		else
                {
                        $errorHash{$lane}{$read2}{value} = "n/a";
                }
	}

	return \%errorHash;
}

# Parses TileMetric data, store/associates values by lane and metric code
sub getTileData
{
	my ($read1, $read2, $tileArrayRef, $metricHashRef, $tileHashRef, $laneHashRef) = @_;
	my @tileArray = @$tileArrayRef;
	my %metricHash = %$metricHashRef; # lists of tile metric codes found in TileMetricOut.bin.json
	my %tileHash = %$tileHashRef;
	my %laneHash = %$laneHashRef;
	
	my $num_tiles = keys %tileHash;	
	
	my %metrics; # stores tile metric data
	
	# associates and assigns each metric value to a lane, metric code and data type (value/nan)
	# loops through every array entry, for every tile metric value in each lane 
	foreach my $lane (sort{$a <=> $b} keys %laneHash)
	{
		foreach my $metric (sort{$a <=> $b} keys %metricHash)
		{
			for my $index (@tileArray)
			{
				if($index->{metric} == $metric && $index->{lane} == $lane) # Array entry must match metric code and lane
				{
					if($index->{metric_val} eq "nan")		# stores occurence of 'not a number' values
					{
						$metrics{$lane}{$metric}{nan} = "true"; 
					}
					else
					{
						# metric values are summed to get totals and later calc averages
						$metrics{$lane}{$metric}{value} += $index->{metric_val};
					}
				}
			}
			
			# average percentage is calculated for read1 and read2 Phasing/Prephasing 
			if($metric == (200+($read1-1)*2) || $metric == (201+($read1-1)*2) || $metric == (200+($read2-1)*2) || $metric == (201+($read2-1)*2))
			{
				$metrics{$lane}{$metric}{value} /= $num_tiles;
				$metrics{$lane}{$metric}{value} *= 100; # multiply by 100 because Phas/Prephas is reported in decimal
			}
		}
	}
	
	return \%metrics;
}

# checks if a 'not a number' value was found and returns an error comment
sub checkNAN
{
	my $HashRef = shift;
	my %Hash = %$HashRef;
	my $comment="";

	foreach my $lane (keys %Hash)
	{
		foreach my $read (keys %{$Hash{$lane}})
		{
			if(exists $Hash{$lane}{$read}{nan} && keys %{$Hash{$lane}} > 4)  # tileHash will only have 4 keys 
			{
				$comment = "A \"nan\" metric value was found in TileMetricsOut.bin.json";
			}
			elsif(exists $Hash{$lane}{$read}{nan})
			{
				$comment = "A \"nan\" error rate was found in ErrorMetricsOut.bin.json";
			}
		}
	}

	return $comment;
}

# Retrieves all binary data
sub getBinaryData
{
	my ($runxmlPath) = @_;
	
	# decodes JSON files
	#my ($tileArrayRef, $errorArrayRef) = decodeJSON($outDir); - TAB 20140811
	my ($tileArrayRef, $errorArrayRef) = decodeJSON($runxmlPath);
	my @tileArray = @$tileArrayRef;
	my @errorArray = @$errorArrayRef;
	
	# reads RunInfo.xml for read information
	my ($read1, $read2, $readHashRef) = readRunInfoXML($runxmlPath);
	my %readHash = %$readHashRef;

	my %cycleHash;
	my %tileHash;
	my %laneHash;
	my %metricHash;
	
	my %errorlaneHash;
	
	# stores cycles and lanes found in ErrorMetricOut.bin.json
	# into the keys of a hash
	for my $index (@errorArray)
	{
		$cycleHash{$index->{cycle}} = 0;
		$errorlaneHash{$index->{lane}} = 0;
	}

	# stores metric codes, tiles, and lanes found in TileMetricsOut.bin.json
	# into the keys of a hash
	for my $index (@tileArray)
	{
		$metricHash{$index->{metric}} = 0;
		$tileHash{$index->{tile}} = 0;
		$laneHash{$index->{lane}} = 0;
	}
	
	# retrieves error data categorized by lane and read
	my $errorHashRef = getErrorData($read1, $read2, $errorArrayRef, \%readHash, \%tileHash, \%laneHash);
	my %errorHash = %$errorHashRef;
	
	# retrieves tile data categorized by lane and metric code
	my $metricsRef = getTileData($read1, $read2, $tileArrayRef, \%metricHash, \%tileHash, \%laneHash);
	my %metrics = %$metricsRef;
	
	return ($read1, $read2, \%metrics,\%errorHash);
}

# Determines if a value is a float and prints value to specified decimal place
sub determineFormat
{
	my($value, $fileHandle, $point, $field) = @_;
	
	if(!defined $value)
	{
		print "$logtime Value Not Defined for $field\n";
                print $fileHandle "n/a (was not defined),";
	}
	elsif($value  =~ /^[+-]?\d*\.?\d+$/)
        {
        	printf $fileHandle "%.". $point . "f,", $value;
        }
	else
	{
		print $fileHandle $value . ",";
	}
}

# Prints a field in the report, with proper formatting 
sub printReportField
{	
	my ($fileHandle, $reportHashref, $src, $field) = @_;
	my %reportHash = %$reportHashref;
	
	if($field eq "R1 Phasing" || $field eq "R1 Prephasing" || $field eq "R2 Phasing" || $field eq "R2 Prephasing")
	{
		determineFormat($reportHash{$src}{$field}, $fileHandle, 3, $field); # prints illumina metrics with 3 decimal places
	}
	elsif($field eq "R1 PhiX Error %" || $field eq "R2 PhiX Error %" || $field eq "PF %")
	{	
		determineFormat($reportHash{$src}{$field}, $fileHandle, 2, $field); # prints illumina metrics with 2 decimal places
	}
	elsif($field eq "# Raw Clusters" || $field eq "Source")
	{
		print $fileHandle $reportHash{$src}{$field} . ",";	# prints illumina metrics with no decimal places
	}
	elsif($field eq "Insert Mean" || $field eq "Insert Stdev" || $field eq "Read Length")
	{
		determineFormat($reportHash{$field}, $fileHandle, 2, $field);   # prints other metrics with 2 decimal places
	}
	elsif($field eq "Comments")
	{
		if(exists $reportHash{$field})
		{
			print $fileHandle $reportHash{$field};
			print $fileHandle "\n";
		}
		else
		{
			print $fileHandle "\n";
		}
	}
	else
	{
		print $fileHandle $reportHash{$field} . ",";
	}
}

# Iterates through the reportHash to print its contents
sub iterateReportHash
{
	my ($fileHandle, $reportHashref, $sourceFileRef) = @_;
	my %reportHash = %$reportHashref;
	my @sourceFile = @$sourceFileRef;

	for my $src (@sourceFile)		# loops through by source type
	{
		if(exists $reportHash{$src})	# will only print an entry if src type exists
		{
			for my $field (@fieldOrder) # iterates field headings and prints	
			{
				printReportField($fileHandle, \%reportHash, $src, $field);
			}
			
		}
	}	
}
