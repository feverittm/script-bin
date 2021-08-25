#!/usr/bin/env perl5
#
#   Author:  Floyd Moore (floyd.moore\@hp.com)
#	$HeadURL: file:///var/lib/svn/repository/projects/metrics/trunk/hold_query.pl $
#       $Revision: 17 $
#       $Date: 2011-03-10 11:52:12 -0800 (Thu, 10 Mar 2011) $
#	Description:
#
use strict;
use warnings;

use Net::Twitter::Lite;
use File::Spec;
use Storable;
use Data::Dumper;

my $high_water;
my %consumer_tokens = (
    consumer_key    => 'mGOrYP3OZlkxCioaypJAA',
    consumer_secret => 'CMUVZqubhRtphCKhKKpe7xgOIdu6dWfD7pnlXzcrSiA',
);

my $datafile = 'twitter.dat';
# my (undef, undef, $datafile) = File::Spec->splitpath($0);
# $datafile =~ s/\..*/.dat/;

my $nt = Net::Twitter::Lite->new(%consumer_tokens);
my $access_tokens = eval { retrieve($datafile) } || [];

if ( @$access_tokens ) {
   $nt->access_token($access_tokens->[0]);
   $nt->access_token_secret($access_tokens->[1]);
   #$high_water = $access_tokens->[2];
} 
else {
   my $auth_url = $nt->get_authorization_url;
   print " Authorize this application at: $auth_url\nThen, enter the PIN# provided to continue: ";
   
   my $pin = <STDIN>; # wait for input
   chomp $pin;

   # request_access_token stores the tokens in $nt AND returns them
   my @access_tokens = $nt->request_access_token(verifier => $pin);

   # safe the access tokens
   store \@access_tokens, $datafile;
}

my @user = $nt->lookup_users({ screen_name => 'FRCFMS' });
#print Dumper @user;

my $frcfms_id = $user[0][0]->{id};
print "FRC FMS User is $frcfms_id\n";;

#my $status = $nt->user_timeline({ count => 1 });

if (!$high_water) { $high_water=0; }
eval {
    my $statuses = $nt->user_timeline({ id => $frcfms_id, since_id => 48876247735992320, count => 10 });
    print Dumper $statuses;
    for my $status ( @$statuses ) {
        print "$status->{created_at} <$status->{user}{screen_name}> '$status->{text}'\n";
        my $status_id = $status->{id};
	if ( $status_id > $high_water ) { $high_water = $status_id; };
        print "item id = $status_id\n";

        my ($location, $type, $match, $red_score, $blue_score, @red_team, @blue_team, $red_bonus);
	my ($blue_bonus, $red_penalty, $blue_penalty);

        # Example tweet: #FRCNC TY Q MC 2 RF 46 BF 30 RE 3224 2119 547 BL 587 2420 342 RB 40 BB 30 RP 0 BP 0
	$status->{text} =~ /#FRC(\w+) TY (\w+) MC (\d+) RF (\d+) BF (\d+) RE (\d+) (\d+) (\d+) BL (\d+) (\d+) (\d+) RB (\d+) BB (\d+) RP (\d+) BP (\d+)/ && do {
	   $location = $1;
	   $type = $2;
	   $match = $3;
	   $red_score = $4;
	   $blue_score = $5;
	   push @red_team, $6;
	   push @red_team, $7;
	   push @red_team, $8;
	   push @blue_team, $9;
	   push @blue_team, $10;
	   push @blue_team, $11;
	   $red_bonus = $12;
	   $blue_bonus = $13;
	   $red_penalty = $14;
	   $blue_penalty = $15;

	};

	print "Match $match: Location = $location, Type=$type\n";
	print "   Red Teams @red_team, Blue Teams @blue_team\n";
	print "   Bonuses: $red_bonus, Blue $blue_bonus\n";
	print "   Penalties: Red $red_penalty, Blue $blue_penalty\n";
	print "   Scores: Red $red_score, Blue $blue_score\n";
    }
};
warn "$@\n" if $@;
#store \$high_water, $datafile;

# The Twitter feed was updated to accomodate the new score details.
#
# FRCABC - where ABC is the Event Code. Each event has a unique code. Note the hashtag was 
# omitted at the beginning of the FRC only because this wiki cannot display the hashtag. 
# This hashtag does exist in the real tweet.
#
# TY X - where x is P for Practice Q for qualification E for Elimination
# MC X - where X is the match number
# RF XXX - where XXX is the Red Final Score
# BF XXX - where XXX is the Blue Final Score
# RE XXXX YYYY ZZZZ - where XXXX is red team 1 number, YYYY is red team 2 number, 
#     ZZZZ is red team 3 number
# BL XXXX YYYY ZZZZ - where XXXX is blue team 1 number, YYYY is blue team 2 number, 
#     ZZZZ is blue team 3 number
# RB X - where X is the Bonus the scoring system gave to Red
# BB X - where X is the Bonus the scoring system gave to Blue
# RP X - where X are the Penalties the Referee gave to Red
# BP X - where X are the Penalties the Referee gave to Blue
# Example tweet: #FRCNC TY Q MC 2 RF 46 BF 30 RE 3224 2119 547 BL 587 2420 342 RB 40 BB 30 RP 0 BP 0



