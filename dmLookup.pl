#!/usr/bin/env perl5
#------------------------------------------------------------------------------
#
#      Copyright (c) 2009,2010 Hewlett-Packard Company, all rights reserved.
#
#------------------------------------------------------------------------------
#
# $Source: /sdg/doc/PerlEcosystem/Starters/RCS/SimpleScript,v $
# $Revision: 3 $
# $Date: 2010-11-15 12:25:39 -0800 (Mon, 15 Nov 2010) $
#

package dmLookup;
use lib '/home/red/bin';

use warnings;
use strict;
use 5.010;

use Carp::Fatal;
use Carp qw ( carp );
use Getopt::Long;
use English        qw( -no_match_vars );
use File::Basename qw( basename );
use Pod::Usage     qw( pod2usage );
use Readonly;
use DBI;

our($VERSION) = '$Revision: 3 $' =~ / ( \d+ (?: [.] \d+ )? )/x;

Readonly my $PROGNAME => basename $PROGRAM_NAME;

use MdaDB    qw( connect_to_db quitdb $verbose $quiet );
use vars qw ( $Rows $RequestLimit $RequestId $RequestLast $ProjLimit );

my @Query = (
        # 0
        {   sql =>
                "SELECT DISTINCT AL1.DESIGN_TASK_ID, AL2.PROJECT_NAME, AL3.PROJECT_REV_NAME FROM MDA.DESIGN_TASK AL1, MDA.PROJECT AL2, MDA.PROJECT_REV AL3 WHERE (AL1.PROJECT_ID = AL2.PROJECT_ID AND AL1.PROJECT_REV_ID = AL3.PROJECT_REV_ID) AND (AL1.DESIGN_TASK_ID>=38500 AND AL2.PROJECT_NAME LIKE 'FLN')",
            fields => [
               'DESIGN_TASK_ID',     'PROJECT_NAME', 'PROJECT_REV_NAME',
	       ],
	},
);

sub numeric { return $a <=> $b }

sub getmda {
    my $local_db_time = time;
    my $query  = $Query[0]->{sql};

    # add in the task filters if defined
    if ($RequestId) {
       $verbose && print " ... applying query for specific request of $RequestId\n";
       $query
           =~ s/AL1\.DESIGN_TASK_ID>=38500/AL1.DESIGN_TASK_ID=$RequestId/;
    } elsif ($RequestLimit) {
       $verbose && print " ... applying query request limit of $RequestLimit\n";
       $query
           =~ s/AL1\.DESIGN_TASK_ID>=38500/AL1.DESIGN_TASK_ID>=$RequestLimit/;
    }
    if ($ProjLimit) {
       $query
           =~ s/AL2\.PROJECT_NAME LIKE \'\w+\'/AL2.PROJECT_NAME LIKE \'$ProjLimit\'/;
    } else {
       $query
           =~ s/AND AL2\.PROJECT_NAME LIKE \'\w+\'//;
    }

    $verbose && print " ... Query is $query\n";

    my $dbh = connect_to_db();
    $Rows = $dbh->selectall_hashref( $query, 'DESIGN_TASK_ID', { Slice => {} } )
       or croak $DBI::errstr;

    my $end_db_time = time();
    my $db_time     = $end_db_time - $local_db_time;
    if ( $verbose) {
       print "    It took $db_time seconds for db operations\n";
    }

    if ($RequestLast){
	    my @ids = reverse sort numeric keys %{ $Rows };
	    my $last= $Rows->{$ids[0]};
	    undef $Rows;
	    $Rows->{$ids[0]} = $last;
    }
}

#----- caller() returns false if we're being run as a scriptart_db_time = time;
main()
    if not caller;

#------------------------------------------------------------------------------

sub main {

    parse_cmdline();

    getmda();

    if ( $verbose ) {
	    print Data::Dumper->Dump( [ \$Rows ], ['*Rows'] );
    } else {
        for my $id ( sort numeric keys %{ $Rows } ){
            for my $field ( @{ $Query[0]->{fields} } ) {
                print "$Rows->{$id}->{$field} ";
	    }
            print "\n";
        }
    }

    exit 0;
}

sub parse_cmdline {

    # Parse standard options from command line
    Getopt::Long::Configure("bundling");
    my $options_okay = GetOptions(
    
        # options
        "last"      => \$RequestLast,
        "limit=i"   => \$RequestLimit,
        "id=i"      => \$RequestId,
        "proj=s"    => \$ProjLimit,
        "verbose|v" => \$verbose,
        "quiet|q"   => \$quiet,
        "help|?"    => sub { argv_help(); },
        "version"   => sub { argv_version(); },
        "usage"     => sub { pod2usage( -exitstatus => 1, -verbose => 0 ); },
        "man" => sub { argv_man(); },
    );

    # Fail if unknown arguments encountered...
    pod2usage(2) if !$options_okay;

    # Validate User supplied options
    validate_options();

    return 1;
}

sub validate_options {
    if ( defined $RequestLimit ) {
        if ( $RequestLimit !~ /^\d+$/ ) {
            die "Bad request: Request limit should be an integer > 0\n";
	}
	if ( $RequestLimit < 0 || $RequestLimit > 99999 ) {
	    die "Bad request: The request limit shouldbe > 0 and less than 99999\n";
	}
    }

    return 1;
}

sub argv_help {

    my $msg = "run '$PROGNAME --man' for full man-page\n";

    pod2usage( -message => $msg,
               -exitval => 0,
               -output  => \*STDOUT,
               -verbose => 0 );

    return;   # NOTREACHED
}

sub argv_man {

    pod2usage( -exitval => 0,
               -output  => \*STDOUT,
               -verbose => 2 );

    return;   # NOTREACHED
}

sub argv_version {

    print "$PROGNAME $VERSION\n"
        or fatal 'print', 'STDOUT';

    exit 0;
}

#==============================================================================
# Stuff used by fatal
#==============================================================================

sub _unknown_option {
    my( $cf, $option ) = @_;

    $cf->filled( "Unknown option: '$option'\n" );

    $cf->synopsis();
    return;
}

#----- In case we are being used as a module.
1;

__END__

=pod

=begin stopwords

myname

=end stopwords

=head1 NAME

myname - my purpose

=head1 SYNOPSIS

 myname arg
 
    -or-
 
 myname
    [ --help    ]
    [ --man     ]
    [ --usage   ]
    [ --version ]

=head1 DESCRIPTION

B<myname> blah blah blah

=head1 EXIT STATUS

=head1 SEE ALSO

=head1 LICENSE AND COPYRIGHT

Copyright (C) Hewlett-Packard Company 2009,2010  All Rights Reserved.

=cut

