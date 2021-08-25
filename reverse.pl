#!/usr/local/bin/perl5 -w
#
#	$Header$
#
#	"/home/red/bin/reverse.pl" created by red
#
#	$Log$

use strict;
use subs qw(handler);
use POSIX qw(strftime);

my($entry, $index, @stack);

my ($Rev, $RunDate, $DirName, $ProgName);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

$SIG{'HUP'} =   \&handler;
$SIG{'INT'} =   \&handler;
$SIG{'QUIT'} =  \&handler;
$SIG{'TERM'} =  \&handler;

sub handler
{
    my($sig) = @_;
    warn "$ProgName:INFO: Caught a SIG$sig -- shutting down\n";

#   close OUT;
#   `rm -f $tmpfile`;

    exit(0);
}

#print "# $ProgName  $Rev\t\t$RunDate\n\n";

@stack=();
while (<>) {
   chop;
   push @stack, $_;
}

for ($index = $#stack; $index>=0; --$index){
   print "$stack[$index]\n";
   }

__END__
