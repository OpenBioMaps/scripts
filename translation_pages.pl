#!/usr/bin/perl

use strict;
use warnings;
my $cmd;
     
my $filename = '/home/banm/Documents/OpenBioMaps/translations/str.csv';
open(my $fh, '<:encoding(UTF-8)', $filename)
      or die "Could not open file '$filename' $!";
     
while (my $row = <$fh>) {
      chomp $row;
      print "\n$row;";
      $cmd = `echo $row | sed -e 's/^/grep /'| sed -e \"s/\$/ *.php | awk -F : '{print \\\$1}'/\" | bash | sort | uniq`;
      print $cmd =~ s/\n/,/gr;
}

#cat /home/banm/Documents/OpenBioMaps/translations/str.csv | sed -e 's/^/grep /'| sed -e "s/$/ *.php | awk -F : '{print \$1}'/" | bash
