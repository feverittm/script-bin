#!/usr/bin/perl -w
#
#       Author:  Floyd Moore (floyd.moore\@hp.com)
#	$Header:$
#	Description:
#
#	"make_dir_dot.pl" created by red
#       make a 'dot' diagram input file that describes the layout
#       of a directory.
#
#	$Log:$
#

use strict;
use vars qw ($opt_V $opt_c $opt_x $opt_v $opt_F @Dirs); 
use Getopt::Std;


sub show_usage
{
   print "$0 [-xVv]\n";
   print "   Options:\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
   print "   -c:        Just create a simple CSV file of the dir structure\n";
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

   unless (&Getopt::Std::getopts('VvxcF')) {
	&show_usage();
	exit(1);
   }
}

sub traverse_dir
{
   my $top = shift;
   opendir (DIR, "$top") || die "Cannot opendir $top";
   while ($_ = readdir(DIR)){
      /^\.$/ && do { next; };
      /^\.\.$/ && do { next; };

      /obsolete/ && do { next; };
      if (defined($opt_F)){
         /RCS/ && do { next; };
      }

      my $fullpath = $top . "/" . $_;
      #print " dir entry = $fullpath\n";
      if (-d "$fullpath"){
         my $fullpath = $top . "/" . $_;
         push @Dirs, $fullpath;
         print " directory = $fullpath\n";
         if (defined($opt_c)){
            print "  CSV: \"$top\" -> \"$fullpath\"\n";
         } else {
            print DOT "  \"$top\" -> \"$fullpath\"\n";
         }
      } 
      elsif (-l "$fullpath"){
         print " sym-link = $fullpath\n";
      } else {
         ; #print "file=$fullpath\n";
      }
   }
   closedir DIR;
}

######################################
#  Main Program	 #####################
######################################

parse_options;
my $depth=0;

my $top_dir=shift;

$top_dir = "." unless defined($top_dir);

if ( ! -d "$top_dir" ){
   die "Cannot find top directory: '$top_dir'\n";
}

if (!defined($opt_c)){
   my $dotfile = "/tmp/dotfile";
   open (DOT, ">$dotfile") ||
      die "Cannot open dot output file: $dotfile\n";
}

push @Dirs, $top_dir;
while (scalar @Dirs > 0){
   my $dir = shift @Dirs;
   traverse_dir($dir);
   print " $dir ... depth=$#Dirs\n";
} 

unless(defined($opt_c)){
   close DOT;
}
