#!/usr/bin/perl -w
# Usage export.pl langfile.php > langfile.csv

use utf8;
binmode(STDOUT, ":utf8");
#
my $filename = $ARGV[0];
open(my $fh, '<:encoding(UTF-8)', $filename)
    or die "Could not open file '$filename' $!";

print "definition,translation,comment\n";
while (my $row = <$fh>) {
	if($row =~ /define\('(.+?)','(.*?)'\);\s*(#?.*)/) {
        $var = $1;
        $text = $2;
		$comment = $3;
        $text =~ s/\n//g;
        $text =~ s/\\'/'/g;
		print "\"$var\",\"$text\",\"$comment\"\n";
	}
}
