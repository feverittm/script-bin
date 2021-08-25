#!/usr/local/bin/perl5 -w
#
#	$Header$
#
#	"make_chpid.pl" created by red
#
#	$Log$
#
###################################################################
#
# Notes:
#   Archive of original chpid_idnum0 for reference.
#   ADD T18 :F40 "    000" 1210,110;
#   ADD T17 :F40 "    000" 1210,160;
#   ADD T16 :F40 "    000" 1210,210;
#   ADD T15 :F40 "    000" 1210,260;
#   ADD T13 :F40 "    000" 1210,310;
#   ADD T12 :F40 "    000" 920,60;
#   ADD T11 :F40 "    000" 920,110;
#   ADD T10 :F40 "    000" 920,160;
#   ADD T9 :F40 "    000" 920,210;
#   ADD T8 :F40 "    000" 920,260;
#   ADD T4 :F40 "    000" 920,310;
#
#   Script depends on a special block 'chpid_num0' which contains a string
#   of numerals "0 1 2 3 4 5 6 7 8 9" (note the space) which are DRC and ISS
#   clean.  These are used to create the correct blocks.
#
#   A trantor script will be needed to convert the contact layers from solid
#   figures into arrays of contact devices.
#
#   A revision.def file in the chpid_idnum0 directory contains the information
#   on the creation of the chipid block numbers.  Specifically the revision 
#   information for each layer.
#

use strict;
use subs qw(handler show_usage);
use vars qw($opt_V $opt_v $opt_x);
use POSIX qw(strftime);
use Getopt::Std;

my ($Rev, $RunDate, $DirName, $ProgName);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 1.2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$SIG{'HUP'} =   \&handler;
$SIG{'INT'} =   \&handler;
$SIG{'QUIT'} =  \&handler;
$SIG{'TERM'} =  \&handler;

#
#  Global Variables
#
my ($blockname, $blockpath);
my $archive;
my ($def_file, $artrep);
my %LAYERS;
my @NUMARC;
my @CHAR;
my $layer_name;
my ($full, $metal, $minor);
my ($char, $layerid,$revid,$location);
my ($xloc, $yloc);

#
# Define some useful terms
#

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print " Create the chpid block:";
   print "\n";
   print "$ProgName [-x] <blockname>\n";
   print "Options:\n";
   print "   -x)  Debug mode.\n";
   print "\n";
   exit 0;
}

sub get_dir	# Fast get_dir
{
    my($B) = @_;
    return (map {"$_/$B"} grep { -d "$_/$B" } split(/:/,$ENV{'BLOCKPATH'}))[0];
}

sub handler
{
    my($sig) = @_;
    warn "$ProgName:INFO: Caught a SIG$sig -- shutting down\n";
    exit(0);
}

sub load_define
{
   my ($layername, $layerid, $font, $dummy, $revid, $dummy, $location);

   open(DEF,"<$def_file") || die "Cannot open $def_file\n";
   while(<DEF>){
      /^\s*#/ && do { next; };
      /^\s*$/ && do { next; };
      chop;
      $opt_v && print "Loading: $_\n";
      # poly   T4  :F40 revision 100 location 920,310
      s/\s+/ /g;
      ($layername, $layerid, $font, $dummy, $revid, $dummy, $location) =
	 split(/ /);
      $layerid =~ s/^[TPRL]//;
      $LAYERS{$layername}=$layerid . ":" . $revid . ":" . $location;
      }
   close(DEF);
}

sub dump_define
{
   my $key;
   print "Dumping Layer information:\n";
   foreach $key (sort keys %LAYERS){
      print "Layer $key: $LAYERS{$key}\n";
      }
}

sub load_num_archive 
{
   my ($num0, $num_archive, $line);

   print "Reading chpid_num0 archive\n";
   $num0=&get_dir("chpid_num0");
   $num_archive=$num0 . "/art_i856/piglet.arc";
   open(ARC,"<$num_archive") || 
      die "Cannot open artwork archive: $num_archive\n";

   # set input record seperator to a ';' for reading a piglet archive.
   $/=";";
   $line=0;
   while (<ARC>){
      chop;
      s/\n/ /;
      s/^\s*//;
      /^\s*$/ && do { next; };
      /^GRID/i && do { next; };
      /^LOCK/i && do { next; };
      /^SAVE/i && do { next; };
      /^EXIT/i && do { next; };
      /^EDIT/i && do { next; };
      /^\$FILES/i && do { next; };
      /^SHOW/i && do { next; };
      /^LEVEL/i && do { next; };
      /^WINDOW/i && do { next; };
      /"GND"/i && do { next; };
      s/\s+/ /g;
      s/^ADD\s+P18\s*//;
      $NUMARC[$line]=$_;
      ++$line;
   }
   close(ARC);
   $/="\n";
}

sub round2
{
   my $in=$_[0];
   return (int(($in * 100.0) + 0.5 ) / 100.0)
}

sub shift_char
{
   #  Shift char by a fixed amount in X, Y;
   my $shift_x=$_[0];
   my $shift_y=$_[1];
   my $char=$_[2];
   my $_new;
   my $len;
   my ($loc, $xloc, $yloc);

   #print "Shifting char string by $shift_x, and $shift_y\n";
   #print "  Line before shift= '$char'\n";
   if ( $shift_x == 0 && $shift_y == 0 ) { return $char; }
   $_new="";
   $len=0;
   while (defined($char)){
      ($loc,$char)=split(/ /,$char,2);
      ($xloc, $yloc) = split(/,/, $loc);
      $xloc+=$shift_x;
      $xloc=&round2($xloc);
      $yloc+=$shift_y;
      $yloc=&round2($yloc);
      #
      #print "Shifting $loc... X=$xloc, Y=$yloc\n";
      $_new=$_new . " " . $xloc . "," . $yloc;
   }
   $_new=~s/^\s*//;
   #print "  Line after shift= '$_new'\n";
   return $_new;
}

sub presort_archive
{
   # using a loaded archive,  create a keylist of the extents of 
   # each character for each polygon line.  This will speed up
   # searching for the correct character.
   # 
   # The array NUM[$i] will contain the information.  We could actually
   # sort the array into actual characters, but the "0" character will
   # have to be special cased since it has >1 polygon.  Now have fixed the
   # '0' character to be a single polygon.  It should work now.
   #
   # Note that at font scale 40 the character spacing is 30um
   # First character "0" starts at x-loc 0.0.
   #   Character:     Xlocation"
   #   0		0
   #   1		60
   #   2		120
   #   3		180
   #  ... etc
   #   xloc = 60 * character_ordinal.
   #   add some padding to make sure to catch the whole character...
   #

   my ($c, $i, $rest, $dummy);
   my ($loc, $xloc, $yloc, $xwin_min, $xwin_max);
   my $tmp_name;
   my ($shift, $NEW);
   my ($len, $save);

   print "Presorting numbers in archive...\n";
   for ($c=0;$c<=15;$c++){
      # remember that the text justification is at the lower left of the char.
      $xwin_min=($c*60)-10;
      $xwin_max=($c*60)+40;   # 30 for 1 character + 10 for padding
      for ($i=0;$i<=$#NUMARC;$i++){
	 ($loc,$rest)=split(/ /,$NUMARC[$i],2);
	 ($xloc, $yloc) = split(/,/, $loc);
	 if ($xloc < $xwin_min || $xloc > $xwin_max) { next; }
	 print "Matched line $i for char $c\n";
	 $CHAR[$c]=$NUMARC[$i];

	 # need to shift the origin of the character to appear at 0,0
	 $rest="dummy";
	 if ($c==0) { next; };
         $shift=-1*($c*60);
	 $CHAR[$c]=&shift_char($shift,0,$CHAR[$c]);
	 last;
      }
   }
   print "Done\n";
   #print "Making a temporary archive to check the extraction\n";
   #$tmp_name="/tmp/tmparc.arc";
   #open (TMP,">$tmp_name")|| die "Cannot open temporary file\n";
   #for ($i=0;$i<=9;$i++){
   #   my $layer=100+$i;
   #   print "dumping character $i\n";
   #   print TMP "ADD T$layer :f40 '$i' ",$i*60,",0;\n";
   #   my $line=&shift_char($i*60,0,$CHAR[$i]);
   #   print TMP "ADD P18 $line;\n";
   #}
   #close(TMP);
}

sub dump_num0
{
   my $i;
   print "Dumping num0 archive information:\n";
   for ($i=0;$i<=$#NUMARC;$i++){
      print "Line $i: $NUMARC[$i]\n";
      }
}

#######################################################################
#
#  Main Part of the Script
#
#######################################################################
unless (&Getopt::Std::getopts('xvV')) {
   &show_usage();
   exit(1);
}

$opt_V && die "# $ProgName  $Rev\t\t$RunDate\n\n";

$blockname="chpid_idnum0";
$blockpath = &get_dir($blockname);
if (length($blockpath) == 0) {
    print "Cannot locate block: $blockname\n";
    &show_usage();
    exit(1);
}

#
# Define some useful terms
#

$def_file= $blockpath . "/revision.def";
$artrep= $blockpath . "/art_" . $ENV{ICPROCESS};
$archive= $artrep . "/piglet.arc";

#do some general checking...

if ( ! -d "$artrep" ) {
    die "No artwork rep found for block $artrep\n";
}

if ( ! -f "$archive" ) {
    die "No artwork archive found for block $artrep/piglet.arc\n";
}

if ( ! -f "$def_file" ){
    die "No revision id file found: $def_file\n";
}
else {
   if ( -w "$def_file" ){
      die "Revision file is still writable: please checkin with 'cu -u file'\n";
      }
}

&load_define;
$opt_v && &dump_define;

&load_num_archive;
$opt_v && &dump_num0;

&presort_archive;

open (WORK,">/tmp/work.arc") || die "Cannot open working archive: /tmp/work.arc\n";

print WORK "\$FILES\n\n";
print WORK " chpid_idnum0A\n";
print WORK "\$;\n";
print WORK "EDIT chpid_idnum0A;\n";
print WORK "SHOW #A;\n";
print WORK "LOCK 45;\n";
print WORK "LEVEL 1;\n";
print WORK "GRID 0.04,1 0,0;\n";
print WORK "WINDOW 0,0 1415,347.52;\n\n";

print "Working through revision information:\n";
foreach $layer_name (sort keys %LAYERS){
   ($layerid,$revid,$location) = split(/:/,$LAYERS{$layer_name});
   ($xloc, $yloc)=split(/,/,$location);
   print "Layer $layer_name:\n";
   $full=hex(substr($revid,0,1))+0;
   $metal=hex(substr($revid,1,1))+0;
   $minor=hex(substr($revid,2,1))+0;
   print "   Full Rev=$full, Metal Rev=$metal, Minor Rev=$minor\n";
   print "   Placing '$full' digit at $xloc,$yloc\n";
   # Full Rev
   $char=&shift_char($xloc,$yloc,$CHAR[$full]);
   print WORK "add P$layerid $char\n";
   # Metal Rev
   $xloc+=30;
   $char=&shift_char($xloc,$yloc,$CHAR[$metal]);
   print "   Placing '$metal' digit at $xloc,$yloc\n";
   print WORK "add P$layerid $char\n";
   # Minor Rev
   $xloc+=30;
   $char=&shift_char($xloc,$yloc,$CHAR[$minor]);
   print "   Placing '$minor' digit at $xloc,$yloc\n";
   print WORK "add P$layerid $char\n";
   }

print WORK "GRID 0.04,10 0,0;\n";
print WORK "LOCK 45;\n";
print WORK "SAVE;\n";
print WORK "EXIT;\n";

close (WORK);

__END__
