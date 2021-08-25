#!/usr/bin/perl5 -w
#
#	$Id: dvrms-gui.pl 2 2008-04-28 19:07:25Z red $
#
#	"dvrms-gui.pl" created by red
#

use strict;
use English;
use Tk;
use Tk::DialogBox;
use Getopt::Std;
use vars qw($opt_f $opt_x);
use vars qw($Version);

#
#  InFiles = Array of input dvr-ms files.  Could be just one, or
#            multiple files.
#  Output  = Either a file or directory to send the output mpg file(s)
use vars qw(@InFiles $Output);

$Version = "1.0";

#Widgets
use vars qw($main $top $menu_bar $file_mb $help_mb $fs_button $convert_button);

sub show_usage
{
   print "$0: [-f -x]\n";
   print "  -f:  fast select mode - go straight to file selection\n";
   print "  -x:  debug mode\n";
   exit 0;
}

sub about_txt
{
   my $message  = "DVR-MS conversion script.  Interfaces with the DVRMSToolBox conversion";
      $message .= " program to transcode from the Media Center (dvs-ms) encoded video files";
      $message .= " to standard MPEG video files.  Handles issues with file names that make";
      $message .= " the standard command line tool hard to use.";

   #print "$message\n";

   my $about_dialog = $top->DialogBox( -title => 'About dvrms-gui',
                                       -buttons => ["OK"] );
   $about_dialog->add("Label", -wraplength=>200, -width=> 35, -text => $message)-> pack();
   $about_dialog->Show;
}

sub help_txt
{
   my $message  = "$0: [-f <fast_mode> ] [-x <debug_mode> ]\n";
      $message .= "   Convert a drv-ms encoded video file to MPEG format.\n";
 

   #print "$message\n";

   my $about_dialog = $top->DialogBox( -title => 'About dvrms-gui',
                                       -buttons => ["OK"] );
   $about_dialog->add("Label", -wraplength=>240, -width=> 40, -text => $message)-> pack();
   $about_dialog->Show;
}

# File Select:
# want:  2 rows, 1 for input, second for output
#    each row has: Label, Text and Buttons for...
#    Input  File: [file input name input]  [browse]
#    Output File: [file output name input] [browse]
#
# can select multple files for input, and then you must
# select a directory for output.  If a single file is selected
# for an input, then a filename can be given for output,
# or a directory name.  In which case the output file will
# default to the base name for the input name and a .mpg as
# the extension.
#
sub GetOpenFile {
   my $input_file = $main->getOpenFile();

   if (! -r "$input_file") { print "Cannot open file: $input_file\n"; }

   print "Input Filename = $input_file\n";

   push @InFiles, $input_file;
}

sub GetSaveFile {
   my $output_file=$main->getSaveFile;

   print "Output file/directory = $output_file\n";
   $Output = $output_file;
}

sub select_files {
   use vars qw($input_file $output_file);

   my $file_dialog = $top->DialogBox( -title => 'Files...',
                                       -buttons => ["OK", "Cancel"] );
   my $f1 = $file_dialog->add("Frame")->pack();
   my $in_lab = $f1->Label(-text=>"Input File:")
      ->pack(-side => 'left');
   my $in_txt = $f1->Entry(-textvariable => \$input_file)
      ->pack(-side => 'left');
   my $in_button = $f1->Button(-text => 'Browse', -command => \&GetOpenFile)
      ->pack(-side => 'right');

   my $f2 = $file_dialog->add("Frame")->pack();
   my $out_lab = $f2->Label(-text=>"Output File:")
      ->pack(-side => 'left');
   my $out_txt = $f2->Entry(-textvariable => \$output_file)
      ->pack(-side => 'left');
   my $out_button = $f2->Button(-text => 'Browse', -command => \&GetSaveFile)
      ->pack(-side => 'right');

   $file_dialog->Show;
}

#----------------------------------------------------------------------------------
#
#  Main program
#

#
# parse options...
#
if (&getopts('fx') == 0) {
    &show_usage;
}

# set up gui
$main = MainWindow->new;
$main->minsize(250,150);
$main->bind('<Control-c>' => \&exit);
$main->bind('<Control-q>' => \&exit);
$main->bind('<Control-o>' => \&update);
$main->title('Dvrms to MPEG GUI ');
$main->configure(-background => 'cyan');
$main->iconname('DvrmsToolBox');

# create the menubar and its contents...

$menu_bar = $main->Frame(-relief=>'groove',
   -borderwidth => 3,
   -background  => 'purple',
   )->pack(   -side => 'top', -fill => 'x');

$file_mb = $menu_bar->Menubutton(-text => 'File',
   -background       => 'purple',
   -activebackground => 'cyan',
   -foreground       => 'white',
   )->pack(   -side => 'left');

$file_mb->command(-label => 'Open...',
   -activebackground => 'cyan',
   -command => \&select_files);

$file_mb->separator();

$file_mb->command(-label => 'Exit',
   -activebackground => 'cyan',
   -command => sub{$main->destroy});


$help_mb = $menu_bar->Menubutton(-text => 'Help',
   -background       => 'purple',
   -activebackground => 'cyan',
   -foreground       => 'white',
   )->pack(   -side => 'right');

$help_mb->command(-label => 'About',
   -activebackground => 'magenta',
   -command => \&about_txt);

$help_mb->command(-label => 'Help',
   -activebackground => 'magenta',
   -command => \&help_txt);

# create the two control buttons...
$top = $main->Frame( -background =>'cyan',
   )->pack(-side => 'top', -fill => 'x');

$fs_button = $top->Button( -text => 'Select Files',
   -background => 'red',
   -command => \&select_files,
   )->pack(-side=>'top', -pady => '5', -anchor => 'n');

$convert_button = $top->Button( -text => 'Start Conversion',
   -background => 'red',
   -command => \&start_convert,
   )->pack(-side=>'top', -pady => '5', -anchor => 'n');

# Call main loop
MainLoop;
