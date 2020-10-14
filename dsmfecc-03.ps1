param(
[Parameter(Mandatory=$True,
           helpmessage="Unique name to ensure data is counted only once and result can be identifed")]
           [string]$namespace,

[Parameter(Mandatory=$True,
           helpmessage="Enter directory where the output should be written to")]
           [string]$directory,

[Parameter(Mandatory=$True,
           helpmessage="Enter name of the database")]
           [string]$applicationentity            
)

# Modification Date: 01/14/15


$productId   = "03"
$productName = "IBM Spectrum Protect for Enterprise Resource Planning : Data Protection for SAP for DB2"
$itemTtype   = "backup";

function queryUsageData()
{   
   $conStr = "db2 connect to $applicationentity 2>&1"
   $cmdStr = 'db2 "call get_dbsize_info(?,?,?,-1)" 2>&1'         
   
   Write-Host "`nConnecting to $applicationentity..."
   $conOut = Invoke-Expression $conStr   
   if ($LastExitCode -ne 0)
   {
      Write-Host "Connecting failed using command $conStr"           
      exit
   } 
   
   Write-Host "`nQuery usage data..."
   $cmdOut = Invoke-Expression $cmdStr   
   if ($LastExitCode -ne 0)
   {
      Write-Host "Query failed using command $cmdStr"           
      exit
   }   
          
   return $cmdOut  
}

function parseUsageData($cmdOut)
{
   $splitLine = $False   
   $dbSize = 0
   
   foreach ($line in $cmdOut)
   {  
      if ($splitLine -eq $True -and $line)
      {           
         $tokens = $line.Split(":")
         $dbSize = $tokens[1]
         $dbSize = $dbSize.trim()
         $dbSize = [decimal]::round($dbSize/1024/1024)         
         $splitLine = $False
      }   
      
      if ($line -match "DATABASESIZE")
      {
         $splitLine = $True                  
      }  
   }
   Write-Host "`nQuery result:";
   Write-Host "Number of objects:" 1
   Write-Host "Size (MB):         $dbSize"
   createXmlFile 1 $dbSize       
}

function createXmlFile($dbCount, $dbSize)
{    
   $cmdStr = '.\dsmfecc.exe "--create" "--namespace=$namespace" "--productid=$productId" "--directory=$directory" "--applicationentity=$applicationentity" "--numberofobjects=$dbCount" "--size=$dbSize" "--type=$itemTtype" 2>&1'
   
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

$queryUsageDataOutput = queryUsageData
parseUsageData $queryUsageDataOutput

