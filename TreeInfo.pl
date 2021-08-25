#!/usr/bin/perl -w
#
#       Author:  Floyd Moore (floyd.moore\@hp.com)
#	$Header:$
#	Description:
#
#	"TreeInfo" created by red
#
#	$Log:$
#

use strict;
use subs qw(handler show_usage parse_options get_dir file_mtime round);
use POSIX qw/strftime/;
use Data::Dumper;
local $Data::Dumper::Indent=1;
use Filesys::Tree qw/tree/;
use vars qw($mgc_home $opt_v $opt_x $opt_V);
use vars qw($ProgName $RunDate $Rev $DirName);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$SIG{'HUP'} =	\&handler;
$SIG{'INT'} =	\&handler;
$SIG{'QUIT'} =	\&handler;
$SIG{'TERM'} =	\&handler;

use Getopt::Std;

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-xVv]\n";
   print "   Options:\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
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

   unless (&Getopt::Std::getopts('Vvx')) {
	&show_usage();
	exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
}

######################################
#  Main Program	 #####################
######################################
my $depth=0;
my $parent;

parse_options;
$opt_v && print "# $ProgName  $Rev\t\t$RunDate\n\n";

my $top_dir = shift;

unless(defined($top_dir)){
   print "You need to specify a directory to dump\n";
   usage();
}

unless (-d "$top_dir"){
   die "$top_dir is not a directory!\n";
}

my $tree = tree({ 'directories-only' => 1, 'exclude-pattern' => q/obsolete/ }, $top_dir);

sub fillspace {
   my $count=shift;

   my $spaces="";
   for (my $i=0; $i<3*$count; $i++){
      $spaces .= " ";
   }
   return $spaces;
}

sub walkdir {
   my $hashref=shift;
   my %dir = %$hashref;
   
   for my $key (keys %dir){
      if ($key =~ /RCS/ ) { next; }
      if ($key =~ /debussyLog/ ) { next; }
      if ($key =~ /obsolete/ ) { next; }
      if ($key =~ /svdb/ ) { next; }
      #print "   ... walk $key at depth=$depth...\n";
      unless (exists ($dir{$key}->{contents})){
         die "Bad directory tree for $hashref\n";
      }
      my $contents = $dir{$key}->{contents};
      if (scalar(keys %{$contents}) > 0 ){
         # contents is another directory
         print fillspace($depth) . "$key\/\n";
         if ($key =~ /LIB_\w+/ ) { next; }
         if ($key =~ /work_\w+/ ) { next; }
         ++$depth;
         walkdir($contents);
         --$depth;
      } else {
         # contents is a simple leaf in the tree
         #print "   ... ... leaf $key\n";
         print fillspace($depth) . "$key\n";
      }
   }
}

walkdir($tree);

#print Data::Dumper->Dump([\$tree], ["*tree"]);

