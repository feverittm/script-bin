#!/usr/bin/perl -w
#
#       Author:  Floyd Moore (floyd.moore\@hp.com)
#	$Header:$
#	Description:
#
#	"<script_name>" created by red
#
#	$Log:$
#

use strict;
use subs qw(handler show_usage parse_options get_dir file_mtime round);
use POSIX qw(strftime);
use vars qw($icp $opt_v $opt_x $opt_V $opt_d);
use vars qw($ProgName $RunDate $Rev $DirName);
use vars qw($MentorProcessFile %Layers @LayerXref);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 2 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

use Getopt::Std;

sub handler
{
    my($sig) = @_;
    warn "$ProgName:INFO: Caught a SIG$sig -- shutting down\n";
    exit(0);
}

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "$ProgName [-xVvd] Mentor_Process_File\n";
   print "   Options:\n";
   print "   -v:        Verbose mode\n";
   print "   -V:        Report Version and quit.\n";
   print "   -x:        Debug mode\n";
   print "   -d:        Dump Calibre DRV layer map\n";
   print "\n";
   exit 0;
}

# my options parser
sub parse_options
{
   if ( $#ARGV > 0 && $ARGV[0] =~ "-help"){
	&show_usage();
	exit(1);
   }

   unless (&Getopt::Std::getopts('Vvxd')) {
	&show_usage();
	exit(1);
   }
   if ($opt_V) { die "$ProgName $Rev\n"; };
}

sub print_attributes
{
   my $layer = shift; # layer name not the number, if number use the xref hash to reverse it

   if ($layer =~ /^\d+/){
      # number
      if (!defined($LayerXref[$layer])){
         die "Cannot reverse map the layer number $layer to a layer name\n";
      }
      print "Mapped layer $layer to $LayerXref[$layer]\n";
      $layer = $LayerXref[$layer];
   }

   if (exists($Layers{$layer}->{line_width})){
      print "  Line Width = $Layers{$layer}->{line_width}\n";
   }

   if (exists($Layers{$layer}->{line_color})){
      print "  Line Color = $Layers{$layer}->{line_color}\n";
   }
      
   if (exists($Layers{$layer}->{line_style})){
      print "  Line Style = $Layers{$layer}->{line_style}\n";
   }

   if (exists($Layers{$layer}->{fill_pattern})){
      print "  Fill Pattern = $Layers{$layer}->{fill_pattern}\n";
   }
         
   if (exists($Layers{$layer}->{fill_color})){
      print "  Fill Color = $Layers{$layer}->{fill_color}\n";
   }
}

sub read_mentor_process
{
   use vars qw($layer $name $type);

   my $pfile=shift;

   if (!defined($pfile)){
      print "You must supply a mentor process file to this script\n";
      show_usage;
   }
   open (PROC,"<$pfile") || die "Cannot open mentor process file $pfile\n";
   while (<PROC>){
      chomp;
      if ($_ !~ /^\$define_layer_name/ && $_ !~ /^\$set_layer_appearance/){ next; }

      s/\(|\)|\;/ /g;
      s/\s+/ /g;
      s/^\s+//g;
      s/\,\s+/,/g;
      s/\s+\,/,/g;

      if ($_ =~ s/^\$define_layer_name\s*//){
         ($name, $layer, $type) = split(",");
         $name=~ s/\"//g;
         if ($type !~ /\@replace/){ die "Bad type defined: $type\n"; }
         if (defined($LayerXref[$layer]) && exists($Layers{$LayerXref[$layer]})){
            die "Layer $layer is redefined\n";
         }
         $Layers{$name}->{number}=$layer;
         $LayerXref[$layer]=$name;

         print "Layer $layer = '$name'\n";
         next;
      }
      
      if ($_ =~ s/^\$set_layer_appearance\s*//){
         # ICstation Reference Manual page 1-1192
         #$set_layer_appearance(highlight, layer, line_style, line_width,  line_color , fill_pattern,  
         #     fill_color ,  text_color )

         #print "Layer Appearance line: $_\n";
         use vars qw($hilight $style $line_width $line_color $fillpatrn $fillcolor $text_color);

         ($hilight,$name,$style,$line_width,$line_color,$fillpatrn,$fillcolor,$text_color) =
            split(",");
         $name=~ s/\"//g;
         $line_color=~ s/\"//g;
         $fillcolor=~ s/\"//g;
         $text_color=~ s/\"//g;
         $style =~ s/\@//;

         if (!exists($Layers{$name})){
            die "Lauer not defined before setting appearance: '$name'\n";
         }

         $Layers{$name}->{line_width}=$line_width;
         $Layers{$name}->{line_color}=$line_color;
         $Layers{$name}->{line_style}=$style;
         $Layers{$name}->{fill_pattern}=$fillpatrn;
         $Layers{$name}->{fill_color}=$fillcolor;

         $opt_v && print_attributes($name);
         next;
      }
      print "Layer set line: $_\n";
   }
   close PROC;
}

sub write_drv 
{
   use vars qw($name $num $color);
   # write a calibre drv layer property file
   
   open (OUT, ">layer_props.txt") ||
      die "Cannot open layer property file for write\n";
   foreach $name (keys %Layers){
      $num=$Layers{$name}->{number};
      $color="white";
      $color=$Layers{$name}->{line_color} if (exists($Layers{$name}->{line_color})); 
      if ($color =~ /lightgold/ ) { $color="gold"; }
      elsif ($color =~ /mediumgoldenrod/){ $color="lightgoldenrod"; }
      elsif ($color =~ /ssspressol/ ) { $color="lightbrown"; }
      my $fill="clear";
      # need to map mentor fill pattern into drv fill pattern
      # $fill=$Layers{$name}->{fill_pattern} if (exists($Layers{$name}->{fill_pattern})); 
      my $vis=1;
      my $width=1;
      #$width=$Layers{$name}->{line_width} if (exists($Layers{$name}->{line_width})); 
      print OUT "$num $color $fill $name $vis $width\n";
      #print "$name\n";
   }
   close OUT;
}


######################################
#  Main Program	 #####################
######################################

parse_options;
$opt_v && print "# $ProgName  $Rev\t\t$RunDate\n\n";

# first non-dash arg is the name of the mentor
# process file to extract and translate
$MentorProcessFile=$ARGV[0];

read_mentor_process($MentorProcessFile);

if (defined($opt_d)){
   write_drv();
}
