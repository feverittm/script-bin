#!/usr/bin/env perl
#
#   Author:  Floyd Moore (floyd.moore\@hp.com)
#   $HeadURL: file:///var/lib/svn/repository/projects/metrics/trunk/QueryBroker/QueryBroker.pl $
#   $Revision: 198 $
#   $Date: 2009-10-09 14:00:29 -0700 (Fri, 09 Oct 2009) $
#       Description:
#       Submit a generic SQL query to a specified database server and
#       save the results to a file.  Implement queries to be placed
#       into an aux file and not have to edit the script to change
#               the query parameters.
#
#

package QueryBroker;

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
use Module::Load;
use Digest::MD5 qw(md5 md5_hex);
use Date::Manip;
use Date::Manip::Date;

# Program Specific Modules
use Config::General;
use DBI qw(:sql_types);
use POSIX qw(strftime);
use Text::ASCIITable;
use Text::CSV;
use YAML::Dumper;
use YAML;
use JSON;
use Email::Sender::Simple qw(sendmail);
use Email::Simple;
use Email::Simple::Creator;

# Define output mode types:
use constant {
    CSV   => 0,
    TABLE => 1,
    PERL  => 2,
    YAML  => 3,
    JSON  => 4,
};

# I seem to use this a million times when I am diagnosing the failures
# in my data structures and to make it easier to see what actual data
# the internal routines are seeing.  The indent thing is a personal
# preference
use Data::Dumper;
local $Data::Dumper::Indent = 1;

# setup general information
our $RUNDATE = strftime '%Y/%m/%d %H:%M:%S', localtime;
our $VERSION = 198;
Readonly my $PROGNAME => basename $PROGRAM_NAME;

# create a local timestamp so that it doesn't change within each
# query.  The 'space' character ' ' causes problems to the joining
# of the fields.
my $report_start_time = strftime '%Y-%m-%d_%H:%M:%S', localtime;

#-----
# Global variables:
# I know defining these globals and not setting them here causes Perl::Critic
# to have fits, but I prefer (especially when I have strict mode on) to
# predefine my global varaibles early in my code.  It lets me see which
# variables *should* be global and try to minimize them.  Also it isn't
# easy to create an initializor for an empty hash like %config.
#-----
our ( $append_mode, $VERBOSE, $DEBUG, %config, $input_query_file );
our ( $input_outfile, $input_sql, $input_sqlfile );
our ( $input_query_name, $check_mode, $list_queries, $shorten_long_fields );
our ( $input_mode, @input_replace_vars, $input_dbsel, %replace_vars );
our ( %Database, %Queries, $Rows, $no_report_headers );

my $OUTFH;

#
# Parse the command line:
# I prefer to DRY out the command line stuff to the Getopt module instead
# of writing my own.  I also like the way I can write a nicely formatted
# specification for the command line variables.
#

sub parse_cmdline {
    Getopt::Long::Configure('bundling');
    my %options_list = (
        'out|outfile|output=s' => \$input_outfile,    # file to write output
        'append|append_mode' =>
          \$append_mode,    # append to a file instead of opening a new one
        'query_file|qf=s' =>
          \$input_query_file,    # file containing the query information
        'mode=s'   => \$input_mode,    # alternate method to set output mode
        'query|queryname|qn=s' =>
          \$input_query_name,    # specifiy which query in the file to run
        'list_queries|list' =>
          \$list_queries,    # dump a list of all defined databases and queries
        'check' =>
          \$check_mode,    # check the database and options, don't run the query
        'shorten:i' => \$shorten_long_fields
        ,                  # shorted long message strings sent to the console
        'var|vars=s@' => \@input_replace_vars
        ,                  # string to be used for variable substitution in SQL
        'no_header' => \$no_report_headers
        ,   # flag to indicate that the user does not want headers in the report

        # Ad-Hoc query definition
        'db=s' => \$input_dbsel, # which database (from the queryfile) to access
        'sql=s' => \$input_sql,  # the raw SQL to use for the query
        'sqlfile=s' => \$input_sqlfile,  # file containing SQL commands not in defs.

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

    # you need to either use a direct 'sql' query or specify one from
    # the query file
    if (   !defined $input_query_name
        && !defined $input_sql
        && !defined $input_sqlfile
        && !defined $list_queries )
    {
        die
"Either a query name from the query file, or a direct SQL query must be specified\n";
    }

    # preprocess the variable substitution list
    # allow both multiple --var(s) options and a comma separated list
    if (@input_replace_vars) {
        @input_replace_vars = split /,/sxm, join q{,}, @input_replace_vars;
        if ( !defined $input_query_name ) {
            die
"You need to use a predefined query from the query file to use variable substitution\n";
        }
        for my $var (@input_replace_vars) {
            my ( $name, $value ) = split /=/sxm, $var, 2;

            $VERBOSE && print " ... var: $name = $value\n";
            $replace_vars{$name} = $value;
        }
    }

    # check the output file to make sure we can write to it.
    if ( defined $input_outfile ) {
        if ( $input_outfile ne q{-} ) {
            if ( defined $append_mode ) {
                open $OUTFH, '>>', $input_outfile
                  or die
"Cannot append to the output file $input_outfile for writing\n";
            }
            else {
                open $OUTFH, '>', $input_outfile
                  or die
                  "Cannot open the output file $input_outfile for writing\n";
            }
            close $OUTFH
              or die "Bad close to starting check of output file: $ERRNO\n";
        }
    }
    
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
# load_and_parse_config_file():
# This is a general loader that uses the Config::General module to grab a bunch of
# definitions from a file and load it into a structure.  I use this method alot in
# my scripts to make config files easier to read and safer to load (I don't
# have to use any 'eval's to load the file into a structure.
#
sub _load_and_parse_config_file {
    my $filename = shift;
    my $cfgfile;
    my $buffer;

    open $cfgfile, '<', $filename
      or die "Cannot open config file $filename for reading: $ERRNO\n";
    while (<$cfgfile>) {
        if (/^ [#] /sxm) {
            next;
        }
        $buffer .= $_;
    }
    close $cfgfile
      or die "Bad close of config file.\n";

    #print "Buffer: \n$buffer\n";

    if ( !defined $buffer ) {
        die "Error: empty config file: $filename\n";
    }

    $buffer =~ s/;\n/\n/gsxm;

    my $parsebuffer = Config::General->new( -String => $buffer, );

    my %hash = $parsebuffer->getall;

    return %hash;
}

# _set_output_handle {
# helper routine to se an output filehandle based on if the use has requested
# a seperate output file or just wants stuff sent to the screen.
sub _set_output_handle {
    my $_outfile = shift;

    if ( defined $_outfile ) {
        my $file_mode;
        if ( defined $append_mode ) {
            $file_mode = '>>';
        }
        else {
            $file_mode = '>';
        }
        open $OUTFH, $file_mode, $_outfile
          or die "Cannot open the output file $_outfile for writing\n";
    }
    else {
        $OUTFH = \*STDOUT;
    }

    return $OUTFH;
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

#
# ---------------------------------------------------
# Handle special alert messages or other triggers
# ---------------------------------------------------
#
# email a message to a user if a metric runs out of process.  This will be used to
# trip a warning by email if for instance the query time for a given request goes
# beyond a given limit.  These alerts will have to be configured in the control file
#

sub check_alerts {
    my $query_name  = shift;
    my @table_array = @{$Rows};
    my @headers;

    #@headers = setup_table_headers( $query_name, \@headers );

    if ( !exists $Queries{$query_name}->{alert} ) {
        return 1;
    }

    my $alert_column = $Queries{$query_name}->{alert}->{column};
    my $alert_limit  = $Queries{$query_name}->{alert}->{limit};
    my $alert_email  = $Queries{$query_name}->{alert}->{email};
    my $alert_date   = `date`;

    $VERBOSE
      && print Data::Dumper->Dump( [ \@table_array ], ['*table_array'] );
    if ( !exists $table_array[-1]->{$alert_column} ) {
        die "Can't find alert column in data rows\n";
    }

    my $value = 0;

    $value = $table_array[-1]->{$alert_column};

    $VERBOSE
      && print "$alert_column: Value = "
      . $table_array[-1]->{$alert_column} . "\n";

    my $email;
    if ( $value == 0 ) {
        $email = Email::Simple->create(
            header => [
                To      => "Alert Email <$alert_email>",
                From    => '"Floyd Moore Workstation" <floyd.moore@hp.com>',
                Subject => "Query returnning Zero! $alert_column",
            ],
            body =>
"Date: $alert_date\nQuery Time is Zero!!! We have found a zero time for the test query  $query_name: $alert_column = $value\n",
        );

        sendmail($email);

        print
"Query Time is Zero!!! We have found a zero time for the test query  $query_name: $alert_column = $value\n",
    }
    elsif ( $value > $alert_limit ) {
        $email = Email::Simple->create(
            header => [
                To      => "Alert Email <$alert_email>",
                From    => '"Floyd Moore Workstation" <floyd.moore@hp.com>',
                Subject => "Query Limit Reached $alert_column",
            ],
            body =>
"Date: $alert_date\nLIMIT!!! We have exceeded the alert limit for $query_name: $alert_column = $value, limit = $alert_limit\nhttps://tableau-dev.corp.hpicorp.net/#/site/HPI/views/ProductionVerticaMonitor/PrdVerticaMonitor?:iid=1\n",
        );

        sendmail($email);

        print
"LIMIT!!! We have exceeded the alert limit for $query_name: $alert_column = $value, limit = $alert_limit\n";
    }

    return 1;
}

sub connect_alert {
    my $query_name  = shift;

    print " ... connect_alert : $query_name\n";

    if ( !exists $Queries{$query_name}->{alert} ) {
        return 1;
    }

    my $alert_column = $Queries{$query_name}->{alert}->{column};
    my $alert_limit  = $Queries{$query_name}->{alert}->{limit};
    my $alert_email  = $Queries{$query_name}->{alert}->{email};
    my $alert_date   = `date`;

    my $email;
    $email = Email::Simple->create(
        header => [
            To      => "Alert Email <$alert_email>",
            From    => '"Floyd Moore Workstation" <floyd.moore@hp.com>',
            Subject => "Query returnning Zero! $alert_column",
        ],
        body =>
"Date: $alert_date\nQuery Time is Zero!!! We have found a zero time for the test query  $query_name: $alert_column\n",
    );

    sendmail($email);

    print
"Query Time is Zero!!! We have found a zero time for the test query  $query_name: $alert_column\n",
    return 1;
}

# ------------------------------------------------------------------
# Script Section: Load the query information from a file.
# ------------------------------------------------------------------

#
# Load the query information from a file.
# This file is the power of the script and so I wanted to keep the format as flexible as
# possible.  I used the Config::General module before and it should would well here.
# There are currently two separate section in the file: the database definitions, and the
# actual query definitions.  There will be a sepeate POD section to describe the file format.
# In the end there will be 2 hashes defined: Databases{} with database information, and
# Queries{} that hold the query infomation.
sub _check_db_defs {

    # check the database definitions
    for my $dblist ( keys %Database ) {
        $VERBOSE && print " checking database entry... $dblist\n";
        if ( !exists $Database{$dblist}->{connect_string} ) {
            die
"Database definition \'$dblist\' does not have a connect string\n";
        }
        $Database{$dblist}->{connect_string} =~ s/\'//sxmg;
        if ( $Database{$dblist}->{connect_string} !~ /^\'?dbi:\S+:/ismx ) {
            die
"Database defintion $dblist has a badly formatted connect string: $Database{$dblist}->{connect_string}\n";
        }
        my $db_adapter = $Database{$dblist}->{connect_string};
        $db_adapter =~ s/^\'?dbi://isxm;
        $db_adapter =~ s/:.*$//isxm;

      #eval "use DBD::$db_adapter";
      #croak "ERROR: Database adapter module DBD::$db_adapter not found in path"
      #    if $EVAL_ERROR;
        my $module = "DBD::$db_adapter";
        load $module;
    }
    return 1;
}

sub _check_all_query_mode {
    my $ret = TABLE;
    for my $qname ( keys %Queries ) {
        my $_mode = $Queries{$qname}->{mode};
        $ret = _check_query_mode($_mode);
        $Queries{$qname}->{mode} = $ret;
    }

    return 1;
}

sub _check_query_mode {
    my $_mode = shift;
    my $ret = TABLE;

    if      ($_mode =~ /perl/isxm) {
        $ret = PERL;
    } elsif ($_mode =~ /csv/isxm) {
        $ret = CSV;
    } elsif ($_mode =~ /json/isxm) {
        $ret = JSON;
    } elsif ($_mode =~ /yaml/isxm) {
        $ret = YAML;
    } else {
        # default mode is table
        $ret = TABLE;
    }

    return $ret;
}

#
# set the file output mode by looking at the 'mode' setting in the query definition
#
sub set_output_mode_by_defn {
    my $query_name = shift;

    if (defined $input_mode){
        my $ret = _check_query_mode($input_mode);
        $input_mode = $ret;
    }

    # set output mode in the query based on the command line if it isn't set already
    # in the definition
    # Command Line takes precidence over Definition and that over the default table 
    # mode
    if ( exists $Queries{$query_name}->{mode} ) {
        if ( defined $input_mode )
        {
            # mode defined in query definition but command line mode set -> 
            #    use command line
            $Queries{ $query_name }->{mode} = $input_mode;
        }
    } else {
        # mode not defined in query definition use command line or default
        if ( defined $input_mode ) {
            $Queries{ $query_name }->{mode} = $input_mode;
        } else {
            # default output mode is a table
            $Queries{ $query_name }->{mode} = TABLE;
        }
    }
    return 1;
}

#
# special case function to verify that for a report querty (a query that contains multiple
# simple queries that get joined together by a given field) all the required information is
# present and looks sane.  This way I don't have to do it later.
#
sub _check_report_queries {
    my $qname = shift;

#
# strictly speaking this isn't a 'check' type of thing.  However, it is the most
# convientient place to take care of defining these variables.
# We need to add an index column to the report dimensions if this is set up as
# an 'autoindex' type of report.
#
    if ( exists $Queries{$qname}->{index}
        && !exists $Queries{$qname}->{dimensions} )
    {
        $Queries{$qname}->{dimensions} = 'index';
        if ( exists( $Queries{$qname}->{facts} ) ) {
            $Queries{$qname}->{facts} .= ' index';
        }
        else {
            $Queries{$qname}->{facts} = ' index';
        }
    }

#
# check if the report definition contains the required dimensions and fact entries.
# All reports need at a minumum a single fact column (how the query results are joined)
# and some report dimensions (what fields are to be carried forward to the report output)
#

    if ( !exists $Queries{$qname}->{dimensions} ) {
        die
"A report must define the 'dimensions' (table headings used in the report) for the report\n";
    }

    if ( !exists $Queries{$qname}->{facts} ) {
        die
"A report must define the 'facts' (heading that join the various queries) for the report\n";
    }

    #my @sql_list = @{$Queries{$qname}->{sql}};
    #for my $sql (@sql_list){
    #    print "report sql = $sql\n";
    #}

}

#
# Verify that the query definitions are sane.
#
sub _check_query_defs {
    my $query_index;

    for my $qname ( keys %Queries ) {
        $VERBOSE && print " checking query... $qname\n";

        if ( !exists $Queries{$qname}->{sql} &&
                 !exists $Queries{$qname}->{sqlfile} ) {
            die
"The query $qname definition must contain at least one sql query!\n";
        }

        if ( !exists $Queries{$qname}->{database} ) {
            die "The query $qname needs a database definition!\n";
        }

        if ( !exists $Database{ $Queries{$qname}->{database} } ) {
            die
"The database $Queries{$qname}->{database} used in query $qname not defined in database list\n";
        }

        if ( ref( $Queries{$qname}->{sql} ) eq 'ARRAY' ) {
            _check_report_queries($qname);
        }

        if ( !exists $Queries{$qname}->{mode} ) {
            set_output_mode_by_defn($qname);
        }
    }

    # need to see if the queries list is empty!
    if ( !%Queries ) {
        croak
          "ERROR: Query 'No Query could not be found in definitions file.\n";
    }

    return 1;
}

#
# Load the query information from a file.
# This file is the power of the script and so I wanted to keep the format as flexible as
# possible.  I used the Config::General module before and it should would well here.
# There are currently two separate section in the file: the database definitions, and the
# actual query definitions.  There will be a sepeate POD section to describe the file format.
# In the end there will be 2 hashes defined: Databases{} with database information, and
# Queries{} that hold the query infomation.
#
sub load_query_definitions {
    my $buffer;
    my $query_file;

    if ( defined $input_query_file ) {
        $query_file = $input_query_file;
    }
    else {
        die "No query definitions specified\n";
    }

    my %hash = _load_and_parse_config_file($query_file);

    %Database = %{ $hash{database} };
    %Queries  = %{ $hash{queries} };

    _check_db_defs();

    _check_query_defs();

    _check_all_query_mode();

    if ( defined $list_queries ) {
        list_queries();
        exit 0;
    }

    #print Data::Dumper->Dump( [ \%Queries ], ['*Queries'] );

    return 1;
}

#
# simple routine to just list out the queries defined in the query
# file.
#
sub list_queries {
    print "Databases Defined:\n";
    for my $dblist ( keys %Database ) {
        print "   $dblist\n";
    }

    print "Queries Defined:\n";
    for my $qname ( keys %Queries ) {
        print "   \'$qname\'\n";
    }
    return 1;
}

#
# routine to do a variable substitution on the query to replace variables
# that might need to change from run to run (like a date)
#
sub process_replace_vars {
    my $query_name = shift;

    # check the variable substitution names versus the names in the query file
    if ( !exists $Queries{$query_name}->{var} ) {
        return 1;
    }

    if (%replace_vars) {
        $VERBOSE && print "Check substitution variables...\n";
        my %varlist = %{ $Queries{$query_name}->{var} };
        for my $check_var ( keys %replace_vars ) {
            $VERBOSE
              && print "check var $check_var against Queries list...\n";
            if ( !exists $varlist{$check_var} ) {
                die
"The variable $check_var does not exist in the $query_name query\n";
            }

 # add a special rule to allow the replacement of a variable called 'today' with
 # a formatted date/time string suitable for inclusion in a database.
            if ( $replace_vars{$check_var} =~ /\'today\'/ismx ) {

                # find out the type of database we are connecting to...
                my $dba =
                  $Database{ $Queries{$query_name}->{database} }->{adapter};

                # print "process a 'today' replacements for database $dba\n";
                if ( $dba =~ /Oracle/ismx ) {
                    my $ora_today = strftime '%d-%b-%Y', localtime;
                    $replace_vars{$check_var} = q{'} . $ora_today . q{'};
                }
            }

            $Queries{$query_name}->{var}{$check_var} =
              $replace_vars{$check_var};
        }
    }

    return 1;
}

#
# set an array of headings used for outputs
#
sub setup_table_headers {
    my $query_name = shift;
    my $header_ref = shift;

    my %header_map;
    my @headers     = @{$header_ref};
    my @table_array = @{$Rows};

    #print "setup_table_headers...\n";
    #print Data::Dumper->Dump( [ \@table_array ], ['*table_array'] );

    foreach my $col ( keys %{ $table_array[0] } ) {
        push @headers, $col;
        $header_map{$col} = 1;
        $VERBOSE && print "Header map: '$col'\n";
    }

    if ( defined $query_name ) {
        #print "... query_name defined: $query_name\n";
        if ( exists $Queries{$query_name}->{order} ) {
            undef @headers;
            my @order = split /\s+/sxm, $Queries{$query_name}->{order};
            #print "in order clause of setup_headers: ", join(" ", @order), "\n";
            for my $hdr (@order) {
                $VERBOSE && print "Header Order: '$hdr'\n";
                if ( $hdr =~ /\%SKIP=(\d+)\%/sxm ) {
                    my $skip = $1;
                    if ( $Queries{$query_name}->{mode} = CSV ) {
                        next;
                    }

                    # in prep of handling skipped/blank fields in reports
                    #print " ... process skip $skip in setup_table_headers\n";
                    for my $skip_count ( 1 .. $skip ) {
                        push @headers, q{};
                    }
                    next;
                }
                if ( !exists $header_map{$hdr} ) {
                    die "No row header that matches order heading $hdr\n";
                }
                else {
                    delete $header_map{$hdr};
                }
                push @headers, $hdr;
            }
            $VERBOSE
              && print
              "Left over items in the fact list not in the order list\n";
            for my $nm ( keys %header_map ) {
                $VERBOSE && print "   ... $nm\n";
                push @headers, $nm;
            }
        }
    }

    return @headers;
}

#
# Dump an ascii formatted table from the database output.
# ascii formatted tables from the database information.
#
sub write_formatted_table {
    my $query_name = shift;
    my $_outfile = shift;
    my $table      = Text::ASCIITable->new();
    my @headers;

    my @table_array = @{$Rows};

    @headers = setup_table_headers( $query_name, \@headers );
    $table->setCols(@headers);

    for my $row (@table_array) {
        my @varray;
        for my $j (@headers) {
            my $value = $row->{$j};
            if ( !defined $_outfile 
                && $j =~ /description|request_reason|_comment/isxm )
            {
                $value = shorten_message( $value, $shorten_long_fields );
            }

            if ( defined $value ) {

                # testing a fix to remove extra Win32 newlines from the output
                $value =~ s/\015\n*//gsxm;
            }
            push @varray, $value;
        }
        $table->addRow(@varray);
        undef @varray;
    }

    $OUTFH = _set_output_handle($_outfile);

    print {$OUTFH} $table;
    undef $table;

    close $OUTFH
      || die "Cannot close output file $_outfile\n";

    undef $OUTFH;
    return 1;
}

#
# All parts of the method to output a CSV formatted table.  It includes a couple
# of helper methods as well.
#

# combine array fields into a csv string
sub _csv_combine {
    my $csv       = shift;
    my $array_ref = shift;
    my @array     = @{$array_ref};

    my $hdrstatus = $csv->combine(@array);
    my $hdrline   = $csv->string();
    if ( !defined $hdrline ) {
        die 'Bad CSV combine: ' . $csv->error_diag() . "\n";
    }
    return $hdrline;
}

# combine array of arrays fields into a csv string
sub _csv_aofa_combine {
    my $csv       = shift;
    my $array_ref = shift;
    my @array     = @{$array_ref};

    #print Data::Dumper->Dump( [ \@array ], ['*array'] );

    my $long_line = q{};
    for my $i (@array) {
        my @line = @{$i};
        my $output_line = _csv_combine( $csv, \@line );
        $long_line .= $output_line . "\n";
    }
    return $long_line;
}

# write the csv file
sub write_csv_file {
    my $query_name = shift;
    my $_outfile = shift;
    my @headers;
    my @lines_array;

    my @table_array = @{$Rows};

    @headers = setup_table_headers( $query_name, \@headers );

    my $csv = Text::CSV->new( { binary => 1 } );

    # print headers
    my $hdrstatus = $csv->combine(@headers);
    my $hdrline   = $csv->string();
    if ( !defined $hdrline ) {
        die 'bad CSV combine: ' . $csv->error_input() . "\n";
    }

    # print each row in the table
    for my $row (@table_array) {
        my @varray;
        for my $j (@headers) {
            my $value = $row->{$j};
            if ( defined $value ) {
                $value =~ s/\015\n*//gsxm;
            }
            push @varray, $value;
        }

        push @lines_array, [@varray];
        undef @varray;
    }
    my $outlines = _csv_aofa_combine( $csv, \@lines_array );

    $OUTFH = _set_output_handle($_outfile);

    print {$OUTFH} "$hdrline\n" if ( !$no_report_headers && !$append_mode );
    print {$OUTFH} "$outlines";

    close $OUTFH
      || die "Cannot close output file $_outfile\n";

    undef $OUTFH;
    return 1;
}

#
# perl Data::Dumper output mode
#
sub write_struct_file {
    my $query_name = shift;
    my $_outfile = shift;

    $OUTFH = _set_output_handle($_outfile);

    print {$OUTFH} Data::Dumper->Dump( [ \$Rows ], ['*Rows'] );

    close $OUTFH
      || die "Cannot close output file $_outfile\n";
    undef $OUTFH;
    return 1;
}

#
# yml output mode
#
sub write_yaml_file {
    my $query_name  = shift;
    my $_outfile = shift;
    my @table_array = @{$Rows};

    my $dumper = YAML::Dumper->new;
    $dumper->indent_width(4);

    $OUTFH = _set_output_handle($_outfile);

    print {$OUTFH} $dumper->dump(@table_array);

    close $OUTFH
      || die "Cannot close output file $_outfile\n";
    undef $OUTFH;
    return 1;
}

#
# json output mode
#
sub write_json_file {
    my $query_name  = shift;
    my $_outfile = shift;
    my @table_array = @{$Rows};

    $OUTFH = _set_output_handle($_outfile);

    my $json_text = to_json( $Rows, { ascii => 1} );
    print {$OUTFH} "$json_text\n";

    close $OUTFH
      || die "Cannot close output file $_outfile\n";
    undef $OUTFH;
    return 1;
}

#
# create a connection to the database
#
sub connect_to_db {
    my $query_name = shift;
    my $db_string = $Queries{$query_name}->{database};

    if ( !$db_string ) {
        die "DB string not defined in configuration\n";
    }

    if ( !exists $Database{$db_string} ) {
        die "Cannot find database $db_string in configuration\n";
    }

    if ( !exists $Database{$db_string}->{connect_string} ) {
        die "No connect string defined in database: $db_string\n";
    }
    my $connect_string = $Database{$db_string}->{connect_string};
    $connect_string =~ s/\'//sxmg;

    # allow for no user or password setting for database.
    my $user;
    if ( exists $Database{$db_string}->{user} ) {
        $user = $Database{$db_string}->{user};
        $user =~ s/\'//sxmg;
    }
    else {
        $user = undef;

        #$user = q{};
    }

    my $password;
    if ( exists $Database{$db_string}->{password} ) {
        $password = $Database{$db_string}->{password};
        $password =~ s/\'//sxmg;
    }
    else {
        $password = undef;

        #$password = q{};
    }

    # review the sql query specified and replace interpolated variables
    # and the date/time query information for an Oracle database.
    # the return will be a string or and error.
    my %db_options = ( RaiseError => 1, AutoCommit => 0 );

    if ( exists $Database{$db_string}->{mode} ) {
        if ( $Database{$db_string}->{mode} =~ /read-?only/ismx ) {
            $db_options{ReadOnly} = 1;
        }
        else {
            warn
"WARNING:  Ignorring database mode.  only valid mode is 'read-only'\n";
        }
    }

    # connect to the specified database server
    $VERBOSE && print "connecting to $db_string: $connect_string\n";
    my $dbh;
    if ( $connect_string =~ /ODBC/sxm ) {
        $dbh =
          DBI->connect( $connect_string, $user, $password,
            { odbc_async_exec => 1, RaiseError => 0, AutoCommit => 0 } );
          if (! $dbh){
              connect_alert($query_name);
              croak $DBI::errstr;
          }
    }
    else {
        $dbh =
          DBI->connect( $connect_string, $user, $password,
            { RaiseError => 1, AutoCommit => 0 } )
          or croak $DBI::errstr;
    }

    # review the sql query specified and replace interpolated variables
    return $dbh;
}

#
# Load a sql query from a file instead of embedded in the query definition
#
sub sql_from_file {
    my $filename = shift;
    my $sqlfile;
    my $buffer;

    open $sqlfile, '<', $filename
      or die "Cannot open sql file $filename for reading: $ERRNO\n";
    while (<$sqlfile>) {
        if (/^ [#] /sxm) {
            next;
        }
        $buffer .= $_;
    }
    close $sqlfile
      or die "Bad close of sql file.\n";

    $buffer =~ s/\n/ /gsxm;
    $buffer =~ s/\s+/ /gsxm;

    if ( !defined $buffer ) {
        die "Error: empty sql file: $filename\n";
    }

    return $buffer;
}

#
# factored out a section of the code used to check and validate the actual sql
# query that will be sent to the database.
#
sub prepare_query {
    my $query_name = shift;
    my $sql_index  = shift;
    my $sql;
    my $dbh_rc;

    if ( exists $Queries{$query_name}->{sqlfile}) {
        $sql = sql_from_file($Queries{$query_name}->{sqlfile});
    } 
    else {
        # need to select a single query if there are more than one is defined
        # in a database query
        if ( ref( $Queries{$query_name}->{sql} ) eq 'ARRAY' ) {

            # there are more than one sql string defined for this query
            my @array = @{ $Queries{$query_name}->{sql} };
            if ( !defined $sql_index ) {
                die "An index must be provided for multi-sql queries\n";
            }
            if ( !defined $array[$sql_index] ) {
                die "Indexed sub-query $sql_index not found in query $query_name\n";
            }

            $sql = $array[$sql_index];
        }
        else {
            $sql = $Queries{$query_name}->{sql};
        }
    }

    #
    #  prepare autoindex.  This should be atomic by moving it out of
    #  the query loop and using a simple check for a date/time/counter
    #  to use for the index.

    if ( exists $Queries{$query_name}->{index} ) {

        #print "  ... insert index timestamp\n";
        if ( $Queries{$query_name}->{index} eq 'autodate' ) {

            #print "  ...    autodate\n";
            $sql =~ s/^[']?\s*SELECT\s*/SELECT Current_Date as "index", /sixm;
        }
        elsif ( $Queries{$query_name}->{index} eq 'autotime' ) {
            $sql =~
s/^[']?\s*SELECT\s*/SELECT \'$report_start_time\' as "index", /sixm;
        }
    }

    $sql = fix_query( $query_name, $sql )
      or die "Query $query_name could not be 'fixed'\n";

    if ( $sql !~ /^[']? \s* select \s+/isxm ) {
        print "sql=$sql\n";
        die "Query must be a simple 'SELECT'.  This is a safety feature: \'$sql\'\n";
    }

    $VERBOSE && print "End prepare_query SQL: $sql\n";
    return $sql;
}

#
# Manage a list of column name aliases
#
sub map_column_names {
    my $query_name = shift;
    my $sql_index  = shift;

    if ( !exists $Queries{$query_name}->{map} ) {
        return 1;
    }

    my %maps;
    if ( defined $sql_index ) {
        %maps = %{ $Queries{$query_name}->{map}[$sql_index] };
    }
    else {
        %maps = %{ $Queries{$query_name}->{map} };
    }

    my @table_array = @{$Rows};
    for my $map ( keys %maps ) {
        for my $row (@table_array) {

            # rows
            if ( !exists $row->{$map} ) {
                die "No row named $map in rows extracted from database\n";
            }
            $row->{ $maps{$map} } = $row->{$map};
            delete $row->{$map};
        }
    }

    return 1;
}

sub fix_query {
    my $query_name   = shift;
    my $query_string = shift;

    my %query = %{ $Queries{$query_name} };

    $VERBOSE && print "start query string = $query_string\n";

    $query_string =~ s/\n//sxm;
    $query_string =~ s/\s+/ /sxm;
    $query_string =~ s/^\'\s*//sxm;
    $query_string =~ s/\s*\'$//sxm;

    $query_string =~ s/MAX\s*[(]\s*/MAX\(/sxmg;
    $query_string =~ s/\s*[)]/\)/sxmg;

    $VERBOSE && print "Query String before fix: $query_string\n";
    if ( $Database{ $query{database} }->{adapter} =~ /oracle/ismx ) {

        # only apply to the selector part of the SELECT clause
        $VERBOSE && print " ... apply Oracle date/time fixes\n";
        my $token;
        my $rest         = $query_string;
        my $build_string = q{};
        while ( length($rest) > 0 ) {
            ( $token, $rest ) = split /\s+/sxm, $rest, 2;
            if ( $token =~ /where|from/isxm ) {
                $build_string .= $token . q{ };
                last;
            }
            if ( $token =~ /select/isxm ) {
                $build_string .= $token . q{ };
                next;
            }

            if ( $token =~ /AL\d+.ACTION_START_DATE,?/sxm ) {
                my $past_token = $token;
                $VERBOSE && print "        ... fix date token $token\n";
                my $comma_after;
                if ( $past_token =~ /\,$/sxm ) { $comma_after = 1; }
                $past_token =~ s/\,$//sxm;
                $token =
"TO_CHAR($past_token,'mm/dd/yyyy hh24:mi:ss') ACTION_START_DATE";
                if ( defined $comma_after ) {
                    $build_string .= $token . ', ';
                }
                else {
                    $build_string .= $token . q{ };
                }
                next;
            }
            $VERBOSE && print "    ... token $token\n";
            $build_string .= $token . q{ };
        }
        $build_string .= $rest;
        $query_string = $build_string;
    }

    if ( exists $query{var} ) {
        $VERBOSE && print " ... interpolate query variables\n";
        for my $var ( keys %{ $query{var} } ) {
            my $value = $query{var}->{$var};
            $VERBOSE && print "    ... apply variable $var = $value\n";
            $query_string =~ s/\%$var\%/$value/sxmg;
        }
    }

    #$VERBOSE && print "Query String after fix: $query_string\n";
    return $query_string;
}

#
# Submit a single database query and return the results.
# The workhorse routine of the script to do the actual database work.
# This routine should work for any DBD defined routine.  By the end this
# routine will need severe refactoring.
#
sub submit_single_query {
    my $query_name = shift;
    my $sql_index  = shift;
    my $sql;
    my $dbh_rc;

    # connect to the database specified in the query
    $VERBOSE && print "Connect to db: $query_name, $Queries{$query_name}->{database}\n";
    my $dbh = connect_to_db( $query_name );

    $DEBUG && $dbh->debug(7);

    # need to select a single query if there are more than one is defined
    # in a database query
    $sql = prepare_query( $query_name, $sql_index )
      or croak $DBI::errstr;

    # create the database query handle
    if ( defined $check_mode ) {
        $dbh_rc = $dbh->commit
          or croak $DBI::errstr;

        $dbh_rc = $dbh->disconnect
          or croak $DBI::errstr;
        return 1;
    }

    $Rows = $dbh->selectall_arrayref( $sql, { Slice => {} } )
      or croak $DBI::errstr;

    $VERBOSE
      && print "disconnecting from $Queries{$query_name}->{database}\n";
    $dbh_rc = $dbh->commit
      or croak $DBI::errstr;

    $dbh_rc = $dbh->disconnect
      or croak $DBI::errstr;

    my @table_array = @{$Rows};

    $VERBOSE && print Data::Dumper->Dump( [ \$Rows ], ['*Rows'] );

    #exit;

    # apply column name aliases
    map_column_names( $query_name, $sql_index );

    return 1;
}

#
# manage the output formatting of the reports, what type of report and what other checks
# need to be made.
#
sub write_output {
    my $query_name = shift;
    my $outfile;

    if ( ! defined $query_name ) {
        die "No query name defined in write_output!\n";
    }

    $VERBOSE && print "Start 'write_output' routine: $query_name\n";

    if ( defined $check_mode ) {
        return 1;
    }

    if ( defined $input_outfile ) {
        if ( $input_outfile ne q{-} ) {
            $outfile = $input_outfile;
        }
    }
    else {
        if ( defined $Queries{$query_name}->{output} ) {
            $outfile = $Queries{$query_name}->{output};
        }
    }

    if ( defined $query_name ) {
        check_alerts($query_name);
    }

    if ( $Queries{ $query_name }->{mode} == TABLE)
    {
        if ( defined $outfile ) {
            print
"Default csv mode selected for output to a file when no mode is selected\n";
            $Queries{ $query_name }->{mode} = CSV;
        }
        else {
            write_formatted_table($query_name, $outfile);
            return 1;
        }
    }

    if ( $Queries{ $query_name }->{mode} == YAML) {
        write_yaml_file($query_name, $outfile);
        return 1;
    }

    elsif ( $Queries{ $query_name }->{mode} == JSON) {
        write_json_file($query_name, $outfile);
        return 1;
    }

    elsif ( $Queries{ $query_name }->{mode} == CSV) {
        write_csv_file($query_name, $outfile);
        return 1;
    }

    elsif ( $Queries{ $query_name }->{mode} == PERL) {
        write_struct_file($query_name, $outfile);
        return 1;
    }


    return 1;
}

#
# Manage queries that are requested on the command line.
# Create a Query structure on the fly to let us run everything through
# the same logic later.
#
# We need to either validate or create a database entry and then
# create the query entry.
#
sub preprocess_adhoc_query {

    my $query_name = 'adhoc';
    my ($dbi, $dbtype, $dbname);

    # run a single ad-hoc query as specified on the command line
    if ( !defined $input_dbsel ) {
        die "No database selected for query!"
    }

    if (index($input_dbsel, ":") == -1){
        if ( !exists $Database{$input_dbsel} ) {
          die
    "Cannot find the selected database.  Try using '--list' to see list of defined databases\n";
        }
        $dbname = $input_dbsel;
    } else {
        #print "extract database defn directly from command line...\n";
        ($dbi, $dbtype, $dbname) = split(":", $input_dbsel);
        #print " ... type = $dbtype\n";
        #print " ... dbname = $dbname\n";
        $Database{$dbname}->{adapter} = $dbtype;
        $Database{$dbname}->{connect_string} = $input_dbsel;
    }

    $Queries{$query_name} = {};
    $Queries{$query_name}->{database} = $dbname;

    if (defined $input_sqlfile) {
        $Queries{$query_name}->{sqlfile} = $input_sqlfile;
    } else {
        $VERBOSE && print "SQL=$input_sql\n";

        if ( $input_sql !~ /^[']? \s* select \s+/isxm ) {
            die "Query must be a simple 'SELECT'.  This is a safety feature: $input_sql\n";
        }

        $Queries{$query_name}->{sql} = $input_sql;
    }

    return 1;
}

#
# Manage queries that are stored in the query definitions file (as apposed to ad-hoc queries
# specified on the command line).
#
sub handle_file_query {
    my ( $tmp_query_name, $tmp_index ) = split /:/sxm, $input_query_name, 2;
    process_replace_vars($tmp_query_name);

    # handle all the queries in the report and join into the full report
    #   ... single file query is a special case of this clause
    if ( ref( $Queries{$tmp_query_name}->{sql} ) eq 'ARRAY'
        && !defined $tmp_index )
    {
        #print "submit full report\n";
        submit_report_queries($tmp_query_name);
        write_output($tmp_query_name);
    }
    else {
        #print "submit a single query: $tmp_query_name\n";
        submit_single_query( $tmp_query_name, $tmp_index );
        write_output($tmp_query_name);
    }
    return 1;
}

#
# REPORT:
# Emulate a simple report query.
#
#         dimensions="DESIGN_TASK_ID RETICLE_DESIGN_ID RETICLE_ORDER_ID"
#         facts="DESIGN_TASK_ID READY_DATE PREVIEW_DATE ORDER_DATE CLOSE_DATE COMPLEXITY RETICLE_DESIGN_NAME PROJECT_NAME PROJECT_REV_NAME %SKIP=1% LAYOUT_DESIG        NER %SKIP=16% REQUESTER DIE_DESIGN_COUNT %SKIP=1% STD_PRICE_DOLLARS TURNAROUND %SKIP=1% DESIGN_TASK_TYPE FIELD_INDEX RETICLE_DESIGN_ID RETICLE_ORDER_ID"

#    1. Need to submit each query in the report
#    2. Remap any column names to those used in the report (also handled in the query submit)
#    3. Save the columns that are required in the final report
#    4. Join the columns into a final output set
#    5. Output the report
#
#    Report Terminology based on hyperion engine:
#       Join queries based on the 'dimensions' variable
#       Report output fields based on the 'facts' field
#
#    What do we have?
#    1 - A simple list of header names used to join the report together.  Each
#        sub-query must contain all of the items in this list, and the hash of
#        these items must be unique.
#    2 - A list of all of the query columns to be included in the final report.
#        These are the post-mapped column names.
#    3 - An array of queries used to supply the data for the report.  Each
#        array slice has the SQL for the actual database query and a possible
#        name map to rename the query's returrned fields,
#

#    process:
#    Input: Name of report query.
#
#    1 - Check

sub submit_report_queries {
    my $query_name = shift;

    my %report_rows;

    # setup some convienence references (and convert the two lists to hashes for
    # easy lookup) see: http://www.perlmonks.org/?node_id=2482
    my @query_list = @{ $Queries{$query_name}->{sql} };
    my %report_dimensions;
    @report_dimensions{ split /\s+/sxm, $Queries{$query_name}->{dimensions} } =
      ();

    my %report_facts;
    my @facts_list = split /\s+/sxm, $Queries{$query_name}->{facts};

    # check if an 'order' line is specified for this report and if it is not
    # then create a synthetic version using the facts line
    if ( !exists $Queries{$query_name}->{order} ) {
        $Queries{$query_name}->{order} = $Queries{$query_name}->{facts};
    }

    # remove the required headers from the facts list so that we don't need to
    # remove them within the loop later.  This is just easier.
    @facts_list = grep { !exists $report_dimensions{$_} } @facts_list;

    # convert the list to a hash
    @report_facts{@facts_list} = ();

    $VERBOSE
      && print 'Facts list from start of report: '
      . join( ', ', @facts_list ) . "\n";

    #
    # loop through each sql statement that makes up a segment of the report.
    #
    for my $query_index ( 0 .. $#query_list ) {

        $VERBOSE
          && print "$query_index: submit query  "
          . shorten_message( $Queries{$query_name}->{sql}[$query_index], 60 )
          . "\n";

        # send the single query out to be processed...
        submit_single_query( $query_name, $query_index );

        # if we are in check mode, then just return now.  Don't worry about
        # building the report
        if ($check_mode) {
            return 1;
        }

        # note that at this point we should have a @$Rows defined.
        if ($VERBOSE) {
            print Data::Dumper->Dump( [ \$Rows ], ['*Rows'] );
        }

        # c - check that all of the fields named in the 'dimensions' list are
        # included
        $VERBOSE
          && print "Facts list after query $query_index : "
          . join( ', ', keys %report_facts ) . "\n";
        $VERBOSE
          && print "Dimension list after query $query_index : "
          . join( ', ', keys %report_dimensions ) . "\n";

        my @table_array = @{$Rows};
        for my $dimension ( keys %report_dimensions ) {
            if ( !exists $table_array[0]->{$dimension} ) {
                die
"Table $query_index does not contain the column heading $dimension\n";
            }

#$VERBOSE && print " ... matched report dimension $dimension in query $query_index\n";
        }

        #$VERBOSE && do {
        #    for my $result_hdr (keys %{$table_array[0]}) {
        #        print "Query $query_index has element: $result_hdr\n";
        #    }
        #};

        # d -    foreach row in the array (step through the @Rows array)...
        for my $query_row_ref (@table_array) {

            #print "the query_row element is a " . ref($query_row) . "\n";
            # it should be a hash...
            my %query_row = %{$query_row_ref};

            my $hash_key;
            for my $dim ( keys %report_dimensions ) {
                $hash_key .= $query_row{$dim} . q{+};
            }
            $hash_key = md5_hex($hash_key);

         #$VERBOSE && print "  ... hash key for report dimensions: $hash_key\n";

            # d (post) - foreach field in the 'dimensions' list...
            for my $dim ( keys %report_dimensions ) {

                # push a copy of the dimension elements into the report
                if ( exists $report_rows{$hash_key}->{dim} ) {
                    die "Duplicate row: $hash_key, dimension=$dim\n";
                }
                $report_rows{$hash_key}->{$dim} = $query_row{$dim};

# $VERBOSE && print "  ... report row $hash_key, dimension $dim => $query_row{$dim}\n";
# No row header that matches order heading start_timestamp

            }    # ...done with the dimensions

            # e - foreach field in the 'facts' list...
            for my $fact ( keys %report_facts ) {

             # f - see if the 'fact' name is in the current @Row (cache the name
             #     if it is found on the row.
                if ( !exists $query_row{$fact} ) {

# g - if not then go to the next fact...
#$VERBOSE && print " $fact loop: fact row does not exist in query results definition\n";
                    next;
                }

       # h - if found then add it to a temporary row build from the 'fact' names
                $report_rows{$hash_key}->{$fact} = $query_row{$fact};

#print " $fact loop: Add to report $hash_key,  $report_rows{$hash_key}->{$fact}\n";

            }    # ...done with the fact rows
        }
    }

    my @table_array;
    for my $key ( keys %report_rows ) {
        push @table_array, $report_rows{$key};
    }

    # compute the end time and the report time interval
    my $report_end_time = strftime '%Y-%m-%d %H:%M:%S', localtime;
    $report_start_time =~ s/_/ /sxgm;

    my $date1 = Date::Manip::Date->new();
    my $err   = $date1->parse($report_start_time)
      && die
      "Bad parsing of starting date/time stamp string: $report_start_time\n";
    my $date2 = $date1->new_date;
    $err = $date2->parse($report_end_time)
      && die
      "Bad parsing of ending date/time stamp string: $report_start_time\n";
    my $delta = $date1->calc($date2);

    my $delta_str = $delta->printf('%mv:%sv');

    #print "Report Run Time = $delta_str secs\n";
    $table_array[0]->{runtime} =
      ( $delta->value() )[5] * 60 + ( $delta->value() )[6];

    undef $Rows;
    $Rows = \@table_array;

    return 1;
}

#
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

    if ( defined $input_query_file ) {
        load_query_definitions();
    }

    if ( defined $input_sql || defined $input_sqlfile ) {
        $input_query_name = "adhoc";
        preprocess_adhoc_query();
    }

    set_output_mode_by_defn($input_query_name);
    handle_file_query();

    exit 0;
}

# make this look like a module... for testing.
1;

__END__

=pod

=head1 NAME

QueryBroker.pl - Execute database queries

=head1 SYNOPSIS

QueryBroker.pl --list

QueryBroker.pl --db=<dbname> --sql=<input_sql> [--check] [--mode=perl|yaml|json|csv|table] 

QueryBroker.pl --query=<query_name> [--out=<file>]

=head1 DESCRIPTION

B<QueryBroker.pl> was born from my frustration dealing with internal
HP IT policies and my inability to have a relatively simple database
query scheduled to be ran every morning for my group's metrics report.
While there is a corporate infrastructure available to run scheduled
queries, it was overloaded with business objects and required way too
much work to set up.  IT also refused to add our simple daily queries
to their already overloaded stack.

I was also frustrated when I needed to run a one-time (ad-hoc) database
query.  I would have to fire up one of a few applications (squirrel, toad,
sqlplus) and work out the query.  I then didn't always save these ad-hoc
queries and a number of times would have to redo my work to recreate
the query (I know this one is my own fault).

When I moved to the Big Data world, I now almost live in these SQL tools
for most of the day (my favorite today is squirrel, but I still run toad
a lot as well).  We also use Qlikview quite a bit as well. As we look
to track certain data issues, we need to run some set of standardized
queries on a regular basis and then save the results to another reporting
database.  I tried to use the Toad automation to run som of these queries,
but it is dependent on: my PC being on, and it being connected to the
HP network.

I decided that the most efficient way to manage all these requirements
was to create my own version of a query engine.  A program that would
launch specific queries on a given database (not hardcoded) and then save
the results to a file that I can import into my metrics tables later
(usually via a text CSV file that I import into excel).  I also have
found that I would also like a path to save report fields to an output
database table in order to track it during time.

I decided that I would make the program a bit more generic and allow
it to connect to not just one enterprise database (Oracle, Vertica),
but to any database that can be managed via the perl DBD routines.
The only requirement is that the database conform to the more standard
database control methods defined in the DBD routines (for instance some
of the file based modules do not have a 'connect' method).

=head1 OPTIONS

Note that the order of preference is for global->file->command_line.  If
an option is specificed on the command line then it will take precidence.

=over 8

=item B<--check>

Check the valdity of the input query and/or the query file definitions

=item B<--sql>

Specify an ad-hoc query directly on the command line.  The database will 
need to be specified using the B<--db> option, and variable replacement
is not available with direct SQL entry.

=item B<--db>

Specify the database to use for the query.  Note that this command will 
override the database specified in the query definition file if used.

=item B<--query|qn>

Run the specified query that is defined in the query definition file.  
To get a list of the names of the defined queries, you can use the B<--list> 
command.

=item B<--query_file|qf>

Specify an alternate query definitions file.  See the section below
which describes the format of the file.  The default file name is 
B<querybroker.query>.

=item B<--mode>

=over 8

=item B<table>

The output will be written as a simple table.  The headings are derived
from the names of the hash names, with the order of the headings possibly
changed by the B<order> section of the query file.

=item B<perl>

Write the output using the standard perl Data::Dumper module of the entire
@Rows structure.  This is useful for debugging the script, as well as
to be used for importing into other perl scripts.

=item B<csv>

Write the output as a standard windows compatible comma-separated-values file.
This is extremely useful for importing into metrics reports in excel.

=item B<yaml>

Write the output using the perl YAML writer.  This is similar to the B<perl>
mode, but is supposedly more human readable.

=item B<json>

Write the output as a json formatted string.  This is useful to create a compact
string output to push into a database.

=back

=item B<--append_mode>

Append output file mode.  This option will not output table headers to allow the
data to be appended to an existing file.  Also the file is opened in append
mode and not new file mode.  Very useful for CSV mode.

=item B<--out>

Define an output file to write the query results.  The other
program responses (including any verbose or diagnostic output messages)
are still reported back to the console.

=item B<--var=string>

Defines a simple variable substitution to use for replacing strings in the
SQL queries.  This is particularly useful to replace dates in a generic
metrics query.  This command is only available when a query file is used
(since that is the only place where the 'var' section is defined). 
Multiple variables can be defined either by including multiple B<--var>
options on the command line, or by separating multiple sets of variables
with commas.

Be careful with including quotes in the variables
(i.e. START_REPORT_DATE='01-Jan-2009') since the command line parser
will remove unprotected quotes; the best method is to enclose the entire
replacement string with double quotes.

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

=head1 Query Definitions File

This is the driver file for the query broker script.  The script will
ignore any white space and ignore anything that comes after a hash '#'
mark (script style comments).  The format is based loosely on the apache
web server configuration file format.  Everything is in a block that is
bounded by <start> </start> breaks (and yes they are case sensitive).

There are two (2) main sections to the file:

1: Database

   The Database section (bounded by the tags '<database> and </database>)
   defines the actual database connections that are to be used for
   the queries.  This is abstracted out of the actual query to allow
   the connection information to be shared between multiple queries, and
   direct ad-hoc sql queries.

   The format of this section contains the following keyword:

      user:            The database user name
      password:        The database password for the user.
      adapter:         The type of database to be used (i.e. Oracle or mysql).  
                            This should match the DBD name for that database.
      connect_string:  The critical string used to establish connection to 
                            the database.  Please refer to the information contained 
                            in 'perl5doc DBI' for more detail on the specific 
                            format of this string.

2: Queries

   The queries section (bounded by the tags <queries> and </queries>)
   defines the queries that are to be made against the database and how
   to format the output and where to place the results.  The queries
   section uses the following keywords:

      database:  Name of the database (as defined in the 'Database' section) 
                    to be used for the query

      mode:      (optional) Used to control the formatting of the results.
                    There are five modes currently defined: table, csv, perl,
                    json and yaml.  If a mode is specified on the command 
                    line it takes precidence.  If mode is not specified in 
                    either the command line, or here in the query file then
                    it will default to 'table' mode.

      <var>      A special section that allows the definition of variables
                    that will be used to replace information in the sql query
                    string.  The main place it is normally used is to abstract
                    the actual query dates from the queries and allow them to
                    be managed separately.  When the queries are processed,
                    any variables are substituted in the query where the 
                    special string %variable_name% is seen.

      alert:     Define an alert based on a database return value.
              
      output:    This section indicates the filename to write the output
                    of the database query.

      sql:       This is the main keyword of the queries section.  The 
                    text describing the SQL query is placed in this section.

=head1 DESIGN

A query configuration file is loaded that contains the definitions for
any database connections ot predefined queries.  There are two sections
defined in this file: the database connection information and the actual
query definitions.  Database connections allow a convenient way to pull
out the database information from the actual query and enable ad-hoc
queries to reference a database without having to include the entire
connection string.  The query definitions are canned SQL queries placed
against a configured database.  Besides the SQL for the query itself,
and the database pointer, it will also contain output formatting options
and special operations to perform when the query is executed.

The script also includes some basic report functionality.  A group of
queries can be joined to generate a report based on specific columns in
the results of the query set. The output of the report is then defined
for which fields from the multiple queries are included in the columns
of the final output report, and which column is to be used as the key
to join the queries.  This functionality would be very useful when you
need to create a joined query from multiple sources.  It is required
that there be a common field to join the report against.

=head1 TODO

The following is a list of features that are intended to be in this script, but have
not yet been implemented.

=head2 NEED TO HAVE FIXED:

=over 5

=item B<need to change and fix 'process_replace_vars'>

FEM: 09212009

The routine B<process_replace_vars> needs to be redone.  Right not it
does not evaluate variables that are set only in the query file, but
only when a user forces a replacement on the command line.  The order
of the loop should be reversed and all entries in the 'vars' hash 
checked.

=item B<need to support multiple fields with the same column name from
different tables in the same query>

Currently the programm keys on the base/column name and quietly ignores the
table name in saving query results.  This has problems in long queries that
look up different information in multiple tables that are however named the
same.  An example is the name of a person in two different tables where
the tables mean two totally different things.

The program will probably have to keep track of the table name in the
extraction (which is unique).

=back

=head2 WANT TO HAVE:

=over 5

=item B<Better Authentication for secured databases>

I really don't like having the database passwords enbedded in the queries file 
and adding them on the command line is equally ugly.  The method of a global
database configuration file which has an enbedded papassword is equally bad
in my opinion.

=back

=head1 AUTHOR

Floyd Moore (floyd.moore\@hp.com)

=head1 EXIT STATUS

The script should exit normally with a zero status.

=head1 ISSUES

While not a bug, there is an error exit condition where the query fails.
If the database adapter requires a specific dynamic library (e.g. the
instant client for the Oracle DBD module) and that library is not loaded
into the environment, the query will fail with module dependent behavior.
The solution is to make sure the proper dynamic libraries are set into the
environment prior to launching this script.  For example in the Corvallis
environment the setting to allow access to the Oracle database is:

    LD_LIBRARY_PATH=/apps/oracle/instantclient_10_2/linux

=head1 SEE ALSO

The user should also reference the B<querybroker.query> example query definitions file.
It is available in the distribution of this script.

=head1 LICENSE AND COPYRIGHT

(c) Hewlett-Packard Development Company LLC 2015

=cut
 
