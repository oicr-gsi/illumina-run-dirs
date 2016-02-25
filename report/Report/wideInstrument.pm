package Report::wideInstrument;
use strict;
use warnings;
use JSON;
use Data::Dumper;
use Cwd;

our @ISA = qw (Exporter);
our @EXPORT_OK = qw(get_instrument_report determineInstrument retrieveReadXML retrieveRunXML checkMissingFiles);

# Provide run name, lane, barcode and returns wide instrument report in JSON format of that specified sample
sub get_instrument_report {
    my ( $runName, $lane, $barcode ) = @_;
    my %jsonHash;
    my %jsonReportHash;

    # Determine instrument and paths
    my $instrument;
    if ( $runName =~ /^\d{6}_(.*?)_.*/ ) {
        $instrument = $1;
    }
    $instrument = parseInstrument($instrument);
    # Read1.xml and Read2.xml
    my $xmlPath = "/oicr/data/archive/$instrument/$runName/Data/reports/Summary";    
    # RunInfo.xml   
    my $runxmlPath = "/oicr/data/archive/$instrument/$runName";    

    # Determine jsonFile location
    my $jsonFilePath = "/oicr/data/archive/${instrument}/${runName}/jsonReport";
    my @jsonFiles;
    my $jsonFile;
    if ( -d $jsonFilePath ) {
		opendir JSONPATH, $jsonFilePath or die "Couldn't open directory: $!";
		@jsonFiles =
		  grep( /.*_${runName}_${barcode}_L00${lane}_.*\.json$/, readdir JSONPATH );
		if ( !defined $jsonFiles[0] ) {
			rewinddir JSONPATH;
			@jsonFiles = grep(/^${runName}_${lane}_.*_${barcode}_.*\.json$/, readdir JSONPATH );
		}
		if ( defined $jsonFiles[0] ) {
			$jsonFile = $jsonFilePath . '/' . $jsonFiles[0];
			if ( open( FILE, $jsonFile ) ) {
				if ( my $line = <FILE> ) {
					$jsonHash{$jsonFile} = decode_json($line);
				}
				else {
					warn "No data found in $jsonFile\n";
				}
				close FILE;
			}
		}
	}
	if ( !-d $jsonFilePath || !defined $jsonFiles[0] ) {
		warn "Couldn't find any associated JSON files... Extracting data from XML\n";
		my @blankFields = ( "Library" , "Uniquely Mapped %" , "Insert Mean" , "Insert Stdev" , "Read Length" , "R1 % >= q30" 
				, "R2 % >= q30" , "R1 Error %" , "R2 Error %" , "R1 Soft Clip %"
				, "R2 Soft Clip %" , "Est Reads/SP" , "% on Target" , "Est Yield"
				, "Est Coverage" , "Coverage Target" , "Comments" );
		for ( @blankFields ) {
			$jsonReportHash{$_} = "n/a";
		}
		%jsonReportHash = retrieveReadXML ( $xmlPath, \%jsonReportHash, $lane );
		%jsonReportHash = retrieveRunXML ( $runxmlPath, \%jsonReportHash, $lane );
		%jsonReportHash = checkMissingFiles( $runxmlPath, $xmlPath, \%jsonReportHash );
	}

    # Add columns to hash
    $jsonReportHash{"Run"}     = $runName;
    $jsonReportHash{"Lane"}    = $lane;
    $jsonReportHash{"Barcode"} = $barcode;
    
    if ( defined $jsonFile ) {
		$jsonReportHash{"Library"} = $jsonHash{$jsonFile}{"library"};

		if ( $jsonHash{$jsonFile}{"number of ends"} eq "paired end" ) {
			$jsonReportHash{"Insert Mean"}  = $jsonHash{$jsonFile}{"insert mean"};
			$jsonReportHash{"Insert Stdev"} = $jsonHash{$jsonFile}{"insert stdev"};
			$jsonReportHash{"Read Length"} =
				$jsonHash{$jsonFile}{"read 1 average length"} . "/"
			  . $jsonHash{$jsonFile}{"read 2 average length"};
		}
		else {
			$jsonReportHash{"Insert Mean"}  = "n/a";
			$jsonReportHash{"Insert Stdev"} = "n/a";
			$jsonReportHash{"Read Length"} =
			  $jsonHash{$jsonFile}{"read ? average length"};
		}

		%jsonReportHash = retrieveReadXML( $xmlPath, \%jsonReportHash, $lane );
		%jsonReportHash = retrieveRunXML ( $runxmlPath, \%jsonReportHash, $lane );
		%jsonReportHash = checkMissingFiles( $runxmlPath, $xmlPath, \%jsonReportHash );
		
		# Uniquely Mapped
		my $rawReads =
		  $jsonHash{$jsonFile}{"mapped reads"} +
		  $jsonHash{$jsonFile}{"unmapped reads"} +
		  $jsonHash{$jsonFile}{"qual fail reads"};

		if ( $rawReads > 0 ) {
			my $mapRate =
			  ( $jsonHash{$jsonFile}{"mapped reads"} / $rawReads )
			  ;    #mapped reads/total reads
			$jsonReportHash{"Uniquely Mapped %"} =
			  $mapRate;    #add uniquely mapped % into the report
		}
		else {
			$jsonReportHash{"Uniquely Mapped %"} = "0";
		}

		# quality calculations
		my $qOver30 = 0;
		my $qTotal  = 0;

		# count first in pair and unpaired reads as read 1
		for my $q ( keys %{ $jsonHash{$jsonFile}{"read 1 quality histogram"} } ) {
			if ( $q >= 30 ) {
				$qOver30 += $jsonHash{$jsonFile}{"read 1 quality histogram"}{$q};
			}
			$qTotal += $jsonHash{$jsonFile}{"read 1 quality histogram"}{$q};
		}
		for my $q ( keys %{ $jsonHash{$jsonFile}{"read ? quality histogram"} } ) {
			if ( $q >= 30 ) {
				$qOver30 += $jsonHash{$jsonFile}{"read ? quality histogram"}{$q};
			}
			$qTotal += $jsonHash{$jsonFile}{"read ? quality histogram"}{$q};
		}

		if ( $qTotal > 0 ) {
			$jsonReportHash{"R1 % >= q30"} =
			  $qOver30 / $qTotal;   #report percent of read qualities over 30 for R1
		}
		else {
			$jsonReportHash{"R1 % >= q30"} = "n/a";
		}

		$qOver30 = 0;
		$qTotal  = 0;
		for my $q ( keys %{ $jsonHash{$jsonFile}{"read 2 quality histogram"} } ) {
			if ( $q >= 30 ) {
				$qOver30 += $jsonHash{$jsonFile}{"read 2 quality histogram"}{$q};
			}
			$qTotal += $jsonHash{$jsonFile}{"read 2 quality histogram"}{$q};
		}

		if ( $qTotal > 0 ) {
			$jsonReportHash{"R2 % >= q30"} =
			  $qOver30 / $qTotal;   #report percent of read qualities over 30 for R2
		}
		else {
			$jsonReportHash{"R2 % >= q30"} = "n/a";
		}

		# mismatch errors
		my $R1errorRate;
		my $R2errorRate;

		if ( byCycleToCount( $jsonHash{$jsonFile}{"read 1 aligned by cycle"} ) > 0 )
		{
			$R1errorRate = (
				(
					byCycleToCount(
						$jsonHash{$jsonFile}{"read 1 mismatch by cycle"}
					  ) + byCycleToCount(
						$jsonHash{$jsonFile}{"read 1 insertion by cycle"}
					  ) + byCycleToCount(
						$jsonHash{$jsonFile}{"read 1 deletion by cycle"}
					  )
				) /
				  byCycleToCount( $jsonHash{$jsonFile}{"read 1 aligned by cycle"} )
			) * 100;
		}
		else {
			$R1errorRate = "n/a";
		}

		if ( byCycleToCount( $jsonHash{$jsonFile}{"read 2 aligned by cycle"} ) > 0 )
		{
			$R2errorRate = (
				(
					byCycleToCount(
						$jsonHash{$jsonFile}{"read 2 mismatch by cycle"}
					  ) + byCycleToCount(
						$jsonHash{$jsonFile}{"read 2 insertion by cycle"}
					  ) + byCycleToCount(
						$jsonHash{$jsonFile}{"read 2 deletion by cycle"}
					  )
				) /
				  byCycleToCount( $jsonHash{$jsonFile}{"read 2 aligned by cycle"} )
			) * 100;
		}
		else {
			$R2errorRate = "n/a";
		}
		$jsonReportHash{"R1 Error %"} = $R1errorRate;
		$jsonReportHash{"R2 Error %"} = $R2errorRate;

		# soft clip errors
		my $R1softClipRate;
		my $R2softClipRate;
		
		if (
			(
				byCycleToCount( $jsonHash{$jsonFile}{"read 1 aligned by cycle"} ) +
				byCycleToCount( $jsonHash{$jsonFile}{"read 1 soft clip by cycle"} )
			) > 0
		  )
		{
			$R1softClipRate =
			  byCycleToCount( $jsonHash{$jsonFile}{"read 1 soft clip by cycle"} ) /
			  (
				byCycleToCount( $jsonHash{$jsonFile}{"read 1 aligned by cycle"} ) +
				  byCycleToCount(
					$jsonHash{$jsonFile}{"read 1 soft clip by cycle"}
				  )
			  ) * 100;
		}
		else {
			$R1softClipRate = "n/a";
		}

		if (
			(
				byCycleToCount( $jsonHash{$jsonFile}{"read 2 aligned by cycle"} ) +
				byCycleToCount( $jsonHash{$jsonFile}{"read 2 soft clip by cycle"} )
			) > 0
		  )
		{
			$R2softClipRate =
			  byCycleToCount( $jsonHash{$jsonFile}{"read 2 soft clip by cycle"} ) /
			  (
				byCycleToCount( $jsonHash{$jsonFile}{"read 2 aligned by cycle"} ) +
				  byCycleToCount(
					$jsonHash{$jsonFile}{"read 2 soft clip by cycle"}
				  )
			  ) * 100;
		}
		else {
			$R2softClipRate = "n/a";
		}

		$jsonReportHash{"R1 Soft Clip %"} = $R1softClipRate;
		$jsonReportHash{"R2 Soft Clip %"} = $R2softClipRate;

		#add estimated reads per start point
		$jsonReportHash{"Est Reads/SP"} =
		  $jsonHash{$jsonFile}{"reads per start point"};

		#calculate percent of reads on target to total mapped reads
		my $onTargetRate;
		my $estimatedCoverage;
		my $estimatedYield;
		if ( $jsonHash{$jsonFile}{"mapped reads"} > 0 ) {
			$onTargetRate =
			  ( $jsonHash{$jsonFile}{"reads on target"} /
				  $jsonHash{$jsonFile}{"mapped reads"} );
		}
		else {
			$onTargetRate = "n/a";
		}

		#calculate estimated yield value = (number of aligned bases * percent of reads on target) / number of reads per start point
		if (    ( $jsonHash{$jsonFile}{"reads per start point"} > 0 )
			and ( $onTargetRate ne "n/a" ) )
		{
			$estimatedYield =
			  int( ( $jsonHash{$jsonFile}{"aligned bases"} * $onTargetRate ) /
				  $jsonHash{$jsonFile}{"reads per start point"} );
		}
		else {
			$estimatedYield = "n/a";
		}

		#calculate estimated coverage = estimated yield value/target size
		if ( $estimatedYield ne "n/a" ) {
			$estimatedCoverage =
			  $estimatedYield / $jsonHash{$jsonFile}{"target size"};
		}
		else {
			$estimatedCoverage = "n/a";
		}

		$jsonReportHash{"% on Target"}  = $onTargetRate;
		$jsonReportHash{"Est Yield"}    = $estimatedYield;
		$jsonReportHash{"Est Coverage"} = $estimatedCoverage;

		$jsonReportHash{"Coverage Target"} = $jsonHash{$jsonFile}{"target file"};
	}
    my $jsonString = encode_json( \%jsonReportHash );
    return $jsonString;
}

# Parses intrument into format that can be found in the file system
sub parseInstrument {
    my ($instrument) = @_;

    # need to adjust instrument name to directory name
    if ( $instrument =~ /^(h|i)/i ) {
        $instrument = lc $instrument;
    }
    elsif ( $instrument =~ /^m/i ) {
        $instrument = "m" . substr( $instrument, 3 );
    }
    elsif ( $instrument =~ /^SN/ ) {
        if ( $instrument =~ /\w{2}\d{7}/ ) {
            $instrument = "h" . substr( $instrument, 5 );
        }
        elsif ( $instrument =~ /\w{2}\d{3}/ ) {
            $instrument = "h" . substr( $instrument, 2 );
        }
    }
    return $instrument;
}

# Counts total number of reading errors of a cycle based on either mismatch, insertion, or deletion errors
sub byCycleToCount {
    my $histRef = $_[0];
    my $sum;

    for my $i ( keys %{$histRef} ) {
        $sum += $histRef->{$i};
    }
    return $sum;
}

# Parses RunInfo.xml for NumCycles, IsIndexedRead, read1, and read2
sub readRunInfoXML {
    my $runxmlPath = shift;
    my %readHash;    # Stores data for each read

    my $read1;
    my $read2;
    my $firstRead = 1;

    my $l;

    if ( not open( XML, "$runxmlPath/RunInfo.xml" ) ) {
        if ( not open( XML, "gzip -dc $runxmlPath/RunInfo.xml.gz|" ) ) {
            warn("Missing $runxmlPath/RunInfo.xml or RunInfo.xml.gz");
        }
    }

    while ( $l = <XML> ) {
        my $readNum;
        if ( $l =~ /<Read.* Number="(.*?)".*>/ ) {
            $readNum = $1;
            if ( $l =~ /<Read.* NumCycles="(.*?)".*>/ ) {
                $readHash{$readNum}{NumCycles} = $1;
            }

            if ( $l =~ /<Read.* IsIndexedRead="(.*?)".*>/ ) {
                $readHash{$readNum}{IsIndexedRead} = $1;
            }
            if ( $readHash{$readNum}{IsIndexedRead} eq 'N' ) {
                if ($firstRead)    # The first non-indexed read is read1
                {
                    $read1     = $readNum;
                    $firstRead = 0;
                }

                #read2 will be the last non-indexed read
                else {
                    $read2 = $readNum;
                }
            }
        }
    }

    if ( not defined $read1 or not defined $read2 ) {
        warn(
"Missing Read Number, NumCycles and IsIndexedRead in RunInfo.xml at $runxmlPath\n"
        );
    }
    close XML;

    return ( $read1, $read2, \%readHash );
}

# decodes JSON InterOp/SAV files and pushes contents to tile metric and error metric arrays
sub decodeJSON {
    my $runxmlPath   = shift;
    my @interopFiles = (
        "$runxmlPath/InterOp/JSON/TileMetricsOut.bin.json",
        "$runxmlPath/InterOp/JSON/ErrorMetricsOut.bin.json"
    );

    my $line;
    my $file;
    my @tileArray;
    my @errorArray;

    for $file (@interopFiles) {
        $line = "";
        if ( open( INTEROP, $file ) ) {
            while (<INTEROP>) {
                $_ =~ s/-nan/"nan"/
                  ; # replaces any 'not a number' values with a JSON readable string
                $line .= $_;    # file contents appended to a single string
            }

            if ( $file =~ /TileMetricsOut.bin.json/ ) {
                push @tileArray,
                  @{ decode_json($line)
                  }; # push and dereference, array reference returned by decode_json()
            }
            elsif ( $file =~ /ErrorMetricsOut.bin.json/ ) {
                push @errorArray, @{ decode_json($line) };
            }

            close INTEROP;
        }
        else {
            warn "Couldn't open $file\n";
        }

    }
    return ( \@tileArray, \@errorArray );
}

# Parses ErrorMetric data, stores/associates values by lane and read
sub getErrorData {
    my ( $read1, $read2, $errorArrayRef, $readHashRef, $tileHashRef,
        $laneHashRef )
      = @_;
    my @errorArray = @$errorArrayRef;    # Array of hashes containing error data
    my %readHash   = %$readHashRef;
    my %tileHash   = %$tileHashRef;
    my %laneHash   = %$laneHashRef;

    my %errorHash;                       # stores error metric data

    my $num_tiles = keys %tileHash;

# calculates number of errors per read
# errors per read = 1 error per tile * total tiles per cycle * number of cycles per read
    my $num_err_read1 = $num_tiles * $readHash{$read1}{NumCycles};
    my $num_err_read2 = $num_tiles * $readHash{$read2}{NumCycles};

# associates and assigns each error value with a lane, read, and data type (value/nan)
# loops through every array entry, of every cycle, of every read, of every lane
    foreach my $lane ( sort { $a <=> $b } keys %laneHash ) {
        my $cycleStart = 0;
        my $cycleEnd   = 0;
        for my $read ( keys %readHash ) {

            # determines which range of cycles corresponds to each read
            # ie. read1 consisted of cycles 1-101, read2 was cycles 102-203
            if ( $read == 1 ) {
                $cycleStart = 1;
            }
            else {
                $cycleStart += $readHash{ $read - 1 }{NumCycles};
            }
            $cycleEnd = $cycleStart + $readHash{$read}{NumCycles};

            if (   $read == $read1
                || $read ==
                $read2 )    # only data from read1 and read2 will be stored
            {
                for my $cycle ( $cycleStart .. $cycleEnd
                  )         # a read is a specific range of cycles
                {
                    for my $index ( @errorArray
                      ) # loops through every error data entry from ErrorMetricOut.bin.json
                    {
                        if (   $index->{cycle} == $cycle
                            && $index->{lane} == $lane )
                        {
                            if ( $index->{err_rate} eq "nan"
                              )    # stores occurence of 'not a number' values
                            {
                                $errorHash{$lane}{$read}{nan} = "true";
                            }
                            else {
                           # err_rate is summed to calculate an average per lane
                                $errorHash{$lane}{$read}{value} +=
                                  $index->{err_rate};
                            }
                        }
                    }
                }
            }
        }

        # calculates average error rate for read1
        if ( exists $errorHash{$lane}{$read1}{value} ) {
            $errorHash{$lane}{$read1}{value} /= $num_err_read1;
        }
        else {
            $errorHash{$lane}{$read1}{value} = "n/a";
        }

        # calculates averages error rate for read2
        if ( exists $errorHash{$lane}{$read2}{value} ) {
            $errorHash{$lane}{$read2}{value} /= $num_err_read2;
        }
        else {
            $errorHash{$lane}{$read2}{value} = "n/a";
        }
    }

    return \%errorHash;
}

# Parses TileMetric data, store/associates values by lane and metric code
sub getTileData {
    my ( $read1, $read2, $tileArrayRef, $metricHashRef, $tileHashRef,
        $laneHashRef )
      = @_;
    my @tileArray  = @$tileArrayRef;
    my %metricHash = %$metricHashRef
      ;    # lists of tile metric codes found in TileMetricOut.bin.json
    my %tileHash = %$tileHashRef;
    my %laneHash = %$laneHashRef;

    my $num_tiles = keys %tileHash;

    my %metrics;    # stores tile metric data

# associates and assigns each metric value to a lane, metric code and data type (value/nan)
# loops through every array entry, for every tile metric value in each lane
    foreach my $lane ( sort { $a <=> $b } keys %laneHash ) {
        foreach my $metric ( sort { $a <=> $b } keys %metricHash ) {
            for my $index (@tileArray) {
                if (   $index->{metric} == $metric
                    && $index->{lane} ==
                    $lane )    # Array entry must match metric code and lane
                {
                    if ( $index->{metric_val} eq
                        "nan" )    # stores occurence of 'not a number' values
                    {
                        $metrics{$lane}{$metric}{nan} = "true";
                    }
                    else {
                # metric values are summed to get totals and later calc averages
                        $metrics{$lane}{$metric}{value} += $index->{metric_val};
                    }
                }
            }

       # average percentage is calculated for read1 and read2 Phasing/Prephasing
            if (   $metric == ( 200 + ( $read1 - 1 ) * 2 )
                || $metric == ( 201 + ( $read1 - 1 ) * 2 )
                || $metric == ( 200 + ( $read2 - 1 ) * 2 )
                || $metric == ( 201 + ( $read2 - 1 ) * 2 ) )
            {
                $metrics{$lane}{$metric}{value} /= $num_tiles;
                $metrics{$lane}{$metric}{value} *= 100
                  ; # multiply by 100 because Phas/Prephas is reported in decimal
            }
        }
    }

    return \%metrics;
}

# Checks if a 'not a number' value was found and returns an error comment
sub checkNAN {
    my $HashRef = shift;
    my %Hash    = %$HashRef;
    my $comment = "";

    foreach my $lane ( keys %Hash ) {
        foreach my $read ( keys %{ $Hash{$lane} } ) {
            if ( exists $Hash{$lane}{$read}{nan}
                && keys %{ $Hash{$lane} } > 4 ) # tileHash will only have 4 keys
            {
                $comment =
                  "A \"nan\" metric value was found in TileMetricsOut.bin.json";
            }
            elsif ( exists $Hash{$lane}{$read}{nan} ) {
                $comment =
                  "A \"nan\" error rate was found in ErrorMetricsOut.bin.json";
            }
        }
    }

    return $comment;
}

# Retrieves all binary data
sub getBinaryData {
    my ($runxmlPath) = @_;

    # decodes JSON files
    #my ($tileArrayRef, $errorArrayRef) = decodeJSON($outDir); - TAB 20140811
    my ( $tileArrayRef, $errorArrayRef ) = decodeJSON($runxmlPath);
    my @tileArray  = @$tileArrayRef;
    my @errorArray = @$errorArrayRef;

    # reads RunInfo.xml for read information
    my ( $read1, $read2, $readHashRef ) = readRunInfoXML($runxmlPath);
    my %readHash = %$readHashRef;

    my %cycleHash;
    my %tileHash;
    my %laneHash;
    my %metricHash;

    my %errorlaneHash;

    # stores cycles and lanes found in ErrorMetricOut.bin.json
    # into the keys of a hash
    for my $index (@errorArray) {
        $cycleHash{ $index->{cycle} }    = 0;
        $errorlaneHash{ $index->{lane} } = 0;
    }

    # stores metric codes, tiles, and lanes found in TileMetricsOut.bin.json
    # into the keys of a hash
    for my $index (@tileArray) {
        $metricHash{ $index->{metric} } = 0;
        $tileHash{ $index->{tile} }     = 0;
        $laneHash{ $index->{lane} }     = 0;
    }

    # retrieves error data categorized by lane and read
    my $errorHashRef =
      getErrorData( $read1, $read2, $errorArrayRef, \%readHash, \%tileHash,
        \%laneHash );
    my %errorHash = %$errorHashRef;

    # retrieves tile data categorized by lane and metric code
    my $metricsRef =
      getTileData( $read1, $read2, $tileArrayRef, \%metricHash, \%tileHash,
        \%laneHash );
    my %metrics = %$metricsRef;

    return ( $read1, $read2, \%metrics, \%errorHash );
}

# Checks whether or not there are JSON files of the bin files and creates them if not
sub jsonBinDirectoryCheck {
    my ($runxmlPath) = @_;

    # checks for and creates any missing InterOp/SAV JSON data
    if ( !-d "$runxmlPath/InterOp/JSON" ) {

# if file system is read-only creates temp directory for JSON output
#$outDir = determineJsonOutDir($runxmlPath, $reportHash{"Run"});
# Target outDir for JSON files no longer supported - if create JSON below fails, error logged

        # creates JSON directory
        `oicr_illuminaSAV_bin_to_json.pl --runDir $runxmlPath`;
    }
    elsif (!-e "$runxmlPath/InterOp/JSON/TileMetricsOut.bin.json"
        && !-e "$runxmlPath/InterOp/JSON/ErrorMetricsOut.bin.json" )
    {
# if file system is read-only creates temp directory for JSON output
#$outDir = determineJsonOutDir($runxmlPath, $reportHash{"Run"});
# Target outDir for JSON files no longer supported - if create JSON below fails, error logged

        # creates necessary JSON files if they don't exist in JSON directory
        `oicr_illuminaSAV_bin_to_json.pl --runDir $runxmlPath`;
    }
    elsif ( ( -e "$runxmlPath/InterOp/JSON/TileMetricsOut.bin.json" ) !=
        ( -e "$runxmlPath/InterOp/JSON/ErrorMetricsOut.bin.json" ) )
    {
# if file system is read-only creates temp directory for JSON output
#$outDir = determineJsonOutDir($runxmlPath, $reportHash{"Run"});
# Target outDir for JSON files no longer supported - if create JSON below fails, error logged

    # removes JSON dir and recreates JSON dir contents of one JSON doesn't exist
        `rm -r $runxmlPath/InterOp/JSON;`;
        `oicr_illuminaSAV_bin_to_json.pl --runDir $runxmlPath`;
    }
}

# Read XML are parsed if available
sub retrieveReadXML {
	my ( $xmlPath, $jsonReportHashRef, $lane ) = @_;
	my $l;
	my $i;
	my %jsonReportHash = %$jsonReportHashRef;
	if ( -d "$xmlPath" ) {
		# read1.xml is checked for existence, opened, and parsed
		# error messages are output accordingly
		if ( -e "$xmlPath/read1.xml" or -e "$xmlPath/read1.xml.gz" ) {
			if ( not open( XMLFILE, "$xmlPath/read1.xml" ) ) {
				if ( not open( XMLFILE, "gzip -dc $xmlPath/read1.xml.gz|" ) ) {
					warn(" Missing $xmlPath/read1.xml or read1.xml.gz");
				}
			}

			while ( my $l = <XMLFILE> )    # should just be one line...
			{
				if ( $l =~
	/<Lane key="$lane".*?TileCount="(.*?)".*?ClustersRaw="(.*?)".*?PrcPFClusters="(.*?)".*?Phasing="(.*?)" Prephasing="(.*?)".*?ErrRatePhiX="(.*?)" ErrRatePhiXSD="(.*?)"/
				  )
				{
					$jsonReportHash{"XML"}{"# Raw Clusters"}    = $1 * $2;
					$jsonReportHash{"XML"}{"PF %"}              = $3;
					$jsonReportHash{"XML"}{"R1 Phasing"}        = $4;
					$jsonReportHash{"XML"}{"R1 Prephasing"}     = $5;
					$jsonReportHash{"XML"}{"R1 PhiX Error %"}   = $6;
					$jsonReportHash{"XML"}{"R1phixErrorRateSD"} = $7;
				}
			}
			close XMLFILE;
		}
		$i = 2;

		# open read files until you find the last one (which is hopefully read 2)
		# Opens and parses read2.xml if it exists
		# read number is incremented - the highest read XML will contain the values for read2
		while ( -e "$xmlPath/read$i.xml" or -e "$xmlPath/read$i.xml.gz" ) {
			if ( not open( XMLFILE, "$xmlPath/read$i.xml" ) ) {
				if ( not open( XMLFILE, "gzip -dc $xmlPath/read$i.xml.gz|" ) ) {
					warn("Missing $xmlPath/read$i.xml or read$i.xml.gz");

			 # assigns 'n/a' in place of missing data if read2.xml doesn't exist
					$jsonReportHash{"XML"}{"R2 Phasing"}        = "n/a";
					$jsonReportHash{"XML"}{"R2 Prephasing"}     = "n/a";
					$jsonReportHash{"XML"}{"R2 PhiX Error %"}   = "n/a";
					$jsonReportHash{"XML"}{"R2phixErrorRateSD"} = "n/a";
				}
			}

			while ( $l = <XMLFILE> )    # should just be one line...
			{
				while ( $l =~
	/<Lane key="$lane".*?TileCount="(.*?)".*?ClustersRaw="(.*?)".*?PrcPFClusters="(.*?)".*?Phasing="(.*?)" Prephasing="(.*?)".*?ErrRatePhiX="(.*?)" ErrRatePhiXSD="(.*?)".*>/g
				  )
				{
					# data is classified as XML
					$jsonReportHash{"XML"}{"R2 Phasing"}        = $4;
					$jsonReportHash{"XML"}{"R2 Prephasing"}     = $5;
					$jsonReportHash{"XML"}{"R2 PhiX Error %"}   = $6;
					$jsonReportHash{"XML"}{"R2phixErrorRateSD"} = $7;
				}
			}
			close XMLFILE;
			$i++;
		}

		#read 2 doesn't exist
		if ( $i == 2 ) {
			warn "Couldn't open [$xmlPath/read2.xml]\n";

			# assigns 'n/a' in place of missing data if read2.xml doesn't exist
			$jsonReportHash{"XML"}{"R2 Phasing"}        = "n/a";
			$jsonReportHash{"XML"}{"R2 Prephasing"}     = "n/a";
			$jsonReportHash{"XML"}{"R2 PhiX Error %"}   = "n/a";
			$jsonReportHash{"XML"}{"R2phixErrorRateSD"} = "n/a";
		}
		$jsonReportHash{"XML"}{"Source"} = "Read XML";
	}
	return %jsonReportHash;
}

# InterOp/SAV binary files are parsed if available
sub retrieveRunXML {
	my ( $runxmlPath, $jsonReportHashRef, $lane ) = @_;
	my $read1;
    my $read2;
    my $metricHashref;
    my $errorHashref;
    my %jsonReportHash = %$jsonReportHashRef;
    
	# Both TileMetricOut and ErrorMetricOut must exist for a full dataset
    if (   -e "$runxmlPath/InterOp/TileMetricsOut.bin"
        && -e "$runxmlPath/InterOp/ErrorMetricsOut.bin" )
    {
        jsonBinDirectoryCheck($runxmlPath);

        # retrieves data from InterOp/SAV files and read information
        ( $read1, $read2, $metricHashref, $errorHashref ) =
          getBinaryData($runxmlPath);

	# assigns retrieved data to the report hash classified as BIN data
	# metric codes correspond to different metric values based on the value of read1 and read2
	# More info - refer to Tile Metric Code Legend above or illumina's RTA Theory of Operations documentation
        $jsonReportHash{"BIN"}{"R1 Phasing"} =
          $metricHashref->{$lane}{ ( 200 + ( $read1 - 1 ) * 2 ) }{value};
        $jsonReportHash{"BIN"}{"R1 Prephasing"} =
          $metricHashref->{$lane}{ ( 201 + ( $read1 - 1 ) * 2 ) }{value};
        $jsonReportHash{"BIN"}{"R1 PhiX Error %"} =
          $errorHashref->{$lane}{$read1}{value};

        $jsonReportHash{"BIN"}{"R2 Phasing"} =
          $metricHashref->{$lane}{ ( 200 + ( $read2 - 1 ) * 2 ) }{value};
        $jsonReportHash{"BIN"}{"R2 Prephasing"} =
          $metricHashref->{$lane}{ ( 201 + ( $read2 - 1 ) * 2 ) }{value};
        $jsonReportHash{"BIN"}{"R2 PhiX Error %"} =
          $errorHashref->{$lane}{$read2}{value};

        $jsonReportHash{"BIN"}{"# Raw Clusters"} =
          $metricHashref->{$lane}{102}{value};

        # PF % = (# clusters passing filters) / (total cluster) * 100
        $jsonReportHash{"BIN"}{"PF %"} =
          ( $metricHashref->{$lane}{103}{value} /
              $metricHashref->{$lane}{102}{value} ) * 100
          if $metricHashref->{$lane}{102}{value};

        $jsonReportHash{"BIN"}{"Source"} = "Binary";

        # reports instances of 'not a number' values in comments
        $jsonReportHash{"Comments"} =
          checkNAN($metricHashref) . " - " . checkNAN($errorHashref);
    }    
    return %jsonReportHash;
}

# Check for missing files and set to NIL if none are available
sub checkMissingFiles {
    my ( $runxmlPath, $xmlPath, $jsonReportHashRef ) = @_;
    my %jsonReportHash = %$jsonReportHashRef;

    # determines current status of illumina metric value source files
    my $missingBothBin = "true"
      if ( !-e "$runxmlPath/InterOp/TileMetricsOut.bin" )
      && ( !-e "$runxmlPath/InterOp/TileMetricsOut.bin" );
    my $missingOneBin = "true"
      if ( !-e "$runxmlPath/InterOp/TileMetricsOut.bin" ) !=
      ( !-e "$runxmlPath/InterOp/ErrorMetricsOut.bin" );
    my $missingXML     = "true" if ( !-d "$xmlPath" );
    my $missingInterOp = "true" if ( !-d "$runxmlPath/InterOp" );

    # If read XML and one or more InterOp/SAV binaries do not exist
    # errors are reported and reportHash values set to 'n/a'
    if ( $missingXML && ( $missingOneBin || $missingBothBin ) ) {
        if ($missingInterOp) {
            warn "Couldn't Find [$xmlPath]\n";
            warn "Couldn't Find [$runxmlPath/InterOp]\n";
        }
        elsif ($missingBothBin) {
            warn "Couldn't Find [$xmlPath]\n";
            warn "Couldn't Find [$runxmlPath/InterOp/TileMetricsOut.bin]\n";
            warn "Couldn't Find [$runxmlPath/InterOp/ErrorMetricsOut.bin]\n";
        }
        elsif ($missingOneBin) {
            warn "Couldn't Find [$xmlPath]\n";
            if ( -e "$runxmlPath/InterOp/TileMetricsOut.bin" ) {
                warn
                  "Couldn't Find [$runxmlPath/InterOp/ErrorMetricsOut.bin]\n";
            }
            else {
                warn
                  "Couldn't Find [$runxmlPath/InterOp/TileMetricsOut.bin]\n";
            }
        }

        # assigns 'n/a' in place of missing data and classifies as NIL
        $jsonReportHash{"NIL"}{"R1 Phasing"}      = "n/a";
        $jsonReportHash{"NIL"}{"R1 Prephasing"}   = "n/a";
        $jsonReportHash{"NIL"}{"R1 PhiX Error %"} = "n/a";

        $jsonReportHash{"NIL"}{"R2 Phasing"}      = "n/a";
        $jsonReportHash{"NIL"}{"R2 Prephasing"}   = "n/a";
        $jsonReportHash{"NIL"}{"R2 PhiX Error %"} = "n/a";

        $jsonReportHash{"NIL"}{"# Raw Clusters"} = "n/a";
        $jsonReportHash{"NIL"}{"PF %"}           = "n/a";

        $jsonReportHash{"NIL"}{"Source"} = "Nil";
    }
    return %jsonReportHash;
}
