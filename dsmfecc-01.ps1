Param(
    [Parameter(mandatory=$true,               
               helpmessage="Enter the name of the SQL Server instance to use")]
               [string]               
               $applicationentity,
    [Parameter(mandatory=$true,               
               helpmessage="Unique name to ensure data is counted only once and result can be identifed")]
               [string]               
               $namespace,

    [Parameter(Mandatory=$True,
               helpmessage="Enter directory where the output should be written to")]
               [string]
               $directory
)  

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null

# Modification Date: 01/14/15
# Modification Date: 11/02/16

$productId   = "01"
$productName = "IBM Spectrum Protect for Databases : Data Protection for Microsoft SQL Server"
$itemTtype   = "backup";
  
function Show-DpSqlUsedDbSizeReport
{  
   process 
   {    
      try
      {       
         $dbSizeAllocations = @(Get-DpSqlUsedDbSize -sqlInstance $applicationentity)     
         $dbSizeAllocations | select ComputerName,InstanceName,DbName,UsedSizeKb,LastBackupDate | ft -AutoSize
         $totalSizeMB = ($dbSizeAllocations | Measure-Object -Property UsedSizeKb -Sum).sum / 1024  
         $totalSizeMB = [decimal]::round($totalSizeMB)     
       
         Write-Host "`nQuery result:"
         if($dbSizeAllocations)
         {
            Write-Host "Number of objects:" $dbSizeAllocations.count
            Write-Host "Total Size (MB)  :" $totalSizeMB
            createXmlFile $dbSizeAllocations.count $totalSizeMB  
         }
         else
         {
            Write-Host "No backup objects found and no XML file created."
         }
   
      }
      catch
      {   
         Write-Host $_.Exception
      }
   }      
}
 
function Get-DpSqlUsedDbSize
{ 
   process 
   {
      try
      {
         $timeStamp = get-date
         $databases = @(Get-SqlDatabasePrivate -sqlInstance $applicationentity)
      
         foreach ($db in $databases)
         {
            if ($db.LastBackupDate -ne "1/1/0001")
            {
               $properties = @{
                  'ComputerName'=(hostname);
                  'InstanceName'=$applicationentity;
                  'DbName'=$db.Name;
                  'UsedSizeKb'=$db.DataSpaceUsage + $db.IndexSpaceUsage;
                  'LastBackupDate'=$db.LastBackupDate;
                  'SampleDate'=$timeStamp;
               }  
               $obj = New-Object -TypeName PSObject -Property $properties
               write-output $obj | select ComputerName,InstanceName,DbName,UsedSizeKb,LastBackupDate,SampleDate
            }       
 
         }
      }   
      catch
      {
         Write-Host $_.Exception
      }
   }      
} 


function Get-SqlDatabasePrivate
{  
   process 
   {
      try
      {
         $srv = New-Object ("Microsoft.SqlServer.Management.Smo.Server") $applicationentity
      
         if (0 -eq $dbName.count)
         { $srv.Databases }
         else
         { 
            foreach ($db in $dbName)
            {
               if ($db.Contains("*"))
                  { $srv.databases | where {$_.name -like $db} }
               else
                  { $srv.databases | where {$_.name -eq $db} } 
            }
         }
      }
      catch
      {
         Write-Host $_.Exception
      }
   }      
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
Write-Host "******** IBM Spectrum Protect Suite - Front End            *********"
Write-Host "********      Terabyte (TB) Capacity Report                *********"
Write-Host "********************************************************************`n"
Write-Host "$productName`n"

Show-DpSqlUsedDbSizeReport


     
   
  