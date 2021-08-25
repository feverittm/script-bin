#!/usr/local/bin/perl5 -w 
# 
#       Author:  Floyd Moore (redfc.hp.com) 
#	$Header: ReadCSV.pl,v 1.2 2003/07/14 11:33:27 red Exp $ 
#	Description:
#          Read a CSV file which is written by Excel and contains
#       a new layer mapping for the beacon process.
#
#

use strict;
use subs qw(handler show_usage parse_options file_mtime round);
use POSIX qw(strftime);
use vars qw($opt_p $opt_v $opt_x $opt_V $opt_e $opt_d $opt_F);
use vars qw($opt_R $opt_c $opt_O $opt_C);
use vars qw($ProgName $RunDate $Rev $DirName $dbfile);
use vars qw(%LayerInfo %Mentor %Map);
use vars qw($ExcelFile $ProcessIn @LayerMap @LayerList);
use vars qw($optout_process $optout_gdsopt $optout_drc);
use Data::Dumper;
use Text::CSV;
use Getopt::Std;

#
# Default files for HCMOS5HV process
#
$ExcelFile="/sdg/lib/stm/release/HCMOS5HV/tech/rev1_2/BeaconLayers.csv";
$ProcessIn="/sdg/lib/stm/release/HCMOS5HV/tech/rev1_2/mentor/hcmos5.ascii";
$dbfile="/sdg/lib/stm/release/HCMOS5HV/tech/rev1_2/xref_new.db";

local $Data::Dumper::Indent=1;

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
($Rev) = q$Revision: 2 $ =~ /: (\S+)/; # Auto-updated by RCS
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName -e excel.csv [-xVvtlpcFOC]\n";
   print "   Options:\n";
   print "   -e <excel_file> Required!\n";
   print "\n";
   print " Floyd Moore \(floyd.moore\@hp.com\)\n";
   print " Script is designed to read a fomatted Comma Seperated Value(CSV)\n";
   print " file from an Excel Spreadsheet that describes the layers used\n";
   print " in a process.\n";
   print "\n";
   print "Optional Arguements:\n";
   print "   -x:        Debug mode\n";
   print "   -V:        Print Version and quit.\n";
   print "   -v:        Verbose mode\n";
   print "   -d:        Check the differences to the existing database\n";
   print "   -e <excel_file> name of the Excel spreadsheet in CSV format\n";
   print "   -p <process_file> use an existing process file for colors\n";
   print "\n";
   print "   -c <file>  Add layer colors from another process file\n";
   print "      This is a extra hack to allow extra \$set_layer_appearance\n";
   print "      commands from other process file ascii dumps.\n";
   print "      (I use this to add the f5/DMD colors to the hcmos5 process)\n";
   print "\n";
   print "   Default Parameters are:\n";
   print "      Excel File = $ExcelFile\n";
   print "      Original Process File = $ProcessIn\n";
   print "      Perl Database File  = $dbfile\n";
   print "\n";
   print "Output Options:\n";
   print "   -R Write new database! Normal mode is read only\n";
   print "   -C Create a new database from scratch\n";
   print "   -F <db_file>  Specifies name for the saved perl database.\n";
   print "\n";
   print "Tool Technology File output filters:\n";
   print "   -O process=<file>:gdsopt=<file>:drc=<file>\n";
   exit 0;
}

# my options parser
sub parse_options
{
   if ( $#ARGV > 0 && $ARGV[0] =~ "-help"){
      &show_usage();
      exit(1);
   }

   unless (&Getopt::Std::getopts('Vvxl:e:p:dF:c:O:R')) {
      &show_usage();
      exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
   if (!defined($opt_e) && defined($opt_R)){ 
      print "Using the default excel file: $ExcelFile\n";
   };

   if (defined($opt_e)){
      $ExcelFile=$opt_e;
   }

   if (defined($opt_F)){
      $dbfile=$opt_F;
   }

   if (defined($opt_p)){
      $ProcessIn = $opt_p;
   }

   if (defined($opt_c)){
      if (! -r "$opt_c"){
         die "Cannot read aux colormap file: $opt_c\n";
      }
   }

   if (defined($opt_O)){
      for my $tag (split(/,/,$opt_O)){
         my ($option, $file, $var);
         ($option, $file) = split('=',$tag);
         if ($option !~ /process/i && $option !~ /gdsopt/i && 
             $option !~ /drc/i){
            die "Bad techfile output option: $option\n";
         }
         if (!defined($file)){
            $file = $option . ".new";
         }
 
         $var = "optout_" . $option;
         no strict 'refs';
         ${$var} = $file;
         use strict 'refs';
      }
   }
}

#############################################
# get the modification time of a file.
#
sub file_mtime {
    my $filename = shift;
    # (stat("file"))[9] returns mtime of file.
    return (stat($filename))[9];
}

#############################################
# Sort array by numeric entries
#
sub numerically { $a <=> $b; }

#############################################
# round a number to a specified number of significant
# digits.
#
sub round {
    my $in=shift;
    my $dec=shift;

    return (int($in * 10**$dec) / 10**$dec);
}

################################################
# Dump a arbitrary data structure to the output.
# Usage: DumpStructure($name, \%Hash);
#        DumpStructure($name, \@Array);
#
sub DumpStructure {
   my $name = shift;
   my $href = shift;
   my %Hash = %$href;
   for my $bkey (sort keys %Hash){
	print "$name: $bkey\n";
	for my $ikey (sort keys %{$Hash{$bkey}}){
	 if (ref ($Hash{$bkey}->{$ikey}) eq "SCALAR"
	  || ref ($Hash{$bkey}->{$ikey}) eq ""){
            print "   $ikey: $Hash{$bkey}->{$ikey}\n";
	 } elsif (ref ($Hash{$bkey}->{$ikey}) eq "HASH"){
            print "$ikey HASH:\n";
            for my $ptr (sort keys %{$Hash{$bkey}->{$ikey}}){
		print "	 $ptr -> ${$Hash{$bkey}->{$ikey}}{$ptr}\n";
                 }
	 } elsif (ref ($Hash{$bkey}->{$ikey}) eq "ARRAY"){
            print "$ikey ARRAY:\n";
            for my $ptr (sort @{$Hash{$bkey}->{$ikey}}){
		print "	 $ptr\n";
            }
	 } else {
            print "  $ikey is an unknown reference type:" .
		ref ($Hash{$bkey}->{$ikey}) . "\n";
	 }
	}
   }
}

################################################
# ReadCSV()
#
# Read an Excel spreadsheet that contains the source for the layer map.
# It is stored as a Comma Seperated Values (CSV) file.
#
# The routine uses a CPAN module: Text::CSV.
#
sub ReadCSV {
   use vars qw($MaskLayer $MentorLayer $LayerName $Acronym $STGds $Desc);
   use vars qw($gdslayer $datatype $name $mentor_layer $record $column);
   use vars qw($HashKey @Header @Fields $first_field);
   use vars qw($error);

   my $csv = Text::CSV->new;
   $column = '';
   $record = 0;
   $first_field=1;
   open (CSV, "<$ExcelFile") 
      || die "Cannot open excel file: $ExcelFile\n";
   while (<CSV>){
      chomp;
      /^,+$/ && do { next; };
      s/\r//;  # clean up the lingering Windows garbage.
      $opt_v && print "Record $record\n";
      if ($csv->parse($_)){
         @Fields = $csv->fields;
         my $count = 0;
         # check that the design layer is valid
         if (length($Fields[1]) == 0){
            undef @Fields;
            ++$record;
            next;
         }
         if (defined($first_field)){
            undef @Fields;
            undef $first_field;
            @Header = @Fields;
            ++$record;
            next;
         }
         ($MaskLayer, $MentorLayer, $LayerName, $Acronym, $STGds, $Desc) = 
            @Fields;

         if ($MentorLayer eq ''){
            die "Bad Layer, no mentor layer number specified: $_\n";
         }

         $opt_v && printf "  Mentor Layer:  %d\n", $MentorLayer;

         if ($MentorLayer >= 4000){
            print "Mentor Reserved Layer $LayerName [$MentorLayer] not put in DB.  For reference only\n";
            next;
         }

         if ($LayerName eq ''){
            die "Bad Layer Name at line $.\n";
         }

         $HashKey = lc($LayerName);

         if (defined($LayerMap[$MentorLayer])){
            die "Mentor Layer Number $MentorLayer used twice: $LayerName and $LayerInfo{$LayerMap[$MentorLayer]}->{name}\n";
         }
         $LayerMap[$MentorLayer] = $HashKey;

         if ($STGds ne ''){
            ($gdslayer, $datatype) = split("/", $STGds);
            #print "GDS information from EXCEL file: $gdslayer, $datatype\n";
            if ($gdslayer !~ /\d+/){
               die "Bad GDS Layer used in layer $LayerName: $gdslayer\n";
            }
            $gdslayer += 0;
            if (!defined($datatype)){
               $datatype = 0;
            } else {
               if ($datatype !~ /\d+/){
                  die "Bad GDS datatype used in layer $LayerName: $datatype\n";
               }
               $datatype += 0;
            }

            my $ref=sprintf "%02d/%02d", $gdslayer,$datatype;
            if (exists($Map{$ref})){
                die "GDS Layer information for $LayerName already used for $Map{$ref}\n";
            } else {
               #print "   ... map $ref to $HashKey\n";
               $Map{$ref} = $HashKey;
            }
         }

         if (!exists($LayerInfo{$HashKey})){
            if (defined($opt_d)){
               print "   New Layer defined in spreadsheet: $HashKey, Layer=$MentorLayer\n";
            }

            $LayerInfo{$HashKey}->{name} = $LayerName;

            if ($MaskLayer ne ''){
               $opt_v && printf "  Mask Number:   %d\n", $MaskLayer;
               $LayerInfo{$HashKey}->{mask} = $MaskLayer;
            } else {
               undef $MaskLayer;
            }

            $opt_v && printf "  Layer Name:    %s\n", $LayerName;
            $LayerInfo{$HashKey}->{mentor} = $MentorLayer;

            if ($Acronym ne ''){
               $opt_v && printf "  Layer Acronym: %s\n", $Acronym;
               $LayerInfo{$HashKey}->{acronym} = $Acronym;
            } else {
               undef $Acronym;
            }

            if ($STGds ne ''){
               $opt_v && printf "  ST GDS Layer:  %s\n", $STGds;
               $Mentor{$MentorLayer}->{gdslayer} = $gdslayer;
               $Mentor{$MentorLayer}->{datatype} = $datatype;

               $LayerInfo{$HashKey}->{gdslayer} = $gdslayer;
               $LayerInfo{$HashKey}->{datatype} = $datatype;
            } else {
               undef $STGds;
            }

            if ($Desc ne ''){
               $opt_v && printf "  Description:   %s\n", $Desc;
               $LayerInfo{$HashKey}->{desc} = $Desc;
            } else {
               undef $Desc;
            }
         } else {
            # Check for Differences mode
            if (!exists($LayerInfo{$HashKey}->{mentor})){
               print "Name change in the layer $HashKey,  No such name in db\n";
               ++$error;
               next;
            }

            # Check the Layer Name field
            if ($LayerInfo{$HashKey}->{name} ne $LayerName){
               print "  Diff: Name in db = $LayerInfo{$HashKey}->{name} while its defined in file as $LayerName\n";
            }

            # Check the Mentor Layer field
            if ($LayerInfo{$HashKey}->{mentor} != $MentorLayer){
               print "  Diff: Mentor Layer number in db = $LayerInfo{$HashKey}->{mentor} while its in the file its $MentorLayer\n";
            }

            # Check the mask field
            if ($MaskLayer ne ''){
               if (!exists($LayerInfo{$HashKey}->{mask})){
                  print "  Diff: Mask Layer not defined in previous database for mask layer $MaskLayer\n";
               } elsif ($LayerInfo{$HashKey}->{mask} != $MaskLayer){
                  print "  Diff $LayerName: Mask Layer number in db = $LayerInfo{$HashKey}->{mask} while in the file its $MaskLayer\n";
               }
            } else {
               if (exists($LayerInfo{$HashKey}->{mask})){
                  print "  Diff $LayerName: Mask Layer not in new file for mask layer $LayerInfo{$HashKey}->{mask}\n";
               }
            }

            # Check the acronym field
            if ($Acronym ne ''){
               if (!exists($LayerInfo{$HashKey}->{acronym})){
                  print "  Diff $LayerName: Acronym not defined in previous database for acronym $Acronym\n";
               } elsif ($LayerInfo{$HashKey}->{acronym} ne $Acronym){
                  print "  Diff $LayerName: Acronym in db = $LayerInfo{$HashKey}->{acronym} while in the file its $Acronym\n";
               }
            } else {
               if (exists($LayerInfo{$HashKey}->{acronym})){
                  print "  Diff $LayerName: Acronym not in new file for mask layer $LayerInfo{$HashKey}->{acronym}\n";
               }
            }

            # Check the description field
            if ($Desc ne ''){
               if (!exists($LayerInfo{$HashKey}->{desc})){
                  print "  Diff $LayerName: Description not defined in previous database \'$Desc\'\n";
               } elsif ($LayerInfo{$HashKey}->{desc} ne $Desc){
                  print "  Diff $LayerName: Description in db = \'$LayerInfo{$HashKey}->{desc}\' while in the file its \'$Desc\'\n";
               }
            } else {
               if (exists($LayerInfo{$HashKey}->{desc})){
                  print "  Diff $LayerName: Description not in new file for mask layer \'$LayerInfo{$HashKey}->{desc}\'\n";
               }
            }

            # Check the GDS field
            if ($STGds ne ''){
               if (!exists($LayerInfo{$HashKey}->{gdslayer})){
                  print "  Diff $LayerName: GDS Layer not defined in previous database for layer $LayerName\n";
               } elsif ($LayerInfo{$HashKey}->{gdslayer} != $gdslayer){
                  print "  Diff $LayerName: GDS Layer number in db = $LayerInfo{$HashKey}->{gdslayer} while in the file its $gdslayer\n";
               }

               if (!exists($LayerInfo{$HashKey}->{datatype})){
                  print "  Diff $LayerName: GDS Datatype not defined in previous database for layer $LayerName\n";
               } elsif ($LayerInfo{$HashKey}->{datatype} != $datatype){
                  print "  Diff $LayerName: GDS Layer Datatype in db = $LayerInfo{$HashKey}->{datatype} while in the file its $datatype\n";
               }
            } else {
               if (exists($LayerInfo{$HashKey}->{gdslayer})){
                  print "  Diff $LayerName: Gds Layer not in new file, was $LayerInfo{$HashKey}->{gdslayer}\n";
               }
            }
         }

         #print "DEBUG:  remove $HashKey,  length=$#LayerList\n";
         @LayerList = grep !/^$HashKey$/, @LayerList;

         undef @Fields;
         undef $LayerName;
         undef $MentorLayer;
         undef $MaskLayer;
         undef $gdslayer;
         undef $datatype;
         undef $STGds;
         undef $Desc;

      } else {
         my $err = $csv->error_input;
         print "CSV parse() failed on argument: ", $err, "\n";
      }
      ++$record;
   }

   close CSV;

   if (defined($error)){
       die "Found $error errors in the processing of the CSV File\n";
   }
}

################################################
# ReadProcess()
#
# Read an ascii file which describes the existing mentor process file (if 
# it exists).  Currently, we will be using an existing process file
# (hcmos5.ascii) as a model for the new layer colors and fill patterns.
#
#
sub ReadProcess {
   use vars qw($layer_name $fill_color $text_color);
   use vars qw($type $LayerName $line_style $line_width $HashKey);
   use vars qw($hilight $layer_number $replace $line_color $fill_pattern);

   my $Process = shift;

   open (PROC, "<$Process") || 
      die "Cannot open ascii process file: $Process\n";
   while (<PROC>){
      chomp;
      /^\s*$/ && do { next; };
      /^\s*\#/ && do { next; };
      /^\/\// && do { next; };

      s/^\s+//;
      s/\s+$//;
      s/\s+/ /g;

      # $define_layer_name("ACTIVE", 65, @replace);

      s/^\$define_layer_name\(// && do {
         ($LayerName, $layer_number, $replace) = split(/,/);
         $LayerName =~ s/\"//g;

         # This is a major hack!
         # clean up some names from the old process to the new names...
         #   this is so that we can pull the colors forward.  These names
         #   are hard to map heuritically.  Once the names stabilize we
         #   should be able to remove this hack.
         $LayerName =~ s/^M(\d)_/M$1/;
         $LayerName =~ s/POLYR/Poly/;
         $LayerName =~ s/POLY_BOUND/PolyBound/;
         $LayerName =~ s/IDRES/idres/;
         $LayerName =~ s/IDCPC/idcap/;
         $LayerName =~ s/LABELS/DocText/;
         $LayerName =~ s/PRBOUND/Die_Border/;
         $LayerName =~ s/NLDDPRT/nlddprot/;
         $LayerName =~ s/BURWELL/buried/;
         $LayerName =~ s/WELIMP/wellhvimp/;
         $LayerName =~ s/GLASS/pad_mask/;
         $LayerName =~ s/PWELPRT/pwellprot/;
         $LayerName =~ s/LVACT/lvactive/;

         # Create a clean hash key that is just the lower case of the name.
         #   Since the new standard for layer names specifies lower case,
         #   the hash key should now be the same as the layer name.
         $HashKey = lc($LayerName);

         $layer_number+=0;  # Simple way to force variable to a numeric value.
         if (exists($LayerInfo{$HashKey})){
            if ($layer_number != $LayerInfo{$HashKey}->{mentor}){
               $opt_v && print "Layer has changed: $LayerName is now on layer $LayerInfo{$HashKey}->{mentor}\n";
            }
         } else {
            print "Layer $LayerName has been removed from the process\n";
         }
         next;
      };

      # $set_layer_appearance(@normal, "ACTIVE", @solid, 1, "greenyellow", 25, "greenyellow", "greenyellow");
      s/^\$set_layer_appearance\(// && do {
         s/\s+//g;
         s/\);//;
         s/\"//g;
         ($hilight, $LayerName, $line_style, $line_width, $line_color, $fill_pattern, $fill_color, $text_color) = split(/,/);
         $LayerName =~ s/\"//g;

         # clean up some names from the old process to the new names...
         #   this is so that we can pull the colors forward.
         $LayerName =~ s/^M(\d)_/M$1/;
         $LayerName =~ s/POLYR/Poly/;
         $LayerName =~ s/POLY_BOUND/PolyBound/;
         $LayerName =~ s/IDRES/idres/;
         $LayerName =~ s/IDCPC/idcap/;
         $LayerName =~ s/LABELS/DocText/;
         $LayerName =~ s/PRBOUND/Die_Border/;
         $LayerName =~ s/NLDDPRT/nlddprot/;
         $LayerName =~ s/BURWELL/buried/;
         $LayerName =~ s/WELIMP/wellhvimp/;
         $LayerName =~ s/GLASS/pad_mask/;
         $LayerName =~ s/PWELPRT/pwellprot/;
         $LayerName =~ s/LVACT/lvactive/;

         $HashKey = lc($LayerName);

         if (exists($LayerInfo{$HashKey})){
            unless(grep /^$hilight$/, @{$LayerInfo{$HashKey}->{appearances}}){
               push @{$LayerInfo{$HashKey}->{appearances}}, $hilight;
            }

            $LayerInfo{$HashKey}->{$hilight}->{line_style}   = $line_style;
            $LayerInfo{$HashKey}->{$hilight}->{line_width}   = $line_width;
            $LayerInfo{$HashKey}->{$hilight}->{line_color}   = $line_color;
            $LayerInfo{$HashKey}->{$hilight}->{fill_pattern} = $fill_pattern;
            $LayerInfo{$HashKey}->{$hilight}->{fill_color}   = $fill_color;
            $LayerInfo{$HashKey}->{$hilight}->{text_color}   = $text_color;
         }
     
         next;
      };

   }
}

################################################
# WriteProcess()
#
sub WriteProcess {
   my $Outfile = shift;

   use vars qw($layer $mentor);

   open (OUT, ">$Outfile") || 
      die "Cannot open output process file: $Outfile\n";

   my $outfh = select OUT;
   $| =1;

   print "// == Layers ==\n\n";

   for $layer (sort keys %LayerInfo){
        $mentor = $LayerInfo{$layer}->{mentor};
        print "// Layer $layer information\n";
        print "\$define_layer_name\(\"$layer\", $mentor, \@replace\)\;\n";

        if (exists($LayerInfo{$layer}->{appearances})){
           for my $hilight (sort @{$LayerInfo{$layer}->{appearances}}){
              printf "\$set_layer_appearance\($hilight, \"$layer\", %s, %d, \"%s\", %d, \"%s\", \"%s\"\)\;\n",
                 $LayerInfo{$layer}->{$hilight}->{line_style},
                 $LayerInfo{$layer}->{$hilight}->{line_width},
                 $LayerInfo{$layer}->{$hilight}->{line_color}, 
                 $LayerInfo{$layer}->{$hilight}->{fill_pattern},
                 $LayerInfo{$layer}->{$hilight}->{fill_color}, 
                 $LayerInfo{$layer}->{$hilight}->{text_color};
           }
        }
        print "\n";
   }

   close (OUT);
   select $outfh;

   print "Layer information has been written to an ascii file \(ample\)\n";
   print "You will need to edit and read the other process information\n";
   print "  as well (see extra.process for a reference)\n";
   print "\n";
}

################################################
# WriteGdsOptions()
#
sub WriteGdsOptions {
   my $Outfile = shift;

   use vars qw($layer $mentor @KeepLayers);

   open (OUT, ">$Outfile") || 
      die "Cannot open output gdsopt file: $Outfile\n";

   my $outfh = select OUT;
   $| =1;

   print "# General Layer Mapping Information\n";

   for $layer (sort keys %LayerInfo){
        if (exists($LayerInfo{$layer}->{desc})){
           if ($LayerInfo{$layer}->{desc} =~ /^drc only/i){
              next;
           }
        }
        if (defined($LayerInfo{$layer}->{gdslayer})){
           $mentor   = $LayerInfo{$layer}->{mentor};
           $gdslayer = $LayerInfo{$layer}->{gdslayer};
           $datatype = $LayerInfo{$layer}->{datatype};

           push @KeepLayers, $mentor;

           if (!defined($datatype)){ 
              die "datatype for $layer not defined\n";
           }

           if (!defined($mentor)){ 
              die "mentor for $layer not defined\n";
           }

           print "# $layer\n";
           print "GDS_LAYER_MAP \[$gdslayer,$datatype\]=$mentor\n";
        }
   }
   print "\n";
   print "REPLACE true\n";
   print "SKIP_UNMAPPED_LAYERS\n";
   print "GDS_LAYER_ORDER layer_major\n";
   print "GDS_TEXT_HEIGHT 1000\n";
   print "GDS_TEXTINFO true\n";

   @KeepLayers = sort numerically @KeepLayers;
   print "# LAYER_FILTER " . join(" ", @KeepLayers) . "\n";

   print "PROCESS /sdg/lib/stm/release/HCMOS5HV/tech/rev1_2/mentor/hcmos5\n";

   close (OUT);
   select $outfh;
}

################################################
# WriteDrcMap()
#
sub WriteDrcMap {
   my $Outfile = shift;

   use vars qw($mentor $gdslayer $datatype $drcname);

   my $hp_layers = $Outfile . "_hp";
   my $st_layers = $Outfile . "_st";
   open (HP, ">$hp_layers") || 
      die "Cannot open output drc layer map file: $Outfile\n";
   open (ST, ">$st_layers") || 
      die "Cannot open output drc layer map file: $Outfile\n";

   print HP "// ===========================================================\n";
   print HP "//  input layers\n";
   print HP "//\n";
   print HP "//  HP Layer Map to be used for calibre drc.\n";
   print HP "//\n";
   print HP "// ===========================================================\n";

   print ST "// ===========================================================\n";
   print ST "//  input layers\n";
   print ST "//\n";
   print ST "//  ST Layer Map to be used for calibre drc.\n";
   print ST "//\n";
   print ST "// ===========================================================\n";


   my %Names;

   for $layer (sort keys %LayerInfo){
        $name     = $LayerInfo{$layer}->{name};
        $mentor   = $LayerInfo{$layer}->{mentor};
        $gdslayer = $LayerInfo{$layer}->{gdslayer};
        $drcname  = $LayerInfo{$layer}->{drcname};
        $datatype = $LayerInfo{$layer}->{datatype};
   
        if (!defined($drcname)){ 
           $opt_v && print "drcname for $layer not defined\n";
           $drcname = uc($layer);
        }

        if (!defined($name)){
           die "Name is not defined\n";
           if ($name ne $layer){
              print "WARN: Name and layer key are not the same for $layer\n";
           }
        }

        if (exists($Names{$drcname})){
           die "Names are not uniq.  Duplicate for $drcname\n";
        }

        $Names{$drcname} = 1;

        if (!defined($mentor)){ 
           die "mentor for $layer not defined\n";
        }

        if (!defined($gdslayer)){
           $gdslayer = $mentor;
           $datatype = 0;
        }

        print HP "LAYER $name $mentor\n";
        print ST "LAYER $name $mentor\n";
        if (exists($LayerInfo{$layer}->{textlayer})){
           print HP "TEXT LAYER $mentor\n";
           print ST "TEXT LAYER $mentor\n";
           print ST "LAYER MAP $gdslayer TEXTTYPE == $datatype $mentor\n";
        } else {
           print ST "LAYER MAP $gdslayer DATATYPE == $datatype $mentor\n";
        }
        print HP "\n";
        print ST "\n";
   }
   print HP "\n";
   print ST "\n";

   close (HP);
   close (ST);
}

################################################
# CheckDb
#
sub CheckDb {
   use vars qw($error);
   for my $HashKey (sort keys %LayerInfo){
      if (!exists($LayerInfo{$HashKey}->{name})){
         ++$error;
         print "DB Error,  Name for layer $HashKey not defined\n";
      } else {
         if ($LayerInfo{$HashKey}->{name} ne $HashKey){
            ++$error;
            print "DB Error,  Name should match hash key. $HashKey <> $LayerInfo{$HashKey}->{name}\n";
         }
      }

      if (!exists($LayerInfo{$HashKey}->{mentor})){
         ++$error;
         print "DB Error,  Mentor Layer number for layer $HashKey not defined\n";
      } else {
         if ($LayerInfo{$HashKey}->{mentor} > 1000){
            ++$error;
            print "DB Error,  Mentor Layer number is > 1000.\n";
         }
      }

      if (exists($LayerInfo{$HashKey}->{mask})){
         if ($LayerInfo{$HashKey}->{mask} != $LayerInfo{$HashKey}->{mentor}){
            ++$error;
            print "DB Error, Mask Layer does not match the mentor layer\n";
         }
      }

      if (exists($LayerInfo{$HashKey}->{gdslayer})){
         my $gdslayer = $LayerInfo{$HashKey}->{gdslayer};
         if (!exists($LayerInfo{$HashKey}->{datatype})){
            print "Warning:  Datatype for layer $HashKey, GDS Layer $gdslayer, not defined.  Setting to 0\n";
            $LayerInfo{$HashKey}->{datatype}=0;
         }

         if ($LayerInfo{$HashKey}->{gdslayer} > 255 || 
                $LayerInfo{$HashKey}->{datatype} > 63){
            ++$error;
            print "DB Error, GDS layer number or datatype > 63 for layer $HashKey\n";
         }
      }

      if (exists($LayerInfo{$HashKey}->{appearances})){
         my %uniqhash;
         my @list=@{$LayerInfo{$HashKey}->{appearances}};
         for my $appear (sort @list){
            if (exists($uniqhash{$appear})){
               print "Warning:  Multiple $appear appearance tags in $HashKey\n";
               next;
            }
            $uniqhash{$appear}=1;
         }
         delete $LayerInfo{$HashKey}->{appearances};
         for my $keys (sort keys %uniqhash){
            push @{$LayerInfo{$HashKey}->{appearances}}, $keys;
         }
      }
   }

   if (defined($error)){
       die "Found $error errors in the checking of the database File\n";
   }
}

########################################################################
########################  Main Program	 ###############################
########################################################################

parse_options;
$opt_x && print "# $ProgName  $Rev\t\t$RunDate\n\n";


# Load in the previous database if we are looking for differences.
if (!defined($opt_C) && -r "$dbfile"){
   # Load the LayerInfo Data Structure
   print "Loading previous results from $dbfile...\n";
   open(IN,"<$dbfile") || die "Cannot read old output from file\n";
   my $ret="";
   my $buf;
   while(read(IN, $buf, 16384)){
      $ret .= $buf;
   }
   close(IN);
   eval $ret;

   print " ... Previous database file loaded into memory.\n";
  
   # Create a list of the previously defined layers and remove them one-by-one
   # while you parse the CSV file.  Anything left in the array is extra.
   for my $localref (sort keys %LayerInfo){
      push @LayerList, $localref;
   }

   CheckDb();
} else {
   unless(defined($opt_C)){
       die "No database file found to load\n";
   }
}

print "Read the xcel file with the new layer map...\n";
ReadCSV();
print "  ... done\n";
print "----------------------------------------------------------\n";


if (defined($opt_C)){
   print "Read the ascii version of the mentor process file\n";
   print "  and extract color, stipple pattern and process variable\n";
   print "  information.\n";
      ReadProcess($ProcessIn);
   print "----------------------------------------------------------\n";

   if (defined($opt_c)){
      print "Reading extra colormap information from extra process file.\n";
      ReadProcess($opt_c);
      print "----------------------------------------------------------\n";
   }
}

print "\n";
if ($#LayerList > -1){
   print "There is/are extra layers left in the list\n";
   for my $aref (sort @LayerList){
      print "   ... Removing extra layer: $aref\n";
      delete $LayerInfo{$aref};
   }
}

if (defined($opt_R)){
   open (OUT,">xref_new.db") || die "Cannot open xref_new.db output file\n";
   print OUT Data::Dumper->Dump([ \%LayerInfo ], ["*LayerInfo"]);
   print "Created a new database at xref_new.db\n";
   close (OUT);
}

if (defined($opt_O)){
   #$optout_process = "/tmp/process.new";
   #$optout_gdsopt = "/tmp/gds_opts.new";
   #$optout_drc = "/tmp/drc_layers.new";

   if(defined($optout_process)){
      print "Dump process file: $optout_process\n";
      WriteProcess($optout_process);
   }

   if(defined($optout_gdsopt)){
      print "Dump GDS options file: $optout_gdsopt\n";
      WriteGdsOptions($optout_gdsopt);
   }

   if(defined($optout_drc)){
      print "Dump DRC map file: $optout_drc\n";
      WriteDrcMap($optout_drc);
   }
}

#
# Dump the structure:

if (defined($opt_v)){
   print "Dump LayerInfo Data Structure:\n";
   DumpStructure("LayerInfo", \%LayerInfo);
}

