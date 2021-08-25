#!/usr/local/bin/perl5 -w
#
#       Author:  Floyd Moore (red@fc.hp.com)
#       Date: Wed Oct 17 10:33:06 MDT 2001
#       $Header:$ 
#       Description:
#
#       "density_check.pl" created by red
#
#       $Log:$
#
#
use strict;
use subs qw(handler show_usage);
use POSIX qw(strftime);
use vars qw($end_x $end_y $end_p);
use vars qw(%Edges @Rects @Polygon @Points);
use vars qw($blk $blockpath $icp);
use vars qw($opt_x $opt_v $opt_V);

unless($ENV{ICPROCESS}){
   die "You must have an environment loaded prior to running this script!\n";
}

my $Uid = getpwuid $<;
my $RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
my $Rev = (split(' ', '$Revision: 1.2 $', 3))[1];
my ($DirName, $ProgName);
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

use Getopt::Std;
unless (&Getopt::Std::getopts('xvV')) {
    &show_usage();
    exit(1);
}

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "Check for the poly denisty of a block\n";
   print "\n";
   print "$ProgName [-xvV] <block>\n";
   print "   Options:\n";
   print "   -V :  Report version number and quit\n";
   print "   -x :  debug mode\n";
   print "   -v :  verbose mode\n";
   print "\n";
}

sub get_dir     # Fast get_dir
{
    my($B) = @_;
    return (map {"$_/$B"} grep { -d "$_/$B" } split(/:/,$ENV{'BLOCKPATH'}))[0];
}

sub round
{
   my $x=$_[0];
   my $dec = $_[1];
   my $add = $x<0 ? -0.5 : 0.5;
   if ( $dec == 0) { return $x; }
   $dec = 10 ** $dec;
   my $out = int(($x)*$dec + $add) / $dec;
   return($out);
}

########################################################################

use vars qw($poly_area $cell_area $twopass $in_block $bounds $percent);
use vars qw($skip_instance $working_block %Area %Bounds);

unless(defined($ARGV[0])){
   &show_usage;
   die "You need to supply a blockname\n";
}

#print "# $ProgName  $Rev\t\t$RunDate\n\n";
$blk=$ARGV[0];
$icp=$ENV{ICPROCESS};

if ($blk !~ /^\//){
   $blockpath=get_dir($blk);
} else {
   $blk = $blockpath;
   $blk =~ s/^.*\/([^\/]+)$/$1/;
}

my $archive="$blockpath/art_$icp/piglet.arc";

# create a new archive...
system ("art_archive -a -n2 $blk") && 
   die "Cannot create archive of bypass block\n";

# parse the archive...
open (ARC,"<$archive") ||
   die "Cannot open piglet archive\n";
$/=";";
undef $in_block;
my $poly_area=0;
my $cell_area=0;
my $twopass;
my $pass=0;
while (<ARC>){
   s/^\s+//;
   s/\s+/ /g;
   chomp;
   /^EDIT\s+(\S+)/ && do {
      $working_block=$1;
      $working_block=~s/[AE]$//;
      if (exists($Area{$working_block})){ $skip_instance=1; next; }
      undef $skip_instance;
      if ($poly_area > 0){
         if ($bounds == 0){
            # no cell boundary specified... use cell boundaries
            $bounds=$cell_area;
         }
       
         $percent=int(1000*($poly_area/$bounds)+0.5)/10;
         print "Sum of area in block $in_block = $poly_area [ $percent% ]\n\n";
         
         $Area{$in_block}=$poly_area;
         $Bounds{$in_block}=$bounds;
      }
      print "Edit block $working_block\n";
      $in_block=$working_block;
      $poly_area=0;
      $cell_area=0;
      $bounds=0;
      next;
   };
   if (defined($skip_instance)) { next; }
   if (defined($in_block) && $in_block eq $blk && defined($twopass)){
      print "Rewinding the archive to beginning to start second pass\n";
      close(ARC);
      open (ARC,"<$archive") ||
         die "Cannot re-open piglet archive\n";
      undef $twopass;
      if ($pass > 1){
         die "Already went around for a second pass.\n";
      }
      $pass++;
      next;
   }

   if ($_ !~ /^ADD\s+/){ next; }
   if ($_ !~ /^ADD R4/ && $_ !~ /^ADD R30/ ){ 
      use vars qw ($x1 $x2 $y1 $y2 $instance);
      /ADD N/ && do { next; };
      /ADD P/ && do { next; };
      /ADD L/ && do { next; };
      /ZCONT/ && do { next; };
      /happy/ && do { next; };
      /ADD R\d+/ && do { next; };
      s/^ADD\s+//;
      ($instance, $_) = split(/ /, $_, 2);
      $instance =~ s/[AE]$//;
      #print "Add instance: $instance\n";
      if (exists($Area{$instance})){
         #print "add instance area for $instance: $Area{$instance}\n";
         $poly_area+=$Area{$instance};
         $cell_area+=$Bounds{$instance};
      } else {
         print "Lower-level cell $instance not yet defined... switch to two pass mode.\n";
         $twopass=1;
      }
      next;
   };
   s/^ADD\s+//;
   s/,/ /g;
   s/R4\s+// && do {
      use vars qw ($x1 $x2 $y1 $y2 $area);
      #print "Add poly: line=$_\n";
      ($x1, $y1, $x2, $y2) = split(/ /);
      $area=($x2-$x1)*($y2-$y1);
      #print "   ...Area=$area\n";
      $poly_area+=$area;
   };
   s/R30\s+// && do {
      use vars qw ($x1 $x2 $y1 $y2);
      #print "Add boundary: line=$_\n";
      ($x1, $y1, $x2, $y2) = split(/ /);
      $bounds=($x2-$x1)*($y2-$y1);
      print "   ...Boundary Area=$bounds\n"
   };
}
close(ARC);

if ($bounds == 0){
   # no cell boundary specified... use cell boundaries
   $bounds=$cell_area;
}
       
$percent=int(1000*($poly_area/$bounds)+0.5)/10;
print "Sum of area in block $in_block = $poly_area / $bounds [ $percent% ]\n\n";

