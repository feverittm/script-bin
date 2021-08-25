#!/usr/bin/perl -w
use strict;
use subs qw(show_usage parse_options);
use POSIX qw(strftime);
use vars qw($opt_v $opt_x $opt_V $opt_f $opt_m $opt_n);
use vars qw($ProgName $RunDate $Rev $DirName);
use vars qw($dbfile %Root $Href);
use Data::Dumper;
local $Data::Dumper::Indent=1;

use Getopt::Std;

unless (&Getopt::Std::getopts('Vvx')) {
	&show_usage();
	exit(1);
}

$dbfile = "out";

if (-f $dbfile){
   open(IN,"<$dbfile") ||
      die "Cannot read old database from file: $dbfile\n";
   my $ret="";
   my $buf;
   while(read(IN, $buf, 16384)){
        $ret .= $buf;
   }
   close(IN);
   #print "Old file:\n$ret\n";
   eval $ret;
}

if (!exists($Root{name})){
   die "Return from file read failed!\n";
}

print "List name is $Root{name}\n";

print Data::Dumper->Dump([\%Root], ["*Root"]);

exit;

my $depth=0;
sub printNode 
{
   my $node=shift;

   if (!exists($node->{name})){
      die "Bad node, no name defined!\n";
   }

   if (!exists($node->{parent}) && $node != $Href){
      die "Bad Node: No parent exists for non-root node\n";
   }

   print "Node Structure: Address=$node\n";
   print "  Name=$node->{name}\n";
   if (defined($node->{description})){
      print "  Description=$node->{description}\n";
   }
   if ($node != $Href){
      print "  Parent=$node->{parent}\n";
   }

   if (exists($node->{kids})){
      my $kids;
      for $kids (@{$node->{kids}}){
         ++$depth;
         print "  Kid Depth=$depth -- $kids:\n";
         printNode($kids);
         print "\n";
         --$depth;
      }
   } else {
      print "  No Children\n";
   }

}

#walk data structure
$Href=\%Root;
my $node=$Href;
print "\n";
print "Root node is $node\n";
printNode($Href);
