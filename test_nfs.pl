#!/usr/bin/perl -w
use strict;
use Benchmark;

$SIG{'HUP'} =   \&handler;
$SIG{'INT'} =   \&handler;
$SIG{'QUIT'} =  \&handler;
$SIG{'TERM'} =  \&handler;

sub handler
{
    my($sig) = @_;
    warn "Caught a SIG$sig -- shutting down\n";
    exit(0);
}

my @foo;
my $time;
my @Times;
my $fails=0;
my $runs=500;

for(my $count=0; $count<=$runs; $count++){
   print "$count: $fails\n";
   my $t0 = new Benchmark;
   my $t1 = new Benchmark;
   my $td = timediff($t1, $t0);
   undef $time;
   #foreach my $key (@{$td}){
   #   print "Key: $key\n";
   #   if (!defined($time)) { $time=$key; }
   #}
   print "\n";
   ++$Times[$time];
   sleep 1;
}

my $tindx;
print "Max time is $#Times seconds\n";
for (my $tindx=0; $tindx<=$#Times; $tindx++){
   print "$tindx:\n";
   if (defined($Times[$tindx])){
      print "Time $tindx: $Times[$tindx] entries\n";
   }
}
