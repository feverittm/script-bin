#!/usr/bin/perl -w
#
#	$Header: $
#
#	"lic_watch.pl" created by red
#
#	$Log: $
#

use strict;
use English;
use Tk;
use Tk::Xrm;
use Tk::DialogBox;
use Tk::ProgressBar;
use subs qw(handler show_usage update get_lic_info cleanup_and_die);
use POSIX qw(strftime);
use Getopt::Std;

use vars qw($opt_w $opt_v $opt_u $opt_x);

#-------------------------------------------------------------------
# General Variables and runtime information.
#-------------------------------------------------------------------

use vars qw($update $header_string $Rev $RunDate $DirName $ProgName);
use vars qw(@fields $job $status $queue $cmdline $label_string);
use vars qw($QueueEmpty %Current %Queue @linfo $machine @title);
use vars qw(@TrackList @ToolList @VendorList %Server %Feature);

my @labellist;
my @bars;

%Server = (
   'mentor'     => {
       lmstring => '1717@hpcvimd3',
   },
   'synopsys'   => {
       lmstring => '27000@hpcvimd4',
   },
   'ise'        => {
       lmstring => '27000@dbprd-m.cv.hp.com',
   },
);

my $FONT = '-*-Helvetica-Medium-R-Normal--*-140-*-*-*-*-*-*';

#Widgets
use vars qw($main $top $ltop $licinfo $header $w_update $w_quit $listbox);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$SIG{'HUP'} =   \&handler;
$SIG{'INT'} =   \&handler;
$SIG{'QUIT'} =  \&handler;
$SIG{'TERM'} =  \&handler;

#--------------------------------------------------------------
# General utility subroutines
#--------------------------------------------------------------
sub handler
{
    my($sig) = @_;
    warn "$ProgName:INFO: Caught a SIG$sig -- shutting down\n";

    exit(0);
}

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n\n";
   print "$ProgName [-xfn] [-u #] app1[[,app2]...]\n";
   print "   Options:\n";
   print "   -u <update>  :  Update time in seconds (default is 1 sec).\n";
   print "   -x           :  Verbose degug information.\n";
   print "\n";
   print "  Put up a small xwindow log to show the status of running\n";
   print "  licensed jobs.\n";
   print "  Hotkeys for lic_watch window:\n";
   print "     Control-C  :  Exits the program.\n";
   print "     Control-Q  :  Exits the program.\n";
   print "     Control-U  :  Run a lmstat and update immediately.\n";
   print "\n";
   exit 0;
}


sub cleanup_and_die {
    my $msg=$_[0];
    close(INFO);
    die "$msg";
}

#----------------------------------------------------------------------------------
# Main subroutine to run the 'lmstat' command and gather the information about the
#   running jobs.
#----------------------------------------------------------------------------------
sub get_lic_info {
   my ($rest, $index, $save);
   undef @linfo;
   my $server;
   open(INFO,"lmutil lmstat -a -c $server |") 
      || cleanup_and_die "Cannot open pipe to lmstat\n";
   $index=0;
   $save="";
   while(<INFO>){
      chop;
      /^\s*$/ && do { undef @linfo; close(INFO); return; };
      s/\s+/ /g;
      s/(.*)\s+'(.*)'/$1/ && do {
	  $save=$2;
	  s/\'//g;
	  s/\s/:/g;
      };
      $opt_x && print "Tinfo $.: $_\n";
      $linfo[$index]=$_;
      $title[$index]=$save;
      $index++;
  }
   close(INFO);
}

sub update {

    my($index);

    #$opt_x && print "Update...\n";
    $index=0;
    my %Slist;
    for my $appl (@TrackList){
       my $server=$Feature{$appl}->{lmstring};
       if (exists($Slist{$server})){ next; }
       $Slist{$server}=$server;
    }
    
    for my $server (keys %Slist){
       print "getting lmstat info for server $server\n";
       open (LM, "lmutil lmstat -a -c $server |" ) ||
          die "Cannot open pipe for lmstat onto $server\n";
       while(<LM>){
          chomp;
          /Users of (\S+):\s+\(Total of (\d+) licenses? issued;\s+Total of (\d+) licenses? in use\)/ && do {
             my $feature = $1;
             my $num_lic = $2;
             my $in_use  = $3;


             unless (exists($Feature{$feature})){
                die "Missing Feature in hash\n";
             }

            $Feature{$feature}->{in_use}=$in_use;

            #print "license feature $feature for server $server, $in_use licenses in use out of $num_lic\n";
            next;
         };
       }
       close LM;
    }

    for (my $idx=0; $idx<=$#TrackList; ++$idx){
      my $feature = $TrackList[$idx];
      my $val=int(100*($Feature{$feature}->{in_use}/$Feature{$feature}->{num_lic}));
      print "feature=$feature, $Feature{$feature}->{in_use} out of $Feature{$feature}->{num_lic}, $val\n";
      $bars[$idx]->value( $val );
    }

    $top->after($update, \&update);
} 

sub load_cache
{
   my $dbfile=shift;
   $opt_v && print "Load license cache... $dbfile\n";
   open (CACHE, "<$dbfile") ||
      die "Cannot open cach'd db file on disc: $dbfile\n";
   my $ret="";
   my $buf;
   while(read(CACHE, $buf, 16384)){
      $ret .= $buf;
   }
   close(CACHE);
   eval $ret;
                                                                                                         
   if (!defined($ToolList[0])){
      die "Bad database load\n";
   }

   for my $key (%Feature){
      $Feature{$key}->{in_use}=0;
   }
}

#----------------------------------------------------------------------------------
#
#  Main program
#

#
# parse options...
#
if (&Getopt::Std::getopts('vwxu:') == 0) {
    &show_usage;
}

if ($#ARGV < 0){
   die "You need to specify at least one license feature to track\n";
}

#print "# $ProgName  $Rev\t\t$RunDate\n\n";

unless($opt_u){
   $update=1000;
} else {
   if ( $opt_u !~ /\d+/ ){
      die "Invalid number specified for the update time: $opt_u\n";
      }
   $update=int($opt_u*1000);
   if ( $update == 0 ) { 
      print "Bad update time conversion\n";
   }
   elsif ($update < 100) {
      print "Setting update time to minimum of 0.1 seconds\n";
      $update=100;
      }
   else {
      print "Update time set at ",($update/1000)," seconds\n";
      }
}

my $dbfile="/var/www/html/tools/tool_cache_db";
load_cache($dbfile);

print "Remainder of command line (assumed to be list of apps to track):\n";
print join(", ",@ARGV) . "\n";

#
#  Need to validate the app names with the Feature hash.  Then can create a simple
#  list of features to track.
#
for my $name (@ARGV){
   print "Checking feature ... $name\n";
   for my $key (sort keys %Feature){
      #print "key: $key, match=$name\n";
      if ($key =~ /$name/){
         print "tracking feature $key from $Feature{$key}->{lmstring}\n";
         push @TrackList, $key;
      }
   }
}

my @colors = (  0, '#ff002a',  1, '#ff0014',  2, '#ff000a',  3, '#ff0500',  4, '#ff1000',
       5, '#ff1b00',  6, '#ff3000',  7, '#ff3b00',  8, '#ff4600',  9, '#ff5100',
      10, '#ff6100', 11, '#ff7600', 12, '#ff8100', 13, '#ff8c00', 14, '#ff9700',
      15, '#ffa100', 16, '#ffbc00', 17, '#ffc700', 18, '#ffd200', 19, '#ffdd00',
      20, '#ffe700', 21, '#fffd00', 22, '#f0ff00', 23, '#e5ff00', 24, '#dbff00',
      25, '#d0ff00', 26, '#baff00', 27, '#afff00', 28, '#9fff00', 29, '#95ff00',
      30, '#8aff00', 31, '#74ff00', 32, '#6aff00', 33, '#5fff00', 34, '#54ff00',
      35, '#44ff00', 36, '#2eff00', 37, '#24ff00', 38, '#19ff00', 39, '#0eff00',
      40, '#03ff00', 41, '#00ff17', 42, '#00ff21', 43, '#00ff2c', 44, '#00ff37',
      45, '#00ff42', 46, '#00ff57', 47, '#00ff67', 48, '#00ff72', 49, '#00ff7d',
      50, '#00ff87', 51, '#00ff9d', 52, '#00ffa8', 53, '#00ffb8', 54, '#00ffc3',
      55, '#00ffcd', 56, '#00ffe3', 57, '#00ffee', 58, '#00fff8', 59, '#00faff',
      60, '#00eaff', 61, '#00d4ff', 62, '#00c9ff', 63, '#00bfff', 64, '#00b4ff',
      65, '#00a9ff', 66, '#008eff', 67, '#0083ff', 68, '#0079ff', 69, '#006eff',
      70, '#0063ff', 71, '#004eff', 72, '#003eff', 73, '#0033ff', 74, '#0028ff',
      75, '#001dff', 76, '#0008ff', 77, '#0200ff', 78, '#1200ff', 79, '#1d00ff',
      80, '#2800ff', 81, '#3d00ff', 82, '#4800ff', 83, '#5300ff', 84, '#5d00ff',
      85, '#6e00ff', 86, '#8300ff', 87, '#8e00ff', 88, '#9900ff', 89, '#a300ff',
      90, '#ae00ff', 91, '#c900ff', 92, '#d400ff', 93, '#df00ff', 94, '#e900ff',
      95, '#f400ff', 96, '#ff00f3', 97, '#ff00e3', 98, '#ff00d9', 99, '#ff00ce' );

# get first update...

unless(defined($opt_w)){
   # 
   # Define the window layout and instanciate the widgets
   #
   $top = MainWindow->new;
   $top->bind('<Control-c>' => \&exit);
   $top->bind('<Control-q>' => \&exit);
   $top->bind('<Control-u>' => \&update);
   $top->title('Application License Information');
   $top->iconname('lic_watch');

   # Define the header
   #$header_string  = sprintf("%-12s %-15s %-15s", "Name", "Total", "Available");
   #$header = $top->Label(   -textvariable  => \$header_string,
   #                         -relief        => 'groove')
   #       ->pack(           -side          => 'top',  
   #                         -fill          => 'y');

   for (my $idx=0; $idx<=$#TrackList; ++$idx){
      my $feature = $TrackList[$idx];
      $labellist[$idx] = $top->Label(   -textvariable  => \$feature)
             ->pack(           -side => 'top',
                               -fill => 'y');
      $bars[$idx] = $top->ProgressBar( -padx=>2, -pady=>2, -borderwidth=>2,
             -troughcolor=>'#BFEFFF', -colors=>[ 0, '#104E8B' ],
             -length=>100)->pack;

      my $val=int(100*($Feature{$feature}->{in_use}/$Feature{$feature}->{num_lic}));
      print "feature=$feature, $Feature{$feature}->{in_use} out of $Feature{$feature}->{num_lic}, $val\n";
      $bars[$idx]->value( $val );
   }

   $w_update = $top->Button(-text       => 'Update',
                            -command    => \&update)
          ->pack(           -side       => 'left',
                            -fill       => 'y',
                            -expand     => 'y');
   $w_quit   = $top->Button(-text       => 'Quit',
                            -command    => sub { exit(0); })
          ->pack(           -side       => 'right',
                            -fill       => 'y',
                            -expand     => 'y');
   &update;

   MainLoop;
}
