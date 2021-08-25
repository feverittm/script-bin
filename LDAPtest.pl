#!/usr/bin/perl -w

use strict;
use Carp;
use Net::LDAP;

use vars qw($ldap $SearchString @Attrs $base);

sub dumpargs {
   my ($cmd,$s,$rh) = @_;
   my @t;
   push @t, "'$s'" if $s;
   map {
      my $value = $$rh{$_};
      if (ref($value) eq 'ARRAY') {
         push @t, "$_ => [" . join(", ", @$value) . "]";
      } else {
         push @t, "$_ => '$value'";
      }
   } keys(%$rh);
   print "$cmd(", join(", ", @t), ")\n";
}

sub dump_entry {
   my $entry = shift;
   print "Dump:\n";
   print "Entry = " . ref($entry) . "\n";
   my $mailref = $entry->get_value("mail", asref => 1);
   print "Mail: " . join (" ", @$mailref) . " \n";

   print "Entry = " . ref($entry) . "\n";
   my @entry_attr=$entry->attributes();
   print "Attributes:\n";
   for my $entry_attr (sort @entry_attr){
      my $ref = $entry->get_value($entry_attr,  asref => 1);
      if (defined($ref)){
         if ($entry_attr =~ /Certificate/){ 
            printf "   %-35s: %-10s\n", $entry_attr, " .. binary";
	    }
         elsif ($entry_attr =~ /binary/){ 
            printf "   %-35s: %40s\n", $entry_attr, "Binary";
	    }
         elsif ($#{@$ref} == 0){
            printf "   %-35s: %40s\n", $entry_attr, @$ref;
         } else {
            printf "   %-35s: %40s\n", $entry_attr, "";
	    for my $value (sort @{$ref}){
               printf "   %-35s: %40s\n", " ", $value;
	    }
	 }
      }
   }
}

$ldap = Net::LDAP->new("ldap.hp.com") or die "$@";
#$ldap = Net::LDAP->new("isrvlx0.cv.hp.com") or die "$@";

if (!$base ) { 
   #$base = "dc=cv,dc=hp,dc=com"; 
   $base = "ou=People,o=hp.com"; 
   print "Base set to '$base'\n";
}
   
# if they don't pass an array of attributes...
# set up something for them

@Attrs = ["cn", "sn", "mail"]; 

my %searchargs;

$searchargs{base} = $base;
$searchargs{scope} = "sub";
$searchargs{filter} = "cn=floyd* moore";
#$searchargs{filter} = "uid=moore*";
$searchargs{attrs} = [];

dumpargs("search", undef, \%searchargs);

my $result = $ldap->search (%searchargs);

$result->code && die $result->error;

print "result = " . ref($result) . "\n";

my @entries = $result->entries;
my $entry = $entries[0];

print "DN: " . $entry->dn . "\n";

dump_entry($entry);
