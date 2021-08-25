#!/usr/bin/perl -w
#
#       Name: parse_bookmarks.pl
#       Author:  Floyd Moore (redfc.hp.com)
#	$Header: /home/red/bin/RCS/parse_bookmarks.pl,v 1.8 2005/01/25 23:45:05 red Exp red $
#	Description:
#         Parse the netscape bookmark file.  Get all links and the list
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
use subs qw(show_usage parse_options);
use POSIX qw(strftime);
use vars qw($FetchCount $FetchCountLimit);
use vars qw($opt_x $opt_V $opt_f $opt_m $opt_n $opt_e $opt_L);
use vars qw($opt_R $opt_o $opt_v $ProgName $RunDate $Rev $DirName);

use vars qw ($PageTitle @Categories @Links %PageCache);
use vars qw ($now $Root $LinkCount @BadHosts);

use HTML::TokeParser::Simple;
use Data::Dumper;
local $Data::Dumper::Indent=1;

use CGI qw(:standard :html3);

my $Home=$ENV{HOME};
if (!defined($Home)){
   die "The HOME environment variable is not defined!";
}

#
#  Default File Locations.
#

# old netscape link
# my $bookmarks = $Home . "/.netscape/bookmarks.html";
# new list from mozilla
my $bookmarks = $Home . "/.mozilla/default/tmwz176u.slt/bookmarks.html";

my $htmlfile  = "verified_bookmarks.html";

my $dbfile    = $Home . "/.pagecache_db";

#
#  Setup usage and runtime/date information
#
$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

#
# Initalize Global Variables
#
$FetchCount = 0;
$now=time;

#####################################################
# Usage message
sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-xVvnf] [-o file.html] [-e filter_regex]\n";
   print "   Options:\n";
   print "   -f:        bookmark file, default is $bookmarks\n";
   print "   -e <regex> filter out bookmarks by a regular expression\n";
   print "   -o <file>  html file for the resultant verified bookmarks\n";
   print "   -m:        include the old svtd server links\n";
   print "   -n:        Don't actually check the links online\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
   print "   -L <#>:    Set limit for number of fetched URLs\n";
   print "\n";
   exit 0;
}

#####################################################
# Options parser
sub parse_options
{
   if ( $#ARGV > 0 && $ARGV[0] =~ "-help"){
	&show_usage();
	exit(1);
   }

   use Getopt::Std;

   unless (&Getopt::Std::getopts('VRvxmnf:e:L:o:')) {
	&show_usage();
	exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };

   if (defined($opt_f)){
      unless ( -r "$opt_f" ){
	 die "Cannot read specified bookmark html file: $opt_f\n";
      }
      $bookmarks = $opt_f;
   }

   if (defined($opt_L)){
      unless ($opt_L =~ /\d+/){
         die "Bad Fetch Limit specification: $opt_L should be a number!\n";
      }
      $FetchCountLimit = $opt_L;
      print "Setting Fetch limit to $FetchCountLimit\n";
   }

   if (defined($opt_o)){
      if (! -w $opt_o){
         die "Cannot write to specified HTML file location: $htmlfile\n";
      }
      $htmlfile = $opt_o;
   }
   
   if (! -w $htmlfile){
         die "Cannot write to HTML file location: $htmlfile\n";
   }
      
}


#####################################################
# Usage: DumpLinks(\%Hash);
#
use vars qw ($ArrayDepth $spaces);
$ArrayDepth = 0;

sub DumpLinks {
   my $href = shift;
   my $html = shift;
   my %Hash = %$href;
   
   if (!defined($href->{name})){
      die "DL list name not defined!\n";
   }

   $spaces="";
   for (my $i = 0; $i < $ArrayDepth; $i++){
      $spaces .= "   ";
   }

   if ($html == 1 ){
      if (defined($href->{url})){
         # List contents DT in standard formatting 
         print "$spaces<DT>$href->{link}</DT>\n";
      } else {
         # List header DT followed by link in H3 formatting
         print "$spaces<DT><H3>$href->{name}</H3></DT>\n";
         print "$spaces<DL><p>\n";
      }
   } else {
      if (defined($href->{url})){
         print "$spaces $href->{name} [$href->{url}]\n";
      } else {
         print "$spaces List: $href->{name}\n";
      }
   }

   if (defined($href->{kids})){
      ++$ArrayDepth;
      for my $aindx (@{$href->{kids}}){
         DumpLinks($aindx, $html);
      }
      --$ArrayDepth;
      if ($html == 1){
         $spaces =~ s/^   //;
         print "$spaces</DL>\n";
      }
   }

}

########################################################################
# Load the page cache and bad site data
#
sub LoadDB {
   if ( ! -r $dbfile ){
      print "No previous cache to load\n";
      return;
   }
   print "Loading page cache from $dbfile...\n";
   open(IN,"<$dbfile") || die "Cannot read old output from file\n";
   my $ret="";
   my $buf;
   while(read(IN, $buf, 16384)){
      $ret .= $buf;
   }
   close(IN);
   eval $ret;
}

sub SaveDB {
   print "Storing Page cache database\n";

   if ( ! -w $dbfile ){
      print "Cannot write to new page cache file: $dbfile\n";
      return;
   }

   # Clean out the page cache of stale entries.
   # Note:  there is a bug in this code and those entries that are
   #    'flushed' still show up as undefined refences in the output
   #    database file.
   my @keylist = sort keys %PageCache;
   for my $key (@keylist){
      unless (exists($PageCache{$key}->{hit})){
         print "  ... removing $key from page cache.\n";
         delete $PageCache{$key};
      }
      delete $PageCache{$key}->{hit};
   }

   open (OUT, ">$dbfile") || die "Cannot open output file\n";
   print OUT Data::Dumper->Dump([\%PageCache], ["*PageCache"]);
   print OUT Data::Dumper->Dump([\@BadHosts], ["*BadHosts"]);
   close OUT;

}

########################################################################
# 
# Write out the newly extracted and verified list
#
sub WriteHTML {
   my $html = "verified_bookmarks.html";

   open (HTML, ">$html" ) || 
      die "Cannot open html output file $html for writing\n";

   my $title = "Translated and Verified Netscape Bookmarks";
   
   print HTML start_html($title);
   print HTML "\n<DL>";

   select(HTML);
   DumpLinks($Root,1);
   select(STDOUT);

   print HTML end_html();
   close(HTML);
}

########################################################################
# Filter URL's based on a user specified regular expression and
# some built-in defaults.
#
#
sub FilterUrl {
   use URI::Heuristic;
   use vars qw ($url $uri $ua);

   $url = shift;
   $opt_x && print "   ... checking filter for $url\n";

   if ($url !~ /^ftp:|http:|https:/){
     print "  ... Skipping other format url: $url\n";
     return 1;
   }

   my $uri_o = URI->new($url);
   my $host = $uri_o->host;
   $opt_x && print "      ... host is $host\n";

   if ($host !~ /\S+\.\S+/){
     die "Bad incoming Url: $host!\n";
   }

   $uri = $uri_o->as_string;

   if ($uri =~ m%^http://eslnt3.fc.hp.com/%){
      return 1;
   }

   if ($uri =~ m%^http://\S+\.dtc\.hp\.com/%){
      return 1;
   }

   if ($uri =~ m%^http://(hpeswjl|fcxena|fcvtcweb|fml-bug|etldepot|(vtc|esl)web).fc.hp.com%){
      if (defined($opt_m)){
         print "Matched old SVTO web address... need authorization\n";
      } else {
	 return 1;
      }
   } 

   return 0;
}

########################################################################
# Check a url to make sure it is still valid...
#
#
sub CheckUrl {
   use LWP::UserAgent;
   use HTTP::Request;
   use URI::Heuristic;

   use vars qw ($url $uri $ua);

   $url = shift;

   if (FilterUrl($url)){ 
      $opt_x && print "      ... filter out url: $url\n";
      return 1;
   }

   my $uri_o = URI->new($url);
   my $host = $uri_o->host;
   $uri = $uri_o->as_string;

   if (defined($opt_n)){
      # don't run the online checks
      return 0;
   }

   if (exists($PageCache{$uri})){
      if (exists($PageCache{$uri}->{error})){
         $opt_x && print " ... page error found from cache\n";
         ++$PageCache{$uri}->{hit};
         return 1;
      }
      my $lastvisit=$PageCache{$uri}->{checked};
      if (!defined($lastvisit)){
         die "Last Visit not defined at $uri\n";
      }
      my $difftime = $now - $lastvisit;
      $opt_x && print "Valid Page $uri exists in page cache already: $difftime\n";
      ++$PageCache{$uri}->{hit};
      return 0;
   }

   if (defined($FetchCountLimit) && $FetchCount > $FetchCountLimit){
      $opt_x && print " ... fetch limit reached\n";
      return 0;
   }

   if (grep /^$host$/, @BadHosts){
      $opt_x && print " ... bad host found.  Skipping\n";
      return 1;
   }

   $|=1;
   #printf "%s =>\n\t", $uri;
   $ua = LWP::UserAgent->new(env_proxy => 1,
                             agent     => "Schmozilla/v9.14 Platinum"
                            );

   my $req = HTTP::Request->new(HEAD => $url);
   $req->referer("http://wizard.yellowbrick.oz");

   my $response = $ua->request($req);
   my $CacheEntry = { uri     => $uri,
                      host    => $host,
                      checked => $now,
                    };
   if ($response->is_error()){
      $opt_v && printf "Error in %s: %s\n", $uri, $response->status_line;
      if ($response->status_line =~ /Unauthorized/){
	 $opt_x && print "... Not authorized\n";
      }
      if ($response->status_line =~ /Unavailable/){
	 $opt_x && print "... Server $host not available\n";
         push @BadHosts, $host;
         return 1;
      }
      $CacheEntry->{error} = $response->status_line,

      $PageCache{$uri} = $CacheEntry;
      ++$PageCache{$uri}->{hit};
      return 1;
   } else { 
      my $header = $response->headers(); 
      my $title = $header->header("Title"); 
      my $server = $header->header("Server"); 
      if (defined($opt_v)){
         print "Url fetched: $uri\n";
         if (defined($server) && defined($title)){
            print "Header info for $server: $title\n";
         } elsif (defined($server)) {
	    print "Header found for $server\n";
         }
      }
      $CacheEntry->{server} = $server;
      $CacheEntry->{title} = $title;
   }

   $PageCache{$uri} = $CacheEntry;
   ++$PageCache{$uri}->{hit};
   ++$FetchCount;
   return 0;
}

########################################################################
# HTML DL List Parser
# This parser is designed to work with the netscape bookmarks file.  I
# don't know if it will work with anything else.
#
# Format of the netscape bookmarks file is a HTML definition list.
#
#  <DL>
#    <DT><H3> category name
#    <DL>  ... again
#      <DT> <A href="referenceurl">url name</a>
#        ...
#         <DL>  ... subcategory...
#         <DT>
#    </DL>
#        ... more categories
#  </DL>
# -----------------------------------------------------------
# When parsing the original list.
# 1 - parse though the top header information and title data.
# 2 - start the normal parser state machine...
#     parse token through end of file...
#     if token=<DD> then save the description into the current node.
#          note there isn't any </dd> so infer using start of next
#          entry and if the previous token was <dd> save the desc.
#     if token=<A> extract the link href.
#     if token=</A> url=token_text, create new node, save url, pop back.
#     if token=</H[13]> then start new list, category=token_text, goto state 1
#     if token=<p|hr> ignore.
#     if token=</dl> end of current node, pop to parent
#     nothing else should be here.
#    
# Use an array of hashs, @Tree, to hold the data.  Parent and Kids will hold
# then node number in the array.  This was we don't have to worry about 
# references.  What about when we delete an entry?  Probably should save 
# parent as a reference.
# -----------------------------------------------------------
sub ParseNetscapeBookmarks()
{
   use vars qw ($root $node);
   use vars qw (@state $token $text_line $tag $label $url);
   use vars qw ($add_date $mod_date $last_visit);
   use vars qw ($p $indx $Desc $count);

   $p = HTML::TokeParser::Simple->new( $bookmarks );
   $indx=0;
   $count=0;
   while ( $token = $p->get_token ) {
      # ignore any header information
      next if $token->is_comment();  # don't care about comments...
      next if $token->is_declaration(); # also don't care about declares..
      next if ($token->is_text() && $token->as_is =~ /^\s*$/);
	 # ignore html whitespace.

      $label = $token->as_is;
      $tag = $token->return_tag();
      #if (defined($text_line)){
      #   print "... text line = '$text_line'\n";
      #}

      if ($token->is_start_tag()){
         next if ($tag =~ /^p$/); # ignore new paragraph tags...
         next if ($tag =~ /^hr$/); # ignore new paragraph tags...

         # if the tag is a hyperlink we need to extract the url to 
         # connect to the site.
         if ($tag eq "a"){
	    $url        = $token->return_attr->{href};
	    $add_date   = $token->return_attr->{add_date};
	    $mod_date   = $token->return_attr->{last_modified};
	    $last_visit = $token->return_attr->{last_visit};
	    #print " ... ... url=$url\n";
         }

	 if (defined($state[0]) && defined($text_line) && $state[-1] eq "dd"){
	    #get description text
	    my $Desc = $text_line;
	    $opt_v && print "... Found description text: $Desc\n";
            if (exists($node->{name})){
               $node->{description}=$Desc;
            }
	    pop @state;
         } elsif (defined($state[0]) && $state[-1] eq "dd"){
            print "... empty description text for $node->{name}\n";
            pop @state; # remove the <dd> tag
         }

         #print "Start tag line $tag: $label\n";
         push @state, $tag;

	 undef $text_line;
         next;
      }

      if ($token->is_end_tag()){
	 if (!defined($tag)){
	    die "no tag defined!.\n";
         }
	 if (!defined($state[-1])){
	    die "Bad state queue!\n";
         }
         if ($tag eq $state[-1]){
	    $opt_x && print "... Found matching ending tag for $tag\n";

	    if ($tag eq "title") {
	       $PageTitle = $text_line;
	    } 
	    elsif ($tag eq "dl") {
	       if ($node != $root) {
		  $opt_v && print "  <<<  Ending sublist: $node->{name} >>>\n";
	          if (exists($node->{kids}) && $#{$node->{kids}} >= 0){
		     $opt_x && print "   ... list $node->{name} has $#{$node->{kids}} kids\n";
                     $opt_x && DumpLinks($node, 0);
	             $node = $node->{parent};
                  } else {
		     # prune empty children lists
		     $opt_x && print "   ... pruning empty children: $node->{name}\n";
		     my $save = $node;
	             $node = $node->{parent};
		     undef $save;
		     pop @{$node->{kids}};
                  }
	       }
	       $opt_x && print "   ... node is now set at: $node->{name}\n";
	       $opt_x && print "\n";
	    }
	    elsif ($tag =~ /^h[13]$/) {
	       $opt_v && print " ... category name is $text_line\n";
	       push @Categories, $text_line;
	       pop @state; # remove the h3 and let the end remove the dt


	       my $linknode = { name   => $text_line
                              };

	       if (!defined($node)){
		  print "Creating root tree from node: $text_line\n";
		  $root = $linknode;
		  $linknode->{parent}=undef;
               } else {
	          $linknode->{parent}=$node;
               }
		  
               push @{$node->{kids}}, $linknode;

	       $node = $linknode;
	    }
	    elsif ($tag eq "a") {
	       # need to build the link into a standard html url link:
	       # <a href="...url...">...name...</a>
	       if (!defined($url) || !defined($text_line)){
	          die " Bad url rewrite: label=$label, tag=$tag\n";
               }
	       my $link_tag="<a href=\"" . $url . "\">" . $text_line . "</a>";
	       #print " ... ... link html re--qritten as: $link_tag\n";

	       if (CheckUrl($url)){
		  $opt_v && print "Bad Url: $url\n";
		  undef $text_line;
	          if ($state[-1] eq "a"){
	             pop @state; # pop 'a' from the queue
                  }
	          if ($state[-1] eq "dt"){
	             pop @state; # pop 'dt' from the queue
                  }
	          #print "Node: $node->{name}, State Queue: " . join(", ", @state) . "\n";
		  next;
               }
	       ++$LinkCount;

	       my $linknode = { name   => $text_line,
				url    => $url,
                                link   => $link_tag,
				parent => $node
                              };


	       #print "new link reference $linknode\n";

               push @{$node->{kids}}, $linknode;

	       if ($state[-1] eq "a"){
	          pop @state;
               }

	       $count++;
	    }
            else {
	       die "Setting $tag to \'$text_line\'\n";
            }

	    pop @state;
         }

         undef $text_line;
         next;
      }
      if ($token->is_text()){
         $text_line .= $label;
	 $text_line =~ s/\s*$//;
         next;
      }

      #$token->rewrite_tag;
      #$tag = $token->return_tag();
      #print "Token Tag=$tag: " . $token->as_is . "\n";
   }

   print "Parsed $LinkCount Links in the bookmark file\n";
   print "Found $#Categories categories and sub-sategories\n";

   return ($root);
}


######################################
#  Main Program	 #####################
######################################

parse_options;
$opt_v && print "# $ProgName  $Rev\t\t$RunDate\n\n";

unless (defined($opt_R)){ LoadDB(); };

$Root = ParseNetscapeBookmarks();

if (!exists($Root->{name})){
   die "Return from parse failed!\n";
}

print "List name is $Root->{name}\n";

@Categories = sort @Categories;

if (defined($opt_v)){
   print "Category List:\n";
   for my $cat (@Categories){
      print "  $cat\n";
   }

   if (defined(@BadHosts) && $#BadHosts >= 0){
      print "Bad Hosts:\n";
      for my $badhost (sort @BadHosts){
         print "   $badhost\n";
      }
   }
}

SaveDB();

if (defined($opt_x)){
   my $node=$Root;
   DumpLinks($Root, 0);
}

WriteHTML();
