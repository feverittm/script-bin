#!/usr/local/bin/perl5 -w
#
#       Author:  Floyd Moore (redfc.hp.com)
#	$Header: /piranha/fmlxd1a/xdb1aax/xx/bin/za_check 1.5 1999-12-15 14:28:03-07 red Exp $
#	Description:
#          Check an artwork design for zero area devices (such as polygons,
#          and rectangles).  These devices can cause confusion at the 
#          Mask fab.
#
#	"za_check" created by red
#
#	$Log: za_check,v $
#
#   TODO:
#   Done: Add listing for the top 10 files by size.
#   Add mail to users for problems found
#

use strict;
use subs qw(handler show_usage parse_options file_mtime);
use POSIX qw(strftime);
use vars qw($opt_v $opt_c $opt_x $opt_U $opt_V $opt_d $opt_s $opt_f);
use vars qw($opt_q $opt_g $opt_w $opt_y $opt_o);
use vars qw($ProgName $RunDate $Rev $DirName);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$SIG{'HUP'} =	\&handler;
$SIG{'INT'} =	\&handler;
$SIG{'QUIT'} =	\&handler;
$SIG{'TERM'} =	\&handler;

use Getopt::Std;

sub handler
{
    my($sig) = @_;
    warn "$ProgName:INFO: Caught a SIG$sig -- shutting down\n";
    exit(0);
}

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-x] [-v] [-V] [-s size] [-d directory]\n";
   print "Give a report on a disk array...\n";
   print "   Options:\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
   print "   -q:        Quiet Mode\n";
   print "   -U:        Only run the 'bdf' reports\n";
   print "   -s size:   Set the large file threshold size (def=500MB).\n";
   print "   -d dir:    Specify a directory to evaluate (def=/sdg).\n";
   print "   -w:        Enable html/web output mode (def=text mode).\n";
   print "   -o file:   Specify an output file (def=stdout).\n";
   print "   -g:        Ignore group permission problems.\n";
   print "   -c:        Pre-run the 'ls-lRF' command, and cache.\n";
   print "   -f:        Use a file for the disk info instead of 'ls-lRF'.\n";
   print "   -y:        Only report '/sdg' stuff used in Mako\n";
   print "\n";
   exit 0;
}

# my options parser
sub parse_options
{
   if ( $#ARGV > 0 && $ARGV[0] =~ "-help"){
	&show_usage();
	exit(1);
   }

   unless (&Getopt::Std::getopts('VUwo:gvxd:cs:f:q')) {
	&show_usage();
	exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
}

sub file_mtime {
    my $filename = shift;
    # (stat("file"))[9] returns mtime of file.
    return (stat($filename))[9];
}

sub round {
    my $in=shift;
    my $dec=shift;

    return (int($in * 10**$dec) / 10**$dec);
}

sub size_suffix {
    my $in_size=shift;
    my $KB = 1024;
    my $MB = $KB*1024;
    my $GB = $MB*1024;
    my $TB = $GB*1024;

    if ($in_size >= $TB){
       return round($in_size/$TB,2) . "Tbytes";
    }
    elsif ($in_size >= $GB){
       return round($in_size/$GB,2) . "Gbytes";
    }
    elsif ($in_size >= $MB){
       return round($in_size/$MB,2) . "Mbytes";
    }
    elsif ($in_size >= $KB){
       return round($in_size/$KB,2) . "Kbytes";
    }
    else {
       return $in_size . "bytes";
    }
}


##
## Main Program Start
##

use vars qw($line $InDir $Dir $Out $FileLinked);
use vars qw($mode $links $owner $group $size $mon $day $tmyear $file);
use vars qw($DirBlks $DirSize $Total);

use vars qw(@CoreFiles @BigFiles %DirCache %UserReport %UserSpace);

parse_options();

$Total=0;

my @TestDisks = qw(/disc );

if (!defined($opt_f)){
   $Dir = "/sdg";
   $Dir = $opt_d if (defined($opt_d));
   if (! -d $Dir ){
      die "Cannot locate a directory called: $Dir\n";
   }
   open (LIST, "ls -lRF $Dir|") ||
      die "Cannot open pipe to 'ls -lR $Dir'\n";
} else {
   #print "Using the ls-lRF cache file\n";
   if (! -f $opt_f){
      die "Cannot open ls-lRF cache file: $opt_f\n";
   }
   open (LIST, "<$opt_f") ||
      die "Cannot open file $opt_f\n";

   $Dir = <LIST>;
   chomp $Dir;
}

my $size_threshold = 500000000;
$size_threshold = $opt_s if (defined($opt_s));

$InDir=$Dir;

if (defined($opt_w)){
   print "<HTML>\n";
   print "<HEAD>\n";
   print "<TITLE>Disk Utilization Report for $Dir</TITLE>\n";
   print "</HEAD>\n";
   print "<BODY>\n";
   print "<H1>Disk Utilization Report for $Dir</H1>\n";
   print "<H2>Created on: $RunDate</H2>\n";
} else {
   print "Disk Utilization Report for $Dir\n";
   print "Created on: $RunDate\n";
}

#
# Check disk space available on the test volumes...
#
do {
   my ($mnt, $fsize, $vsize, $vused, $vfree, $pcnt, $name, $margin);
   unless (defined($opt_q)){
      if (defined($opt_w)){
         print "<H1>Disk Usage Report</H1>\n";
      } else {
         print "Disk Usage Report:\n";
      }
   }

   if (defined($opt_w)){
      print "<TABLE>\n";
      print "<TR>\n";
      print "<TH>Disk</TH><TH>Percent Full</TH><TH>Mount Point</TH>\n";
      print "</TR>\n";
   }

   for my $disk (@TestDisks){
      my $space=`bdf $disk`;
      $space=~s/^Filesystem[^\n]*\n//;
      $space =~ s/\s+/ /g;
      ($mnt, $vsize, $vused, $vfree, $pcnt, $name) = split(" ", $space);
      $pcnt =~ s/\%//;
      $margin = (int(($vfree / $vsize) * 100)) / 100;
      unless (defined($opt_q)){
         if (defined($opt_w)){
            print "<TR>\n";
            if ($margin < 0.18){
               print "<TD>$mnt</TD><TD>$pcnt%</TD>\n";
               print "<TD><FONT color=\"#FF0000\">$disk</FONT></TD>\n";
            } else {
               print "<TD>$mnt</TD><TD>$pcnt%</TD><TD>$disk</TD>\n";
            }
            print "</TR>\n";
         } else {
            printf("%-20s %2d%% -- %s\n", $mnt, $pcnt, $disk);
         }
      }
      if ($margin < 0.18 && !defined($opt_w)){ 
         print "Margin on disk $mnt is less than 18%: $margin\n";
      }
   }

   if (defined($opt_w)){
      print "</TABLE>\n";
   }

   unless (defined($opt_q)){
      if (defined($opt_w)){
         print "<H1>&quot;duquot; Usage Report Top-5</H1>\n";
      } else {
         print "'du' Usage Report:\n";
      }
   }

   for my $disk (@TestDisks){
      if (defined($opt_w)){
         print "<H2>$disk:</H2>\n";
         print "<TABLE>\n";
         print "<TR>\n";
         print "<TH>Space</TH><TH>Directory\/File</TH>\n";
         print "</TR>\n";
      }

      unless (defined($opt_w)){
         print "Running 'du' report for $disk...\n";
      }
      open (DU, "du -sk $disk/* | sort -nr | head -5 |") ||
         die "Cannot open pipe to 'du'\n";
      while(<DU>){
         chomp;
         ($fsize, $name) = split(" ", $_, 2);
         if (defined($opt_w)){
            print "<TR>\n";
            print "<TD>$fsize</TD><TD>$name</TD>\n";
            print "</TR>\n";
         } else {
            printf("%-10d %-50s\n", $fsize, $name);
         }
      }
      close(DU);
      if (defined($opt_w)){
         print "</TABLE>\n";
      } else {
         print "\n";
      }
   }

};

if (defined($opt_U)){ exit; }

unless (defined($opt_f)){
   my $Cache = "/tmp/ls-lRF";
   open (CACHE, ">$Cache")
      || die "Cannot open Cache file: $Cache\n";
}

if (defined($opt_c)){
   $Dir = "/xy/test/";
   $Dir = $opt_d if (defined($opt_d));
   if (! -d $Dir ){
      die "Cannot locate a directory called: $Dir\n";
   }
   system ("ls -lRF $Dir > /tmp/ls-lRF");
}

#
# Go through all of the files in the test directory...
#   Store the data on the name, size and owner of the file.
#   Look for problems (ie core files, large files...)
#
while (<LIST>){
   unless (defined($opt_f)){
      if ($. == 1){
         print CACHE "$Dir:\n" 
      }
      print CACHE "$_";
   }

   chomp;
   $line=$_;

   /^total\s+(\d+)/ && do { $DirBlks=$1; next; };

   if (!defined($InDir) && /^\/.*:$/) { 
      $InDir=$_;
      $InDir =~ s/:$//;
      $DirSize=0;
      if (defined($opt_x)) { print "Decent Directory: $_\n"; }
      next;
   }

   /^\s*$/ && do {
      if (defined($opt_x)) { print "End of Directory Record...\n"; }
      undef $InDir;
      undef $FileLinked;
      next;
   };

   if($_ =~ /^p[rw-]+/){
      # skip pipe files...
      next;
   }

   if($_ =~ /^l[sSrw-]+/){
      # skip pure link files...
      next;
   }

   if($_ !~ /^[rdwxlsS-]+\s+\d+/){
      print "SKIP Bad ls record at line $.: '$_'\n";
      next;
   }

   if ($DirBlks == 0) { 
      if (defined($opt_x)){ print "Skip Empty directory: $InDir\n"; }
      next; 
   }

   ($mode, $links, $owner, $group, $size, $mon, $day, $tmyear, $file)
      = split(" ", $_, 9);

   if (!defined($file)){
      die "\$file variable undefined at line $_: $.\n";
   }

   if ($file =~ /\/$/){
      if (defined($opt_x)) { print "... tag directory: $file\n"; }
      next;
   }

   if ($file =~ /->/){
      $file=~s/^.*\s+->\s+//;
      if (defined($opt_x)) { print "... tag link: $file\n"; }
      $FileLinked=1;
   }

   unless ($file =~ /\/net\/|\/nfs\//){
      if ($InDir =~ /\/$/){
         $file= $InDir . $file;
      } else {
         $file= $InDir . "/" .  $file;
      }
   } else {
      if (defined($opt_x)) { print "NFS link detected: $file\n"; }
   }

   $file=~ s/\*$//;

   $DirCache{$file}->{line} =$line;
   $DirCache{$file}->{size} =$size;
   $DirCache{$file}->{owner}=$owner;

   #
   # Add file size to the space used by the individual user...
   #
   $UserSpace{$owner} += $size;

   #
   # Check file group...  should always be 'esl' for the regular files...
   #
   # ... skip this wierd taskbroker file, it is always small and is owned 
   #      by group 'sys'

   if (!defined($opt_g) && !defined($FileLinked) && $group !~ /esl/){
      if ($file =~ /info_taskbroker_top/){ next; }
      if (defined($opt_v)){
         print "Bad Group $group on file: $file, Owner=$owner\n";
      }
      my $report = "File with bad group id $group =\n     $file";
      push @{$UserReport{$owner}}, $report;

      #
      # Check file mode...  we should always have read permission
      #  ... except for the pgp encoded files 
      #
      if (!defined($FileLinked) && $mode !~ /.r..r...../){
         if ($file !~ /\.pgp$/){ 
            if (defined($opt_v)){
               print "Bad file mode $mode on file: $file, Owner=$owner\n";
            }
            my $report = "File without group esl read permission, mode=$mode for\n      $file";
            push @{$UserReport{$owner}}, $report;
         }
      }
   }

   #
   # Check file size...
   #
   if ($size > $size_threshold){
      if (defined($opt_v)){
         print "Large file detected: $owner, $size: $file\n";
      }
      push @BigFiles, $file;
      my $report = "Large File = $file";
      push @{$UserReport{$owner}}, $report;
   }

   #
   # Check for core files...
   #
   if ($file =~ /\/core$/){
      if ($file =~ /waste\/core/){ next; }

      if (defined($opt_v)){
         print "Core file detected:  $owner, $size: $file\n";
      }
      push @CoreFiles, $file;
      my $report = "Core File = $file";
      push @{$UserReport{$owner}}, $report;
   }

   #print "$size $file $owner\n";
}
close(LIST);
close(CACHE);

if (defined($opt_v)){ 
   print "-----------------\n"; 
}

sub by_size {
   my $a_size = $DirCache{$a}->{size};
   my $b_size = $DirCache{$b}->{size};

   if    ($a_size > $b_size) { return -1; }
   elsif ($a_size < $b_size) { return 1; }
   else  { return 0; }

}

unless(defined($opt_w)){
   print "\nSorting Files by Size...\n";
}
do {
   use vars qw (@DSort);
   for my $file (keys %DirCache){
      if ($DirCache{$file}->{size} > 10000){
         push @DSort, $file;
      }
   }

   @DSort = sort by_size @DSort;
   my $count = 1;

   if (defined($opt_w)){
      print "<H1>Top-10 files by size on $Dir</H1>\n";
      print "<TABLE>\n";
      print "<TR>\n";
      print "<TH>Size</TH><TH>Owner</TH><TH>Filename</TH>\n";
      print "</TR>\n";
   } else {
      print "Top-10 files by size on $Dir:\n";
      printf ("%-12s %-6s %-30s\n", "Size","Owner", "Filename");
   }

   for my $file (@DSort ){
      if (defined($opt_w)){
         print "<TR>\n";
         print "<TD>" . $DirCache{$file}->{size} . "</TD>\n";
         print "<TD>" . $DirCache{$file}->{owner} . "</TD>\n";
         print "<TD>" . $file . "</TD>\n";
         print "</TR>\n";
      } else {
         printf ("%-12d %-6s %-30s\n",  $DirCache{$file}->{size}, $DirCache{$file}->{owner}, $file);
      }
      ++$count;
      if ($count > 10){ last; }
   }

   if (defined($opt_w)){
      print "</TABLE>\n";
   }
   undef @DSort;
};

sub by_user_size {
   my $a_size = $UserSpace{$a};
   my $b_size = $UserSpace{$b};

   if    ($a_size > $b_size) { return -1; }
   elsif ($a_size < $b_size) { return 1; }
   else  { return 0; }
}

print "\nSorting by Username and ranking by Filesystem Space used...\n";
do {
   use vars qw (@USort);
   for my $owner (keys %UserSpace){
      if ($UserSpace{$owner} > 10000000) {
         push @USort, $owner;
      }
   }

   @USort = sort by_user_size @USort;
   my $count = 1;
   if (defined($opt_w)){
      print "<H1>Top-10 users by disk space used on $Dir</H1>\n";
      print "<TABLE>\n";
      print "<TR>\n";
      print "<TH>Rank</TH><TH>Owner</TH><TH>Disk_Space_Used</TH>\n";
      print "</TR>\n";
   } else {
      print "Top-10 users by disk space used on $Dir:\n";
      printf ("%-4s %-6s %-20s\n", "Rank", "Owner", "Disk_Space_Used");
   }
   for my $owner (@USort ){
      if (defined($opt_w)){
         print "<TR>\n";
         print "<TD>$count</TD><TD>$owner</TD>\n";
         print "<TD>" . size_suffix($UserSpace{$owner}) . "</TD>\n";
         print "</TR>\n";
      } else {
         printf ("%3d: %-6s %-20s\n", $count, $owner, size_suffix($UserSpace{$owner}));
      }
      ++$count;
      if ($count > 10){ last; }
   }

   if (defined($opt_w)){
      print "</TABLE>\n";
   }
   undef @USort;
};

if (defined(%UserReport)){
   if (defined($opt_w)){
      print "<H1>User Reports</H1>\n";
      print "<DL>\n";
   } else {
      print "\nUser Reports:\n";
   }
   for my $key (sort keys %UserReport){
      if (defined($opt_w)){
         print "<DT>User $key:</DT>\n";
      } else {
         print "   User $key:\n";
      }
      for my $data (sort @{$UserReport{$key}}){
         ($file = $data) =~ s/^.*=\s+//;
         if (defined($opt_w)){
            if ($data =~ "^Large") {
               print "<DD>$data, size=$DirCache{$file}->{size}</DD>\n";
            } else {
               print "<DD>$data</DD>\n";
            }
         } else {
            if ($data =~ "^Large") {
               print "   $data, size=$DirCache{$file}->{size}\n";
            } else {
               print "   $data\n";
            }
         }
      }
      if (defined($opt_w)){
         print "</DL>\n";
      } else {
         print "\n";
      }
   }
}

if (defined($opt_w)){
   print "<HR>\n";
   print "<ADDRESS>\n";
   print "Floyd Moore (red\@fc.hp.com)\n";
   print "</ADDRESS>\n";
   print "</BODY>\n";
   print "</HTML>\n";
}
