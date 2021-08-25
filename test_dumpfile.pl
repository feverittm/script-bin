#!/usr/bin/perl -w
#
#       Name: parse_bookmarks.pl
#       Author:  Floyd Moore (redfc.hp.com)
#	$Header: parse_bookmarks.pl,v 1.4 2003/12/03 17:03:46 red Exp $
#	Description:

#       structure,  verify the links and then write out the valid links
#       to a new html document.
#         By default it reads the .netscape/bookmarks.html file.
#

#--------------------------------------------------------------------------
# Data Structure Notes:
# --------------------
# Node structure
# $node[i]->{name}   : Def'n list name (comes from the <h1|3> tag
# $node[i]->{desc}   : Description of node from the <DD> tag
# $node[i]->{url}    : Actual url of the bookmark link.
# $node[i]->{parent} : Which list owns/instanciates this list $undef if root.
# $node[i]->{kids>   : children lists,  $undef if a leaf node.
#
# All leaf nodes should be links (ie urls).  If a node is a url then the
# kids should be undef (leaf), if it is another child list, then the url
# will be undef.
#
#     

#--------------------------------------------------------------------------

use strict;
use Data::Dumper;
local $Data::Dumper::Indent=1;

#####################################################
# Usage: DumpLinks(\%Hash);
#
use vars qw ($ArrayDepth $spaces);
$ArrayDepth = 0;

sub DumpLinks {
   my $href = shift;
   my %Hash = %$href;
   
   if (!defined($href->{name})){
      die "DL list name not defined!\n";
   }

   $spaces="";
   for (my $i = 0; $i < $ArrayDepth; $i++){
      $spaces .= " . ";
   }

   if (defined($href->{url})){
      print "$spaces $href->{name} [$href->{url}]\n";
   } else {
      print "$spaces List: $href->{name}\n";
   }
   if (defined($href->{kids})){
      ++$ArrayDepth;
      DumpKidsList($href->{kids});
      --$ArrayDepth;
   }
}

#####################################################
# Dump a arbitrary hash data structure to the output.
# Usage: DumpListStructure($name, \@Array);
#

sub DumpKidsList {
   my $aref = shift;
   my @Array = @$aref;

   for my $aindx (@Array){
      DumpLinks($aindx);
   }
}

######################################
#  Main Program	 #####################
######################################

use vars qw($dbfile $node $Root);
use vars qw(%PageCache @BadHosts);

$dbfile="out";
print "Loading previous results from $dbfile...\n";
open(IN,"<$dbfile") || die "Cannot read old output from file\n";
my $ret="";
my $buf;
while(read(IN, $buf, 16384)){
   $ret .= $buf;
}
close(IN);
eval $ret;

print " ... Previous database file loaded into memory.\n";

print "Page Cache...\n";
print Data::Dumper->Dump([\%PageCache], ["*PageCache"]);

print "\nBad Hosts defined...\n";
print Data::Dumper->Dump([\@BadHosts], ["*BadHosts"]);
