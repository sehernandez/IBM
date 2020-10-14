param(
[Parameter(Mandatory=$True,
           helpmessage="Unique name to ensure data is counted only once and result can be identifed")]
           [string]$namespace,

[Parameter(Mandatory=$True,
           helpmessage="Enter directory where the output should be written to")]
           [string]$directory             
)

# Modification Date: 01/14/15


$productId   = "06"
$productName = "IBM Spectrum Protect for Mail : Data Protection for Microsoft Exchange Server"
$itemTtype   = "backup";

function queryUsageData()
{
   Write-Host "`nQuery protected Mailbox Databases"         
   $cmdOut = Get-MailboxDatabaseCopyStatus | where {$_.ActiveCopy -eq $true } | select name   

   if ($? -ne $True)
   {      
      exit
   }   
          
   return $cmdOut  
}

function parseUsageData($cmdOut)
{
   $splitLine = $False
   $dbNames = @()
   $dbSize = 0
   $dbCount = 0

   foreach ($db in $cmdOut)
   {
      $tokens = [regex]::Split($db.name, "\\")
      $dbNames += $tokens[0]
   }

   $cmdOut = Get-MailboxDatabase -status | where {$_.Recovery -eq $false } | select name,databasesize,last*
   
   foreach ($db in $cmdOut)
   {
      if ($dbNames -contains $db.name)
      {
         Write-Host "`nGetting size for" $db.name ":" $db.databasesize
         $sizeStr = $db.databasesize -replace ".+\((.+)\s\w+\)", '$1'
         $size = $sizeStr -replace ",", ""         
         $dbSize += $size
         $dbCount +=1         
      }      
   }
   
   $dbSize = [decimal]::round($dbSize/1024/1024)
   
   Write-Host "`nQuery result"
   Write-Host "Number of objects: $dbCount"
   Write-Host "Size (MB):         $dbSize"
   createXmlFile $dbCount $dbSize
   
        
}

function createXmlFile($dbCount, $dbSize)
{ 
   $cmdStr = '.\dsmfecc "--create" "--namespace=$namespace" "--productid=$productId" "--directory=$directory" "--applicationentity=$namespace" "--numberofobjects=$dbCount" "--size=$dbSize" "--type=$itemTtype" 2>&1'
   
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

