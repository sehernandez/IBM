#********************************************************************
#********      IBM Spectrum Protect Suite - Front End       *********
#********          Terabyte (TB) Capacity Report            *********
#********************************************************************

# Modification Date: 03/20/17
# Modification Date: 11/16/17
# Modification Date: 01/02/18
# Modification Date: 03/03/18

param(
[Parameter(Mandatory=$True,
           helpmessage="Unique name to ensure data is counted only once and result can be identifed")]
           [string]$namespace,

[Parameter(Mandatory=$True,
           helpmessage="Enter directory where the output should be written to")]
           [string]$directory,

[Parameter(Mandatory=$True,
           helpmessage="Enter the user name of the vSphere Datacenter")]
           [string]$applicationusername,

[Parameter(Mandatory=$True,
           helpmessage="Enter the user password to login to the vSphere Datacenter")]
           [string]$applicationpassword,

[Parameter(Mandatory=$True,
           helpmessage="Enter the URL of the vSphere Datacenter")]
           [string]$applicationentity,

[Parameter(Mandatory=$True,
           helpmessage="Enter the IBM Spectrum Protect asnode name")]
           [string]$asnode,

[Parameter(Mandatory=$True,
           helpmessage="Enter the path to the dsm.opt file. Including file name")]
           [string]$dsmoptpath,

[Parameter(Mandatory=$True,
           helpmessage="Enter the installation directory of the IBM Spectrum Protect client")]
           [string]$tsminstall,
           
[string]$debugmode
)

$productId   = "10"
$productName = "IBM Spectrum Protect for Virtual Environments : Data Protection for VMware"
$itemTtype   = "backup";

function queryUsageData()
{
   Write-Host "`nDetecting protected VMs for node '$asnode' ..."
   Set-Location $tsminstall      
   $cmdStr = '.\dsmc q vm * -optfile="' + $dsmoptpath +'" -asnodename=' + $asnode + ' 2>&1'
   $cmdOut = Invoke-Expression $cmdStr
   
   if ($LastExitCode -ne 0)
   {
      Write-Host "Querying protected VMs failed using command $cmdStr"  
      Set-Location $scriptdir    
      exit
   }  
          
   return $cmdOut  
}

function getDataMoverVersion()
{
   $MyProperties = Get-ItemProperty -Path HKLM:\SOFTWARE\IBM\ADSM\CurrentVersion\BackupClient -Name PtfLevel | Select-Object -Property PtfLevel | Out-String

   $Separator="-","."
   $tokens = $MyProperties.Split($Separator, [System.StringSplitOptions]::RemoveEmptyEntries)

   $Version=[int]$tokens[-4]
   $Release=[int]$tokens[-3]
   $Level  =[int]$tokens[-2]
   $Maint  =[int]$tokens[-1]
   $CombinedVersion = 100*100*100*$Version + 100*100*$Release + 100*$Level + $Maint

   return $CombinedVersion
}

function parseUsageData($cmdOut)
{
   $splitLine = $False
   $vmNames = @()
   $TotalProtectedStorageSize = 0
   
   $Version= getDataMoverVersion
   $SplitNum=[int]9
   if ($Version -ge 8010200)
   {
      $SplitNum = [int]10
   }
   
   foreach ($line in $cmdOut)
   {
      if ($splitLine -eq $True)
      {
         $tokens = $line.Split(" ", $SplitNum, [System.StringSplitOptions]::RemoveEmptyEntries)
         if ($tokens.Count -gt $SplitNum-1)
         {             
            if ($vmNames -cnotcontains $tokens[$SplitNum-1])
            {
               $vmNames += $tokens[$SplitNum-1]        
            }
         }
      }   
      
      if ($line -match "---------")
      {
         $splitLine = $True         
      }  
   }
   
   Write-Host "`nConnecting to vSphere Datacenter: $applicationentity ..."
   connect-viserver -Server $applicationentity -user $applicationusername -password $applicationpassword 
   if ($?  -ne $True)
   {    
      Set-Location $scriptdir  
      exit
   }

   Write-Host "`nCalculating Protected Storage size querying vSphere information ...`n"

   $vmsProtected = [int]0

   if ($vmNames.Count -ne 0)
   {
      foreach ($vmName in $vmNames)
      {
         # query the unshared storage size
         $UnsharedSizeByte = 0
         get-vm -name $vmName -ea silentlyContinue -WarningAction silentlyContinue | get-view | select -expandproperty storage | select -expandproperty perdatastoreusage | select -expandproperty Unshared | foreach { $UnsharedSizeByte += $_; }

         # query the usage storage / committed size (contains swap and other files)
         $CommittedSizeByte = 0
         get-vm -name $vmName -ea silentlyContinue -WarningAction silentlyContinue | get-view | select -expandproperty storage | select -expandproperty perdatastoreusage | select -expandproperty Committed | foreach { $CommittedSizeByte += $_; }

         # query the uncommitted storage size
         $UncommittedSizeByte = 0
         get-vm -name $vmName -ea silentlyContinue -WarningAction silentlyContinue | get-view | select -expandproperty storage | select -expandproperty perdatastoreusage | select -expandproperty Uncommitted | foreach { $UncommittedSizeByte += $_; }

         # query the memory size
         $MemorySizeGB    = 0
         $hostMemoryUsage = 0
         get-vm -name $vmName -ea silentlyContinue -WarningAction silentlyContinue | select -expandproperty MemoryGB | foreach { $MemorySizeGB += $_; }    
         get-vm -name $vmName -ea silentlyContinue -WarningAction silentlyContinue | get-view | select -expandproperty summary | select -expandproperty quickStats | select -expandproperty hostMemoryUsage | foreach { $ConsumedHostMemoryMB = $_; }
         
         # translate values to MByte 
         $UnsharedStorageMB    = [math]::round($UnsharedSizeByte/1MB)
         $CommittedStorageMB   = [math]::round($CommittedSizeByte/1MB)
         $UncommittedStorageMB = [math]::round($UncommittedSizeByte/1MB)
         $MemorySizeMB         = $MemorySizeGB * 1024

         # calculate the provisioned storage
         $ProvisionedStorageMB = $CommittedStorageMB + $UncommittedStorageMB

         # query the independent, thick and thin disk size
         $NumberOfDisks            = 0
         $NumberOfThickDisks       = 0
         $NumberOfThinDisks        = 0
         $NumberOfIndependentDisks = 0

         $ThinDiskStorageMB        = 0
         $ThickDiskStorageMB       = 0
         $IndependentDiskStorageMB = 0

         $VM = Get-VM | ?{$_.name -eq $vmName}      
         foreach ($Harddisk in $VM.Harddisks)
         {
            $NumberOfDisks  += 1 
              
            If ($Harddisk.Persistence -eq "IndependentPersistent" -Or $Harddisk.Persistence -eq "IndependentNonPersistent")
            { 
               $NumberOfIndependentDisks += 1
               $IndependentDiskStorageMB += ($Harddisk.CapacityKB / 1024)
            }

            If ($Harddisk.StorageFormat -eq "Thick")
            {
               $NumberOfThickDisks += 1
               $ThickDiskStorageMB += ($Harddisk.CapacityKB / 1024)
            }
            Else
            {
               $NumberOfThinDisks  += 1
               $ThinDiskStorageMB += ($Harddisk.CapacityKB / 1024)
            }
         }
         
         if ($NumberOfThickDisks -gt 0)
         {
            $VMsNameListWithThickDisks += "             $vmName`n"
         }

         # METRIC: calculate the protected storage size as "Unshared - Independent disk size"
         $ProtectedStorageSize = $UnsharedStorageMB - $IndependentDiskStorageMB

         if ($? -ne $True) 
         {
            Write-Host "`nFound backup of VM '$vmName', but no existing VM with the same name. Skip from capacity counting."
         }
         if ($ProtectedStorageSize -ge 0)
         { 
            Write-Host "   VM '${vmName}': ${ProtectedStorageSize}MB"
            $vmsProtected                  += 1
            $TotalNumberOfDisks            += $NumberOfDisks
            $TotalNumberOfThickDisks       += $NumberOfThickDisks
            $TotalNumberOfThinDisks        += $NumberOfThinDisks
            $TotalIndependentDisk          += $NumberOfIndependentDisks
            
            $TotalUnsharedStorageMB        += $UnsharedStorageMB
            $TotalIndependentDiskStorageMB += $IndependentDiskStorageMB
            $TotalProtectedStorageSize     += $ProtectedStorageSize
            
            $TotalProvisionedStorageMB     += $ProvisionedStorageMB
            $TotalCommittedStorageMB       += $CommittedStorageMB
            $TotalUncommittedStorageMB     += $UncommittedStorageMB
            $TotalThinDiskStorageMB        += $ThinDiskStorageMB
            $TotalThickDiskStorageMB       += $ThickDiskStorageMB

            $TotalMemorySizeMB             += $MemorySizeMB
            $TotalConsumedHostMemoryMB     += $ConsumedHostMemoryMB
         }

         if($debugmode -eq $True)
         {
             ""
             "   Number of total Disks      {0,10}"    -f $NumberOfDisks
             "   Number of Thick Disks      {0,10}"    -f $NumberOfThickDisks
             "   Number of Thin Disks       {0,10}"    -f $NumberOfThinDisks
             "   Number of Independent Disks{0,10}"    -f $NumberOfIndependentDisks
             ""
             "   Unshared Storage         {0,10:n0}MB" -f $UnsharedStorageMB
             "   Independent Disk Storage {0,10:n0}MB" -f $IndependentDiskStorageMB
             ""
             "   Provisioned Storage      {0,10:n0}MB" -f $ProvisionedStorageMB
             "   Used/Committed Storage   {0,10:n0}MB" -f $CommittedStorageMB 
             "   Uncommitted Storage      {0,10:n0}MB" -f $UncommittedStorageMB
             "   Thin Disk Storage        {0,10:n0}MB" -f $ThinDiskStorageMB
             "   Thick Disk Storage       {0,10:n0}MB" -f $ThickDiskStorageMB
             ""
             "   Memory                   {0,10:n0}MB" -f $MemorySizeMB
             "   Consumed Host Memory     {0,10:n0}MB" -f $ConsumedHostMemoryMB
             ""
             ""
         }
      }
       
      # round the MByte value to a int
      $TotalProtectedStorageSize = [decimal]::round($TotalProtectedStorageSize)

      # printout the results
      ""
      "Number of protected VMs                {0,10}"    -f $vmsProtected
      "Number of total disks                  {0,10}"    -f $TotalNumberOfDisks
      "Number of protected thin disks         {0,10}"    -f $TotalNumberOfThinDisks
      "Number of protected thick disks        {0,10}"    -f $TotalNumberOfThickDisks
      "Number of unprotected independent disks{0,10}"    -f $TotalIndependentDisk
          
      if($debugmode -eq $True)
      {
         ""
         "Total size of Unshared Storage        {0,10:n0}MB"  -f $TotalUnsharedStorageMB
         "Total Size of Independent Disks       {0,10:n0}MB"  -f $TotalIndependentDiskStorageMB
         ""
         "Total size of Provisioned Storage     {0,10:n0}MB"  -f $TotalProvisionedStorageMB
         "Total size of Used/Committed Storage  {0,10:n0}MB"  -f $TotalCommittedStorageMB
         "Total size of Uncommitted Storage     {0,10:n0}MB"  -f $TotalUncommittedStorageMB
         "Total size of Thin Storage            {0,10:n0}MB"  -f $TotalThinDiskStorageMB
         "Total size of Thick Storage           {0,10:n0}MB"  -f $TotalThickDiskStorageMB
         ""
         "Total Size of VMs Memory              {0,10:n0}MB"  -f $TotalMemorySizeMB
         "Total Size of Consumed Host Memory    {0,10:n0}MB"  -f $TotalConsumedHostMemoryMB
      }
       
      "Total size of Protected Storage       {0,10:n0}MB"  -f $TotalProtectedStorageSize

      if ($TotalIndependentDisk -gt 0) 
      {
         Write-Host "`nWARNING: The tool has detected $TotalIndependentDisk independent disks that are not protected and "
         Write-Host "         not included in the above 'Total size of Protected Storage'."
      }
      
      if ($TotalNumberOfThickDisks -gt 0) 
      {
         Write-Host "`nWARNING: The tool has detected $TotalNumberOfThickDisks disks as THICK provisioned that are included with"
         Write-Host "         their full provisioned size in the above 'Total size of Protected Storage'."
         Write-Host "         In order to have an exact estimation of the protected storage it is recommended"
         Write-Host "         to check the real usage space on the following VMs:`n$VMsNameListWithThickDisks"
      }

      # create the xml file
      createXmlFile $vmsProtected $TotalProtectedStorageSize      
   }
   else
   {
      Write-Host "`nNo protected VMs found"
   }       
}

function createXmlFile($vmCount, $TotalProtectedStorageSize)
{ 
   Set-Location $scriptdir
   $cmdStr = '.\dsmfecc.exe "--create" "--namespace=$namespace" "--productid=$productId" "--directory=$directory" "--applicationentity=$applicationentity" "--numberofobjects=$vmCount" "--size=$TotalProtectedStorageSize" "--type=$itemTtype" 2>&1'

   Write-Host "`nCreating XML file ..."
      
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
$queryUsageDataOutput = queryUsageData
parseUsageData $queryUsageDataOutput
