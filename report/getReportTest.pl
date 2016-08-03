use warnings;
use strict;

use File::Basename qw(dirname);
use JSON;
use Data::Dumper;
use Cwd qw(abs_path);
use lib dirname(dirname abs_path $0) . "/Report";
use Report::wideInstrument qw (get_instrument_report get_XML_Data);

my $path = $ARGV[0];
my $run = $ARGV[1];
my $barcode = $ARGV[2];

for (my $i = 1; $i < 9; $i++) {
	print decode_json(get_XML_Data ($path, $run, $i, $barcode));
}
