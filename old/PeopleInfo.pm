package PeopleInfo;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
use Carp;
use Net::LDAP;
use URI;
use Exporter;
#
#       Author:  Floyd Moore (floyd.moore@hp.com)
#	$Header: PeopleInfo.pm,v 1.2 2004/01/29 11:38:25 red Exp $
#
############################################################################
#	Description:
#         Perl module to read and create a data structure that contains
#         information about the people working within an organization.
#         Dec 4, 2001:  Updated to use LDAP information for the fields instead
#            if the Autoplan data which is out of date.
#         Jan 29, 2004: Updated to be more general than SVTD
#
#       Assumptions:
#         The organization structure assumes that all users are in some way 
#       associated with the "SVTO" organization (with the exception of John
#       Wheeler who is on Scott Stallard's staff.  If this changes then the
#       routines that create the virtual org chart will need to change.
#
############################################################################
#
#       This module make use of the perl-ldap module:
#       http://perl-ldap.sourceforge.net/
#
#       This module requires the following other modules:
#       Convert::ASN1   - required
#       URI::ldap       - required (for this application)
#
#       I will be creating a RPM for this data.
#
############################################################################
#
#
#	$Log:	PeopleInfo.pm,v $
#       Revision 1.2  2004/01/29  11:38:25  11:38:25  red (Floyd E Moore)
#       Checkpoint with move to Corvallis
# 
#	Revision 1.1  2000/03/29 22:47:05  red
#	Initial revision
#
#

# Set up module parameters:
$VERSION=1.2;
@ISA = qw(Exporter);

use vars qw (%LdapInfo %People %Pass);
@EXPORT = qw(%LdapInfo %People &LoadPeople);

#
#  Define the holy grail of machine data.  This type of information is
#  surprising hard to get at in an online form.  Any number of people 'know' 
#  the information, but it isn't stored electronically anywhere.
#  This information is needed for a variety of script/processes like automatic
#  generation of mailing lists and organizational charts,  web access control,
#  and NIS/NFS network access list generation.
#
#  Data Structure for storing the people records:
#
#  %People{}->{user}      = LDAP SEA of person (normal NT login name)
#  %People{}->{dn}        = LDAP DN attribute to tie back to ED data.
#  %People{}->{phone}     = Internal Phone number (ldap: telephoneNumber)
#  %People{}->{location}  = Physical Location
#  %People{}->{name}      = Name of person (as stated in LDAP, as 'cn')
#  %People{}->{uid}       = Unix User ID of person 
#  %People{}->{gid}       = Unix Group ID Number of user
#  %People{}->{mngr}      = Manager
#  %People{}->{email}     = Email Address
#  %People{}->{machine}   = Personal Workstation name
#  %People{}->@staff      = Span of authority (who works for this person.)
#
#  Ldap return records:
#  %LdapInfo{}->{key}       = Populated hash from LDAP return data
#
# -------------------------------------------------------------
# Algorithm for generation on the list:
# 1 - Start with me (Hah).
#
# 2 - Look up the employee in the ED using LDAP and identify all of
#     the required data.  Especially: manager, telephone number, user, and sea.  Also
#     do another search and expand a list of all direct reports for this employee.
#
# 3 - Recursively work up the tree to a given level (my default will be 2 levels -
#     Currently up to Lori Tulley) and fill in the structure.


# Local variables scoped to this module
use vars qw($file $file_loaded);
use vars qw($mngr $uid $gid $name $phone $location $type);
use vars qw($ldap $level);

sub LDAPsearch
{
  my ($searchString,$attrs) = @_ ;

  use vars qw(%searchargs $base);

  #set up base address
  $base = "o=hp.com";

  $searchargs{base}   = $base;
  $searchargs{scope}  = "sub";
  $searchargs{attrs}  = [];
  $searchargs{filter} = $searchString;

  my $result = $ldap->search (
     scope   => "sub",
     base    =>  $base,
     filter  => "$searchString",
     attrs   =>  $attrs
  );
}

sub StartLDAP {
   use vars qw($host @attrs);

   my $DEBUG = 1 if (defined($main::opt_x));
   #get configuration setup
   $host = "ldap.hp.com";

   $ldap =Net::LDAP->new($host) or die "$@";
   $base = "o=hp.com";

   #will bind as specific user if specified else will be binded anonymously
   $ldap->bind(); 

   #get the group DN
   my @attrs = ();
                            
   #my $result = LDAPsearch($base,"&(hporganizationchartacronym=SVTO)(hptelnetnumber=898*)",\@Attrs);
}

sub LoadPeople {
   if (defined($file_loaded)){ 
      print "File already loaded...\n";
      return;
   }

   my @BadUsers  = qw[];

   StartLDAP();

   # Get password file information from NIS...
   my $count=0;
   open (PASSWD,"ypcat passwd |") || die "Cannot ypcat passwd information\n";
   while (<PASSWD>){
      use vars qw($user $uid $gid $passwd $dummy $geckos $rest);
      use vars qw($result $rest $phonenum $location $emplnum);
      use vars qw($search_term $name $Surname $firstName);
      chomp;
      ($user,$passwd,$uid,$gid,$geckos,$rest) = split(/:/,$_,6);
      if ($passwd =~ /\*/) { next; };
      if ($user =~ /root/) { next; };
      if ($uid < 200)     { next; };
      if ((grep {/^$user$/} @BadUsers) > 0){
         print "  ... Skip '$user'\n";
         next;
      }
      $geckos =~ s/^\s*//;
      $geckos =~ s/\s*$//;
      $passwd=~s/,.*$//;
      $Pass{$user}="$passwd";
      {
         print "\n";
         print "$count: Password: User=$user, Pass=$passwd\n";
      }
      my @Attrs = ();

      ($name, $location, $emplnum, $phonenum) = split(/,/,$geckos,4);
      $name =~ s/\s+/ /g;
      $name =~ s/^\s*//;
      $name =~ s/\s*$//;
     
      # Need to get geckos name and call ldap_search to get LDAP record...

      my @fields = split(/ /,$name);
      print "Found " . $#fields . " name fields\n";
      $search_term = "(cn=$name)";
      #if ($#fields == 1 ){
      #   $search_term = "(&(sn=$fields[1]*)(|(givenname=$fields[0]*)(preferredgivenname=$fields[0]*)))";
      #} else {
      #   carp "Bad number of fields in the name: $name\n";
      #}
       
      print "Start search... $search_term\n";
      my $result = LDAPsearch($search_term,\@Attrs);
      print "...ldap returnned\n";

      my $href = $result->as_struct;
      my @arrayOfDNs  = keys %$href; 
      
      print "Found " . $#arrayOfDNs . " values from ldap\n";

      exit;

      if ($#arrayOfDNs == 0){
         print "LDAP match: $arrayOfDNs[0]\n";
         $user=$arrayOfDNs[0];
      } elsif ($#arrayOfDNs > 0){
         foreach (@arrayOfDNs){
            print "   --- match: $_\n";
         }
         die "Bad Match multiple names for $user, $name\n";
      }
      else {
         print "Failure to match user: $name in ldap\n";
         print STDERR "Failed to match user $name, $user in ldap\n";
         next;
      }
      
      my $valref = $$href{$user};
      my @arrayOfAttrs = sort keys %$valref; #use Attr hashes
      
      # truncate the user to be only the user id.
      $user=~s/.*user=(\S+),.*/$1/;
      $user=~s/\@hp.com//;

      print "Ldap info for Employee record of $user\n";
      for my $attrName (@arrayOfAttrs) {
         # skip any binary data: yuck!
         next if ( $attrName =~ /;binary$/ );

         # get the attribute value (pointer) using the
         # attribute name as the hash
         my $attrVal =  @$valref{$attrName} ;
         print "\t $attrName: @$attrVal \n";
         $LdapInfo{$user}->{$attrName}=@$attrVal;
      }

      ++$count;

      #($mngr,$user) = split(/,/,$user);

      my $mngr_ref=@$valref{manager};
      $mngr = @$mngr_ref[0];
      $mngr=~s/.*user=(\S+),.*/$1/;
      $mngr=~s/\@hp.com//;
      if (defined($LdapInfo{$mngr})){
         print "Manager Ldap info found\n";
      }
      print "Manager=$mngr\n";

      if (defined ($main::opt_x)){
         print "DEBUG: Loading $name as $user, $user\n";
      }

      # store the fields out
      unless ($mngr eq $user){
         $People{$user}->{MNGR}     = $mngr;
      }
      $People{$user}->{USERID}   = $user;
      $People{$user}->{LDAP}     = $user;
      $People{$user}->{NAME}     = $name;
      $People{$user}->{PHONE}    = $LdapInfo{$user}->{hptelnetnumber};

      unless ($mngr eq "other" || $mngr eq $user){
         push @{$People{$mngr}->{"STAFF"}}, $user;
      }
   }
   close PASSWD;
   $file_loaded=1;
   return;
}

undef $file_loaded;
undef %People;

1;
