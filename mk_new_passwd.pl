#!/usr/local/bin/perl5
$List="/nfsusers/janitor/lib/esl_people/People";
#<other>bethhall,Beth Hallmark,80307,6UE13,VOLT
#<other>wbb,Bill Betters,89224,6UL5,ETW
#<jkw>rwn,Bob Noller,84582,6UL10,Competitive
#<it>haag,Brett Haag,87995,MOD5,IT
#<other>bbode,Brian Bode,86362,MOD2,NCS
#<jkw>chriscab,Chris Cabral,80832,6UL11,FOM
#<other>cks,Corey Stone,,,
#<other>dpc,Dave Cleaver,,,NCS
#<rwn>debmac,Debbi MacLeod,80037,6UJ10,SPM
#<cxc>dewayneg,DeWayne Gonzales,80604,6UL10,Finance

sub expand_list 
{
}

# cache the passwd file to get the password field
open (PASSWD,"ypcat passwd |") || die "Cannot ypcat passwd information\n";
while (<PASSWD>){
   my $dummy, $rest;
   chomp;
   ($userid,$passwd,$dummy,$dummy,$geckos,$rest) = split(/:/,$_,6);
   $passwd =~ /\*/ && do { next; };
   $geckos =~ s/^\s*//;
   $geckos =~ s/\s*$//;
   $geckos =~ /INTEL/ && do { next; };
   $Pass{$userid}="$passwd";
   #print "   Password: User=$userid, Pass=$passwd\n";
}
close PASSWD;

# preread the people list from autoplan...
open(ERR,">list.errs") || die "Cannot open error output list\n";
open(LIST,"<$List") || die "Cannot open Peiple list:  $List\n";
while (<LIST>){
   chomp;
   if ($_ !~ /^</ ) {next;}
   #print "Load from List: '$_'\n";
   s/<([^>]+)>// && do { $mgr=$1; };
   if ($mgr eq "other" ) { next; };
   s/\,\,/,/g;
   s/\,$//;
   ($userid,$name,$phone,$locate,$type,$rest)=split(/,/,$_,6);
   if ($userid eq "asset") { next;}
   if (length($type) == 0){ 
      print ERR "ERROR: $name has invalid Null Type\n"; 
      next; 
   }
   $type =~s/\s+/_/g;
   if ($type eq "Competitive") { next; }
   if ($type eq "Doc_Czar") { next; }
   if ($type eq "AA") { next; }
   if ($type eq "IT") { next; }
   if ($type eq "FOM") { next; }
   if ($type eq "SPM") { next; }
   if ($type eq "Finance") { next; }
   if ($type eq "INTEL") { next; }
   if ($type eq "ETW") { next; }
   if ($type eq "BPA") { next; }
   if ($type eq "SEED") { next; }
   if ($type eq "STEP_2") { next; }
   if ($type eq "VOLT") { next; }
   if ($type eq "WEEP") { next; }
   if ($type =~ /Admin/) { next; }
   if ($type eq "Human_Resources") { next; }
   if (!defined($Pass{$userid})){
      print ERR "ERROR: User $userid does not have a password entry\n";
      $badusers=1;
   }
   $Users{$userid}="$name:$mgr:$phone";
   print "User=$userid, Type=$type, $Users{$userid}\n";
   if (defined($Hier{$mgr})) { 
      $Hier{$mgr} .= ":$userid";
   } else {
      $Hier{$mgr} = "$userid";
   }
}

print "----------------------\n";
print "Users:\n";
foreach $key (sort keys %Users){
   print "User $key=$Users{$key}\n";
}

print "----------------------\n";
print "Management Hierarchy:\n";
foreach $key (sort keys %Hier){
   print "Hier $key=$Hier{$key}\n";
}

exit

# get a new of the people in the lab from the peoplw pages
#  this is a list of Proper Names and not user_ids
open (PLIST,">fml_org.txt") || die "Cannot open fml organization list\n";
open (PEOPLE,"/softtools/bin700/lynx -dump http://eslweb.fc.hp.com/cgi-bin/core/people/People.cgi?Org_Chart |") || die "Cannot launch lynx to grab people pages infomation\n";
undef $match;
$input="";
while (<PEOPLE>){
   chomp;
   /\s*\+\s/ && do { undef $match;};
   /\s*\+\sDonovan Nickel, Lab Mgr/ && do { $match=1;};
   if (!defined($match)){next;}
   print PLIST "$_\n";
   s/^\s*//;
   s/\s+$//;
   s/^..//;
   s/\s*,.*$//;
   $name=$_;
   $lookup = $name;
   $lookup =~ s/\s+/_/g;
   if (defined($Pass{$lookup})){
      print "Found: $name - '$Pass{$lookup}'\n";
      ($userid,$passwd,$dummy,$dummy,$geckos,$rest) = split(/:/,$Pass{$lookup},6);
   } elsif (defined($remaps{$lookup})){
      print "Remap: $name - '$remaps{$lookup}'\n";
      ($userid,$passwd,$dummy,$dummy,$geckos,$rest) = split(/:/,$remaps{$lookup},6);
   } else {
      print "Not Found Name: $name - '$lookup'\n";
      next;
   }
  
   if (!defined($USER{$userid})){
      $passwd=~s/,.*$//;
      $USER{$userid}=$userid . ":" . $passwd . ":" . $name;
      $input .= "$userid, ";
   } else {
      print "Redefined user $userid: $name\n";
   }
}

close PLIST;
close PEOPLE;

open(GROUP,">group.new") || die "Cannot open new group file";
$group=$input;
$group=~ s/,//g;
print GROUP "fmllab: $group\n\n";

$non_fml=0;
$nofml="";
open (NONFML,">non_fml.new") || die "Cannot open non_fml list\n";
open (LIST,"</users/cuda_abe/PhoneNumbers") || die "Cannot open PhoneNumber list\n";
while(<LIST>) {
   chop;
   s/^\s*//;
   s/\s*$//;
   s/\s+/ /g;
   ($user, $email, $name)=split(" ",$_,3);
   if (!defined($USER{$user})) {
      print NONFML "Add non-fml user $non_fml:$user:$email:$name\n";
      ++$non_fml;
      # default p2 user passwd is "cuda_p2"
      $USER{$user}=$user . ":Vyr9Avm3hOBT6:$name";
      $nofml = $nofml . " " . $user;
   }
}

close(NONFML);

$nofml =~ s/^\s*//;
print GROUP "nonfml: $nofml\n";
print GROUP "abeaccess: fmllab nonfml";

open (PASSWD,">passwd.new") || die "Cannot write to new passwd file\n";
foreach $user (sort keys %USER)
{
   print PASSWD "$USER{$user}\n";
}


close (GROUP);
close (PASSWD);
