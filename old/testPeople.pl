#!/usr/local/bin/perl5 -w
use strict;
use vars qw($opt_x $opt_v $opt_u);
use PeopleInfo;
use Getopt::Std;
my @users = (qw/red byoung algaut jehi/);

unless (&Getopt::Std::getopts('xvu:')) {
   die "Bad user option\n";
}

if (defined($opt_u)){
   undef @users;
   @users=split(/,/,$opt_u);
}

#
# Run the loader...
PeopleInfo::LoadPeople();

exit;

#
# Run some tests of the data structure...
#
for my $userid (@users){
   if (exists($People{$userid})){
      print "-------------------------\n";
      #print "Information about " . $People{$userid}->{'NAME'} . ":\n";
      for my $attr (qw/NAME PHONE LOCATION TYPE LAB/){
          if (exists($People{$userid}->{$attr})){
             print "   $attr = $People{$userid}->{$attr}\n";
          }
      }
      if(defined(@{$People{$userid}->{STAFF}}[0])){
         print "   Staff:\n";
         for my $empid (@{$People{$userid}->{STAFF}}) {
            print "   -> [$empid] $People{$empid}->{NAME}\n";
         }
      }
   } else {
   print "Unknown userid: $userid\n";
   }
}
