#!/usr/local/bin/perl5 -w
#
#       Author:  Floyd Moore (redfc.hp.com)
#	$Header:$
#	Description:
#
#	"<script_name>" created by red
#
#	$Log:$
#

use strict;
use subs qw(show_usage parse_options);
use POSIX qw(strftime);
use vars qw($opt_v $opt_x $opt_V $opt_t);
use vars qw($ProgName $RunDate $Rev $DirName);
use vars qw ($url $uri $ua $FedexTrackingSite);
use vars qw ($FedExPackageId $response);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

use Getopt::Std;
use LWP::Simple;
use URI::Heuristic;
use HTML::TokeParser::Simple;
use Data::Dumper;

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-xVv]\n";
   print "  Track FedEx Shipments using FedEx web site.\n";
   print "   Options:\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
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

   unless (&Getopt::Std::getopts('Vvx')) {
	&show_usage();
	exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
}

######################################
#  Main Program	 #####################
######################################

parse_options;
$opt_v && print "# $ProgName  $Rev\t\t$RunDate\n\n";

$FedexTrackingSite="http://www.fedex.com/cgi-bin/tracking?action=track&language=english&last_action=alttrack&ascend_header=1&cntry_code=us&initial=x&mps=y&tracknumbers=";

#Fedex tracking number comes in from command line
$FedExPackageId=shift;

#if ($FedExPackageId !~ /^\d+$/){
#   die "FedEX Tracking Numbers are all numberic! $FedExPackageId\n";
#}

print "Tracking FedEx Shippment: $FedExPackageId\n";

$url = $FedexTrackingSite . $FedExPackageId;
$uri = URI::Heuristic::uf_urlstr($url);

my $content = get($uri); #put site html in $content.
die "get failed" if (!defined $content); 
my $tmpfile="/tmp/tracking_$$.html";
open (TMP, ">$tmpfile") || 
   die "cannot open temporary file for html\n";
print TMP $content;
close TMP;

# create parser object
my $parser = HTML::TokeParser::Simple->new( $tmpfile );

use vars qw ( $tag $text $match $token $row );
$row=-2;
my @data;
while ($token = $parser->get_token ){
   unless (defined($match)){
      next unless $token->is_comment();  # don't care about comments...
      next unless ($token->as_is =~ /BEGIN Scan Activity/);

      $match=1;
      next;
   }

   $tag = $token->return_tag();

   if ($token->is_start_tag("img")){ next; }
   if ($token->is_start_tag("td")){ next; }
   if ($token->is_start_tag("span")){ next; }
   if ($token->is_start_tag("br")){ next; }
   if ($token->is_start_tag("b")){ next; }
   if ($token->is_end_tag("span")){ next; }
   if ($token->is_end_tag("b")){ next; }

   if ($token->is_end_tag("td")){
     if (!defined($text) || $text =~ /^\s*$/){
        next;
     }
     if ($row >= 0){
        #print "... Push data '$text' into row $row\n";
        push @{$data[$row]}, $text;
     }
     undef $text;
   }

   if ($token->is_text()){
      $text .= $token->as_is;
      $text =~ s/\&nbsp\;//;
      $text =~ s/\s*$//;
      if ($text =~ /^\s*$/){ next; }
      $text =~ s/^\s*//;
      #print "Table row $row data = '$text'\n";
      next;
   }

   #print "Tag=$tag, Line: '" . $token->as_is . "'\n";

   if ($token->is_start_tag("tr")){
      undef $text;
      next;
   }

   if ($token->is_end_tag("tr")){
      ++$row;
      next;
   } 

  if ($token->as_is =~ /END Scan Activity/){
     undef $match;
  }
}

unlink $tmpfile;

for ($row = 0; $row <= $#data; $row++){
   if ($data[$row][0] =~ /^[a-zA-Z]/){
      printf("%14s  %8s %28s %20s\n", @{$data[$row]});
   } else {
      printf("%14s  %8s %28s %20s\n", " ", @{$data[$row]});
   }
}

