#!/usr/local/bin/perl5 -w
#
###############################################################################
#
# File:         taskmaster.pl
# RCS:          $Header: /home/red/bin/RCS/taskmaster.pl,v 1.1 2001/01/03 22:38:38 red Exp red $
# Description:  System to manage PMF task lists including work breakdown and
#                  schedule flows.
#               Now the code reads from and writes to the text output of 
#                  the planning tools (ie pplan.<yymmdd>)
# Author:       Floyd Moore
# Created:	Mon Aug 18 09:45:41 MDT 1997
# Modified:     Wed Jul 19 10:15:11 MDT 2000
# Language:     Perl (Version 5)
# Package:      N/A
# Status:       Experimental (Do Not Distribute)
#
# (C) Copyright 1997, Hewlett-Packard Systems Technology Lab,
#     all rights reserved.
#
#	$Log: taskmaster.pl,v $
#	Revision 1.1  2001/01/03 22:38:38  red
#	Initial revision
#

use strict;
use subs qw(show_usage);
use POSIX qw(strftime);
use vars qw($opt_v $opt_d $opt_m $opt_f);

use vars qw($Rev $RunDate $DirName $ProgName);

$RunDate = strftime '%Y/%m/%d %H:%M:%S', localtime;
$Rev = (split(' ', '$Revision: 1.1 $', 3))[1];
$0 =~ m!(.*)/!; $ProgName = $'; $DirName = $1; $DirName = '.' unless $DirName;

# Global Vars.
use vars qw($Num $taskfile $in_line);
use vars qw($Dependency $Description $Result $skip);
use vars qw($PlanTime $ActualTime $TimeRemain);
use vars qw($Owner $Id $Name $Category);
use vars qw(%Cat %Parents %Children @Task);
use vars qw($ParentId $ChildId $Mar);
use vars qw($intask $ProjectName $ProjectMngr $PlanDate);

use vars qw(%Task @TasksById $TotalTimeRemain $TotalPlanTime);

# Task information data structure:
#------------------------------------------------------------------
# Task Fields (indexed by task WBS name)
#   Task WBS Name           = $Task{$wbs}->{"Name"}
#        Task Id            = $Task{$wbs}->{"ID"}
#        Description        = $Task{$wbs}->{"Description"}
#        Category           = $Task{$wbs}->{"Category"}
#        Owner              = $Task{$wbs}->{"Owner"}
#        Planned Time       = $Task{$wbs}->{"PlanTime"}
#        Actual Time        = $Task{$wbs}->{"ActualTime"}
#        Remaining          = $Task{$wbs}->{"Remain"}
#        Result             = $Task{$wbs}->{"Results"}
#------------------------------------------------------------------

use Getopt::Std;
unless (&Getopt::Std::getopts('df:m:v')) {
    &show_usage();
    exit(1);
}

sub show_usage
{
   print "$ProgName  $Rev\t\t$RunDate\n";
   print "Description:\n";
   print "  System to manage tasks and schedules along the PMF lines.\n";
   print "Specifically designed to help with the planning process,\n";
   print "Taskmaster can help to create and manage work breakdown lists\n";
   print "and provide a place to record progress on those tasks.\n";
   print "\n";
   print "Provides an interface from the task list to:\n";
   print "     - plain text (create a template, and use for a journal).\n";
   print "     - possibly to Microsoft project and autoplan and mit later.\n";
   print "\n";
   print "$ProgName [-v] [-o<output type] <task_file_name>\n";
   print "   Options:\n";
   print "   -v           :  Verbose mode\n";
   print "   -m <file>    :  Mit planning framework mode, read from <file>\n";
   print "   -f <file>    :  wbs task file\n";
   print "\n";
   exit 0;
}

#-----------------------------------------------------------------------
# Routine to sort tasks
#-----------------------------------------------------------------------
sub byTaskId {
   $b cmp $a;
}

#-----------------------------------------------------------------------
# Routine to dump the contents of the task structure out to stdout
#   in order to allow debug of the routines later.
#-----------------------------------------------------------------------
sub print_structure
{
    print "\n";
    print "####################################\n";
    print "Task list\n";
    print "####################################\n";

    my $task;
    my $role;
    my $name_len=40;
    printf ("%-35s %-40s %-6s %-6s %-6s\n", "Autoplan Task Id", "Task Name", "Plan", "Actual", "Remain");
    printf ("%-35s %-40s %-6s %-6s %-6s\n", "----------------", "---------", "----", "------", "------");
    foreach $task ( @TasksById ) {
        my $short_name = $Task{$task}->{Name};
        if (length($short_name) > ($name_len -3)){
           $short_name=substr($short_name,0,$name_len-3) . "...";
        }
	printf("%-35s %-40s %-6d %-6d %-6d\n", $task,
                              $short_name,
                              $Task{$task}->{"PlanTime"},
                              $Task{$task}->{"ActualTime"},
                              $Task{$task}->{"Remain"});
    }
}

#-----------------------------------------------------------------------
#
# Start Main program
#
#-----------------------------------------------------------------------

#
print "# $ProgName  $Rev\t\t$RunDate\n\n";
if ($opt_v) { print "Verbose mode set\n"; }

undef $intask;
undef($in_line);
undef($skip);

# find the task file.  Default is to search the users home directory for the
#  latest file named: pplan.*
#
unless(defined($ARGV[0])){
   my $file;
   my ($latest, $wtime);
   $wtime=0;
   opendir (HOME,$ENV{HOME}) || die "Cannot open directory Home for reading\n";
   while(defined($file = readdir (HOME))){
      chomp $file;
      $file =~ s/\<\s+\>//g;
      $file =~ /\.+$/ && do { next; };
      unless ($file =~ /^pplan/) { next; };
      $file= $ENV{HOME} . "/" . $file;
      $opt_v && print "   planning file found: $file\n";
      unless(defined($latest)){
         $latest=$file;
         $wtime = (stat($file))[9];
         #print "   ... Setting initial latest to: $file\n";
         #print "   ... Setting initial mod time to: $wtime\n";
      } else {
         if ($wtime < (stat($file))[9]) {
            $latest=$file;
            $wtime = (stat($file))[9];
         }
      } 
   }
   closedir(HOME);
   unless(defined($latest)){
      die "Cannot locate any planning file in your home directory\n";
   }
   $opt_d && print "Setting default planning file to: $latest\n";
   $taskfile=$latest;
} else {
   $taskfile=$ARGV[0];
}

#
# Task file used by the autoplan program...
# Format:
#
#wbs
#
#mako.COMP.j_route_fp1p.core         cat(artwork)         plan(4)      spent(0)     wbsrem(4?) 
#name{Maintain Core Floorplan}
#desc{Maintain Core (PUP1) Floorplan}
#hist  #### For Informational Use Only!
#{
#	0005 spent(0) wbsrem(4)
#}
#
#mako.COMP.j_route_fp1p.makoint      cat(artwork)         plan(8)      spent(0)     wbsrem(8?) 
#name{Maintain Mako Interface Floorplan}
#desc{Maintain Mako Interface (MAKOINT1) Floorplan}
#hist  #### For Informational Use Only!
#{
#	0005 spent(0) wbsrem(8)
#}

undef $intask;  # currently parsing a task
my $me= `whoami`;
chomp $me;
   
$Num=0;
$TotalTimeRemain=0;
$TotalPlanTime=0;
open (TASKS, "<$taskfile") || die "Cannot open the specified taskfile: $taskfile\n";
while (<TASKS>){
   chomp;
   /^#/ && do { next; };

   if (/^\s*$/) {
       if (defined($intask)){
          ++$Num;
          $opt_d && print "\n";
          undef $intask;
       }
       if (defined($in_line)){
          undef($in_line);
          unless (defined($intask)) { next; }
       }
   }

   # pattern to hit task name and info:
   if (!defined($intask) && /\s+cat\(\S+\)/ && /\s+wbsrem\(\S+\)/  ){
      my $rest;
      s/\s+/ /g;
      ($Id, $rest)=split(/ /,$_,2);
      ($ProjectName, $Mar, $ParentId, $ChildId) = split(/\./, $Id);

      $ParentId =~ s/^[a-z]_//;

      $rest = s/\s+cat\((\S+)\)//;
      $Category = $1;

      $rest = s/\s+plan\((\S+)\)//;
      $PlanTime = $1;
      $TotalPlanTime += $PlanTime;

      $rest = s/\s+spent\((\S+)\)//;
      $ActualTime = $1;

      $rest = s/\s+wbsrem\((\S+)\?\)//;
      $TimeRemain = $1;
      $TotalTimeRemain += $TimeRemain;

      $Task{$Id}->{Category}   = $Category;
      $Task{$Id}->{PlanTime}   = $PlanTime;
      $Task{$Id}->{ActualTime} = $ActualTime;
      $Task{$Id}->{Remain}     = $TimeRemain;

      if (exists($Parents{$ParentId})){
         $Task{$Id}->{Owner}      = $Parents{$ParentId};
      } elsif (exists($Children{$ChildId})){
         $Task{$Id}->{Owner}      = $Children{$ChildId};
      } elsif (exists($Cat{$Id})){
         $Task{$Id}->{Owner}      = $Cat{$Id};
      } else {
         $Task{$Id}->{Owner}      = $me;
      }

      $opt_d && print "Task #$Num:\n";
      $opt_d && print "Taskid:    $Id\n";
      $opt_d && print "   Parent: $ParentId\n";
      $opt_d && print "   Child:  $ChildId\n";
      $opt_d && print "Category:  $Category\n";
      $opt_d && print "Plan Time: $PlanTime\n";
      $opt_d && print "Owner:     $Task{$Id}->{Owner}\n";

      $intask=1;
   };

   if (defined($intask)){
      # Capture task name
      /^name\{([^\}]+)}/ && do { 
         $Name=$1;
         $opt_d && print "Name: $Name\n";
         $Task{$Id}->{Name} = $Name;
      };
   
      # Capture task description
      /^desc\{([^\}]+)}/ && do { 
         $Description = $1;
         $opt_d && print "Description: $1\n";
         $Task{$Id}->{Description} = $Description;
      };
   }
}
close (TASKS);

foreach $Id ( keys %Task ) {
   push @TasksById, $Id;
}

@TasksById = sort byTaskId @TasksById;

print_structure();

print "\n";
print "Total Plan Time = $TotalPlanTime\n";
print "Total Time Remaining = $TotalTimeRemain\n";

__END__
