#!/usr/bin/perl

########## Copyright ##########
# Copyright (C) 2008, NCSA.  All rights reserved
#
# Developed by:
# 	National Center for Supercomputing Applications
# 	University of Illinois at Urbana/Champaign
# 	http://www.ncsa.uiuc.edu
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# with the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# 	* Redistributions of source code must retain the above copyright
# 	notice, this list of conditions and the following disclaimers.
#
# 	* Redistributions in binary form must reproduce the above copyright
# 	notice, this list of conditions and the following disclaimers in the
# 	documentation and/or other materials provided with the distribution.
#
#	* Neither the names of National Center for Supercomputing Applications,
#	University of Illinois at Urbana/Champaign, nor the names of its
#	contributors may be used to endorse or promote products derived from
#	this Software without specific prior written permission.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS WITH
# THE SOFTWARE. 
#
# http://www.otm.uiuc.edu/node/396


########## Declarations ##########

## Includes ##
use strict;
use GraphViz;
use PPI;
use PPI::Dumper;
use Getopt::Long;
use File::Basename;
use Digest::SHA1 qw(sha1 sha1_hex sha1_base64);

## "Constants" ##
# Colors of the rainbow (ROYGBIV), adjusted so that they contrast with a white
# background. 
my @fgcolors = (
	'Maroon',
	'Firebrick',
	'Red',
	'SaddleBrown',
	'Orange',
	'DarkGoldenrod',
	'DarkGreen',
	'SeaGreen',
	'MidnightBlue',
	'CornflowerBlue',
	'Indigo',
	'Violet');

## Command-Line Parameters ##
my $INFILE = undef;
my $OUTFILE = undef;
my $DEBUG = undef;

## Globals ##
my %functions;



########## Functions ##########
sub usage {
print <<EOF;
usage:
	$0 -i <inputfile.pl> -o <outfile> [-debug]

<outfile> is the image file to be written.  The format is selected
	based on the extension of the filename.  The supported types
	are: .png, .bmp, .cmapx, .imap, .svg, .vrml, .gv, and .txt.

EOF
}


sub bangline {
	my $file = shift;
	my $bangline;

	open BANGLINE, "<$file";
	$bangline = <BANGLINE>;
	close BANGLINE;
	chomp($bangline);

	return $bangline;
}


sub wcl {
	my $file = shift;
	my $linecount = 0;
	
	open WCL, "<$file";
	while (<WCL>) { $linecount++; };
	close WCL;
	
	return $linecount;

}


sub graphviz_escape {
	my $s = shift;
	$s =~ s/[\\]/\\\\/g;
	$s =~ s/[\"]/\\\"/g;
	$s =~ s/[\.]/\\\./g;
	return $s;
}


sub elipsis {
	my $elipsis = shift;

	# Extract the first line from the string we were given
	my @lines = split(/\n/, $elipsis);
	chomp($lines[0]);
	$elipsis = $lines[0];

	# Truncate the string:
	$elipsis = substr($elipsis, 0, 30);

	# Add an elipsis, if anything was removed.
	if ( ($#lines > 1) or (length($lines[0]) > length($elipsis)) ) {
		$elipsis .= "...";
	} 

	# Done!
	return $elipsis;
}


sub calledfrom {
	### Pre-Work ###
	my $n = shift;
	my $word = sprintf("%s", $n);

	### Analyze ###
	# Walk up the prase tree, until we find solid ground
	while ( (not $n->isa('PPI::Document') ) and (not $n->isa('PPI::Statement::Sub')) ) {
		$n = $n->parent;
	}

	### Interpret the results ###
	if ( $n->isa('PPI::Document') ) {
		# Did we fall through to the root of the document?		
		# If so, this must have been called from Main.
		return "MAIN";
	}
	elsif ( defined($n->name) and ($n->name ne $word) ) {
		# FIXME
		return $n->name;
	}
	else {
		# FIXME
		return undef;
	}

}


########## Main ##########

### Parse the command-line ###
# Read the command-line arguments
GetOptions(
	'i=s' => \$INFILE,
	'o=s' => \$OUTFILE,
	'debug' => \$DEBUG,
	'help' => sub { usage() ;}
	) or usage();

# Are missing any critical arguments?
if ((not defined $INFILE) or (not defined $OUTFILE)) {
	# If critical arguments are missing, quit and display help.
	usage();
	exit(1);
}


### Parse the Perl input-file ###
# Do the actual parsing
my $Document = PPI::Document->new($INFILE, readonly=>1) or die ("Parser could not read \"$INFILE\"\n");
$Document->index_locations();

# Generate debug output
if (defined $DEBUG) {
	my $Dumper = PPI::Dumper->new($Document);
	print "--- Begin $INFILE PPI Dump ---\n";
	$Dumper->print;
	print "--- End $INFILE PPI Dump ---\n\n";
}


### Create the graph data-structure ###
# Generate debug output
if (defined $DEBUG) { print "--- Begin Nodelist ---\n" }

# Create the data-structure
my $g = GraphViz->new(
	layout=>'dot',
	directed=>1,
	overlap=>'orthoyx',
	rankdir=>'RL',
	concentrate=>1);

# Add the node for $INFILE's Main
my $label = graphviz_escape($INFILE . "\n" . bangline($INFILE) . "\nMAIN\n" . wcl($INFILE) . " lines");
$g -> add_node(
	"MAIN",
	label=>$label,
	shape=>'box',
	style=>'bold');
if (defined $DEBUG) { print "MAIN Block: label=>\"$label\"\n"; }

## Read Nodes ##
# Find subroutines and add them to the graph
my $nodes = $Document->find( sub { $_[1]->isa('PPI::Statement::Sub') and $_[1]->name });
foreach (@$nodes) {
	## Pre-Work ##

	# Retrieve the line-number of the sub declaration:	
	my $linenumber = $_->location()->[0];

	# Record the name of the function we've just seen, so that we can look
	# for calls to it:
	$functions{$_->name} = 1; 

	# Pick a color for this node in a deterministic fashion. The
	# color-value is derived from the function name.  The destination-node
	# and all edges leading to it will be the same color:
	my $myfgcolor = $fgcolors[unpack("N", sha1($_->name)) % ($#fgcolors+1)]; 
	## Note the edges ##
	if (not $_->isa('PPI::Statement::Scheduled')) {
		# Debug output
		if (defined $DEBUG) { print "Subroutine: ".$_->name."\n"; }

		# This node is a regular subroutine
		$g->add_node(
			$_->name,
			label=>graphviz_escape($linenumber.': sub '.$_->name.'{}'),
			color=>$myfgcolor,
			fontcolor=>$myfgcolor);
	}
	else {
		# Debug output
		if (defined $DEBUG) { print "Scheduled Block: ".$_->name."\n"; }

		# This node is a BEGIN{}, END{}, or other "scheduled" block
		$g->add_node(
			$_->name,
			label=>graphviz_escape($linenumber.': '.$_->name.'{}'),
			shape=>'box',
			color=>$myfgcolor,
			fontcolor=>$myfgcolor);
		$g->add_edge(
			"MAIN",
			$_->name,
			label=>graphviz_escape($linenumber.": Scheduled Block"),
			color=>$myfgcolor,
			fontcolor=>$myfgcolor);
	}
}
if (defined $DEBUG) { print "--- End Nodelist ---\n\n" }


## Edges ##
# Add the edges (calls) from main to the graph
if (defined $DEBUG) { print "--- Begin Edgelist ---\n" }
my $calls = $Document->find( sub { $_[1]->parent->isa('PPI::Statement') and ($_[1]->isa('PPI::Token::Word') or $_[1]->isa('PPI::Token::Symbol') ); }
);
foreach (@$calls) {
	# Pre-Work
	my $linenumber = $_->location()->[0];
	my $bareword=sprintf("%s", $_); 
	$bareword =~ s/^\&//;

	# Is this a Word we're interested in?
	if ( not defined $functions{$bareword} ){
		# If not, skip it!
		next;
	}

	# See where the word resides in the program-structure, if possible.
	my $calledfrom = calledfrom($_);
	if (defined $calledfrom) {
		# Debug output
		if (defined $DEBUG) { print "CAll: ".$calledfrom."->".$bareword."\n"; }

		# Color: Pick a color for this edge in a deterministic fashion.
		# The color-values is derived from the destination name.  The
		# destination-node and all edges leading to it will be the same
		# color.  Without further ado:
		my $myfgcolor = $fgcolors[unpack("N", sha1($bareword)) % ($#fgcolors+1)];  

		# Add the edge to the graph
		$g -> add_edge(
			$calledfrom,
			$bareword,
			label=>graphviz_escape("$linenumber: ".elipsis($_->parent->content)),
			color=>$myfgcolor,
			fontcolor=>$myfgcolor);
	}
}
if (defined $DEBUG) { print "--- End Edgelist ---\n\n" }



### Write the graph ###
# In case of debug, dump to stdout
if (defined $DEBUG) {
	print "--- Begin Graph Specification ---\n";
	print $g->as_debug;
	print "--- End Graph Specification ---\n";
}

# Write the image
open(GRAPH, ">$OUTFILE") or die ("Could not create $OUTFILE\n");
if ($OUTFILE =~ /\.png$/) { print GRAPH $g->as_png }
elsif ($OUTFILE =~ /\.bmp$/) { print GRAPH $g->as_wmbp }
elsif ($OUTFILE =~ /\.cmapx$/) { print GRAPH $g->as_cmapx }
elsif ($OUTFILE =~ /\.imap$/) { print GRAPH $g->as_imap }
elsif ($OUTFILE =~ /\.svg$/) { print GRAPH $g->as_svg }
elsif ($OUTFILE =~ /\.vrml$/) { print GRAPH $g->as_vrml }
elsif ($OUTFILE =~ /\.gv$/) { print GRAPH $g->as_debug }
elsif ($OUTFILE =~ /\.txt$/) { print GRAPH $g->as_plain }
else { die("Don't know how to generate $OUTFILE -- unknown extension\n") }
close(GRAPH);

