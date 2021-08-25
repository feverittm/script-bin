#!/usr/bin/env perl
#
#   Author:  Floyd Moore (floyd.moore\@hp.com)
#   $HeadURL: $
#       Description:
#
#

package <name>;

use strict;
use warnings;
use 5.010;

# General Modules
use Carp qw( croak carp );
use English qw( -no_match_vars );
use File::Basename qw( basename );
use Pod::Usage qw( pod2usage );
use Readonly;
use Getopt::Long;
use File::Spec::Functions;
use POSIX qw(strftime);

# I seem to use this a million times when I am diagnosing the failures
# in my data structures and to make it easier to see what actual data
# the internal routines are seeing.  The indent thing is a personal
# preference
use Data::Dumper;
local $Data::Dumper::Indent = 1;

# setup runtime information
our $RUNDATE = strftime '%Y/%m/%d %H:%M:%S', localtime;
our $VERSION = 198;
Readonly my $PROGNAME => basename $PROGRAM_NAME;

#-----
# Global variables:
# I know defining these globals and not setting them here causes Perl::Critic
# to have fits, but I prefer (especially when I have strict mode on) to
# predefine my global varaibles early in my code.  It lets me see which
# variables *should* be global and try to minimize them.  Also it isn't
# easy to create an initializor for an empty hash like %config.
#-----
our ( $VERBOSE, $DEBUG );

# Parse the command line:
# I prefer to DRY out the command line stuff to the Getopt module instead
# of writing my own.  I also like the way I can write a nicely formatted
# specification for the command line variables.
#

sub parse_cmdline {
    Getopt::Long::Configure('bundling');
    my %options_list = (

        # Standard gnu like meta-options
        'help|?'  => sub { pod2usage(1); },
        'man'     => sub { pod2usage( -exitstatus => 0, -verbose => 2 ); },
        'version' => sub { command_version(); },
        'usage'     => sub { pod2usage( -verbose => 0 ); },
        'verbose|v' => \$VERBOSE,
        'debug|x'   => \$DEBUG,
    );

    my $options_okay = GetOptions(%options_list);

    # Fail if unknown arguemnts encountered...
    pod2usage(2) if !$options_okay;

    # tell people who we are...
    $VERBOSE && print "# $PROGNAME $VERSION\t\t$RUNDATE\n\n";

    return;
}

#
# print the program version and return.  Only called by the command line parser
#
sub command_version {

    # simply print the version number of the script
    print "$PROGNAME Revision $VERSION\n";
    exit 0;

}

#
# shorten an ascii message to a shorter length more suitable for printing in long
# column contents (like descriptions) directed to a screen instead of to a file.
sub shorten_message {
    my $msg    = shift;
    my $MAXLEN = shift;
    Readonly my $DEFAULT_MAXIMUM_LENGTH => 20;

    if ( !defined $msg ) {
        return 1;
    }

    if ( !defined $MAXLEN ) {
        $MAXLEN = $DEFAULT_MAXIMUM_LENGTH;
    }

    if ( ( my $idx = index $msg, "\n" ) > 0 ) {
        $msg = substr $msg, 0, $idx - 1;
    }
    if ( length($msg) > $MAXLEN ) {
        $msg = substr $msg, 0, $MAXLEN;
        $msg .= '...';
    }
    return $msg;
}

# main routine.  Since we are trying to keep the module like structure of the script (
# to help with testing using Test::More ) we have defined a wrapper for the main work.

#-----
# This conditional is a trick to aid in testing.  caller() returns false
# if this file is being run as a script - it is top level code, NOT called
# by anyone else.  caller() will return true if this file is being used
# as a module, as might be done for testing.  The easiest way to use it is
# with 'do file'.
#-----

if ( not caller ) {

    parse_cmdline();
    exit 0;
}

# make this look like a module... for testing.
1;

__END__

=pod

=head1 NAME

Script Name

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item B<--verbose>

Make the output quite chatty.  Print out messages to the user regarding
the status of any queries in process and the processing of the query
queue.

=item B<--debug>

Print out much more detailed messages from the database routines to help
diagnose failures in database and queue issues.  It actually sets the DBI
mode to maximum verbosity.

=item B<--version>

print the script version number and exit

=item B<--help>

print the full help message

=item B<--man>

Prints the full pod manual

=item B<--usage>

Prints the short usage message

=back

=head1 AUTHOR

Floyd Moore (floyd.moore\@hp.com)

=head1 EXIT STATUS

The script should exit normally with a zero status.

=head1 ISSUES

=head1 SEE ALSO

=head1 LICENSE AND COPYRIGHT

(c) Hewlett-Packard Development Company LLC 2015

=cut
 
