#!/usr/bin/perl5 -w

my $dir;

print "Num Args=$#ARGV\n";
if ( $#ARGV >= 0 ){
   $dir=$ARGV[0];
} else {
   $dir=".";
}
print "<html>\n";
print "<head>Directory index: $dir\n";
print "</head>";
print "<body>\n";
opendir DIR, "$dir" || die "Cannot open directory: $dir\n";
@files = grep !/^\./, readdir DIR;
closedir(DIR);
print "<h1>Directory index: $dir</h1>\n";
print "<ul>\n";
foreach $entry (@files){
   if ($entry !~ /.gif|.jpg/){ next; }
   print "<li>$entry<br>\n";
   print "<img alt=\"$entry\" src=\"$entry\">\n";
   print "<br clear=\"top\">\n";
}
print "</ul>\n";
print "</body>\n";
print "</html>\n";
