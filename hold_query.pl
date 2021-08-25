#!/usr/bin/env perl
#
#   Author:  Floyd Moore (floyd.moore\@hp.com)
#       $HeadURL: file:///var/lib/svn/repository/projects/metrics/trunk/hold_query.pl $
#       $Revision: 41 $
#       $Date: 2011-05-04 14:36:10 -0700 (Wed, 04 May 2011) $
#       Description:
#
#       "run_query" created by red
#

use warnings;
use strict;
use 5.010;

use Local::MdaCredentials qw( mda_credentials );

use English qw( -no_match_vars );
use Getopt::Long;
use Pod::Usage;
use Carp::Fatal qw( fatal );
use DBI qw(:sql_types);
use File::Spec::Functions;
use File::Basename qw( basename );
use Text::ASCIITable;
use Date::Parse;
use Date::Calc qw( Delta_DHMS );
use Readonly;
use POSIX qw(strftime);
use Data::Dumper;
local $Data::Dumper::Indent = 1;

# global variables
my $dumpandstop;
my $verbose;
my $input_request;
my $csvfile;
my @Vars;
my %Metrics;

# setup runtime information
our ($VERSION) = '$Revision: 41 $' =~ / ( \d+ (?: [.] \d+ )? )/sxm; ## no critic (RequireConstantVersion)

Readonly my $PROGNAME => basename $PROGRAM_NAME;

#----- caller() returns false if we're being run as a script
main()
    if not caller;
exit 0;

#----------------------------------------------------------------------------------------------------
# report the script version and exit

sub CommandVersion {

    # simply print the version number of the script
    print "$PROGNAME Revision $VERSION\n";
    exit 0;
}

sub divert_stderr {

    open my ($save), '>&', \*STDERR
        or fatal 'open', '>&', 'STDERR';

    close STDERR
        or fatal 'close', 'STDERR';

    my $buf = q{};
    open STDERR, '>', \$buf
        or fatal 'open', 'string file buffer';

    return ( $save, \$buf );
}

sub revert_stderr {
    my ($save) = @_;

    close STDERR
        or fatal 'close', 'STDERR';

    open STDERR, '>&', $save
        or fatal 'open', '>&', 'Saved STDERR';

    close $save
        or fatal 'close', 'STDERR';

    return;
}

#
# Get the date information from the MDA database.  Each row will have three (3) columns:
#   Design Task Id, Action Start Date, and Task State Description.
# We can extract the times associated with the changes from the various MDA states from this
# infomation.
#
# All data is stored into the @Vars array.
#
sub get_info_from_mda {

    my ( $stderr_save, $stderr_buf_ref ) = divert_stderr();
    my $dbh;

    foreach my $cred ( mda_credentials() ) {

        my $conn
            = 'dbi:Oracle:host ='
            . $cred->{host}
            . ';service_name='
            . $cred->{service}
            . ';port='
            . $cred->{port};

        $dbh = DBI->connect( $conn, $cred->{user}, $cred->{passwd} );

        #print "Conn: $conn\n";

        last
            if $dbh;
    }

    revert_stderr($stderr_save);

    fatal 'db_cannot_connect', $DBI::errstr, ${$stderr_buf_ref}
        if not $dbh;

    #$dbh->debug(2);
    my $sth;

    my $query_date = '01-Nov-2009';

    ## no critic (ProhibitInterpolationOfLiterals)
    my $mda_hold_query
        = "SELECT AL1.DESIGN_TASK_ID, TO_CHAR(AL2.ACTION_START_DATE,'mm/dd/yyyy hh24:mi:ss') ACTION_START_DATE, AL3.TASK_STATE_DESCRIPTION FROM MDA.DESIGN_TASK AL1, MDA.DESIGN_TASK_ACTION AL2, MDA.TASK_STATE AL3 WHERE (AL2.DESIGN_TASK_ID=AL1.DESIGN_TASK_ID AND AL3.TASK_STATE_ID=AL2.TASK_STATE_ID) AND (AL1.DESIGN_TASK_ID > 39500) ORDER BY  1,  2";

    my @hold_fields
        = qw( DESIGN_TASK_ID ACTION_START_DATE TASK_STATE_DESCRIPTION );

    ## use critic

    if ( defined $input_request ) {
        $mda_hold_query =~ s/>\s37500/= $input_request/sxm;
    }

    $dbh->{RaiseError} = 1;

    $sth = $dbh->prepare($mda_hold_query)
        or die
        "Cannot prepare sql query.  SQL syntax error found: $dbh->errstr\n";

    $sth->execute()
        or die "SQL Command failed:  $dbh->errstr\n";

    $sth->bind_col( 2, undef, { TYPE => SQL_DATETIME } );

    my @row;
    my $design_task = 0;
    my $count       = 0;

    while ( @row = $sth->fetchrow_array ) {
        my $save;

        undef $design_task;

        for ( my $j = 0; $j <= $#row; $j++ )
        {    ## no critic (ProhibitCStyleForLoops)
            if ( !defined $row[$j] ) { next; }
            $row[$j] =~ s/\015//sgxm;
            $row[$j] =~ s/\n/ /sgxm;
            $row[$j] =~ s/\s{3,}/ /sgxm;

            if ( $hold_fields[$j] eq 'DESIGN_TASK_ID' ) {
                $design_task = $row[$j] + 0;
            }

            if ( !defined $design_task ) {
                die "Design Task not defined\n";
            }

            $save->{ $hold_fields[$j] } = $row[$j];
            if ($verbose) {
                print "$count: $hold_fields[$j]: $row[$j]\n";
            }
        }

        ++$count;

        # print "... request $design_task\n";
        push @Vars, $save;

    }

    $sth->finish;

    my $rc = $dbh->disconnect;

    return 0;
}

#
# Dump data from the Vars table
#
sub dump_vars_table {
    my $lines     = shift;
    my $table     = Text::ASCIITable->new();
    my $final_row = 10;
    my @varray;
    my @headers;

    foreach my $key ( keys %{ $Vars[0] } ) {
        push @headers, $key;
    }

    $table->setCols(@headers);

    if ( defined $lines ) {
        $final_row = $lines;
    }
    foreach my $row (@Vars) {
        for my $j (@headers) {
            push @varray, $row->{$j};
        }
        $table->addRow(@varray);
        undef @varray;
    }

    print $table;
    undef $table;

    return 0;
}

#
# Compute the difference in time between two dates.
#
sub date_diff {
    my $start = shift;
    my $end   = shift;

    #print "find differnce in time from start=$start to end=$end\n";
    my ( $M1, $d1, $y1, $h1, $n1, $s1 ) = split /[ :\/]+/sxm, $start;
    my ( $M2, $d2, $y2, $h2, $n2, $s2 ) = split /[ :\/]+/sxm, $end;

    #print "Start Date = $M1/$d1/$y1\n";
    my ( $Dd, $Dh, $Dm, $Ds )
        = Delta_DHMS( $y1, $M1, $d1, $h1, $n1, $s1, $y2, $M2, $d2, $h2, $n2,
        $s2 );
    my $secs = $Ds + 60 * $Dm + 3600 * $Dh + 3600 * 24 * $Dd;

    #print "delta = $Dd:$Dh:$Dm:$Ds ($secs seconds)\n";
    return $secs;
}

#
# round a number to 3 decimal places
#
sub round {
    my $number = shift;
    return sprintf '%.3f', $number;
}

#
# convert time from seconds to hours
#
sub secs_to_hrs {
    my $secs = shift;

    return round( $secs / 3600 );
}

#
# convert time from seconds to days
#
sub secs_to_days {
    my $secs = shift;

    return round( $secs / ( 3600 * 24 ) );
}

#
# Parse options from the command line
#
sub parse_cmdline {
    Getopt::Long::Configure('bundling');
    my $options_okay = GetOptions(
        'id=i'  => \$input_request,
        'csv=s' => \$csvfile,

        # Standard meta-options
        'dumpandstop' => \$dumpandstop,
        'verbose|v'   => \$verbose,
        'help|?'      => sub { pod2usage(1); },
        'version'     => sub { CommandVersion(); },
        'usage'       => sub { pod2usage( -verbose => 0 ); },
        'man' => sub { pod2usage( -exitstatus => 0, -verbose => 2 ); },
    );

    # Fail if unknow arguemnts encountered...
    pod2usage(2) if !$options_okay;

    if ( defined $input_request ) {
        if ( $input_request !~ /\d+/sxm ) {
            die "Input Request should be a number!\n";
        }
    }

    return 0;
}

#
# Request Sorting Routine (called by sort() )
#
sub by_request_and_time {

   #print "compare requests: $a->{DESIGN_TASK_ID} and $b->{DESIGN_TASK_ID}\n";
    if ( $a->{DESIGN_TASK_ID} == $b->{DESIGN_TASK_ID} ) {
        my $diff
            = date_diff( $b->{ACTION_START_DATE}, $a->{ACTION_START_DATE} );
        return $diff <=> 0;
    }
    else {
        return $a->{DESIGN_TASK_ID} <=> $b->{DESIGN_TASK_ID};
    }
    return 0;
}

# 3:
# Compress the result array to remove the redundent information.
#
# Inital:
# |          37938 | 03-02-2009 21:15:03 | Layout Preview         |
# |          37938 | 03-05-2009 21:39:01 | Layout Preview         |
# |          37938 | 03-06-2009 17:57:10 | Layout Preview         |
# |          37938 | 03-06-2009 17:58:17 | Layout Preview         |
# |
#
# Should compress to a single line:
# |          37938 | 03-02-2009 21:15:03 | Layout Preview         |
#
# Algorithm:
# If row <n> and <n-1> are both the same id and both have
# the same state, then don't save <n>.
#

sub compress_array {
    my @new;
    my $count = 0;
    my $row   = 0;
    my $save;

    while ( defined( $Vars[$row]->{DESIGN_TASK_ID} ) ) {
        my $np1 = $row + 1;
        if ( !defined $Vars[$row] ) { last; }
        if ( !defined $Vars[$row]->{DESIGN_TASK_ID} ) {
            print "Error trap: Vars[row] not defined!\n";
            exit 1;
        }

#print "==================================\n";
#print "row[$row]: $Vars[$row]->{DESIGN_TASK_ID}, $Vars[$row]->{ACTION_START_DATE}, $Vars[$row]->{TASK_STATE_DESCRIPTION}\n";

        if ( !defined $save ) {

            #print " ... no save\n";
            # no previous row to check...
            if ( !defined $Vars[$np1] ) {

                #print "... trap1 np1 last\n";
                push @new, $Vars[$row];
                last;
            }

#print "row[$np1]: $Vars[$np1]->{DESIGN_TASK_ID}, $Vars[$np1]->{ACTION_START_DATE}, $Vars[$np1]->{TASK_STATE_DESCRIPTION}\n";

            if ( $Vars[$row]->{DESIGN_TASK_ID}
                != $Vars[$np1]->{DESIGN_TASK_ID} )
            {

        # next request is different... save it in the final array and continue
        #print " ... no save, different requestid\n";
                push @new, $Vars[$row];
                $row++;
                next;
            }

            if ( $Vars[$row]->{TASK_STATE_DESCRIPTION} ne
                $Vars[$np1]->{TASK_STATE_DESCRIPTION} )
            {

# request id's are the same, but states are different.  Save it in the final array
# and continue
#print " ... no save, same requestid, different states\n";
                push @new, $Vars[$row];
                $row++;
                next;
            }

# new save state.  Id's and the states are the same.  Need to save this point into the
# final array and save this point to check next state.
#print " ... no save and uniqe row: save this row into final: $row\n";
            push @new, $Vars[$row];
            $row++;
            $save = $row;
            next;
        }
        else {

            # We have a previously saved row to compare against.
            if ( $Vars[$save]->{DESIGN_TASK_ID}
                != $Vars[$row]->{DESIGN_TASK_ID} )
            {

# is this request different from the saved state? save it in the final array and continue
#print " ... saved row, different requestids\n";
                $save = $row;
                push @new, $Vars[$row];
                $row++;
                next;
            }

            if ( $Vars[$save]->{TASK_STATE_DESCRIPTION} ne
                $Vars[$row]->{TASK_STATE_DESCRIPTION} )
            {

# request id's are the same, but states are different.  Save it in the final array
# and continue
#print " ... saved row, same requestid, different states\n";
                $save = $row;
                push @new, $Vars[$row];
                $row++;
                next;
            }

# the saved row and the current one have the same Id and state, we can skip saving this row
# into the final array.
#print " ... saved row, same requestid, same state: skip saving this row: $row\n";
            $row++;
            next;
        }
    }

    @Vars = @new;
    undef @new;

    return 0;
}

#
# Using the new compressed and ordered result array, start counting the state time.
#
sub calculate_hold_time {

    # 4:  Compute the individual hold time segments for each request state
    # 4b: Total the intervals up for each request.
    #
    my $idx;
    my $current;
    my $hold_mark;
    my $total = 0;
    my $ReadyDate;
    my $PreviewDate;
    my $CloseDate;

    for ( $idx = 0; $idx <= $#Vars; $idx++ )
    {    ## no critic (ProhibitCStyleForLoops)

        # check if this is a different request?
        $Vars[$idx]->{INDEX} = $idx;
        if ( defined $current ) {
            if ( $current != $Vars[$idx]->{DESIGN_TASK_ID} ) {

                # this is a new request
                if ( $total >= 0 ) {
                    $Vars[ $idx - 1 ]->{MARK}
                        = 'Hold=' . secs_to_days($total);
                    $Metrics{ $Vars[ $idx - 1 ]->{DESIGN_TASK_ID} }
                        ->{HoldTime} = secs_to_days($total);
                }
                if ( defined $ReadyDate ) {
                    $Metrics{ $Vars[ $idx - 1 ]->{DESIGN_TASK_ID} }
                        ->{ReadyDate} = $ReadyDate;
                }
                if ( defined $PreviewDate ) {
                    $Metrics{ $Vars[ $idx - 1 ]->{DESIGN_TASK_ID} }
                        ->{PreviewDate} = $PreviewDate;
                }
                if ( defined $CloseDate ) {
                    $Metrics{ $Vars[ $idx - 1 ]->{DESIGN_TASK_ID} }
                        ->{CloseDate} = $CloseDate;
                }
                $total              = 0;
                $current            = $Vars[$idx]->{DESIGN_TASK_ID};
                $Vars[$idx]->{MARK} = 'new';
                undef $hold_mark;
                undef $ReadyDate;
                undef $PreviewDate;
                undef $CloseDate;
            }
        }
        else {
            $current = $Vars[$idx]->{DESIGN_TASK_ID};
            $Vars[$idx]->{MARK} = 'new';
        }

        # develop task state machine
        my $state    = $Vars[$idx]->{TASK_STATE_DESCRIPTION};
        my $datetime = $Vars[$idx]->{ACTION_START_DATE};
    SWITCH: {
            if ( $state eq 'Layout on Hold' ) {
                if ( !defined $hold_mark ) {
                    $Vars[$idx]->{MARK} = 'start';
                    $hold_mark = $datetime;
                }
                last SWITCH;
            }
            if ( $state eq 'Layout in Rework' ) {
                if ( defined $hold_mark ) {
                    my $diff = date_diff( $hold_mark, $datetime );
                    $total += $diff;
                    $Vars[$idx]->{MARK} = secs_to_hrs($diff);
                    undef $hold_mark;
                }
                last SWITCH;
            }
            if ( $state eq 'Layout Preview' ) {
                $ReadyDate = $datetime;
                $Vars[$idx]->{MARK} = 'ready';
                last SWITCH;
            }
            if ( $state eq 'Closed' ) {
                $CloseDate = $datetime;
                last SWITCH;
            }
            if ( $state eq 'Layout' ) {
                if ( defined $hold_mark ) {
                    my $diff = date_diff( $hold_mark, $datetime );
                    $total += $diff;
                    $Vars[$idx]->{MARK} = secs_to_days($diff);
                    undef $hold_mark;
                }
                if ( !defined $PreviewDate ) {
                    $PreviewDate = $datetime;
                }
                last SWITCH;
            }
            undef $hold_mark;
            my $nothing = 1;
        }
    }
    if ( $total >= 0 ) {
        $Vars[ $idx - 1 ]->{MARK} = 'Total=' . secs_to_days($total);
        $Metrics{ $Vars[ $idx - 1 ]->{DESIGN_TASK_ID} }->{HoldTime}
            = secs_to_days($total);
    }

    return 0;
}

sub _csv_file_loop {
    my $outfh = shift;

    print {$outfh}
        "'Design Task Id','Ready Date','Preview Date','Close Date','Raw Hold Time'\n";
    foreach my $id ( sort keys %Metrics ) {
        my $line = q{};
        for my $field (qw/ReadyDate PreviewDate CloseDate HoldTime/) {
            if ( defined( $Metrics{$id}->{$field} ) ) {
                $line .= $Metrics{$id}->{$field};
            }
            $line .= q{,};
        }
        $line =~ s/,$//sxm;
        print {$outfh} "$id,$line\n";
    }
    return 0;
}

sub write_csv_file {
    if ( defined $csvfile ) {
        my $outfh;
        open $outfh, '>', $csvfile
            || fatal "Cannot write $csvfile output file: $OS_ERROR\n";

        _csv_file_loop($outfh);

        close $outfh
            || fatal "Bad close of csv file: $OS_ERROR\n";
    }
    else {
        dump_vars_table($#Vars);
    }
    return 0;
}

#
# Main script
#
sub main {

    # get user options
    parse_cmdline();

    #
    # 1:
    # Get the raw request state transitions from MDA database or test file.
    #
    get_info_from_mda();

    #
    # 2:
    # Sort the requests by id and then by time
    #
    @Vars = sort by_request_and_time @Vars;

    # 3:
    # Compress the sorted results to remove the redundent information.
    #
    compress_array();

    #
    # see if we just want to dump the raw table or continue...
    #
    if ( defined $dumpandstop ) { dump_vars_table($#Vars); exit; }

    #
    # 4:  Compute the individual hold time segments for each request state

    calculate_hold_time();

    #
    # write the final data out to a CSV file to import into Excel
    #
    write_csv_file();

    # success!
    exit 0;
}

#==============================================================================
# 'handlers' used by fatal()
#==============================================================================

sub _cf_cannot_execute_query {
    my ( $cf, $q, $dbh ) = @_;

    $cf->filled('SQL Command failed to execute');

    my @diags = eval { $dbh->errstr() };

    $cf->verbatim( join( "\n", @diags ), 'Oracle errstr() diagnostic' )
        if not $EVAL_ERROR;

    $cf->verbatim( $q, 'Query String' );

    return;
}

sub _cf_cannot_prepare_query {
    my ( $cf, $q, $dbh ) = @_;

    $cf->filled('Oracle is rejecting a database query at preparation.');

    my @diags = eval { $dbh->errstr() };

    $cf->verbatim( join( "\n", @diags ), 'Oracle errstr() diagnostic' )
        if not $EVAL_ERROR;

    $cf->verbatim( $q, 'Query String' );

    return;
}

sub _cf_db_cannot_connect {
    my ( $cf, $diag, $err_log ) = @_;

    $cf->filled( <<"EOF" );
Unable to connect to Oracle server that houses the MDA database.
EOF

    $cf->verbatim( $diag, 'Server Diagnostic' )
        if defined $diag
            and length $diag;

    $cf->verbatim( $err_log, 'Stderr from server call' )
        if length $err_log;

    return;
}

__END__

=pod

=begin stopwords

MDA sendorder csv

=end stopwords

=head1 NAME

hold_query.pl - Perl Script to extract the mask request hold time information from MDA.

=head1 SYNOPSIS

hold_query.pl                   [--id=<design task id>]|
                                [--file=<sendorder file name>]
                                [--testfile=<test input file for testing>]
                                [--outfile=<test output file for writing test results>]
                                [--csv=<write a comma separated value file to input into Excel>]

see --man or --help for a full list of all options

=head1 OPTIONS

=over 8

=item B<--id>|B [MDA Request Id]

Specify a particular design task id to extract from the sendorder file.  This will enable
the table output functions and disable the csv storage option.

=item B<--file> [file name]

Change the sendorder transcript file that is read by the script.  Normally this file has a
static path: /sdg/lib/metrics/sendorder.txt.

=item B<--version>

print the script version number and exit

=item B<--help>

print the full help message

=item B<--man>

Prints the full pod manual

=item B<--usage>

Prints the short usage message

=back

=head1 DESCRIPTION

B<hold_query.pl> runs an oracle query on the MDA database to extract and calculate the hold time for
all requests.

=head1 EXIT STATUS

B<hold_query.pl> should exit with a status of 0.

=head1 SEE ALSO

Please refer to the MDA specifications to understand the definition of hold time as it applies to 
mask requests.

=head1 LICENSE AND COPYRIGHT
(c)2010-2011 Hewlett-Packard Company.
Author: Floyd Moore (floyd.moore@hp.com)

=cut

