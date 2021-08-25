#!/usr/local/bin/perl5 -w
# Usage: permute $seq $length
# Author: Floyd Moore <red@fc.hp.com>
# Reference: Copied from permute code (mjd-permute) in Example 4-4 of the 
# Perl Cookbook (page 126).
# Date: Tue May 23 10:21:58 MDT 2000
# Description:
#    Create a sequence of numbers $length long and choosing the $seq from 
#    the available $length factorial sequences.
#
use strict;
use Getopt::Std;

use subs qw(usage n2pat n2perm pat2perm);
use vars qw($opt_s $opt_l $opt_m);
use vars qw($seq $length $max @list);

if ($#ARGV<0){
   usage;
   exit 1;
}
   
unless (&Getopt::Std::getopts('s:l:m:')) {
   usage;
   exit 1;
} 

if (defined($opt_s)){
   $seq = $opt_s;
} else {
   usage
   $seq = 0;
}

if (defined($opt_l)){
   $length = $opt_l;
} else {
   $length = 5;
}

$max=$length+1;
if (defined($opt_m)) {
   $max=$opt_m;
   if ($max > $length){ $max = $length+1; }
} 


#print "Looking up $seq permuted index\n";
@list=n2perm($seq,$length-1);
@list=splice(@list, 0, $max);
print "@list\n";

#----------------------------------------------------
# usage 
sub usage {
   print "Usage: permute.pl -s <sequence number> [ -l <length> -m <max> ]\n";
   print "  Default is a length 5 and display the full sequence.\n";
}

#----------------------------------------------------
# n2pat($N, $len) : pruduce the $N-th pattern of length $len
sub n2pat {
   my $i	= 1;
   my $N	= shift;
   my $len	= shift;
   my @pat;
   while ($i <= $len + 1){
      push @pat, $N % $i;
      $N = int($N/$i);
      $i++;
   }
   return @pat;
}

#----------------------------------------------------
# pat2perm(@pat) : turn pattern returnned by n2pat() into
# permutation of integers.  XXX: splice is already O(N)
sub pat2perm {
   my @pat	= @_;
   my @source   = (0 .. $#pat);
   my @perm;

   push @perm, splice(@source, (pop @pat), 1) while @pat;
   return @perm;
}

#----------------------------------------------------
# n2perm($N, $len) : generate the Nth permutation of $len objects
sub n2perm {
   pat2perm(n2pat(@_));
}


