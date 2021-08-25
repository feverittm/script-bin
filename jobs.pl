#!/usr/bin/env perl

use warnings;
use strict;

use LWP::UserAgent;
use HTML::TokeParser;
use HTTP::Cookies;
use Term::ReadKey;

my $DEBUG=0;

# Uncomment these for debugging LWP stuff
#use LWP::Debug qw(+ +conns);
#$ENV{HTTPS_DEBUG}=1;

# Pick one of these for script debugging
#$DEBUG=1;	# display entry to each subroutine
#$DEBUG=2;	# display all the html from all get/post calls. LOTS O' OUTPUT!

$|=1;

# Point to the HP CA certificate. If you don't have one, you can get it from
# the digital badge site.
foreach my $dir (qw(/etc/ssl/certs/ /usr/share/ssl/certs /opt/openssl/certs)) {
	foreach my $file ("hpq-ca.pem","cacert.pem") {
		$ENV{HTTPS_CA_FILE}="$dir/$file",last if (
			! defined $ENV{HTTPS_CA_FILE} && -r "$dir/$file");
	}
	last if defined $ENV{HTTPS_CA_FILE};
}

die "Set HTTPS_CA_FILE environment variable to point to HP's CA. You can get it at digitalbadge.hp.com" if ! defined $ENV{HTTPS_CA_FILE};

# Point to a convenient proxy server.
$ENV{HTTPS_PROXY}="http://web-proxy.corp.hp.com:8080" if ! defined $ENV{HTTPS_PROXY};

# Point to your class B digital badge. I don't know if this works with
# a class A. It certainly doesn't work with your NT login and password.
# Somebody might be able to make it work.
$ENV{HTTPS_PKCS12_FILE}='digital_badge.p12' if (! defined $ENV{HTTPS_PKCS12_FILE} && -r "digital_badge.p12");

die "Set HTTPS_PKCS12_FILE environment variable to point to your class B digital badge. You can get one at digitalbadge.hp.com" if ! defined $ENV{HTTPS_PKCS12_FILE};

# No changes should be required past this point.
##############################################################################

my $agent="Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.8.0.10) Gecko/20070302 Ubuntu/dapper-security Firefox/1.5.0.10";

my $summary=1,shift if (scalar @ARGV && $ARGV[0] eq "-s");
my $bigsummary=1,shift if (scalar @ARGV && $ARGV[0] eq "-S");

# The interface isn't elegant--it works.
# Only allow search on keyword right now.
die("Usage: $0 [-s][-S] keyword/req#\n" .
	"  -s: short summary of job\n" .
	"  -S: longer summary of job\n" .
	"  (none): entire job entry, in html\n" .
	"  keyword is put into keyword field of search screen.\n")
	if ! scalar @ARGV;

# get what to look for
my $keyword=join " ",@ARGV;
chomp($keyword);

# get user's passkey for their digital badge
print STDERR "password? ";
Term::ReadKey::ReadMode("noecho");
chomp(my $password=<STDIN>);
Term::ReadKey::ReadMode("restore");
print STDERR "\n";

$ENV{HTTPS_PKCS12_PASSWORD}=$password;

#-----------------------------------------------------------------------------
sub blah_blah {
	my ($output)=@_;

	warn "blah_blah\n" if $DEBUG;

	my @blah=(
	"Heading for zero-time technology transfer  At HP, we in R&D don't just dream about the future",
	"On manufacturing sites we turn foundation technology from HP labs into real solutions",
	"Prepare to be busy",
	"At HP, we in R&D don't just dream about the future. We invent it",
	"we in R&D don't just dream about the future",
	"Heading for zero-time technology transfer",
	"has the world's second largest computer research laboratory",
	"Software Engineers play lead roles in multi-discipline teams working on new products and solutions",
	"Additionally, innovation is the key",
	"And that gives hp leadership",
	"We're getting smarter",
	"Acting sharper",
	"Moving faster",
	"Then we invent",
	"Getting people off the bench and into customer sites",
	"Change markets",
	"Create business opportunities",
	"We invent new technologies and innovative information products",
	"speed up time to market",
	"And reinvent if necessary",
	);
	map($$output=~s/$_/blah/i,@blah);

}; # blah_blah

#-----------------------------------------------------------------------------
sub get_form_fields {
	# parse form for fields. Somewhat job-searcher specific
	my ($content)=@_;

	warn "get_form_fields\n" if $DEBUG;

	my $p=HTML::TokeParser->new($content);

	my %content;
	while (my $t=$p->get_tag("input")) {
		#print STDERR $t->[0], ": ", $t->[3], "\n";
		if (defined $t->[1]{type} && $t->[1]{type} eq "image" && (
				! defined $content{ComponentID} || 
					(defined $content{ComponentID} && $content{ComponentID}=~/^\s*$/) )
				&& defined $t->[1]{name} && $t->[1]{name}=~/^ComponentID/) {
			$t->[1]{name}=~/ComponentID\.([^.]+)\./;
			$content{ComponentID}=$1;
		}
		next if (defined $t->[1]{type} && $t->[1]{type} eq "image");

		warn("no name for ",$t->[3]),next if ! defined $t->[1]{name};
		warn("no value for ",$t->[1]{name}),next if ! defined $t->[1]{value};
		$content{$t->[1]{name}}=$t->[1]{value};
	}

	undef $p;

	return \%content;
}; # get_form_fields

#-----------------------------------------------------------------------------

sub new_agent {
	warn "new_agent\n" if $DEBUG;
	# start a new agent
	my $ua=LWP::UserAgent->new;
	$ua->agent($agent);
	$ua->cookie_jar(HTTP::Cookies->new( {} ));
	return $ua;
}; # new_agent

#-----------------------------------------------------------------------------

sub portal_login {
	# Log us into the portal. Optionally, login to a specific URL
	my ($ua, $request, $url)=@_;

	warn "portal_login\n" if $DEBUG;
	
	$url="http://athp.hp.com/portal/site/athp/template.LOGIN:?RememberMe=false" if ! defined $url;

	my $login_url="https://login.portal.hp.com/smlogin/" .
				"x509b/cert_url_redirect_ClassB.html?hp_url=";

	# https://login.portal.hp.com/smlogin/x509b/cert_url_redirect_ClassB.html?hp_url=http%3A%2F%2Fathp.hp.com%2Fportal%2Fsite%2Fathp%2Ftemplate.LOGIN%2F%3FRememberMe%3Dfalse

	$request->method("GET");
	$request->uri($login_url . $url);

	my $response=$ua->request($request);
	my $content=$response->content;

	warn("portal login response:\n" . $content) if $DEBUG > 1;

	# see if login worked
	# Output specific message if expired badge, else generic one
	if ($response->is_error) {
		my $expired="Your DigitalBadge is Missing or Expired";
		die $expired if $content=~/$expired/s;
		die $response->error_as_HTML() 
	}

	return $response;

}; # portal_login

#-----------------------------------------------------------------------------

sub jobsearcher_login {
	# log into job searcher. Must login to portal first.
	my ($ua, $request, $response)=@_;

	warn "jobsearcher_login\n" if $DEBUG;

	my $jobsearcher_url="http://hrcms01.atl.hp.com:6125/" .
			"employees/pages/jobsearcher/en_US/column_page_0005.htm";
	
	my $staffing_url="http://staffing.corp.hp.com/recruitsoft/" .
			"jobsearcher2.asp?Lang=en&Type=J&CsNo=1";

	my $taleo_url="https://hp.taleo.net/servlets/CareerSection";

	# Go to initial page
	$request->uri($jobsearcher_url);
	$response=$ua->request($request);
	die $response->error_as_HTML() if $response->is_error;

	warn("jobsearcher login response:\n" . $response->content) if $DEBUG > 1;

	# Set that page as a referer, and go to next page
	$request->referer($jobsearcher_url);
	$request->uri($staffing_url);
	$response=$ua->request($request);
	die $response->error_as_HTML() if $response->is_error;

	# Now go to taleo
	$request->uri($taleo_url);
	$request->method("POST");

		# This is the form fields needed
		#
		# POST https://hp.taleo.net/servlets/CareerSection

		#	csUserNo=2077942
		# not input
		#	&csNo=1
		#	&flowTypeNo=13
		#	&pageSeq=1
		#	&art_servlet_language=en
		#	&timeStamp=1179185791612
		#	&selected_language=en
		#	&RS_CHARSET_=UTF-8
		#	&HISTORY=
		#	&art_ip_action=PreApplyFlowController
		#	&SessionID=noneRequiredWhenCookiesAreEnabled
		# JServSessionIdhp" value="somevalues.withnumbersandletters"
		#	&JavascriptEnable=1
		# JavascriptEnable=0
		#	&ComponentID=preapply_pg_blk10308_jlcid_jlscid
		# ComponentID=
		#	&ToolbarActionToExecuteID=
		#	&toolbar_submitted=0
		# not input
		#	&preapply=1
		#	&current_flow=10324
		#	&current_page=1
		#	&callback=
		#	&preapply_pg_blk10308=1
		#	&show=search_comp
		# show=
		#	&jobListAction=show
		# jobListAction=
		#	&JobListBlock=10308
		#	&search_mode=advanced
		#	&search_comp=hiddenField
		#	&filter_comp=hiddenField
		#	&locationH=
		#	&location_HISTORYNOTSEARCHED=
		#	&organizationH=
		#	&organization_HISTORYNOTSEARCHED=
		#	&categoryH=
		#	&category_HISTORYNOTSEARCHED=
		#	&previousTimeStamp=1179185517434
		#	&list_comp=showField
		#	&sortBy=1
		#	&OrderBy=1
		#	&pageNb=0
		#	&preapply_pg=1

	# get the search page
	my $content=$response->content;
	warn("taleo login response:\n" . $content) if $DEBUG > 1;
	my $csUserNo=$1 if $content=~/csUserNo=(\d+)/;
	die("Couldn't find csUserNo" .
		($DEBUG > 1 ? "\ncontent=\n$content" : "")
	) if ! defined $csUserNo;

	my $new_content=get_form_fields(\$content);

	# We have to add some extra fields to the form
	$new_content->{show}="search_comp";
	$new_content->{jobListAction}="show";
	$new_content->{JavascriptEnable}="1";

	$request->content_type('application/x-www-form-urlencoded');
	$request->content("csUserNo=$csUserNo&" . join("&",map("$_=$new_content->{$_}",keys %$new_content)));

	$response=$ua->request($request);

	die $response->error_as_HTML() if $response->is_error;

	warn("search page response:\n" . $response->content) if $DEBUG > 1;
	return $response;

}; # jobsearcher_login

#-----------------------------------------------------------------------------
sub jobsearcher_search {
	# Do the actual search. Must login first
	my ($ua, $request, $response, $keyword)=@_;

	warn "jobsearcher_search\n" if $DEBUG;

	# Prepare to search
	my $content=$response->content;
	my $new_content=get_form_fields(\$content);

	# https://hp.taleo.net/servlets/CareerSection#jlanc
	#	csUserNo=2077942
	#	&csNo=1
	#	&flowTypeNo=13
	#	&pageSeq=1
	#	&art_servlet_language=en
	#	&timeStamp=1179182300415
	#	&selected_language=en
	#	&RS_CHARSET_=UTF-8
	#	&HISTORY=
	#	&art_ip_action=PreApplyFlowController
	#	&SessionID=noneRequiredWhenCookiesAreEnabled
	#	&JavascriptEnable=1
	# JavascriptEnable=0
	#	&ComponentID=preapply_pg_blk10308_jlcid_jlscid
	# ComponentID=
	#	&ToolbarActionToExecuteID=
	#	&toolbar_submitted=0
	# not found
	#	&preapply=1
	#	&current_flow=10324
	#	&current_page=1
	#	&callback=
	#	&preapply_pg_blk10308=1
	#	&show=
	#	&jobListAction=apply
	# jobListAction=
	#	&JobListBlock=10308
	#	&search_mode=advanced
	#	&search_comp=showField
	#	&filter_comp=hiddenField
	#	&locationH=
	#	&location_HISTORYNOTSEARCHED=
	#	&organizationH=
	#	&organization_HISTORYNOTSEARCHED=
	#	&categoryH=
	#	&category_HISTORYNOTSEARCHED=
	#	&keyword=137322
	# keyword=
	#	&keywordH=
	#	&jtH=
	#	&jt=-1
	# not found
	#	&scheduleH=
	#	&schedule=-1
	# not found
	#	&shH=
	#	&sh=-1
	# not found
	#	&tH=
	#	&t=-1
	# not found
	#	&10122H=
	#	&10122=-1
	# not found
	#	&10012H=
	#	&10012=-1
	# not found
	#	&10010H=
	#	&10010=
	#	&previousTimeStamp=1179182185902
	#	&list_comp=showField
	#	&sortBy=1
	#	&OrderBy=1
	#	&pageNb=0
	#	&preapply_pg=1

	# This is where the search parameters are set
	# For now, just keyword is allowed
	foreach (qw(jt schedule sh t 10122 10012 10010)) {
		$new_content->{$_}="-1" if ! defined $new_content->{$_};
	}
	$new_content->{keyword}=$keyword;
	
	$new_content->{jobListAction}="apply";
	$new_content->{JavascriptEnable}="0";

	$request->content_type('application/x-www-form-urlencoded');
	$request->content(join("&",map("$_=$new_content->{$_}",keys %$new_content)));
	$request->uri("https://hp.taleo.net/servlets/CareerSection#jlanc");

	# make search request
	$response=$ua->request($request);
	die $response->error_as_HTML() if $response->is_error;
		
	warn("search results response:\n" . $content) if $DEBUG > 1;

	# These are for debugging
	#print STDERR "request: ", $response->request->as_string;
	#print STDERR "message: ", $response->message;
	#print STDERR "content: ", $response->content;
	#print STDERR "as string: ", $response->as_string;

	return $response;

}; # jobsearcher_search

#-----------------------------------------------------------------------------
sub find_job_urls {
	# Once we have the search result, pull the URL(s) out of it
	my ($ua, $request, $response)=@_;

	warn "find_job_urls\n" if $DEBUG;

	# https://hp.taleo.net/servlets/CareerSection?art_ip_action=FlowDispatcher&flowTypeNo=13&pageSeq=2&reqNo=958213&art_servlet_language=en&selected_language=en&csNo=1#topOfCsPage
	
	my @urls;

	my $content=$response->content;
	my $p=HTML::TokeParser->new(\$content);
	while (my $t=$p->get_tag("td")) {
		if (defined $t->[1]{headers} && $t->[1]{headers} eq "jobTitleCol") {
			$t=$p->get_tag("a");
			push @urls,$t->[1]{href};
		}
	}
	# If we don't find URL, didn't find a job
	die("no job URLs found") if ! scalar @urls;

	return @urls;
}; # find_job_urls

#-----------------------------------------------------------------------------

sub get_job {
	# For a job URL, get the actual job content
	my ($ua, $url)=@_;

	warn "get_job\n" if $DEBUG;

	my $request=HTTP::Request->new(GET=>$url);
	my $response=$ua->request($request);
	die $response->error_as_HTML() if $response->is_error;
	return $response->content;

}; # get_job

#-----------------------------------------------------------------------------

sub get_job_html {
	# For a job URL, return the html. The javascript modification
	# allows more than one job to be displayed, and turns off the
	# session timeout, so--if you're displaying a bunch of jobs--you don't
	# get a timeout popup for every single one!
	my ($ua, $url)=@_;

	warn "get_job_html\n" if $DEBUG;

	my $content=get_job($ua, $url);

	# turn of javascript that sets timeout, only allows one req at a time
	$content=~s/cs_cnt\s*=\s*cs_cnt\s*\+\s*1;/cs_cnt = 1;/gs;
	$content=~s/resetSessionTimeout\(\);//gs;
	return $content;

}; # get_job_html

#-----------------------------------------------------------------------------

sub get_job_summary {
	# for a job URL, return a summary of the job. Strip out all the html and
	# try to make it look nice as ascii.
	my ($ua, $url, $big)=@_;

	warn "get_job_summary\n" if $DEBUG;

	my @output;

	my $content=get_job($ua, $url);
	my $p=HTML::TokeParser->new(\$content);
	
	# Get job number
	$p->get_tag("h1");
	my $headline=$p->get_trimmed_text("/h1");
	$headline=~s/\xa0\x96\xa0/ /;
	push @output,$headline;

	# get to Description
	while (my $t=$p->get_token()) {
		last if ($t->[0] eq "C" && $t->[1]=~/DESCRIPTION.*QUALIFICATION PART/);
	}

	# Start looking at the html. If doing big summary, output text.
	# In any case, stop when get to PROFILE PART.
	my $text="";
	while (my $t=$p->get_token()) {
		last if ($t->[0] eq "C" && $t->[1]=~/PROFILE PART/);
		if (defined $big) {
			push(@output, $text),$text="",next if ($t->[0]=~/S|E/ && 
				$t->[1]=~/^(p|br|span|div|table|tr|th)$/);

			next if ($t->[0]=~/S|E/ && 
				$t->[1]=~/^(strong|b|u|i|sup|ol|ul|font)$/);

			$text.=$t->[1],next if $t->[0] eq "T";

			push(@output, $text),$text="- ",next if ($t->[0]=~/S|E/ && 
				$t->[1]=~/^(li|dir)$/);

			$text="\t",next if ($t->[0]=~/S|E/ && $t->[1]=~/^(td)$/);
		}
	}

	push @output,"-B+i+G-" if defined $big;

	# For either big summary or plain summary, always output the information
	# in PROFILE PART and later.
	my $subtitle;
	while (my $tag=$p->get_tag("span")) {
		if (defined $tag->[1]{class} && $tag->[1]{class} eq "label-box-title") {
			push @output,"-" . $p->get_trimmed_text("/span") . "-";
		}
		if (defined $tag->[1]{class} && $tag->[1]{class}=~/label-(box-)?subtitle/) {
			push @output, "$subtitle=unknown" if defined $subtitle;
			$subtitle=$p->get_trimmed_text("/span");
		}
		if (defined $tag->[1]{class} && $tag->[1]{class}=~/label-(box-)?text/) {
			my $text="Unknown";
			$text=$subtitle,undef $subtitle if defined $subtitle;
			push @output, $text . "=" . $p->get_trimmed_text("/span");
		}
	}

	# Now do some fixups on the data to make it look nice.
	my $output=join "\n",@output;
	my $dash="-" x 72;
	# Microsoft cruft
	$output=~s/&#8216;/'/g;
	$output=~s/&#8217;/'/g;
	$output=~s/&#8210;/-/g;
	$output=~s/&#8211;/-/g;
	$output=~s/&#8220;/"/g;
	$output=~s/&#8221;/"/g;
	$output=~s/&#8230;/.../g;

	$output=~s/\n\s*\n/\n/gs;
	$output=~s/&nbsp;/ /g;
	$output=~s/&amp;/\&/g;
	$output=~s/&shy;//g;
	$output=~s/-B\+i\+G-/$dash/;

	$output.="\n" . "=" x 72 . "\n";

	blah_blah(\$output);

	return $output;

}; # get_job_summary

#-----------------------------------------------------------------------------

# Pretty straight-forward:
# Get new agent.
# Login to portal.
# Login to jobsearcher.
# Do search.
# Convert search results to job URLs
# Process job URLs to either get summary or full data

my $ua=new_agent($agent);

my $request=HTTP::Request->new;

my $response=portal_login($ua, $request);

$response=jobsearcher_login($ua, $request, $response);

$response=jobsearcher_search($ua, $request, $response, $keyword);

my @urls=find_job_urls($ua, $request, $response);

foreach (@urls) {
	if (defined $summary || defined $bigsummary) {
		print get_job_summary($ua, $_, $bigsummary);
	} else {
		print get_job_html($ua, $_);
	}
}

# Copyright 2007 by Doug Claar
# vi:set tabstop=4 shiftwidth=4: # set the tabs to 4
