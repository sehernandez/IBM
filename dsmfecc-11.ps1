param(
[Parameter(Mandatory=$True,
           helpmessage="Unique name to ensure data is counted only once and result can be identifed")]
           [string]$namespace,

[Parameter(Mandatory=$True,
           helpmessage="Enter directory where the output should be written to")]
           [string]$directory,

[Parameter(Mandatory=$True,
           helpmessage="Enter the path to the dsm.opt file. Including file name")]
           [string]$dsmoptpath,

[Parameter(Mandatory=$True,
           helpmessage="Enter the installation directory of the IBM Spectrum Protect client")]
           [string]$tsminstall,           

[Parameter(Mandatory=$False,
           helpmessage="Enter the IBM Spectrum Protect asnode name")]
           [string]$asnode
)

# Modification Date: 09/04/17
$productId   = "11"
$productName = "IBM Spectrum Protect for Virtual Environments : Data Protection for Hyper-V"
$itemTtype   = "backup";

# Enable DEBUG to get a list of all counted disks
$DEBUG       = $False

# get vm backup information from spectrum protect server
function buildAndExecuteQueryCommand()
{   
    $wd = Get-Location
    Set-Location $tsminstall
    $getVMCommand = ".\dsmc query vm * -optfile='$dsmoptpath' -asnode=$asnode 2>&1"
    $getVMCommandOut = Invoke-Expression $getVMCommand
    Set-Location $wd

    return $getVMCommandOut
}

# extract the list of protected vm's from spectrum protect query
function getProtectedVMList($getVMCommandOut)
{
    $splitLine = $false
    $splitNum = [int]10
    $vmNames = @()

    foreach($line in $getVMCommandOut)
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

    return $vmNames
}

# get the list of all vm's in the environment
function getExistingVMList()
{
    $allVMList = (Get-VM | Select-Object Name).Name
    return $allVMList
}

# compare the lists and get the existing and protected vm's
function getCountableVMList($protectedVMList, $existingVMList)
{
    $countableVMList = @()

    foreach($vm in $protectedVMList)
    {
        if($existingVMList -contains $vm)
        {
            $countableVMList += $vm
            if($DEBUG) { Write-Host " DEBUG: ADD vm to countable vm list: $vm" }
        }
    }

    return $countableVMList
}


# traverse the list of vm's and get all the virtual disks
function countUsageData($countableVMList)
{
    $vmSize = 0

    foreach($vm in $countableVMList)
    {
        $virtualDiskList = Get-VMHardDiskDrive -VMName $vm | Get-VHD | select Path

        foreach($virtualDisk in $virtualDiskList)
        {
            # if this is a snapshot get the size of the parent disk
            if($virtualDisk -match ".avhdx")
            {
                $snapPath       = $virtualDisk.Path
                if($DEBUG) { Write-Host " DEBUG: IGNORE snap disk: $snapPath" }
                $parentPath     = (Get-VHD -Path $snapPath | Select-Object ParentPath).ParentPath
                $parentDiskSize = (Get-VHD -Path $parentPath | select FileSize).FileSize
                $vmSize        += [decimal]::round($parentDiskSize/1024/1024)
                if($DEBUG) { Write-Host " DEBUG: COUNT disk with size: $vmSize MB, name: $parentPath" }
            }
            # get the size of the disk
            else
            {
                $diskSize       = (Get-VHD -Path $virtualDisk.Path | select FileSize).FileSize
                $vmSize        += [decimal]::round($diskSize/1024/1024)
                if($DEBUG) { Write-Host " DEBUG: COUNT disk with size: $vmSize MB, name: $virtualDisk.Path" }
            }
        }
    }
    return $vmSize
}

function createXmlFile($vmCount, $vmSize)
{ 
   $cmdStr = '.\dsmfecc.exe "--create" "--namespace=$namespace" "--productid=$productId" "--directory=$directory" "--applicationentity=$namespace" "--numberofobjects=$vmCount" "--size=$vmSize" "--type=$itemTtype" 2>&1'
   
   Write-Host "`nCreate XML report"
      
   Invoke-Expression $cmdStr
   if ($LastExitCode -ne 0)
   {
      Write-Host "Create XML report failed."
   }    
}

function main
{
    Write-Host "`n"
    Write-Host "********************************************************************"
    Write-Host "********      IBM Spectrum Protect Suite - Front End       *********"
    Write-Host "********          Terabyte (TB) Capacity Report            *********"
    Write-Host "********************************************************************`n"
    Write-Host "$productName`n"

    $getVMCommandOut = buildAndExecuteQueryCommand
    $protectedVMList = getProtectedVMList $getVMCommandOut
    $existingVMList  = getExistingVMList
    $countableVMList = getCountableVMList $protectedVMList $existingVMList
    $vmCount         = $countableVMList.Count
    $vmSize          = countUsageData $countableVMList

    Write-Host "`nNumber of VM's: $vmCount"
    Write-Host "Size of disks: $vmSize MB"

    createXmlFile $vmCount $vmSize

    Write-Host "`nFront End Capacity Report created"
}

main


