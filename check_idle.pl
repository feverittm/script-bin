#!/usr/bin/perl -w
#
#       Author:  Floyd Moore (floyd.moore\@hp.com)
#	$Header:$
#	Description:
#
#	"<script_name>" created by red
#
#	$Log:$
#

use strict;
use IO::File;
use subs qw(handler show_usage parse_options get_dir file_mtime round);
use POSIX qw(strftime);
use vars qw($icp $opt_v $opt_x $opt_n $opt_V);
use vars qw($ProgName $RunDate $Rev $DirName $HostName $IdleTime);
use Getopt::Std;

my $HostName = `hostname`; chomp($HostName);
$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $DirName = $1; $DirName = '.' unless $DirName;
$ProgName = $0; $ProgName =~ s@.*/@@;

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-xVv]\n";
   print "   Options:\n";
   print "   -n <time>  Idle time in secs (default is 5 minutes)\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
   print "\n";
   exit 0;
}

# my options parser
sub parse_options
{
   if ( $#ARGV > 0 && $ARGV[0] =~ "-help"){
	&show_usage();
	exit(1);
   }

   unless (&Getopt::Std::getopts('Vvxn:')) {
	&show_usage();
	exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
}

sub user_idle {

    my $idle_time = shift;

    # Check each device.  If someone has touched the machine by typing
    # on keys or moving the mouse then it is interactive.  Do this by
    # looking at the access time of the raw device files in /dev.
    #
    # This catches almost all interactive input even if the user is in
    # a GUI program that does not type on the keyboard.  In that case
    # the mouse device will be new.  But frequently people bump the
    # mouse or strike a key when it is really not interactively being
    # driven.  Therefore low pass filter the information.  The devices
    # must be active continuously for more than a minute.
    #
    # This follows the spirit of the check since this is only an
    # auxiliary routine to supplement the tty informaton.  If someone
    # bumps the mouse once we keep thinking we are non-interactive.
    # But if the condition persists then something is happening.
    # Normally the tty information will govern.  But if needed this
    # device information will be a fall back.

    my $now = time();

    # Check for older HP-HIL devices (/dev/hil*) and PS2 devices (/dev/ps2*).
    if (!opendir(DIR,"/dev")) {
	warn "Error: could not get a directory listing for /dev\n";
	return 0;
    }
    my $dir = '';
    while (defined($dir = readdir(DIR))) {
	# hil devices are older HP interface loop keyboards
	# ps2 are ps2 devices
	# (?:RE) groups but does not make backreferences like (RE) does.
	if ($dir =~ m/^(?:hil|ps2)/) {
	    # (stat("file"))[8] returns atime of file.
	    if ((stat("/dev/$dir"))[8] > $now - $idle_time) {
		closedir(DIR);
                $opt_v && print " ... found hil or p2 device active: $dir\n";
		return 0;	# Input is new.
	    }
	}
    }
    closedir(DIR);

    # The /dev/hid directory is for USB devices.  It may not exist on
    # non-USB hosts.  That is okay.
    if (-d "/dev/hid") {

	if (!opendir(DIR,"/dev/hid")) {
	    warn "Error: could not get a directory listing for /dev/hid\n";
	    return 0;
	}
	my $dir = '';
	while (defined($dir = readdir(DIR))) {
	    # (?:RE) groups but does not make backreferences like (RE) does.
	    if ($dir =~ m/^(?:\.|\.\.)$/) {
		next;		# Skip "." and ".." dir entries.
	    }
	    # (stat("file"))[8] returns atime of file.
	    if ((stat("/dev/hid/$dir"))[8] > $now - $idle_time) {
		closedir(DIR);
                $opt_v && print " ... found hid device active: $dir [" . ($now - (stat("/dev/hid/$dir"))[8]) . "]\n";
		return 0;	# Input is new.
	    }
	}
	closedir(DIR);
    }

    return 1;			# No input for a while.
}

parse_options;
$opt_v && print "# $ProgName  $Rev\t\t$RunDate\n\n";

# Global Variables

$IdleTime=300;
$IdleTime=$opt_n if defined $opt_n;

my $ret=user_idle( $IdleTime );

if ($ret != 0){
   exit 1;
}

exit 0;
