#!/usr/local/bin/perl  -w
use strict;
use POSIX qw(strftime);
use File::stat;
use vars qw($now $Hour $RunDate $suff $NewHour @mtime);

my $sem_file="/tmp/.cuckoo.sem";

@mtime=localtime();
$Hour = $mtime[2];

$Hour =~ s/^0//;

print "Current Hour is $Hour\n";

if (-f $sem_file){
   my $stime=stat($sem_file)->mtime;
   print "Last hour clock rang was: $stime\n";
   print "time is " . time . "\n";
   my $diff = time - $stime;
   print "Difference is $diff seconds\n";
   print "localtime is @mtime\n";
   if ($Hour > 9 && $Hour < 18 && $diff > 3600 ){
      $NewHour=$Hour;
      system ("touch $sem_file");
   } else {
      print "Not making sound for off work hours\n";
      undef $NewHour;
   }
} else {
   $NewHour=$Hour;
   system ("touch $sem_file");
}

exit;

if (defined $NewHour) {
        $suff = $Hour;
        $suff -= 12 if $Hour > 12;
        $suff = "0" . $suff if $suff < 10;
        my $file="/home/red/cprog/misterhouse-2.61/sounds/";
        $file .= "chimes/cuckoo" . $suff . ".wav";
        print "File is: $file\n";
        system("/opt/audio/bin/splayer -volume -5 $file");
}
