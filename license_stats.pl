#!/usr/bin/perl -w
#
#       Author:  Floyd Moore (floyd.moore\@hp.com)
#	$Header: /home/red/bin/RCS/license_stats.pl,v 1.3 2005/05/05 17:53:45 red Exp red $
#	Description:
#
#	"<script_name>" created by red
#
#	$Log: license_stats.pl,v $
#	Revision 1.3  2005/05/05 17:53:45  red
#	Updated to reflect changes in the cache file and the Server cache information in
#	particular.  I also modified the final output to include port information.
#
#	Revision 1.2  2005/01/25 16:40:27  red
#	moved the lmstat stuff to a subroutine to load a data structure
#	made %Server a structure instead of a simple hash to hold more
#	information (ie status and machine).
#
#	Revision 1.1  2005/01/25 16:24:24  red
#	Initial revision
#
#

#use strict;
use subs qw(show_usage parse_options);
use POSIX qw(strftime);
use vars qw($opt_v $opt_x $opt_V $opt_c $opt_a $opt_f $opt_i $opt_l);
use vars qw($ProgName $RunDate $Rev $DirName);
use vars qw(@ToolList @VendorList %Server %Feature $lm_string $Buffer);
use vars qw(%Usage %Status);
use vars qw($vendor);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

use Getopt::Std;

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-xVv] [-c string] name\n";
   print "   name is the symbolic name for the service (ie 'mentor' for Mentor Graphics\n";
   print "   Options:\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
   print "   -c:        Use explicit server string \'port\@host\'\n";
   print "   -a:        report all usage, use lmstat -a\n";
   print "   -l:        list all features in a concise list\n";
   print "   -f <name>: report usage on feature <name> only\n";
   print "       -i:    ignore case in feature name matching\n";
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

   unless (&Getopt::Std::getopts('Vvxiaf:c:l')) {
	&show_usage();
	exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
}

sub load_cache
{
   my $dbfile=shift;
   $opt_v && print "Load license cache... $dbfile\n";
   open (CACHE, "<$dbfile") ||
      die "Cannot open cach'd db file on disc: $dbfile\n";
   my $ret="";
   my $buf;
   while(read(CACHE, $buf, 16384)){
      $ret .= $buf;
   }
   close(CACHE);
   eval $ret;

   if (!defined($ToolList[0])){
      unless(exists($ToolList[0]->{short_name})){
         die "Cannot access toollist table\n";
      }
      die "Bad database load\n";
   }

   for (my $i=0; $i<=$#VendorList; $i++){
      my $ref;
      my $vendor=$VendorList[$i];
      unless (exists($vendor->{license_info})){ next; }
      my $info=$vendor->{license_info};
      if (exists($vendor->{short_name})){
         $ref=$vendor->{short_name};
         $ref=~ s/^_//;
         #print "    short name ... $ref\n";
      } else {
         die "No short name defined for vendor: $vendor->{name}\n";
      }
      $opt_v && print "    info $ref ... $info\n";
      if (exists($Server{$ref}->{lmstring})){
         if ($Server{$ref}->{lmstring} ne $info){
            die "Mismatch between hardcoded $ref server and file cache: $Server{$ref}->{lmstring} <=> $info\n";
         }
         $Server{$ref}->{lmstring} =~ s/\.cv\.hp\.com//;
      } else {
         $Server{$ref}->{lmstring} = $info;
         $Server{$ref}->{lmstring} =~ s/\.cv\.hp\.com//;
      }
   }
}

sub get_lmstats 
{
   use vars qw ($feature $issued $inuse);

   $lic = shift;
   $opts = shift;
   $feature="";
   $inuse=0;
   $Buffer="";
   my $lmutil="/apps/flexlm/bin/lmutil";
   my $cmd="$lmutil lmstat ";

   if (defined($opts)){
      $cmd .= " " . $opts;
   }
   $cmd .= " -c $lic";
   open (LMSTAT, "$cmd |") || die "Cannot open pipe to lmutil\n";
   while (<LMSTAT>){
      chomp;
      /^Users of (\S+):\s+.Total of (\d+) licenses? issued;\s+Total of (\d+) licenses? in use/ && do {
         $feature=$1;
         $issued=$2;
         $inuse=$3;
         if (defined($opt_l)){ $Buffer .= "$feature, ";
            next;
         }
         #next unless ($inuse > 0);
         #print "Feature=$feature, inuse=$inuse, issued=$issued\n";
      };
      if (defined($opt_f)){
         if (defined($opt_i)){
            if ($feature !~ /$opt_f/i){ 
               next; 
            } 
         } else {
            if ($feature !~ /$opt_f/){ 
               next; 
            } 
         }
      }
      if (defined($vendor)){ 
         next if ($inuse == 0);
      }
      $Buffer .= "$_\n" unless defined($opt_l);
   }
   close LMSTAT;
}

sub load_status
{
   use vars qw($machine $state $port);

   foreach my $lic (keys %Server){
      undef $state;
      undef $machine;
      undef $port;

      # initialize variables to those from the database
      #($port, $machine) = split(/@/,$lic);
      #$Server{$lic}->{port} = $port;
      #$Server{$lic}->{machine} = $machine;

      # get license stats...
      get_lmstats($Server{$lic}->{lmstring}, undef);

      # see if the server is up...
      $Buffer =~ s/\s*License server status:\s+(\S+)// && do {
         #License server status: 1735@hpcvimd4
         my $line=$1;
         ($port,$machine) = split(/@/,$line);
         $opt_v && print "   ... server status $line: Machine=$machine, Port=$port\n";
         $Server{$lic}->{port} = $port;
      };
      $Buffer =~ s/\s*(\S+):\s+license server\s+(\S+)// && do {
         $machine=$1;
         $state=$2;
         if (exists($Server{$lic}->{machine}) && $Server{$lic}->{machine} ne $machine){
            die "Mismatch between server line and status line for machine: $machine\n";
         }
      };
      if (defined($machine)){
         $machine =~ s/\.cv\.hp\.com//i;
         $Server{$lic}->{machine} = $machine;
         $opt_v && printf " ... load_status: %-10s, Server=%-10s,State=%s\n",$lic, $machine, $state;
      }
      if (defined($state)){
         $Server{$lic}->{status} = $state;
      }
      #print "$Buffer\n";
   }
}

sub load_usage
{
   my $lic = shift;
}

######################################
#  Main Program	 #####################
######################################

my $dbfile="/com/red/tool_cache_db";
parse_options;

if (defined($opt_c)){
   if ($opt_c !~ /\d+\@\S+/){
      die "Bad license server specification: Need to be of form port\@host\n";
   }
   get_lmstats($opt_c, undef);
   print "$Buffer\n";
} else {
   load_cache($dbfile);
   if (defined($ARGV[0])){
      # if we have a vendor then we can extract currently used features
      $vendor=$ARGV[0];
      if (exists($Server{$vendor}->{lmstring})){
         $lm_string=$Server{$vendor}->{lmstring};
      } else {
         die "Cannot map $vendor to port\n";
      }
      get_lmstats($lm_string, "-a");
      print "$Buffer\n";
   } else {
      print "License Server Status:\n";
      load_status();
      foreach my $lic (sort keys %Server){
         if (exists($Server{$lic}->{status})){
            my ($machine, $state);
            $machine=$Server{$lic}->{port} . "@" . $Server{$lic}->{machine};
            $port=$Server{$lic}->{port};
            $state=$Server{$lic}->{status};
            printf "%-15s, Server=%-15s,State=%s\n",$lic, $machine, $state;
         } else {
            printf "%-15s, Server=%-15s,State=%s\n",$lic, $Server{$lic}->{lmstring}, "DOWN";
         }
      }
   }
}

