param(
[Parameter(Mandatory=$True,
           helpmessage="Unique name to ensure data is counted only once and result can be identifed")]
           [string]$namespace,

[Parameter(Mandatory=$True,
           helpmessage="Enter directory where the output should be written to")]
           [string]$directory,

[Parameter(Mandatory=$True,
           helpmessage="Enter user name for logging on to the database")]
           [string]$applicationusername,
   
[Parameter(helpmessage="Enter password for logging on to the database")]
           [string]$applicationpassword             
)

# Modification Date: 11/09/17


$productId   = "02"
$productName = "IBM Spectrum Protect for Databases : Data Protection for Oracle"
$itemTtype   = "backup";

function queryUsageData()
{
   Write-Host "`nQuery usage data..."
   $sqlStr = "select sum(bytes)/1024/1024 " + '"Meg"' + " from dba_segments;`nEXIT"

   Set-Content -Value $sqlStr -Path .\cmd.sql
   $cmdStr = ""

   if($applicationpassword)
   { 
      $cmdStr = "sqlplus $applicationusername/$applicationpassword" + '"@cmd.sql" 2>&1'
   }
   else
   {
      $cmdStr = 'sqlplus / as $applicationusername "@cmd.sql" 2>&1'
   }           
   
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
      
      if ($splitLine -eq $True)
      {
         $dbSize = $line.trim()
         $dbSize = [decimal]::round($dbSize)         
         $splitLine = $False
      }   
      
      if ($line -match "---------")
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
   $cmdStr = '.\dsmfecc.exe "--create" "--namespace=$namespace" "--productid=$productId" "--directory=$directory" "--applicationentity=$namespace" "--numberofobjects=$dbCount" "--size=$dbSize" "--type=$itemTtype" 2>&1'
   
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

