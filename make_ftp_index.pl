#!/usr/local/bin/perl5
# Create an index to a directory for an ftp site.
#

require "getopt.pl";

&Getopt('');

# find target directory for ftp server.
if ( $#ARGV == -1 ) {
   if (defined($opt_h)){
      &usage;
      die "Bad Arguments.  Need a base directory for server in hier mode.\n";
      } else {
      &usage;
      die "Bad Arguments.  Need a target directory for the index file.\n";
      }
}

$target=@ARGV[0]; 

if (defined($opt_h)){
   #Build Hierarchy
   open(LIST,"find $target -type d -print |") || 
      die "Cannot generate hierarchy of server from find\n";
   while(<LIST>){
      chop;
      s/\s*//;
      push(Dirs,$_);
      }
   $dummy=join(":",@Dirs);
   print "List=$dummy\n";
} else {
   push(Dirs,$target);
}

print "Working through entire server...\n" if $opt_h;

foreach $target (@Dirs)
{
   print "Target: $target...\n" if ($opt_d);
   open(OUT ,">$target/.message") || 
      die "Cannot open new INDEX file in target: $target\n";

   # Print header information from .header file if it exists.
   $date=`date`;
   chop $date;
   open(HEAD,"<$target/.header") || 
      do {
	 print "Cannot open header for directory $target\n";
	 print OUT "######################\n";
	 print OUT "# Index of directory $target\n";
	 print OUT "# \n";
	 print OUT "# Last Modified: $date\n\n";
	 };

   while (<HEAD>){
      s/<date>/$date/;
      print OUT $_
      };
   close(HEAD);

   printf OUT ("%-15s %-8s %-50s\n","Name","Size","Description");
   printf OUT ("%-15s %-8s %-50s\n","---------------","--------","-----------------------------------------");
   printf OUT ("%-15s %-8s %-50s\n",".message","","This file");

   undef($Describe);
   open (DESC,"<$target/.describe") || print "Cannot find descriptions file\n";
   while(<DESC>){
        chop;
        /^#/ && do {next;};
        /^\s*$/ && do { next;};
        ($name,$desc)=split(":");
        $desc =~ s/^\s*//;
        $Describe{$name}=$desc;
        #print "DEBUG: Desciption for $name is '$desc'\n";
      }
   close(DESC);

   #total 282732
   #-rw-rw-r--   1 red      esl      3741577 Aug 31  1995 1rott13.zip
   #-rw-rw-r--   1 red      esl      3484202 Nov 20 19:27 2knetdem.zip
   #-rw-r--r--   1 red      esl      3954983 Jul 11  1995 3dtv12.zip

   open (LIST,"ll -1 $target |") || die "Cannot open 'ls -l' pipe to target\n";
   while (<LIST>){
      chop;
      s/\s+/ /g;
      /^total/ && do { next; };
      /README/ && do { next; };
      /INDEX/ && do { next; };
      /.header/ && do { next; };
      @fields=split(" ");
      $mode=@fields[0];
      $description="";
      if ($mode =~ /^l/){
         $name=@fields[$#fields-2];
         $size=@fields[4];
      } else {
         $name=@fields[$#fields];
         $size=@fields[4];
      }
      $description=$Describe{$name} unless (!defined($Describe{$name}));
      if ($mode =~ /^d/){
         printf OUT ("%-15s %-8s %-50s\n",$name,"..dir..",$description);
      } else {
         if (length($name) >= 15 ){
            printf OUT ("%-s\n",$name);
            printf OUT ("%-15s %-8d %-50s\n"," ",$size,$description);
         } else {
            printf OUT ("%-15s %-8d %-50s\n",$name,$size,$description);
         }
      }
      };
   close(LIST);
}
close(OUT);

if ($opt_h) {
   open(LS,"cd $target;ls -ltR .|") || die "Cannot open 'ls' pipe\n";
   open(OUT,">$target/tmp.ls") || die "Cannot open 'ls' output file\n";
   while(<LS>){
      chop;
      print OUT "$_\n";
      };
   close(OUT);
   close(LS);
   unlink("$target/ls-ltR.gz");
   rename("$target/tmp.ls","$target/ls-ltR");
   system("gzip","$target/ls-ltR");
   }


sub usage {
   print "make_ftp_index.pl ([-h <base_directory]|[<ftp_directory])\n";
   };
