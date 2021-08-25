#!/usr/local/bin/perl5 -w
#
#	$Header$
#
#	"pagemail.pl" created by red
#
#	$Log$

use strict;
use subs qw(handler show_usage);
use POSIX qw(strftime);

my ($Rev, $RunDate, $DirName, $ProgName);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 1.2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$SIG{'HUP'} =   \&handler;
$SIG{'INT'} =   \&handler;
$SIG{'QUIT'} =  \&handler;
$SIG{'TERM'} =  \&handler;

$ENV{EPAGE_HOME}="/opt/epage";

use Getopt::Std;
unless (&Getopt::Std::getopts('v')) {
    &show_usage();
    exit(1);
}

sub handler
{
    my($sig) = @_;
    warn "$ProgName:INFO: Caught a SIG$sig -- shutting down\n";

#   close OUT;
#   `rm -f $tmpfile`;

    exit(0);
}

sub show_usage
{
   print "Usage: <cmd> | pagemail\n";
   print "  send a page for data in stdin\n";
}


my $now=`date`; chop $now;
open(DEBUG,">>/tmp/page.log") || die "cannot open page debug log\n";
print DEBUG "------------------------\n";
print DEBUG "$now:\n";
my $in_header=1;
my $outline;

while (<STDIN>) {
   chop;
   if ($in_header == 1){
      /^From\s+/ && do { next; };
      /^>From\s+/ && do { next; };
      /^Message-Id:\s+/ && do { next; };
      /^Received:\s+/ && do { next; };
      /^To:\s+/ && do { next; };
      /^X-Mailer:\s+/ && do { next; };
      /^MIME-Version:\s+/ && do { next; };
      /^Content-Type:\s+/ && do { next; };
      /^Content-Transfer-Encoding:\s+/ && do { next; };
      /^\s*$/ && do { $in_header=0; }
   }

   s/\t/   /g;
   s/ /_/g;
   print DEBUG "$_\n";
   s/\'/\"/g;
   $outline .= " " if (defined($outline));
   $outline .= $_;
   #print "$_\n";
}

my $save = "\'" . $outline . "\'";
print DEBUG "\n$save\n";

my $ret=-1;
select (DEBUG);
$ret=system ("/opt/epage/bin/epage","-r","fc_ncs01","moore,floyd",$outline);
select (STDOUT);
print DEBUG "System return code: $ret\n";
print DEBUG "------------------------\n";
close(DEBUG);

__END__
