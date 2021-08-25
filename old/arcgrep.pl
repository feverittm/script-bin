#!/usr/local/bin/perl5 -w 
use strict;
use Getopt::Std;
use vars qw($File $LineBuffer $InputLine $MatchPat);
use vars qw($opt_v $opt_p);

if ( $#ARGV < 0) {
   die "Bad Usage: Not enough arguenments!\n";
} elsif ( $ARGV[0] =~ "-help"){
   die "Usage: arcgrep [-v] <pattern> <file>\n";
}

unless (&Getopt::Std::getopts('vp:')) {
     die "Bad arguement. Usage:  arcgrep [-v] <pattern> <file>\n";
   }

$MatchPat=$ARGV[0];
$File=$ARGV[1];
#print "Match pattern=$MatchPat\n";
#print "File: $File\n";

$LineBuffer="";
open (ARC,"<$File") || die "cannot open grep file $File\n";
while (<ARC>){
   $InputLine=$_;
   # 
   if (defined($LineBuffer)){
      $LineBuffer = $LineBuffer . " " . $_;
   } else {
      $LineBuffer = $_;
   }
   
   unless($LineBuffer =~ /;$/) { next; }
   
   if ($LineBuffer =~ /$MatchPat/){
      #print "Matched pattern at line: $.\n";
      unless(defined($opt_v)){
         print "$LineBuffer";
      }

      undef($LineBuffer);
      next;
   }

   if (defined($opt_v)){
      print "$LineBuffer";
   }

   undef($LineBuffer);
}
close(ARC);
