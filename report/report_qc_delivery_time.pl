#!/bin/perl

use strict;
use warnings;
use Data::Dumper;

use Statistics::Descriptive;

my @dirs = @ARGV;

if ( not @dirs ) {
    die
"Usage $0 path_to_run_directory\n\nCompares the time the run completed to the time the report came out";
}

my $dir  = "";
my %diff = ();

#iterate through all directories passed on command line
foreach $dir (@dirs) {

    #find seconds since epoch for oicr_run_complete files (run completed)
    my @runcomplete = split(
        "\n",

`find $dir -maxdepth 2 -name "oicr_run_complete" -exec stat --format="%n %Y" {} +`
#`find $dir/*/jsonReport -maxdepth 1 -name "*json" -exec stat -L --format="%n %Y" {} +`
    );

    #find seconds sinch epoch for report.html files (indicates time delivered)
    my @reportout = split( "\n",
`find $dir/*/jsonReport -maxdepth 1 -name "*report.html" -exec stat --format="%n %Y" {} +;`
    );

    my $line           = "";
    my %reportouttimes = ();

    #calculate first the report delivery time
    foreach $line (@reportout) {
        my ( $run, $epochtime ) = get_run_and_int($line);
        $reportouttimes{$run} = $epochtime;
    }

    #find the run completed time
    foreach $line (@runcomplete) {
        my ( $run, $start ) = get_run_and_int($line);
        my $end = $reportouttimes{$run};

        #ignore if no report has been delivered yet
        if ( not defined $end ) {
            next;
        }

        #calculate days from the seconds given
        my $days = ( $end - $start ) / 60 / 60 / 24;

        #remove re-generated reports or extreme outliers
        if ( $days < 0 or $days > 100) {
        }
        else {
            $diff{$run} = $days;
        }
    }

}

#Header
print("Set\tCount\tMean\tMedian\tStandardDeviation\n");

#Summary stats
my @totaltimes = ( values %diff );
printf("Total\t");
print_stats( values %diff );

#years
for ( my $i = 1 ; $i < 6 ; $i++ ) {
    printf( "%s\t", "201$i" );
    my @filteredruns = grep { m/^1$i.*/g } ( keys %diff );
    my @newvals = @diff{@filteredruns};
    print_stats(@newvals);
    undef @filteredruns;
    undef @newvals;
}

#Instrument types
print("MiSeq\t");
my @filteredruns = grep { m/^[\d]{6}_M.*/g } ( keys %diff );
my @newvals = @diff{@filteredruns};
print_stats(@newvals);
undef @filteredruns;
undef @newvals;

print("HiSeq\t");
@filteredruns = grep { m/^[\d]{6}_[DhS].*/g } ( keys %diff );
@newvals = @diff{@filteredruns};
print_stats(@newvals);
undef @filteredruns;
undef @newvals;

#Calculates basic stats for array and prints in tab separated format
sub print_stats {
    my @times = @_;
    if ( not @times ) {
        printf("\n");
        return;
    }
    my $stat = Statistics::Descriptive::Full->new();
    $stat->add_data(@times);
    my ( $count, $mean, $median, $std ) = (
        $stat->count(), $stat->mean(), $stat->median(),
        $stat->standard_deviation()
    );
    printf( "%d\t",   $count );
    printf( "%.2f\t", $mean );
    printf( "%.2f\t", $median );
    printf( "%.2f\t", $std );
    printf("\n");
}

#Parses out the run name and the number of seconds since epoch from the stat results
sub get_run_and_int {
    my ($line) = @_;

    if ( $line =~ /.*\/([\d]{6}_[a-zA-Z0-9]*_[\d]{4}_[a-zA-Z0-9-]*)\/.* (.*)$/ )
    {
        return ( $1, $2 );
    }

}
