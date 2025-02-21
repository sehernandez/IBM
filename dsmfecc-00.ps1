param(
[Parameter(Mandatory=$True,
           helpmessage="Enter the IBM Spectrum Protect node name.")]
           [string]$namespace,

[Parameter(Mandatory=$True,
           helpmessage="Enter the directory where the output should be written to")]
           [string]$directory,

[Parameter(Mandatory=$True,
           helpmessage="Enter the user name to login to IBM Spectrum Protect Server")]
           [string]$tsmusername,
   
[Parameter(Mandatory=$True,
           helpmessage="Enter the password to login to IBM Spectrum Protect Server")]
           [string]$tsmpassword,
   
[Parameter(Mandatory=$True,
           helpmessage="The mount point of file system")]
           [string]$applicationentity,
        
[Parameter(Mandatory=$True,
           helpmessage="Enter the installation directory of the IBM Spectrum Protect client")]
           [string]$tsminstall,
          
[Parameter(Mandatory=$True,
           helpmessage="Enter the path to the dsm.opt file. Including file name")]
           [string]$dsmoptpath
                                     
)

# Modification Date: 02/04/19


$productId   = "00"
$productName = "IBM Spectrum Protect Extended Edition : IBM Spectrum Protect Client"
$itemTtype   = "backup"
$selectMode = ""

function queryUsageData()
{
   $cmd_str = '"select '  
   $cmd_str += "(sum( bk.bfsize )/1048576) as front_end_size_mega_byte, "
   $cmd_str += "count( bk.bfsize ) as number_of_objects "
   $cmd_str += "from backups b, backup_objects bk "
   $cmd_str += "where b.state='ACTIVE_VERSION' "
   $cmd_str += "and b.object_id=bk.objid "
   $cmd_str += "and b.filespace_id in "
   $cmd_str += "( "
   $cmd_str += "select f.filespace_id from filespaces f "
   $cmd_str += "where b.node_name='$namespace' "
   $cmd_str += "and f.filespace_id=b.filespace_id "
   $cmd_str += "and f.filespace_name='$applicationentity' "
   $cmd_str += "and f.filespace_type not like 'API:%' "
   $cmd_str += "and f.filespace_type not like 'TDP%' "
   $cmd_str += "and f.filespace_name not like '%Microsoft Exchange Writer%' "
   $cmd_str += ") "
   $cmd_str += "and b.node_name in "
   $cmd_str += "( "
   $cmd_str += "select node_name from nodes "
   $cmd_str += "where repl_mode not in ('RECEIVE','SYNCRECEIVE') "
   $cmd_str += ')"'
  
   Write-Host "`nQuery usage data for: node($namespace) and fs($applicationentity)..."
   Set-Location $tsminstall      
   $cmdStr = '.\dsmadmc "-id=$tsmusername" "-pass=$tsmpassword" "-optfile=$dsmoptpath" $cmd_str 2>&1'
   $cmdOut = Invoke-Expression $cmdStr
   
   if ($LastExitCode -ne 0)
   {
      Write-Host "Query failed using command $cmdStr"
      Set-Location $scriptdir      
      exit
   }   
          
   return $cmdOut  
}

function queryAllUsageData()
{
   $cmd_str = '"select '  
   $cmd_str += "(sum( bk.bfsize )/1048576) as front_end_size_mega_byte, "
   $cmd_str += "count( bk.bfsize ) as number_of_objects "
   $cmd_str += "from backups b, backup_objects bk "
   $cmd_str += "where b.state='ACTIVE_VERSION' "
   $cmd_str += "and b.object_id=bk.objid "
   $cmd_str += "and b.filespace_id in "
   $cmd_str += "( "
   $cmd_str += "select f.filespace_id from filespaces f "
   $cmd_str += "where b.node_name=f.node_name "
   $cmd_str += "and f.filespace_id=b.filespace_id "   
   $cmd_str += "and f.filespace_type not like 'API:%' "
   $cmd_str += "and f.filespace_type not like 'TDP%' "
   $cmd_str += "and f.filespace_name not like '%Microsoft Exchange Writer%' "
   $cmd_str += ") "
   $cmd_str += "and b.node_name in "
   $cmd_str += "( "
   $cmd_str += "select node_name from nodes "
   $cmd_str += "where repl_mode not in ('RECEIVE','SYNCRECEIVE') "
   $cmd_str += ')"'
  
   Write-Host "`nQuery usage data for all nodes and all fs..."
   Set-Location $tsminstall      
   $cmdStr = '.\dsmadmc "-id=$tsmusername" "-pass=$tsmpassword" "-optfile=$dsmoptpath" $cmd_str 2>&1'
   $cmdOut = Invoke-Expression $cmdStr
   
   if ($LastExitCode -ne 0)
   {
      Write-Host "Query failed using command $cmdStr"
      Set-Location $scriptdir      
      exit
   }   
          
   return $cmdOut  
}

function queryUsageDataByNode()
{
   $cmd_str = '"select '  
   $cmd_str += "(sum( bk.bfsize )/1048576) as front_end_size_mega_byte, "
   $cmd_str += "count( bk.bfsize ) as number_of_objects "
   $cmd_str += "from backups b, backup_objects bk "
   $cmd_str += "where b.state='ACTIVE_VERSION' "
   $cmd_str += "and b.object_id=bk.objid "
   $cmd_str += "and b.filespace_id in "
   $cmd_str += "( "
   $cmd_str += "select f.filespace_id from filespaces f "
   $cmd_str += "where b.node_name='$namespace' "
   $cmd_str += "and f.filespace_id=b.filespace_id "   
   $cmd_str += "and f.filespace_type not like 'API:%' "
   $cmd_str += "and f.filespace_type not like 'TDP%' "
   $cmd_str += "and f.filespace_name not like '%Microsoft Exchange Writer%' "
   $cmd_str += ") "
   $cmd_str += "and b.node_name in "
   $cmd_str += "( "
   $cmd_str += "select node_name from nodes "
   $cmd_str += "where repl_mode not in ('RECEIVE','SYNCRECEIVE') "
   $cmd_str += ')"'
  
   Write-Host "`nQuery usage data for: all fs of node($namespace) ..."
   Set-Location $tsminstall      
   $cmdStr = '.\dsmadmc "-id=$tsmusername" "-pass=$tsmpassword" "-optfile=$dsmoptpath" $cmd_str 2>&1'
   $cmdOut = Invoke-Expression $cmdStr
   
   if ($LastExitCode -ne 0)
   {
      Write-Host "Query failed using command $cmdStr"
      Set-Location $scriptdir      
      exit
   }   
          
   return $cmdOut  
}

function parseUsageData($cmdOut)
{
   $splitLine = $False
   $fileCount = 0
   $sizeAllFiles = 0
   
   foreach ($line in $cmdOut)
   {
      if ($splitLine -eq $True)
      {
         $tokens = [regex]::Split($line, "\s+")
         if ($tokens.Count -eq 3)
         {             
            $fileCount = $tokens[2]
            $sizeAllFiles = $tokens[1]           
         }
         elseif ($tokens.Count -eq 2)
         {
            $fileCount = $tokens[1]
            $sizeAllFiles = 0
         }
      }   
      
      if ($line -match "-----------")
      {
         $splitLine = $True         
      }     
   }
   $sizeAllFiles = [decimal]::round($sizeAllFiles)
   
   Write-Host "`nQuery result:";
   Write-Host "Number of objects: $fileCount";
   Write-Host "Size (MB):         $sizeAllFiles";
   
   createXmlFile $fileCount $sizeAllFiles
}
      

function createXmlFile($fileCount, $sizeAllFiles)
{     
   Set-Location $scriptdir
   if ($selectMode -eq "all")
   {
      $cmdStr = '.\dsmfecc.exe "--create" "--namespace=all" "--productid=$productId" "--directory=$directory" "--applicationentity=all" "--numberofobjects=$fileCount" "--size=$sizeAllFiles" "--type=$itemTtype" 2>&1'
   }
   elseif ($selectMode -eq "sel_by_node")
   {
      $cmdStr = '.\dsmfecc.exe "--create" "--namespace=$namespace" "--productid=$productId" "--directory=$directory" "--applicationentity=all" "--numberofobjects=$fileCount" "--size=$sizeAllFiles" "--type=$itemTtype" 2>&1'
   }
   else
   {     
      $cmdStr = '.\dsmfecc.exe "--create" "--namespace=$namespace" "--productid=$productId" "--directory=$directory" "--applicationentity=$applicationentity" "--numberofobjects=$fileCount" "--size=$sizeAllFiles" "--type=$itemTtype" 2>&1'
   }
   Write-Host "`nCreate XML file"
   Invoke-Expression $cmdStr
   if ($LastExitCode -ne 0)
   {
      Write-Host "Create XML file failed."      
      exit
   }    
}

Write-Host "`n"
Write-Host "********************************************************************"
Write-Host "********      IBM Spectrum Protect Suite - Front End       *********"
Write-Host "********          Terabyte (TB) Capacity Report            *********"
Write-Host "********************************************************************`n"
Write-Host "$productName`n"

$scriptdir = Get-Location
$queryUsageDataOutput = ""
if ($namespace -eq "*" -and $applicationentity -eq "*")
{
   $selectMode = "all"
   $queryUsageDataOutput = queryAllUsageData
}
elseif ($namespace -ne "*" -and $applicationentity -eq "*")
{
   $selectMode = "sel_by_node"
   $queryUsageDataOutput = queryUsageDataByNode 
}
elseif ($namespace -eq "*" -and $applicationentity -ne "*")
{
   Write-Host "Using -namespace=* in conjunction with a -applicationentity parameter value not equal * is not supported"  
   exit 
}
else
{
   $selectMode = "sel"
   $queryUsageDataOutput = queryUsageData
}

parseUsageData $queryUsageDataOutput
