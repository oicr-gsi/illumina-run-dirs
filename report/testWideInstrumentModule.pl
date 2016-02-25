#!/usr/bin/perl

# This is script is to be used in association with dir_to_script/Report/wideInstrument.pm
# Ensure you have the line "use Report::wideInstrument qw (get_instrument_report)"
# To add dir/Report/wideInstrument.pm to @INC (where perl modules are accessed), either:
##### directly run it using perl but containing "use File::Basename qw(dirname); in the script
#					   							 use Cwd qw(abs_path);
#												 use lib dirname(dirname abs_path $0) . '/Report';"
##### add the folder to a directory in @INC or the folder to @INC
##### run the script using perl -IReport <perl script>

use warnings;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(dirname abs_path $0) . '/Report';
use Report::wideInstrument qw (get_instrument_report);

my $runName = "160209_D00353_0127_AC8T56ANXX";
my $lane = "6";
my $barcode = "CCGTCC";
print get_instrument_report ( $runName, $lane, $barcode );

