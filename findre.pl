#!/usr/bin/perl -w
#
# Recursive search for *pattern* in files
# You can specify filename patterns
# Result is going to the standard output
# 
# 2006.08.01 / Bán Miklós / banm@kornel.zool.klte.hu
# 2017.02.19
#
use Term::ANSIColor;

$exclude_path = " -not -path '*UMS_REPOSITORY/*'";

## code

if ($ARGV[0]) {
    $searchstring = join " ", @ARGV;
    print colored( sprintf('%s',$searchstring),"yellow"),"\n";
} else {
    print colored( sprintf("Type the string for search it:"),"green"),"\n";
    $searchstring = <STDIN>;
}
chomp ($searchstring);
$lqqote = "'";
if ($searchstring =~ /'/) {
    $lqqote = '"';
}

print colored( sprintf("Type the filename pattern (default: *, example: *.html,*.txt):"),"green"),"\n";
$filepattern = <STDIN>;
chop ($filepattern);

if ($filepattern eq '') {
  $FP = '';
} else {
  @patterns = split(/,/,$filepattern);
  $FP = " \\( ";
  foreach $pat (@patterns) {
    $FP .= "-name '$pat' $exclude_path -o ";
  }
  ($FP,) = split(/ -o $/,$FP,2);
  $FP .= " \\)";
}
#print "Searching for `$searchstring` in ./$filepattern    --->\n\n";
$cmd = sprintf("find -type f %s -exec grep -lq %s%s%s '{}' \\; -print",$FP,$lqqote,$searchstring,$lqqote);
print colored( sprintf("\t$cmd"),"magenta"),"\n";
system($cmd);
#print "find -type f $FP -exec grep -lq '$searchstring' '{}' \\; -print\n";
#system( "find -type f $FP -exec grep -lq '$searchstring' '{}' \\; -print");

#find example
#find . \( -name '*.php' -o -name '*.html' \) -exec grep -lq "examplestring" '{}' \; -print

#replace example
#find . \( -name '*.php' -o -name '*.html' \) -exec sed -i~ "s/\"\$OPATH\//\"\$OPATH\"\.\"/g" '{}' \;
