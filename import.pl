#!/usr/bin/perl -w

use utf8;
binmode(STDOUT, ":utf8");
#
my $filename = $ARGV[0];
open(my $fh, '<:encoding(UTF-8)', $filename)
    or die "Could not open file '$filename' $!";

print "<?php\n";
while (my $row = <$fh>) {
	if($row =~ /^"(.+?)","(.+?)?",/) {
        my $text = '';
        my $var = $1;
        if (defined $2) {
            $text = $2;
        }
        if($var eq 'definition' and $text eq 'translation') {
            next;
        }
        if ($text ne '') {
            if($text =~ /^"(.+?)"$/) {
                $text = $1;
            }
            $text =~ s/\n//g;
            $text =~ s/'/\'/g;
        }
		print "define('$var','$text');\n";
	}
}
print "?>\n";
