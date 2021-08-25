#!/usr/bin/env perl5
#
#   Author:  Floyd Moore (floyd.moore\@hp.com)
#	$HeadURL: file:///var/lib/svn/repository/projects/bin/trunk/perl_header.pl $
#	Description:
#
#	"<script_name>" created by red
#
# First run this command to get the data from chief delphi:
#    curl http://www.chiefdelphi.com/forums/frcspy.php?xml=2 > frc.xml
#
#

use lib "$ENV{HOME}/src/mylib/lib/perl5";

use strict;
use warnings;
use 5.010;

use English qw( -no_match_vars );
use Getopt::Long;
use Pod::Usage;
use Carp;
use Readonly;
use File::Spec::Functions;
use File::Basename qw( basename );
use Text::CSV;
use POSIX qw(strftime);
use vars qw($xml $verbose @Matches);
use vars qw($ProgName $RunDate $Rev $DirName);
use Data::Dumper;
local $Data::Dumper::Indent = 1;

use XML::SimpleObject;

# setup runtime information
Readonly my $PROGNAME => basename $PROGRAM_NAME;
our ($VERSION) = '$Revision: 17 $' =~ / ( \d+ (?: [.] \d+ )? )/sxm;  ## no critic (RequireConstantVersion)

sub CommandVersion {
    # simply print the version number of the script
    print "$PROGNAME Revision $VERSION\n";
    exit 0;
}

my %Locations = (
	'NV' => 'Vegas',
	'ON' => 'Toronto E',
	'ON2' => 'Toronto W',
	'SJ' => 'Silicon Valley',
	'MN2' => 'North Star',
	'MN' => '10,000 Lakes',
	'TN' => 'Smoky Mtn.',
	'CT' => 'Connecticut',
	'STX' => 'Alamo',
	'OR' => 'Oregon',
	'NH' => 'BAE Granite State',
);

#############################################
# get the modification time of a file.
#
sub file_mtime {
    my $filename = shift;
    # (stat("file"))[9] returns mtime of file.
    return (stat($filename))[9];
}

#############################################
# round a number to a specified number of significant
# digits.
#
sub round {
    my $in=shift;
    my $dec=shift;

    return (int($in * 10**$dec) / 10**$dec);
}

#############################################
# Convert a number to a string with a suffix
# describing its size using engineering notation.
#
sub size_suffix {
    my $in_size=shift;
    my $KB = 1024;
    my $MB = $KB*1024;
    my $GB = $MB*1024;
    my $TB = $GB*1024;

    if ($in_size >= $TB){
       return round($in_size/$TB,2) . "Tbytes";
    }
    elsif ($in_size >= $GB){
       return round($in_size/$GB,2) . "Gbytes";
    }
    elsif ($in_size >= $MB){
       return round($in_size/$MB,2) . "Mbytes";
    }
    elsif ($in_size >= $KB){
       return round($in_size/$KB,2) . "Kbytes";
    }
    else {
       return $in_size . "bytes";
    }
}

sub write_csv_file {
    my ( $OUTFH, $oldfh );
    my $file = 'scores.csv';
    my @order = ( 'event', 'typ', 'mch', 'red1', 'red2', 'red3', 'blue1', 'blue2', 'blue3', 'rfin', 'bfin', 'rbonus', 'bbonus', 'rpen', 'bpen' );
    open $OUTFH, '>', $file ## no critic ( RequireBriefOpen )
        or croak "Cannot open the output file $file for writing: $OS_ERROR\n";

    my $csv = Text::CSV->new( { binary => 1 } );

    # print headers
    my $hdrstatus = $csv->combine(@order);
    my $hdrline   = $csv->string();
    if ( !defined $hdrline ) {
        die 'bad CSV combine: ' . $csv->error_input() . "\n";
    }
    #if ( !defined $NoCSVHeader ) {
        print { $OUTFH } "$hdrline\n";
    #}

    # print each row in the table
    my @varray;
    foreach my $idx ( 0 .. $#Matches ) {
	#print "Match $idx\n";
	my %match_data = %{$Matches[$idx]}; 
        for my $j (@order) {
            my $value = $match_data{$j};
            if ( defined $value ) {
                $value =~ s/\015\n*//gsxm;
                #print " .. $j: key=$j value = $value\n";
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

# Parse standard options from command line
Getopt::Long::Configure("bundling");
my $options_okay = GetOptions(

    # Application-specific options...

    # Standard Data Management Command Options

    # Standard meta-options
    "verbose|v" => \$verbose,
    "help|?"    => sub { pod2usage(1); },
    "version"   => sub { CommandVersion(); },
    "usage"     => sub { pod2usage( -verbose => 0 ); },
    "man"       => sub { pod2usage( -exitstatus => 0, -verbose => 2 ); },
);

# Fail if unknow arguemnts encountered...
pod2usage(2) if !$options_okay;

######################################
#  Main Program	 #####################
######################################

$verbose && print "# $ProgName  $Rev\t\t$RunDate\n\n";

our ($xmlfile) = "$ENV{HOME}/frc.xml";
open $xml, '<', $xmlfile ||
   die "Cannot read xml file: $xmlfile\n";

my $xmlobj = new XML::SimpleObject(XML => $xml, ErrorContext => 2);

close $xml;

my $match;
foreach my $element ( $xmlobj->child("matches")->children("match") ) {
    my $values = {};
    foreach my $key ( sort $element->children_names ) {
        my $value = $element->child($key)->value;
	if ($key eq 'mch'){
           $match = $value;
        }
        elsif ( $key eq 'st' or $key eq 'tim' or $key eq 'pubdate' ){
           next;
        } 

	if ( defined $value ) {
           #print "   $key = $value\n";
	   $values->{$key} = $value;
        } else {
           #print "   $key = \n";
	   $values->{$key} = '';
        }

    }

    my $event = $values->{'event'};
    if ( exists $Locations{$event} ){
        $event = $Locations{$event};
    }
    #print "Event: $event, Match: $values->{'typ'} - $match\n";
    foreach my $v ( sort keys %{$values} ){
         if ($v eq 'event' || $v eq 'typ' || $v eq 'mch'){ next; }
	 #print "   $v  $values->{$v}\n"; 
    }
    #print "\n";
    push @Matches, $values;
    undef $match;
}

# I need these columns:
# Event, Match (incl Qual, Elim, or Practice), alliances, score, bonuses, and penalties
# therefore I need to map these xml elements:
# event => event code (up to three characters)
# mch => match number
# typ => match type (P=practice, Q=qualifier, E=elimination)
#
# blue1, blue2, blue3 => blue alliance teams
# bfin, bbonus, bpen => blue score, blue bonus, and blue penalties
# red1, red2, red3 => red alliance teams
# rfin, rbonus, rpen => red score, red bonus, and red penalties
# 

write_csv_file();

__END__

=head1 NAME

frcscores.pl

=head1 SYNOPSYS

Generic Header for perl scripts

=head1 OPTIONS

=head1 DESCRIPTION

=cut
