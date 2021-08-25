#!/usr/bin/perl -w

# the user_idle section from the lab.aff
# taskbroker script.

use 5.004;
use IO::File;
use Getopt::Long;

use strict;

# Global Variables

my $progname = $0; $progname =~ s@.*/@@;
my $hostname = `hostname`; chomp($hostname);
my $tmpdir = '/tmp';
my $logfile = '/tmp/aff-info.out';
my $verbose = 0;
my $debug = 0;

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
	    my $calc_idle_time = $now - (stat("/dev/hid/$dir"))[8];
            if ($calc_idle_time < $idle_time){
               print "Calculated idle time for $dir=$calc_idle_time\n";
            }
	    if ((stat("/dev/hid/$dir"))[8] > $now - $idle_time) {
		closedir(DIR);
		return 0;	# Input is new.
	    }
	}
	closedir(DIR);
    }

    my $file = IO::File->new();
    if (!$file->open("who -u|")) {
	die "Error: Could not execute who -u: $!\n";
    }
    while ($_ = $file->getline()) {
        print "Output line from who -u: $_\n";
	my $idle = (split(' ',$_))[5];
	if ($idle eq 'old') {
	    next;
	}
	if ($idle eq '.') {
	    return 0;
	}
	my ($hours,$minutes) = split(/:/,$idle);
	$minutes += $hours * 60;
	if ($minutes < $idle_time) {
	    return 0;
	}
    }
    undef $file;

    return 1;			# No input for a while.
}

my $idle_time = 15;
print "User Idle=" . &user_idle($idle_time) . "\n";

exit;
