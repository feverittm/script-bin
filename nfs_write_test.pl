#!/usr/bin/perl -w
use strict;
use POSIX qw(strftime);
use Data::Dumper;
use Time::localtime;
use Benchmark;
use vars qw($verbose %Speed @TestPath $ret $Path $cmd $out $write_speed);
use vars qw(@XfrSizes $size $today $datestamp);
use vars qw($opt_v $opt_o $opt_s $opt_m $opt_d);


use Getopt::Std;
unless (&Getopt::Std::getopts('vo:s:m:d')) {
   die "Nfs write speed test: options = versbose [-v], Outfile [-o]\n";
}

$verbose=1 if (defined($opt_v));

# location of the output file...
my $outfile="/home/red/bin/nfs_speed.out";
$outfile = $opt_o if (defined($opt_o));

#What size transfers are we going to test... (in MB)
#@XfrSizes = ( 10, 100, 500 );
@XfrSizes = ( 100 );
if (defined($opt_s)){ undef @XfrSizes; push @XfrSizes, $opt_s; }

# which machines am I going to test...
@TestPath = ( "/home/red", 
              "/com/red/",
              "/net/hpcvifm/disc/home/red", 
            );
if (defined($opt_m)){
   undef @TestPath;
   $verbose=1;
   unless ( -w "$opt_m"){
      die "Cannot write into the machine path specified: $opt_m\n";
   }
   push @TestPath, $opt_m;
}

#Read in the previous results...
if ( -f $outfile){
   open(IN,"<$outfile") || die "Cannot read old output from file\n";
   $ret="";
   my $buf;
   while(read(IN, $buf, 16384)){
      $ret .= $buf;
   }
   close(IN);
   #print "Old file:\n$ret\n";
   eval $ret;
}

$today = ctime();
$datestamp=sprintf("%04d%02d%02dT%02d%02d%02d", 
                                      (localtime->year + 1900),
                                      (localtime->mon + 1),
                                      (localtime->mday),
                                      (localtime->hour),
                                      (localtime->min),
                                      (localtime->sec));

open (HTML, ">>/var/www/html/nfs_stats.inc") || 
   die "Cannot open html file for append\n";

$verbose && print "DateStamp: $datestamp\n";
my @array;
my $start_timer = new Benchmark;
my $passes=0;
for $size (sort @XfrSizes){
for $Path (sort @TestPath){
   ++$passes;
   my @array = [];

   my $net = (split("/",$Path))[1];
   my $host = (split("/",$Path))[2];
   if ( $net eq "home") { $host = "localdisk"; }
   if ( $net eq "com") { $host = "hpcvmask-com"; }
   
   # a side effect of the next test is that it will cause the automounter
   # to mount the remote directory specifed.  Therefore all of the remote
   # directory tests should have the same latency.
   unless ( -w "$Path"){
      print "Cannot access directory path: $Path";
      next;
   }
 
   my $start_bonnie_timer = new Benchmark;

   $verbose && print "Host: $host, $size MB, Path=$Path\n";
   $cmd="bonnie -d $Path -s $size -m $host -html 2>/dev/null";
   $out = `$cmd`;

   my $end_bonnie_timer = new Benchmark;

   my $bonnie_time = timediff ($end_bonnie_timer, $start_bonnie_timer);
   my $bonnie_secs = $bonnie_time->[0];

   $verbose && 
      print "Time to run bonnie on $Path for $size MB files, $bonnie_secs seconds: " . timestr($bonnie_time) . "\n";

   chomp $out;

#-------------------------------------------------------------
# Bonnie Output:
# 
#           -------Sequential Output-------- ---Sequential Input-- --Random--
#
#           -Per Char- --Block--- -Rewrite-- -Per Char- --Block--- --Seeks---
#Machine    MB K/sec %CPU K/sec %CPU K/sec %CPU K/sec %CPU K/sec %CPU  /sec %CPU
#hpcvifm     5 42666 83.3 256000 100.0 46545  9.1 31999 56.2 511999  0.0 33333.3 91.7
#
# html output:
#<TR><TD>hpcvifm</TD><TD>10</TD><TD>51199</TD><TD>90.0</TD><TD>341333</TD><TD>100.0</TD><TD>64000</TD><TD>25.0</TD><TD>37925</TD><TD>66.7</TD><TD>512000</TD><TD>50.0</TD><TD>33333.3</TD><TD>100.0</TD></TR>
#-------------------------------------------------------------
#
   
   $out =~ s/^<TR><TD>([^<]+)<\/TD>/<TR><TD>$1<\/TD><TD>$bonnie_secs<\/TD>/;
   $out =~ s/^<TR>/<TR><TD>$datestamp<\/TD>/;
   $out =~ s/\s+//;  # remove all whitespace.
   $verbose && print "$host = '$out'\n";
   unless (defined($opt_m)){
      print HTML "$out\n";
   }

   # Originally I was going to use HTML::Parser to parse the output, but
   # figured for this simple of hmml, it was way overkill and made the
   # code slower and less readable.  I will use a simple parser in direct
   # perl RE code here.
   {
      $out =~ s/<\/?TR>//ig; # remove the start and end <TR> tags...
      $out =~ s/<\/TD>//ig;  # remove the ending </TD> tag...
      $out =~ s/^<TD>//i;    #   ... and the <TD> at the start...
      $out =~ s/<TD>/:/ig;   #   ... finally change the remaining <TD>'s to
                             #       ":" to facilitate a simple 'split'
      #print "   ... Out = $out\n";
      @array = split(":", $out);
   }

   # Now the array \@array contains the data from the bonnie run...
   shift @array;
   shift @array;

   if (defined($opt_d)){
      for my $item (@array){
         print "... array item $item\n";
      }
   }

   $Speed{$host}->{$datestamp}=join(":",@array);
}
}

close HTML;
my $end_timer = new Benchmark;

my $total_time = timediff ($end_timer, $start_timer);
my $total_secs = $total_time->[0];

print "NFS Write test for $passes passes of bonnie $total_secs seconds: " . timestr($total_time) . "\n";


#print "\n";

unless (defined($opt_m)){
   local $Data::Dumper::Indent=1;
   open (OUT,">$outfile") || die "Cannot open speed output file\n";
   print OUT Data::Dumper->Dump([\%Speed],["*Speed"]);
   close (OUT);
}
