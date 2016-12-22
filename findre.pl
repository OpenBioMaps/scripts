#!/usr/bin/perl -w
#
# Recursive search for *pattern* in files
# You can specify filename patterns
# Result is going to the standard output
# 
# 2006.08.01 / Bán Miklós / banm@kornel.zool.klte.hu

print "Type the string for search it:\n";
if ($ARGV[0]) {
	$searchstring = $ARGV[0];
} else {
	$searchstring = <STDIN>;
}
chomp ($searchstring);

# what is ums_repository?
# https://github.com/miklosban/ums
$exclude_path = " -not -path '*UMS_REPOSITORY/*'";

print "Type the filename pattern (default: *, example: *.html,*.txt):\n";
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
print "Searching for `$searchstring` in ./$filepattern    --->\n\n";
print "find -type f $FP -exec grep -lq '$searchstring' '{}' \\; -print\n";

system( "find -type f $FP -exec grep -lq '$searchstring' '{}' \\; -print");

#find example
#find . \( -name '*.php' -o -name '*.html' \) -exec grep -lq "examplestring" '{}' \; -print

#replace example
#find . \( -name '*.php' -o -name '*.html' \) -exec sed -i~ "s/\"\$OPATH\//\"\$OPATH\"\.\"/g" '{}' \;
