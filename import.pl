#!/usr/bin/perl -w

use utf8;
binmode(STDOUT, ":utf8");
#
my $filename = $ARGV[0];
open(my $fh, '<:encoding(UTF-8)', $filename)
    or die "Could not open file '$filename' $!";

print "<?php\n";
$lc = 0;
my $quote = '"';
my $sep = ",";

my $text = '';
my $var = '';

while (my $row = <$fh>) {
    if ($lc == 0) {
        $row =~ /^(["']?)definition["']?([,;\t])["']?translation["']?/;
        $quote = $1;
        $sep = $2;
        $lc++;
        next;
    }
    $text = "";
    $var = "";
    if ($row =~ /^$quote(.+?)$quote$sep$quote(.+?)?$quote$sep?/) {
        $text = $2;
        $var = $1;
    }

    if ($text ne '') {
            if($text =~ /^"(.+?)"$/) {
                $text = $1;
            }
            $text =~ s/\n//g;
            $text =~ s/'/\\'/g;
    }
    print "define('$var','$text');\n";
}
print "?>\n";
