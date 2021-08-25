#!/usr/bin/env perl5
#------------------------------------------------------------------------------
#
#      Copyright (c) 2009,2010 Hewlett-Packard Company, all rights reserved.
#
#------------------------------------------------------------------------------
#
# $Id: RequestReport.pl 19 2011-05-18 16:53:35Z red $
# $HeadURL: file:///var/lib/svn/repository/projects/Request_Review_Report/trunk/RequestReport.pl $
# $Revision: 19 $
# $Date: 2011-05-18 09:53:35 -0700 (Wed, 18 May 2011) $
# $Author: red $
#

package RequestReport;

# Required Modules
use warnings;
use strict;
use 5.010;

use Local::MdaCredentials qw( mda_credentials );

use English qw( -no_match_vars );
use Carp::Fatal;
use Carp qw( croak carp );
use Getopt::Long;
use File::Spec::Functions;
use File::Temp qw(tempfile);
use File::Basename qw( basename );
use Text::CSV;
use Data::Dumper;
use Pod::Usage;
use Readonly;

use DBI;
local $Data::Dumper::Indent = 1;

my ( $RequestId, $RequestLimit, $DateLimit, $ReportFull, $input_outfile, $outfile ,$NoCSVHeader);
my $verbose;
my $quiet;
my $dbh;
my $sth;

# gather runtime information for usage and status messages
our ($VERSION) = '$Revision: 19 $' =~ / ( \d+ (?: [.] \d+ )? )/sxm; ## no critic (RequireConstantVersion)

# Database Interface variables, note that we use a read-only
# (select only) query!
my @Data;    # Array to store the results of the database queries
my %Results
    ;    # Hash to store the final results after cross-referencing the data.

#
# Define the database query needed to get the fields from the MDA database.
# currently the time required for these queries on the Houston data center are
# Query0: 74 Seconds
# Query1: 61 Seconds
#

## no critic (ProhibitInterpolationOfLiterals)

my @Query = (

    # 0
    {   sql =>
            "SELECT DISTINCT AL1.DESIGN_TASK_ID, AL2.PROJECT_NAME, AL3.PROJECT_REV_NAME, AL1.DESIGN_TASK_TYPE, AL4.DESIGN_SITE_NAME, AL1.REQUEST_REASON, AL1.CHANGE_DESCRIPTION, AL6.PERSON_SEA AS REQUESTER, MAX ( AL5.PERSON_SEA ) AS READINESS_APPROVER, AL7.PERSON_SEA AS LAYOUT_DESIGNER, AL8.COMPLEXITY, TO_CHAR(MAX(AL9.ACTION_START_DATE), 'mm/dd/yyyy hh24:mi:ss') ACTION_START_DATE, AL6.PERSON_ROLE AS ACTION_ROLE, AL7.PERSON_ROLE AS DESIGNER_ROLE, AL5.PERSON_ROLE AS PROJECT_ENGINEER_ROLE FROM MDA.DESIGN_TASK AL1, MDA.PROJECT AL2, MDA.PROJECT_REV AL3, MDA.DESIGN_SITE AL4, MDA.DESIGN_TASK_ACTION AL5, MDA.DESIGN_TASK_PERSON AL6, MDA.DESIGN_TASK_PERSON AL7, MDA.DML_INTEGRATION_DATA AL8, MDA.DESIGN_TASK_ACTION AL9 WHERE ( AL1.PROJECT_ID = AL2.PROJECT_ID (+) AND  AL1.PROJECT_REV_ID = AL3.PROJECT_REV_ID (+) AND AL1.DESIGN_SITE_ID = AL4.DESIGN_SITE_ID (+) AND  AL1.DESIGN_TASK_ID = AL5.DESIGN_TASK_ID (+) AND  AL6.DESIGN_TASK_ID (+)= AL1.DESIGN_TASK_ID  AND  AL7.DESIGN_TASK_ID (+)= AL1.DESIGN_TASK_ID  AND  AL8.DESIGN_TASK_ID (+)= AL1.DESIGN_TASK_ID  AND  AL9.DESIGN_TASK_ID (+)= AL1.DESIGN_TASK_ID )  AND ((AL1.DESIGN_TASK_ID>=38000 AND AL6.PERSON_ROLE(+)='mda-users' AND AL7.PERSON_ROLE(+)='mda-layout-designers' AND AL5.PERSON_ROLE(+)='mda-project-engineers' )) GROUP BY AL1.DESIGN_TASK_ID, AL2.PROJECT_NAME, AL3.PROJECT_REV_NAME, AL1.DESIGN_TASK_TYPE, AL1.REQUEST_REASON, AL1.CHANGE_DESCRIPTION, AL4.DESIGN_SITE_NAME, AL6.PERSON_SEA, AL7.PERSON_SEA, AL8.SPECIAL_CONSIDERATIONS, AL8.COMPLEXITY, AL9.ACTION_START_DATE, AL6.PERSON_ROLE, AL7.PERSON_ROLE, AL5.PERSON_ROLE",
        fields => [
            'DESIGN_TASK_ID',     'PROJECT_NAME',
            'PROJECT_REV_NAME',   'DESIGN_TASK_TYPE',
            'DESIGN_SITE_NAME',   'REQUEST_REASON',
            'CHANGE_DESCRIPTION', 'REQUESTER',
  	    'READINESS_APPROVER', 'LAYOUT_DESIGNER',    
            'COMPLEXITY',         'ACTION_START_DATE',
	    'ACTION_ROLE',        'DESIGNER_ROLE',
	    'PROJECT_ENGINEER_ROLE'
        ],
    },

    # 1

    {   sql =>
            "SELECT AL1.DESIGN_TASK_ID, TO_CHAR(MAX(AL2.ACTION_START_DATE), 'mm/dd/yyyy hh24:mi:ss') ACTION_START_DATE FROM MDA.DESIGN_TASK AL1, MDA.DESIGN_TASK_ACTION AL2 WHERE (AL1.DESIGN_TASK_ID>=38000 AND AL2.DESIGN_TASK_ID=AL1.DESIGN_TASK_ID) GROUP BY AL1.DESIGN_TASK_ID ORDER BY 1 DESC",
        fields => [ 'DESIGN_TASK_ID', 'ACTION_START_DATE', ],
    },

    # 2

    {   sql =>
            "SELECT AL1.DESIGN_TASK_ACTION_ID, TO_CHAR(MAX(AL1.ACTION_START_DATE), 'mm/dd/yyyy hh24:mi:ss') ACTION_START_DATE, TO_CHAR(MAX(AL3.ORDER_DATE), 'mm/dd/yyyy hh24:mi:ss') ORDER_DATE, AL1.TASK_STATE_ID, AL2.TASK_STATE_DESCRIPTION, AL1.DESIGN_TASK_ID FROM MDA.DESIGN_TASK_ACTION AL1, MDA.TASK_STATE AL2, MDA.RETICLE_ORDER AL3 WHERE ( AL1.DESIGN_TASK_ID = AL3.DESIGN_TASK_ID (+) AND AL2.TASK_STATE_ID=AL1.TASK_STATE_ID)  AND (AL1.DESIGN_TASK_ID>=38000) GROUP BY AL1.DESIGN_TASK_ACTION_ID, AL1.TASK_STATE_ID, AL2.TASK_STATE_DESCRIPTION, AL1.DESIGN_TASK_ID",
        fields => [
            'DESIGN_TASK_ACTION_ID',  'ACTION_START_DATE',
            'ORDER_DATE',             'TASK_STATE_ID',
            'TASK_STATE_DESCRIPTION', 'DESIGN_TASK_ID',
        ],
    },
);

## use critic

my @report_fields
    = qw(DESIGN_TASK_ID TASK_STATE_ID PROJECT_NAME PROJECT_REV_NAME DESIGN_TASK_TYPE DESIGN_SITE_NAME
    REQUEST_REASON CHANGE_DESCRIPTION REQUESTER READINESS_APPROVER
    LAYOUT_DESIGNER COMPLEXITY ACTION_START_DATE);

sub quitdb {
    $sth->finish     if ($sth);
    $dbh->disconnect if ($dbh);
    return 1;
}

sub divert_stderr {

    open my( $save ), '>&', \*STDERR
        or fatal 'open', '>&', 'STDERR';

    close STDERR
        or fatal 'close', 'STDERR';

    my $buf = '';
    open STDERR, '>', \$buf
       or fatal 'open', 'string file buffer';

    return ($save, \$buf);
}

sub revert_stderr {
    my( $save ) = @_;

    close STDERR
        or fatal 'close', 'STDERR';

    open STDERR, '>&', $save
        or fatal 'open', '>&', 'Saved STDERR';

    close $save;

    return;
}


sub connect_to_db {
    # modified to handle MDA databae failover 07/03/2012
    # code leveraged from dmMDA

    my ( $stderr_save, $stderr_buf_ref ) = divert_stderr();
    my $dbh;

    foreach my $cred (mda_credentials()) {

        my $conn
            = 'dbi:Oracle:host ='
            . $cred->{host}
            . ';service_name='
            . $cred->{service}
            . ';port='
            . $cred->{port}
            ;

        $dbh = DBI->connect( $conn, $cred->{user}, $cred->{passwd} );

        #print "Conn: $conn\n";

        last
             if $dbh;
    }

    revert_stderr( $stderr_save );

    fatal 'db_cannot_connect', $DBI::errstr, ${ $stderr_buf_ref }
        if not $dbh;

    $dbh->{AutoCommit}    = 0;
    $dbh->{RaiseError}    = 1;
    $dbh->{ora_check_sql} = 0;
    $dbh->{RowCacheSize}  = 16;

    return $dbh;
}

# simple routine used in sorting to get the numbers right
sub numeric { return $a <=> $b }

# report a shorter version of a message to make reports to the screen more readable.
sub _shortmsg {
    my $msg    = shift;
    my $maxlen = shift;

    if ( !defined $maxlen ) { $maxlen = 20; }

    if ( !$msg ) {
        return 1;
    }

    if ( $ReportFull ) {
        return $msg;
    }

    if ( ( my $idx = index $msg, "\n" ) > 0 ) {
        $msg = substr $msg, 0, $idx - 1;
    }
    if ( length($msg) > $maxlen ) {
        $msg = substr $msg, 0, $maxlen;
        $msg .= '...';
    }
    return $msg;
}

#
# Main subrouting to fetch the data from the MDA Oracle database.
# 12022010: Need to add a method to fetch an array instead of a hash
#    and check to make sure we only get one line per request.
#
sub GetRequestData {
    # connect to the MDA Oracle database
    $dbh = connect_to_db();

    my $start_db_time = time;
    my @skey_array    = qw(DESIGN_TASK_ID DESIGN_TASK_ACTION_ID);

    foreach my $i ( 0 .. $#Query ) {
        $verbose && print "[$i] Query $i...\n";
        my $local_db_time = time;
        my $query         = $Query[$i]->{sql};

        # add in the task filters if defined
        if ($RequestLimit) {
            print " ... applying query request limit of $RequestLimit\n";
            $query
                =~ s/AL1.DESIGN_TASK_ID>=38000/AL1.DESIGN_TASK_ID>=$RequestLimit/sxm;
        }

        elsif ($DateLimit) {
            print " ... applying query date limit of $DateLimit\n";
            my $id = 'AL1';
            if ( $i == 0 ) { $id = 'AL9'; }
            $query
                =~ s/AL1.DESIGN_TASK_ID>=38000/$id.ACTION_START_DATE>=TIMESTAMP '$DateLimit'/sxm;
        }

        elsif ($RequestId) {
            print " ... applying specific request check of $RequestId\n";
            $query
                =~ s/AL1.DESIGN_TASK_ID>=38000/AL1.DESIGN_TASK_ID=$RequestId/sxm;
        }

        my $Rows = $dbh->selectall_arrayref( $query, { Slice => {} } )
            or croak $dbh->errstr;

        foreach my $row (@{$Rows}) {
            #print "Request: $row->{DESIGN_TASK_ID}\n";
            if ( exists( $row->{ACTION_START_DATE} ) ) {
                my $pseudo_key = $row->{ACTION_START_DATE};
                $pseudo_key =~ s/[\/:]//sxgm;
                $pseudo_key =~ s/\s+/_/sxgm;
                $row->{PSK} = $pseudo_key;
            }
        }

        push @Data, $Rows;
        my $end_db_time = time;
        my $db_time     = $end_db_time - $local_db_time;
        if ( !$quiet ) {
            print
                "    time required for db operations on query $i is $db_time seconds\n";
        }
    }

    # disconnect from the database.
    my $rc = $dbh->disconnect;

    # Dump the database results during development
    #{
    #    my $dumpfile = "dumpfile";
    #    open( DUMP, ">$dumpfile" ) || die "Cannot open debug dump file\n";
    #    print DUMP Data::Dumper->Dump( [ \@Data ], ['*Data'] );
    #    close DUMP;
    #}

    # capture the time in the database functions...
    my $end_db_time = time;
    my $db_time     = $end_db_time - $start_db_time;
    if ( !$quiet ) {
        print "Time required for db operations is $db_time seconds\n";
    }

    return 1;
}

sub corrolate_data {

# extract the max-action-date data from the three major arrays into corrolation
# matrices
# walk the elemens of the actions array using the state time information as a key to look-up
# the remainder of the task information in the other arrays.
# therefore I need to create xref hashes for the info and the state data arrays
    my @Actions = @{ $Data[1] };
    my @Info    = @{ $Data[0] };
    my %InfoXref;
    my @States = @{ $Data[2] };
    my %StateXref;

    print " found $#Info info tags to xref\n";
    foreach my $idx ( 0 .. $#Info ) {
        if ( exists( $Info[$idx]->{PSK} ) ) {
            $InfoXref{ $Info[$idx]->{PSK} } = $idx;
        }
        else {
            print
                " ... Info entry $idx does not have an 'PSK' element in the Info Array\n";
        }
    }
    print " found $#States state tags to xref\n";
    foreach my $idx ( 0 .. $#States ) {
        if ( exists $States[$idx]->{PSK} ) {
            $StateXref{ $States[$idx]->{PSK} } = $idx;
        }
        else {
            print
                " ... State $idx does not have an 'PSK' element in the States Array\n";
        }
    }

# query 1 is the array with the action times which tell how to connect the other data
    foreach my $idx ( 0 .. $#Actions ) {
        if ( defined $Actions[$idx]->{PSK} ) {

            # the pseudo-key is in the information hash
            my $request = $Actions[$idx]->{DESIGN_TASK_ID};
            my $lookup  = $Actions[$idx]->{PSK};
            if ( exists$StateXref{$lookup} ) {
                my $action_id
                    = $States[ $StateXref{$lookup} ]->{DESIGN_TASK_ACTION_ID};
                my $task_state_id
                    = $States[ $StateXref{$lookup} ]->{TASK_STATE_ID};
                my $task_state_desc = $States[ $StateXref{$lookup} ]
                    ->{TASK_STATE_DESCRIPTION};

# now we have a connection between the Full info hash and the task state hash key
# print "   ... [$key] Request $request is at state $task_id\n";

                if ( $task_state_id > 8 ) {
		    #print "    Skipping $task_state_desc request $request\n";
                    next;
                }

                # Copy all three array elements into the results
                for my $key ( keys %{ $Info[ $InfoXref{$lookup} ] } ) {
                    my $value = $Info[ $InfoXref{$lookup} ]->{$key};
                    if ( exists $Results{$request}->{$key} ) {
			#print
			#    "skipping existing result key in info array $key = $value\n";
			next;
                    }
                    $Results{$request}->{$key}
                        = $Info[ $InfoXref{$lookup} ]->{$key};
                }
                for my $key ( keys %{ $States[ $StateXref{$lookup} ] } ) {
                    my $value = $States[ $StateXref{$lookup} ]->{$key};
                    if ( exists $Results{$request}->{$key} ) {
			#print
			#    "skipping existing result key in states array $key = $value\n";
                        next;
                    }
                    $Results{$request}->{$key}
                        = $States[ $StateXref{$lookup} ]->{$key};
                }
            }
            else {
                print
                    "   ... [$idx] Cannot find connection for $request between Task State and Full information for key $lookup\n";
            }
        }
        else {
            print
                " ... Request $idx does not have an 'PSK' element in the Actions array\n";
            next;
        }
    }
    return 1;
}

sub _dump_task_info {

    # print out the request information
    print "\nTask Information:\n";
    foreach my $key ( reverse sort numeric keys %Results ) {
        print "Request $key:\n";
        foreach my $tag ( sort keys %{ $Results{$key} } ) {
            if ( $Results{$key}->{$tag} ) {
                print "    $tag = "
                    . _shortmsg( $Results{$key}->{$tag} ) . "\n";
            }
            else {
                print "    $tag\n";
            }
        }
    }
    return;
}

sub write_csv_file {
    my ( $OUTFH, $oldfh );
    my $file = $outfile . '.csv';
    open $OUTFH, '>', $file ## no critic ( RequireBriefOpen )
        or croak "Cannot open the output file $file for writing: $OS_ERROR\n";

    my $csv = Text::CSV->new( { binary => 1 } );

    # define a shortcut
    my %hash = %Results;
    my $last_request_row = ( sort numeric keys %hash )[-1];

    #print "last = $last_request_row\n";

    # print headers
    my @headers   = keys %{ $hash{$last_request_row} };
    my $hdrstatus = $csv->combine(@report_fields);
    my $hdrline   = $csv->string();
    if ( !defined $hdrline ) {
        die 'bad CSV combine: ' . $csv->error_input() . "\n";
    }
    if ( !defined $NoCSVHeader ) {
        print { $OUTFH } "$hdrline\n";
    }

    # print each row in the table
    foreach my $key ( reverse sort numeric keys %hash ) {

        #print "Request $key:\n";
        my @varray;
        for my $j (@report_fields) {
            my $value = $hash{$key}->{$j};
            if ( defined $value ) {
                $value =~ s/\015\n*//gsxm;

                #print " .. $key: key=$j value = $value\n";
            }
            push @varray, $value;
        }

        my $status  = $csv->combine(@varray);
        my $csvline = $csv->string();
        if ( !defined $csvline ) {
            die 'bad CSV combine: ' . $csv->error_input() . "\n";
        }
        print { $OUTFH } "$csvline\n";
        undef @varray;
    }

    close $OUTFH
        or croak "Cannot close the output file $file: $OS_ERROR\n";

    return 1;
}

sub write_perl_file {
    my ( $OUTFH, $oldfh );
    my $file = $outfile . '.dat';
    open $OUTFH, '>', $file
        or croak "Cannot open the perl output file $file for writing: $OS_ERROR\n";

    print { $OUTFH } Data::Dumper->Dump( [ \%Results ], ['*Results'] );

    close $OUTFH
        or croak "Cannot close the perl output file $file: $OS_ERROR\n";
    return 1;
}

sub main {

    parse_cmdline();

    GetRequestData();

    corrolate_data();

    if ($verbose) {
        _dump_task_info();
    }
    else {
        write_perl_file();
        write_csv_file();
    }

    exit 0;
}

sub validate_options {
    if ( defined $RequestLimit ) {
        if ( $RequestLimit !~ /^\d+$/sxm ) {
            die "Bad request: Request limit should be an integer > 0\n";
        }
        if ( $RequestLimit < 0 || $RequestLimit > 99_999 ) {
            die
                "Bad request: The request limit shouldbe > 0 and less than 99999\n";
        }
    }

    # check the output file to make sure we can write to it.
    if ( defined $input_outfile ) {
        if ( $input_outfile ne q{-} ) {
            my $OUTFH;
            open $OUTFH, '>', $input_outfile
                or croak
                "Cannot open the output file $input_outfile for writing: $OS_ERROR\n";
            close $OUTFH
                or croak "Bad close to starting check of output file: $OS_ERROR\n";
            $outfile = $input_outfile;
        }
    }
    else {
        $outfile = '/home/red/projects/metrics/review_report';
    }

    return 1;
}

sub parse_cmdline {

    # Parse standard options from command line
    Getopt::Long::Configure('bundling');
    my $options_okay = GetOptions(

        # note that this script does not use the default set of
        # options used for the remainder of the scripts.  This is
        # by design since this script is meant to be called for
        # the entire diskspace and not for a single design.

        # options
        'out|outfile|output=s' => \$input_outfile,
        'id=i'                 => \$RequestId,
        'date=s'               => \$DateLimit,
        'limit=i'              => \$RequestLimit,
        'full'                 => \$ReportFull,
        'verbose|v'            => \$verbose,
        'quiet|q'              => \$quiet,
	'no_csv_header'        => \$NoCSVHeader,
        'help|?'               => sub { argv_help(); },
        'version'              => sub { argv_version(); },
        'usage' => sub { pod2usage( -exitstatus => 1, -verbose => 0 ); },
        'man' => sub { argv_man(); },
    );

    # Fail if unknown arguments encountered...
    pod2usage(2) if !$options_okay;

    # Validate User supplied options
    validate_options();

    return 1;
}

sub argv_help {

    my $msg = "run 'RequestReview --man' for full man-page\n";

    pod2usage(
        -message => $msg,
        -exitval => 0,
        -output  => \*STDOUT,
        -verbose => 0
    );

    return;    # NOTREACHED
}

sub argv_man {

    pod2usage(
        -exitval => 0,
        -output  => \*STDOUT,
        -verbose => 2
    );

    return;    # NOTREACHED
}

sub argv_version {

    print "Revision $VERSION\n"
        or fatal 'print', 'STDOUT';

    exit 0;
}

#==============================================================================
# Stuff used by fatal
#==============================================================================

sub _unknown_option {
    my ( $cf, $option ) = @_;

    $cf->filled("Unknown option: '$option'\n");

    $cf->synopsis();
    return;
}

#----- caller() returns false if we're being run as a script
# MAIN PROGRAM LAUNCH
main()
    if not caller;

#------------------------------------------------------------------------------

__END__

=pod

=begin stopwords

RequestReport

=end stopwords

=head1 NAME

RequestReport - recreate the dily request review report used in the managers review meeting.

=head1 SYNOPSIS

 RequestReport arg
 
    -or-
 
 RequestReport
    [ --help    ]
    [ --man     ]
    [ --usage   ]
    [ --version ]
    [ --quiet   ]
    [ --full ]

    [ --no_csv_header ]
    [ out|outfile|output <filename> ]
    [ date=DateLimit ]
    [ limit=RequestLimit ]

=head1 DESCRIPTION

B<RequestReport> blah blah blah

=head1 EXIT STATUS

=head1 SEE ALSO

=head1 LICENSE AND COPYRIGHT

Copyright (C) Hewlett-Packard Company 2009,2010  All Rights Reserved.

=cut

