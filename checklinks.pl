#!/usr/bin/perl -w
# checklinks -- Check Hypertext
# Links on a Web Page
# Usage:  See POD below

#------------------------------------
# Copyright (C) 1996  Jim Weirich.
# All rights reserved. Permission
# is granted for free use or
# modification.
#------------------------------------

use HTML::LinkExtor;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Simple;
use URI::URL;

use Getopt::Std;
$version = '1.0';

# Usage
#-------------------------------------
# Display the usage message by scanning
# the POD documentation for the
# usage statement.

sub Usage {
    while (<DATA>) {
	if (/^B<[-A-Za-z0-9_.]+>;/) {
	    s/[BI]<([^>]*)>/$1/g;
	    print "Usage: $_";
	    last;
	}
    }
    exit 0;
}


# ManPage 
#------------------------------------
# Display the man page by invoking the
# pod2man (or pod2text) script on
# self.

sub ManPage {
    my($pager) = 'more';
    $pager = $ENV{'PAGER'} if $ENV{'PAGER'};
    if ($ENV{'TERM'} =~ /^(dumb|emacs)$/) {
	system ("pod2text $0");
    } else {
	system ("pod2man $0 | nroff -man | $pager");
    }
    exit 0;
}


# HandleParsedLink
#---------------------------------
# HandleParsedLink is a callback 
#provided for parsing handling HTML
# links found during parsing.  $tag
# is the HTML tag where the link was
# found. %links is a hash that contains
# the keyword/value pairs from
# the link that contain URLs. For
# example, if an HTML anchor was
# found, the $tag would be "a"
# and %links would be (href=>"url").

# We check each URL in %links. We make
# sure the URL is absolute
# rather than relative. URLs that don't
# begin with "http:" or "file:"
# are ignored. Bookmarks following a "#"
# character are removed.  
# If we have not seen this URL yet, we
# add it to the list of URLs to
# be checked. Finally, we note where
# the URL was found it its list of
# references.

sub HandleParsedLink {
      my ($tag, %links) = @_;
      for $url (values %links) {
        	my $urlobj = new URI::URL $url, $currentUrl;
	        $url = $urlobj->abs;
	        next if $url !~ /^(http|file):/;
	  $url =~ s/#.*$//;
	  if (!$refs{$url}) {
	      $refs{$url} = [];
	      push (@tobeChecked, $url);
	}
	  push (@{$refs{$url}}, $currentUrl);
    }
    1;
}

# HandleDocChunk
#--------------------------------
# HandleDocChunk is called by the
# UserAgent as the web document is
# fetched. As each chunk of the
# document is retrieved, it is passed
# to the HTML parser object for further
# processing (which in this
# case, means extracting the links).

sub HandleDocChunk {
    my ($data, $response, $protocol) = @_;
    $parser->parse ($data);
}


# ScanUrl
# ------------------------------
# We have a URL that needs to be
# scanned for further references to
# other URLs. We create a request to
# fetch the document and give that
# request to the UserAgent responsible
# for doing the fetch.

sub ScanUrl {
    my($url) = @_;
    $currentUrl = $url;
    push (@isScanned, $url);
    print "Scanning $url\n";
    $request  = new HTTP::Request (GET => $url);
    $response = $agent->request ($request, \&HandleDocChunk);
    if ($response->is_error) {
	die "Can't Fetch URL $url: $!\n";
    }
    $parser->eof;
}

# CheckUrl
# ------------------------------
# We have a URL that needs to be
# checked and validated. We attempt
# to get the header of the document
# using the head() function. If this
# fails, we add the URL to our list
# of bad URLs. If we do get the
# header, the URL is added to our 
# good URL list. If the good URL
# is part of our local web site 
#(i.e. it begins with the local
# prefix), then we want to scan
# this URL for more references.

sub CheckUrl {
    my($url) = @_;
    print "    Checking $url\n" if $verbose;
    if (!head ($url)) {
           push (@badUrls, $url);
    } else {
	   push (@goodUrls, $url);
	   if ($doRecurse && $url =~ /\.html?/ && $url =~ /^$localprefix/) {
	         push (@tobeScanned, $url);
	   }
    }
}

# Main Program
#---------------------------------

use vars qw ($opt_h $opt_H $opt_V);

getopts('hHpruvV') || die "Command aborted.\n";
$verbose   = ($opt_v ? $opt_v : 0);
$printUrls = ($opt_u ? $opt_u : 0);
$doRecurse = ($opt_r ? $opt_r : 0);

die "Version $version\n" if $opt_V;
ManPage() if $opt_H;
Usage() if $opt_h || @ARGV==0;

# Initialize our bookkeeping arrays

@tobeScanned = ();
# list of URLs to be scanned
@goodUrls    = ();
# list of good URLs
@badUrls     = ();
# list of bad URLs
@isScanned   = ();
# list of scanned URLs
%refs        = ();
# reference lists

# Use the first URL as the model
# for the local prefix. We remove the
# trailing file name of the URL and
# retain the prefix. Any URL that
# begins with this prefix will be 
#considered a local URL and available
# for further scanning.

$localprefix = ($opt_p ? $opt_p : $ARGV[0]);
$localprefix =~ s%[^/]*$%%;
print "Local Prefix = $localprefix\n" if $verbose;
if ($doRecurse && !$localprefix) {
    die "A local prefix is required i\
       to restrict recursive fetching\n";
}

# Put each command line arg on the
# list of files to scan. If the
# argument is a file name, convert
# it to a URL by prepending a "file:"
# to it.

for $arg (@ARGV) {
    if (-e $arg) {
	$arg = "file:" . $arg;
    }
    push (@tobeScanned, $arg);
}
    
# Create the global parser and
# user agent.

$parser = new HTML::LinkExtor(\&HandleParsedLink);
$agent  = new LWP::UserAgent;

# Keep Scanning and Checking until
# there are no more URLs

while (@tobeScanned || @tobeChecked) {
    while (@tobeChecked) {
	my $url = shift @tobeChecked;
	CheckUrl ($url);
    }

    if (@tobeScanned) {
	my $url = shift @tobeScanned;
	ScanUrl ($url);
    }
}

# Print the results.

if ($printUrls) {
    print "Scanned URLs: ", join (" ",
        sort @isScanned), "\n";
    print "\n";
    print "Good URLs: ", join (" ", 
        sort @goodUrls), "\n";
    print "\n";
    print "Bad URLs: ", join (" ", 
        sort @badUrls), "\n";
}

print "\n";
for $url (sort @badUrls) {
    print "BAD URL $url referenced in ...\n";
    for $ref (sort @{$refs{$url}}) {
	print "... $ref\n";
    }
    print "\n";
}

print int (@isScanned), " URLs Scanned\n";
print int (keys %refs), " URLs checked\n";
print int (@goodUrls), " good URLs found\n";
print int (@badUrls),  " bad  URLs found\n";

__END__

=head1 NAME

checklinks - Check Hypertext
 Links on a Web Page

=head1 SYNOPSIS

B<checklinks> [B<-hHpruvV>] I<urls>...

=head1 DESCRIPTION

I<checklinks> will scan a web site
 for bad HTML links.

=head1 OPTIONS

=over 6

=item B<-h> (help)

Display a usage message.

=item B<-H> (HELP ... man page)

Display the man page.

=item B<-p> I<prefix> (local prefix)

Specify the local prefix to be used
when testing for local URLs.  If
this option is not specified when 
using the B<-r> option, then a local
prefix is calculated from the first URL
 on the command line.

=item B<-r> (recurse)

Normally, only the URLs listed on the
 command line are scanned.  If
this option is specified, local URLs
 (as defined by the local prefix)
found within documents are fetched and scanned.

=item B<-u> (print URL lists)

The complete lists of good, bad and 
scanned URLs will be printed in
addition to the normally printed information.

=item B<-v> (verbose mode)

Display "Checking" messages 
as well as "Scanning" messaegs.

=item I<urls>

List of urls to be scanned. If the URLs
is a filename, then a "file:"
is prepended to the filename (this allows
 local files to be scanned
like other URLs).

=back

=head1 AUTHOR

Jim Weirich <C<jweirich@one.net>>

=head1 LIMITATIONS

When recursive scanning URLs 
option B<-r>), a local prefix is
calculated from the first URL on the 
command line by removing the last
file name in the URL path. If the 
URL specifies a directory, the
calculated prefix may be incorrect.
Always specify the complete URL
or use the B<-p> prefix 
option to directly specify a local prefix.

=head1 SEE ALSO

See also related man pages for 
HTML::LinkExtor, HTTP::Request,
LWP::UserAgent, LWP::Simple, and URI::URL.

=cut
