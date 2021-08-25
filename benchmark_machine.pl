#!/usr/local/bin/perl5 -w
#
#	$Header$
#
#	"benchmark_machine.pl" created by red
#
#	$Log$

use strict;
use subs qw(handler show_usage parse_options get_dir tak);
use vars qw($opt_V $opt_x $opt_v $opt_h $opt_b $opt_t);
use POSIX qw(strftime);
use Getopt::Std;
use Net::Ping;
use Benchmark;

# Global variables
use vars qw($t0 $t1 $td);
use vars qw($Uid $RunDate $Rev $DirName $ProgName);
use vars qw($tak_loops $machine $hops $packet_size $bytes $count);
use vars qw($cpu_time $local_disk $remote_disk);
$tak_loops=5;
$hops=10;
$packet_size=4096;
$bytes=1024*1024*2;
$count=0;

sub show_usage
{
   print "Usage: benchmark_machine.pl <machine>\n";
   print " -V)  print version info\n";
   print " -h)  number of ping hops\n";
   print " -b)  Size of disk file\n";
   print " -t)  Number of loops of the tak benchmark to run\n";
   print " -v)  Verbose mode\n";
   print " -x)  Debug mode\n";
   exit -1;
}

sub get_dir	# Fast get_dir
{
    my($B) = @_;
    return (map {"$_/$B"} grep { -d "$_/$B" } split(/:/,$ENV{'BLOCKPATH'}))[0];
}

sub parse_options
{
   if ( defined($ARGV[0]) && $ARGV[0] =~ "-help"){
      &show_usage();
      exit(1);
   }

   unless (&Getopt::Std::getopts('Vb:h:p:t:vx')) {
      &show_usage();
      exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };

   if (defined($ARGV[0])){
      $machine=$ARGV[0];
   } else {
      $machine=`uname -n`;
      chomp $machine;
   }
   $hops=$opt_h if(defined($opt_h));
   $bytes=1024*$opt_b if(defined($opt_b));
   $tak_loops=$opt_t if(defined($opt_t));
}

sub tak {
    my($x, $y, $z) = @_;
    if (!($y < $x)) {
	return $z;
    } else {
	return &tak(&tak($x - 1, $y, $z),
		    &tak($y - 1, $z, $x),
		    &tak($z - 1, $x, $y));
    }
}



#------------------------------------------------------------------------
# Main program
#------------------------------------------------------------------------
my $Uid = getpwuid $<;
my $RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
my $Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$opt_v && print "# $ProgName  $Rev\t\t$RunDate  $Uid\n\n";

parse_options;
if (!defined($machine)){ print "Must run with machine name\n"; show_usage;}
my $check=`ypcat hosts | grep $machine | wc -l`+0;
if ($check == 0) { 
   die "Machine: $machine does not exist in the hosts database\n"; 
}
if (defined($opt_v)) {
   print "Machine information from hosts database:\n";
   print `ypcat hosts | grep $machine` . "\n";
}

my $model=`model`;
my $datestamp=`date +%Y%m%d%H%M`;
chomp $model;
chomp $datestamp;

#--------------------------------------------------------------------
# run the system utp ping for machine
#--------------------------------------------------------------------
use vars qw($machine $ping $ping_string $ret);
if (defined($opt_v)){
   $ret=system("/etc/ping hpcvmask $packet_size -n $hops | tee /tmp/ping.out");
} else{
   $ret=system("/etc/ping hpcvmask $packet_size -n $hops > /tmp/ping.out");
}

$ping_string=`grep "min\/avg\/max = " /tmp/ping.out`;
chomp $ping_string;
$ping_string=~s/.+=\s*//;
$ping=((split("/",$ping_string))[1])+0;
print "Ping=$ping\n";

#--------------------------------------------------------------------
# Use perl's internal TCP ping
#--------------------------------------------------------------------
die "Machine cannot be reached by TCP echo\n" unless(pingecho($machine));


#--------------------------------------------------------------------
# check uptime to machine for performance...
#--------------------------------------------------------------------
use vars qw($uptime);
$uptime=`uptime`;
chomp $uptime;
$uptime=~s/.*load average:\s*//i;
$uptime=(split(",",$uptime))[0];
print "Uptime=$uptime\n";

#--------------------------------------------------------------------
# Run a computational benchmark
#--------------------------------------------------------------------
use vars qw($total $avg $laps $ret);

$td = timeit($tak_loops, '$ret=&tak(20,12,6)');
print "$tak_loops loops of tak code took:",timestr($td),"\n";
$cpu_time=$td->[1];
print "Cpu index=$cpu_time\n";

#--------------------------------------------------------------------
# Time the creation and building of a large local file.
#--------------------------------------------------------------------
my $tmpfile="/tmp/bechmark.$$";
$t0= new Benchmark;
open(TMP,">$tmpfile") || 
   die "Cannot create tmp benchmark file on remote machine\n";
for($count=0; $count <= $bytes; $count++){
   print TMP "0123456789";
   if ($count % 80 == 0) { print TMP "\n"; }
}
close(TMP);
unlink $tmpfile;
$t1= new Benchmark;
$td=timediff($t1,$t0);
print "Time to create $bytes sized file: ", timestr($td), "\n";
$local_disk=$td->[1] + $td->[2];
print "Local Disk index=$local_disk\n";

#--------------------------------------------------------------------
# Time the creation and building of a large remote file.
#--------------------------------------------------------------------
$tmpfile="/net/fmlyd8/tmp/bechmark.$$";
$t0= new Benchmark;
open(TMP,">$tmpfile") || 
   die "Cannot create tmp benchmark file on remote machine\n";
for($count=0; $count <= $bytes; $count++){
   print TMP "0123456789";
   if ($count % 80 == 0) { print TMP "\n"; }
}
close TMP;
#
# do some random seek's on the file...
#
open(TMP,"<$tmpfile") || 
   die "Cannot re-open tmp benchmark file on remote machine\n";
srand ( time() ^ ($$ + ($$ << 15)) );
seek TMP, 0, 0;
my ($i, $ptr);
for ($i=0; $i<=16; $i++){
   $ptr=int(rand $bytes*8);
   seek TMP, $ptr, 0;
}
seek TMP, 0, 0;

close(TMP);
unlink $tmpfile;
$t1= new Benchmark;
$td=timediff($t1,$t0);
print "Time to create $bytes sized remote file: ", timestr($td), "\n";
$remote_disk=$td->[1] + $td->[2];
print "Remote Disk index=$remote_disk\n";


#
# Log the information into a database file:
#
my $logfile="/net/hpcvifm/disc/home/red/bin/benchmark.db";
open(LOG, ">>$logfile") || die "Cannot open logfile to write stats\n";
print LOG "$machine:$model:$datestamp:$cpu_time:$local_disk:$remote_disk\n";
close (LOG);
__END__
