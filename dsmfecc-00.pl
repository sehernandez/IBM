#!/usr/bin/perl
# Modification Date: 01/14/15

use warnings;
use strict;
use POSIX;

my $product_id = "00";
my $item_type = "backup";
my $product_name = "Tivoli Storage Manager Extended Edition Tivoli Storage Manager Client";
my @result = "";
my $selectMode = "";

my $opt_prefix = "--";
my %defined_options = (
      "tsmusername"        => [255, "true", "<TSM user name>", "required", "User name to login to TSM Server."],
      "tsmpassword"        => [255, "true", "<TSM password>",  "required", "Password to login to TSM Server."],
      "namespace"          => [255, "true", "<TSM node name>", "required", "TSM node name."],
      "applicationentity"  => [255, "true", "<filespace>",     "required", "The mount point of file system."],
      "directory"          => [255, "true", "<directory>",     "required", "Directory where the output should be written to."]     
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

if ($selectMode eq "all")
{
   query_all_usage_data();   
}
elsif ($selectMode eq "sel_by_node")
{
   query_usage_data_by_node();
} 
else
{
   query_usage_data();   
}
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
   
   if ($num_args != 5) 
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
   
   print"Input values:\n";
   my @options = keys %user_options;   
   
   foreach (@options)
   {
      print"${opt_prefix}$_=$user_options{$_}\n";      
   }  
   
   if ($user_options{'namespace'} eq "*" && $user_options{'applicationentity'} eq "*")
   {
      $selectMode = "all";   
   }
   elsif ($user_options{'namespace'} ne "*" && $user_options{'applicationentity'} eq "*")
   {
      $selectMode = "sel_by_node";      
   }
   elsif ($user_options{'namespace'} eq "*" && $user_options{'applicationentity'} ne "*")
   {
      print "Using --namespace=* in conjunction with a --applicationentity parameter value not equal * is not supported.\n";
      exit(12);        
   }
   else
   {
      $selectMode = "sel";   
   }  
}

#-----------------------------------------------------------------------+
# query_usage_data                                                      |
# ===================================================================== |
# Purpose: Collect the usage data information for given node and fs.    |
#                                                                       |
#-----------------------------------------------------------------------+
sub query_usage_data 
{
   print"\nQuery usage data for: node($user_options{'namespace'}) and fs($user_options{'applicationentity'})... \n\n";
   
   my $cmd_str = "dsmadmc ";
   $cmd_str .= "-id=$user_options{'tsmusername'} ";
   $cmd_str .= "-pass=$user_options{'tsmpassword'} ";
   $cmd_str .= '"select ';  
   $cmd_str .= "(sum( bk.bfsize )/1048576) as front_end_size_mega_byte, ";
   $cmd_str .= "count( bk.bfsize ) as number_of_objects ";
   $cmd_str .= "from backups b, backup_objects bk ";
   $cmd_str .= "where b.state='ACTIVE_VERSION' ";
   $cmd_str .= "and b.object_id=bk.objid ";
   $cmd_str .= "and b.filespace_id in ";
   $cmd_str .= "( ";
   $cmd_str .= "select f.filespace_id from filespaces f ";
   $cmd_str .= "where b.node_name='$user_options{'namespace'}' ";
   $cmd_str .= "and f.filespace_id=b.filespace_id ";
   $cmd_str .= "and f.filespace_name='$user_options{'applicationentity'}' ";
   $cmd_str .= "and f.filespace_type not like 'API:%' ";
   $cmd_str .= "and f.filespace_type not like 'TDP%' ";
   $cmd_str .= ") ";
   $cmd_str .= "and b.node_name in ";
   $cmd_str .= "( ";
   $cmd_str .= "select node_name from nodes ";
   $cmd_str .= "where repl_mode not in ('RECEIVE','SYNCRECEIVE') ";
   $cmd_str .= ')"';  
   
   @result = `$cmd_str`;  
   
   if($? != 0)
   {
      print "@result\n";  
      exit(12);     
   }       
}

#-----------------------------------------------------------------------+
# query_all_usage_data                                                  |
# ===================================================================== |
# Purpose: Collect the usage data information for all nodes and fs.     |
#                                                                       |
#-----------------------------------------------------------------------+
sub query_all_usage_data
{
   print"\nQuery usage data for all nodes and all fs... \n\n";
   
   my $cmd_str = "dsmadmc ";
   $cmd_str .= "-id=$user_options{'tsmusername'} ";
   $cmd_str .= "-pass=$user_options{'tsmpassword'} ";
   $cmd_str .= '"select ';  
   $cmd_str .= "(sum( bk.bfsize )/1048576) as front_end_size_mega_byte, ";
   $cmd_str .= "count( bk.bfsize ) as number_of_objects ";
   $cmd_str .= "from backups b, backup_objects bk ";
   $cmd_str .= "where b.state='ACTIVE_VERSION' ";
   $cmd_str .= "and b.object_id=bk.objid ";
   $cmd_str .= "and b.filespace_id in ";
   $cmd_str .= "( ";
   $cmd_str .= "select f.filespace_id from filespaces f ";
   $cmd_str .= "where b.node_name=f.node_name ";
   $cmd_str .= "and f.filespace_id=b.filespace_id ";   
   $cmd_str .= "and f.filespace_type not like 'API:%' ";
   $cmd_str .= "and f.filespace_type not like 'TDP%' ";
   $cmd_str .= ") ";
   $cmd_str .= "and b.node_name in ";
   $cmd_str .= "( ";
   $cmd_str .= "select node_name from nodes ";
   $cmd_str .= "where repl_mode not in ('RECEIVE','SYNCRECEIVE') ";
   $cmd_str .= ')"';  
   
   @result = `$cmd_str`;  
   
   if($? != 0)
   {
      print "@result\n";  
      exit(12);     
   }     
}

#-----------------------------------------------------------------------+
# query_usage_data_by_node                                              |
# ===================================================================== |
# Purpose: Collect the usage data information for given node.           |
#                                                                       |
#-----------------------------------------------------------------------+
sub query_usage_data_by_node 
{   
   print"\nQuery usage data for: node($user_options{'namespace'}) and all fs... \n\n";
   
   my $cmd_str = "dsmadmc ";
   $cmd_str .= "-id=$user_options{'tsmusername'} ";
   $cmd_str .= "-pass=$user_options{'tsmpassword'} ";
   $cmd_str .= '"select ';  
   $cmd_str .= "(sum( bk.bfsize )/1048576) as front_end_size_mega_byte, ";
   $cmd_str .= "count( bk.bfsize ) as number_of_objects ";
   $cmd_str .= "from backups b, backup_objects bk ";
   $cmd_str .= "where b.state='ACTIVE_VERSION' ";
   $cmd_str .= "and b.object_id=bk.objid ";
   $cmd_str .= "and b.filespace_id in ";
   $cmd_str .= "( ";
   $cmd_str .= "select f.filespace_id from filespaces f ";
   $cmd_str .= "where b.node_name='$user_options{'namespace'}' ";
   $cmd_str .= "and f.filespace_id=b.filespace_id ";   
   $cmd_str .= "and f.filespace_type not like 'API:%' ";
   $cmd_str .= "and f.filespace_type not like 'TDP%' ";
   $cmd_str .= ") ";
   $cmd_str .= "and b.node_name in ";
   $cmd_str .= "( ";
   $cmd_str .= "select node_name from nodes ";
   $cmd_str .= "where repl_mode not in ('RECEIVE','SYNCRECEIVE') ";
   $cmd_str .= ')"';  
   
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
      if ($_ =~ /-----------------/)
      {
         $split_lines = 1; 
         next;        
      }
      
      if ($split_lines)
      {
         my @line = split(/\s+/, $_);         
        
         if (@line == 3)
         {
            $capacity_counting{'item_count'} = $line[2];
            $capacity_counting{'item_size'} = floor($line[1]);
         }
         elsif (@line == 2)
         {
            $capacity_counting{'item_count'} = $line[1];
            $capacity_counting{'item_size'} = 0;            
         }        
         $split_lines = 0;         
      }      
   }
   
   $capacity_counting{'item_type'} = $item_type;
   $capacity_counting{'item_name'} = $user_options{'applicationentity'}; 
   
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
   my $command_str = "./dsmfecc --create ";
   $command_str .= ($selectMode eq "all") ? "--namespace=all " : "--namespace=$user_options{'namespace'} ";
   $command_str .= "--productid=$product_id ";
   $command_str .= "--directory=$user_options{'directory'} ";
   $command_str .= ($selectMode eq "all") ? "--applicationentity=all " : "--applicationentity=$capacity_counting{'item_name'} ";
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
      my $option = " ${opt_prefix}$_";
      if ($defined_options{$_}[1] eq "true")
      {
         $option .= "=$defined_options{$_}[2]";
      }
      printf("%-40s", $option);
      
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

