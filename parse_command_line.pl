#######################################################################
# parse_command_line()
#    input = option string from environment
#    return = 1/0 success indicator
#  Parse command line options
#  todo:
#     Need to be able to hand single files as well as a directory of files
#     Should be able to handle the filename as a non '-'
#

sub parse_command_line {
    my $jsondir;

    # Parse standard options from command line
    Getopt::Long::Configure('bundling');
    my $options_okay = GetOptions(

        # Configuration File
        'cnf|cfg=s' => \$cfgfile,

        # Application-specific options...
        'cover=s'               => \$coverage_file,
        'counters=s'            => \$Counters_file,
        'jsondir|tmp|t=s'       => \$jsondir,
        'fields|s=s'            => \$save_field_input,

        # Standard meta-options
        'verbose|v' => \$VERBOSE,
        'help|?'    => sub { pod2usage(1); },
        'version'   => sub { CommandVersion(); },
        'usage'     => sub { pod2usage( -VERBOSE => 0 ); },
        'man'       => sub { pod2usage( -exitstatus => 0, -VERBOSE => 2 ); },
    );

    # Fail if unknown arguements encountered...
    pod2usage(2) if !$options_okay;

    # load the configuration file if it exists
    if ( $cfgfile && -r $cfgfile ) {
        print "Read variables from configuration file\n";
        load_config_file($cfgfile);
    }

    if ( $coverage_file ) {
        load_coverage_file();
    }

    # Any left over options from the commannd line are either:
    #    1 - JSON file name(s) ... add to the array for processing
    #    2 - Name of Directory containing a group of JSON files (same as --t option)
    for my $file_option (@ARGV) {
        print "file option: $file_option\n";
        if ( -d $file_option ) {
            # directory -- act like the user called the '-t' option
            $jsondir = $file_option;
        }
        elsif ( -r $file_option ) {
            # path to JSON file...
            push @JsonFileList, $file_option;
        }
        else {
            # can't read it (what ever it is)
            die "Bad filename option: $file_option\n";
        }
    }

    if ($jsondir) {
        append_json_filelist(\@JsonFileList, $jsondir);
    }

    if (! @JsonFileList ) {
        die "All Done! No JSON files specified!\n";
    }

    return 1;
}
