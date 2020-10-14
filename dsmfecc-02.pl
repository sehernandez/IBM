#!/usr/bin/perl
# Modification Date: 01/14/15

use warnings;
use strict;
use POSIX;

my $product_id = "02";
my $item_type = "backup";

my $product_name = "Tivoli Storage Manager for Databases : Data Protection for Oracle";
my @result = "";

my $opt_prefix = "--";
my %defined_options = (
      "applicationusername" => [255, "true", "<database user>", "required", "User name for logging on to the database."],
      "applicationpassword" => [255, "true", "<database user password>", "optional", "Password for logging on to the database."],      
      "namespace" => [255, "true", "<unique namespace definition>", "required", "Unique name to ensure data is counted only once and result can be identifed."],
      "directory" => [255, "true", "<directory>", "required", "Directory where the output should be written to."]           
);

my %user_options = ();

my %capacity_counting = (      
      "item_type"    => "",
      "item_name"    => "",
      "item_count"   => "",
      "item_size"    => ""
); 

print"\n";
print"********************************************************************\n";
print"******** Tivoli Storage Manager Suite for Unified Recovery *********\n";
print"********      Front-End Terabyte (TB) Capacity Report      *********\n";
print"********************************************************************\n\n";
print"$product_name\n\n";

parse_cmd_line();
query_usage_data();
parse_usage_data();
create_xml_file();

#-----------------------------------------------------------------------+
# parse_cmd_line                                                        |
# ===================================================================== |
# Purpose: Parse command line parameter.                                |
#                                                                       |
#-----------------------------------------------------------------------+
sub parse_cmd_line 
{   
   my $num_args = @ARGV;     
   
   if ($num_args == 0) 
   {
      print_help();
      exit(12);            
   }
   
   foreach (@ARGV)
   {
      my $option_str = $_;      
      
      if($option_str =~ /^$opt_prefix(([a-z]|[A-Z])+)$/)
      {
         my $option_name = $1; 
         if(validate_option($option_name))
         {            
            $user_options{$option_name} = "";
         }
         else
         {            
            print "Invalid option/value pair: $_\n";
            print_help();
            exit(12);
         }
      }
      elsif ($option_str =~ /^$opt_prefix(([a-z]|[A-Z])+)=(.+)$/)
      {
         my $option_name = $1;
         my $option_value = $3;         
         
         if(validate_option_with_value($option_name, $option_value))
         {            
            $user_options{$option_name} = $option_value;           
         }
         else
         {
            print "Invalid option/value pair: $_\n";
            print_help();
            exit(12);            
         }
      }
      else
      {
         print "Invalid option/value pair: $_\n";
         print_help();
         exit(12);           
      }     
   }
   
   my @options = keys %defined_options;      
   foreach (@options)
   {
      if ($defined_options{$_}[3] eq "required")
      {
         if (!exists($user_options{$_}))
         {
            print "Missing option: $opt_prefix$_\n";
            print_help();
            exit(12);
         }  
      }      
   }    
}

#-----------------------------------------------------------------------+
# query_usage_data                                                      |
# ===================================================================== |
# Purpose: Collect the usage data information for a given DB instance.  |
#                                                                       |
#-----------------------------------------------------------------------+
sub query_usage_data 
{
   print"\nQuery usage data... \n\n";
   my $sqlStr = "select sum(bytes)/1024/1024 " . '"Meg"' . " from dba_data_files;\nEXIT";
   open(SQLCMD, ">cmd.sql") or die "Couldn't open file file.txt, $!";
   print SQLCMD $sqlStr;
   close SQLCMD;
   
   my $cmd_str = "";
   
   if (!exists($user_options{'applicationpassword'}))
   {
      $cmd_str .= "sqlplus  / as $user_options{'applicationusername'} \@cmd.sql";       
   }
   else
   {
      $cmd_str .= "sqlplus $user_options{'applicationusername'}/$user_options{'applicationpassword'} \@cmd.sql";
   }              
   
   @result = `$cmd_str`;    
   
   if($? != 0)
   {
      print "@result\n";  
      exit(12);     
   }     
}

#-----------------------------------------------------------------------+
# parse_usage_data                                                      |
# ===================================================================== |
# Purpose: Parse the collected usage data and create an internal data   |
#          structure                                                    |
#                                                                       |
#-----------------------------------------------------------------------+
sub parse_usage_data
{  
   my $split_lines = 0;
   foreach (@result)
   {            
      if ($_ =~ /-----/)
      {
         $split_lines = 1; 
         next;        
      }
      
      if ($split_lines)
      {
         my $size = $_;
         chomp($size);
         $size =~ s/^\s+//;        
         $capacity_counting{'item_count'} = 1;
         $capacity_counting{'item_size'} = $size;
         $split_lines = 0;         
      }      
   }
   
   $capacity_counting{'item_type'} = $item_type;
   $capacity_counting{'item_name'} = 0; 
   
   print"Query result:\n";
   print"Number of objects: $capacity_counting{'item_count'}\n";
   print"Size (MB):         $capacity_counting{'item_size'}\n";
}

#-----------------------------------------------------------------------+
# create_xml_file                                                       |
# ===================================================================== |
# Purpose: Create the XML file based on the internal data structure     |
#                                                                       |
#-----------------------------------------------------------------------+
sub create_xml_file
{
   print"\nCreate XML file... \n\n";
   my $command_str = "dsmfecc --create ";
   $command_str .= "--namespace=$user_options{'namespace'} ";
   $command_str .= "--productid=$product_id ";
   $command_str .= "--directory=$user_options{'directory'} ";
   $command_str .= "--applicationentity=$capacity_counting{'item_name'} ";
   $command_str .= "--numberofobjects=$capacity_counting{'item_count'} ";
   $command_str .= "--size=$capacity_counting{'item_size'} ";
   $command_str .= "--type=$capacity_counting{'item_type'}";   
   
   system($command_str);

   if ($? == 0)
   {
       print "XML file created in $user_options{'directory'}\n";
   }        
}

#-----------------------------------------------------------------------+
# print_help                                                            |
# ===================================================================== |
# Purpose: Display command line help                                    |
#                                                                       |
#-----------------------------------------------------------------------+
sub print_help 
{
   print"Usage:\n";
   print "dsmfecc-${product_id}.pl\n";
   my @options = keys %defined_options;      
   foreach (@options)
   {
      my $option = "";      
      if ($defined_options{$_}[1] eq "true")
      {
         if($defined_options{$_}[3] eq "optional")
         {
            $option .= "[${opt_prefix}$_";
            $option .= "=$defined_options{$_}[2]]";
         }
         else
         {
            $option .= " ${opt_prefix}$_";
            $option .= "=$defined_options{$_}[2]";
         }        
      }
      printf("%-50s", $option); 
      
      my $desc = "$defined_options{$_}[4]";
      $desc .= "\n";
      print "$desc";
   }  
}

sub validate_option
{
   my $rc = "";
   my $option_name = $_[0];   
   if (is_valid_option($option_name))
   {
      if ($defined_options{$option_name}[1] ne "true")
      {
         $rc = 1;
      }      
   }         
   return $rc;  
}

sub validate_option_with_value
{
   my $rc = "";
      
   if (is_valid_option($_[0]))
   {      
      if ($defined_options{$_[0]}[1] eq "true")
      {
         $rc = 1;
      }
   }         
   return $rc;  
}

sub is_valid_option
{
   my $option = $_[0];
   my $rc = "";
   
   if (exists($defined_options{$option}))
   {
      $rc = 1;
   }   
   return $rc;   
}

