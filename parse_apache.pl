#!/usr/local/bin/perl5 -w
#
#       Author:  Floyd Moore (redfc.hp.com)
#	$Header:$
#	Description:
#          Analyze the apache logs
#
#	"parse_apache.pl" created by red
#
#	$Log:$
#

use strict;
use subs qw(handler show_usage parse_options file_mtime);
use POSIX qw(strftime);
use Time::Local;
use vars qw($opt_l $opt_m $opt_x $opt_v $opt_V);
use vars qw($client $identuser $authuser $date $time $tz $method $url);
use vars qw($protocol $status $bytes $rest);

my %Clients;
my %Pages;
my $page_limit=5;

my ($Rev, $RunDate, $DirName, $ProgName);
use vars qw($LogFile $datestamp);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$SIG{'HUP'} =   \&handler;
$SIG{'INT'} =   \&handler;
$SIG{'QUIT'} =  \&handler;
$SIG{'TERM'} =  \&handler;

use Getopt::Std;

sub handler
{
    my($sig) = @_;
    warn "$ProgName:INFO: Caught a SIG$sig -- shutting down\n";
    exit(0);
}

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-x] [-v] [-V] [-m <machine_name> [-l logfile] \n";
   print "   -m <machine_name> : check machine\n";
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

   unless (&Getopt::Std::getopts('Vvxl:m:')) {
      &show_usage();
      exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
}

sub file_mtime {
    my $filename = shift;
    # (stat("file"))[9] returns mtime of file.
    return (stat($filename))[9];
}

######################################
#  Main Program  #####################
######################################

# Global variables

parse_options;

$LogFile="/var/opt/apache/logs/access_log";
if (defined($opt_l)){
   $LogFile=$opt_l;
}
if ( ! -r $LogFile) {
   die "Cannot read Apache logfile $LogFile\n";
}

open (LOG, "<$LogFile" ) || 
   die "Cannot open file $LogFile for read access\n";

print "# $ProgName  $Rev\t\t$RunDate\n\n";

while (<LOG>){
   chomp;
   #print "Line: $_\n";
   ($client, $identuser, $authuser, $_) =
      split(/ /, $_, 4);

   ($date, $time, $tz, $method, $url, $protocol, $status, $bytes) =
      /\[([^:]+):(\d+:\d+:\d+) ([^\]]+)\] "(\S+) (.*?) (\S+)" (\S+) (\S+)$/;

   #($client, $identuser, $authuser, $date, $time, $tz, $method, $url,
   # $protocol, $status, $bytes) =
   #/^(\S+) (\S+) (\S+) \[([^:]+):(\d+:\d+:\d+) ([^\]]+) "(\S+) (.*?) (\S+)"
   #   (\S+) (\S+)$/;
   
   print "Client: $client\n";
   if ( exists($Clients{$client})){
      $Clients{$client}++;
   } else {
      $Clients{$client}=1;
   }
   print "  url   = $url\n";
   if ( exists($Pages{$url})){
      $Pages{$url}++;
   } else {
      $Pages{$url}=1;
   }
   print "  date  = $date at $time\n";
   print "  status= $status\n";
   if ($status == 200){
      print "  bytes= $bytes\n";
   }
}

print "===============================\n";
print "Client Stats:\n";
for my $key (sort keys %Clients){
   printf "%-40s: %d\n", $key, $Clients{$key};
}

print "===============================\n";
print "Page Stats:\n";
for my $key (sort keys %Pages){
   if ($Pages{$key} > $page_limit){
      printf "%-40s: %d\n", $key, $Pages{$key};
   }
}

__END__
