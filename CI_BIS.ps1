




#######################################################################
#
# GetIPv4ViaKVP()
#
#######################################################################
function GetIPv4ViaKVP( [String] $vmName, [String] $server)
{
    <#
    .Synopsis
        Ise KVP to retrieve the VMs IPv4 address.
    .Description
        Do a KVP intrinsic data exchange with the VM and
        extract the IPv4 address from the returned KVP data.
    .Parameter vmName
        Name of the VM to retrieve the IP address from.
    .Parameter server
        Name of the server hosting the VM
    .Example
        GetIpv4ViaKVP $testVMName $serverName
    #>

    $vmObj = Get-WmiObject -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vmName`'" -ComputerName $server
    if (-not $vmObj)
    {
        Write-Error -Message "GetIPv4ViaKVP: Unable to create Msvm_ComputerSystem object" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $kvp = Get-WmiObject -Namespace root\virtualization\v2 -Query "Associators of {$vmObj} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent" -ComputerName $server
    if (-not $kvp)
    {
        Write-Error -Message "GetIPv4ViaKVP: Unable to create KVP exchange object" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $rawData = $Kvp.GuestIntrinsicExchangeItems
    if (-not $rawData)
    {
        Write-Error -Message "GetIPv4ViaKVP: No KVP Intrinsic data returned" -Category ReadError -ErrorAction SilentlyContinue
        return $null
    }

    $name = $null
    $addresses = $null

    foreach ($dataItem in $rawData)
    {
        $found = 0
        $xmlData = [Xml] $dataItem
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name" -and $p.Value -eq "NetworkAddressIPv4")
            {
                $found += 1
            }

            if ($p.Name -eq "Data")
            {
                $addresses = $p.Value
                $found += 1
            }

            if ($found -eq 2)
            {
                $addrs = $addresses.Split(";")
                foreach ($addr in $addrs)
                {
                    if ($addr.StartsWith("127."))
                    {
                        Continue
                    }
                    return $addr
                }
            }
        }
    }

    Write-Error -Message "GetIPv4ViaKVP: No IPv4 address found for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
    return $null
}



#######################################################################
#
# GetIPv4()
#
#######################################################################
function GetIPv4([String] $vmName, [String] $server)
{
    <#
    .Synopsis
        Retrieve the VMs IPv4 address
    .Description
        Try the various methods to extract an IPv4 address from a VM.
    .Parameter vmName
        Name of the VM to retrieve the IP address from.
    .Parameter server
        Name of the server hosting the VM
    .Example
        GetIPv4 $testVMName $serverName
    #>

    $errMsg = $null
    $addr = GetIPv4ViaKVP $vmName $server
    if (-not $addr)
    {
		#TODO?
		"Warning: Cannot get ipv4 from kvp."
    }

    return $addr
}


function DoStartVM([String] $vmName, [String] $server)
{
    "VM name is $vmName."
	"**************"
    # Check the VM is whether in the running state
    $v = Get-VM $vmName -ComputerName $server
    $hvState = $v.State
    if ($hvState -eq "Running")
    {
		"The vm $vmName is in running."
		return 0
    }

    # Start the VM and wait for the Hyper-V state to go to Running
    Start-VM $vmName -ComputerName $server | out-null
    
    $timeout = 180
    while ($timeout -gt 0)
    {
        # Check if the VM is in the Hyper-v Running state
        $v = Get-VM $vmName -ComputerName $server
        if ($($v.State) -eq "Running")
        {
            break
        }

        start-sleep -seconds 1
        $timeout -= 1
    }

    # Check if we timed out waiting to reach the Hyper-V Running state
    if ($timeout -eq 0)
    {
		"Error:failed to start the vm $vmName"
    }
    else
    {
		"Go to sleep 60 until the vm boot successfully"
		sleep 60
		"Start vm $vmName successfully."
    }


}

<#
Usage:
	CIUpdateConfig $originalConfigFile $CIFolder $newConfigFileName $runfileName
Description:
	This is a function to update cloud configuration for CI job.
#>
# Function CIUpdateConfig([string]$originalConfigFile, [string]$CIFolder, [string]$newConfigFileName, [string]$runfileName)
Function CIUpdateConfig([string]$originalConfigFile, [string]$CIFolder, [string]$newConfigFileName)
{
	# $runfile = "$CIFolder\$runfileName"
	$newConfigFile = "$CIFolder\$newConfigFileName"
    
    # The $newConfigFileName is a copy of $originalConfigFile. All changes will be written into the $newConfigFileName
    Copy-Item $originalConfigFile $newConfigFile


	[xml]$xml = Get-Content "$newConfigFile"


	
	$vmName = $xml.config.VMs.vm.vmName
	"The vm name is $vmName before change"
	$TestSuite = $xml.config.VMs.vm.suite
	"The test suite is $suite before change"
	
	# Update vmName
	$xml.config.VMs.vm.vmName = $env:VMName
	
	# Update test suite
	$xml.config.VMs.vm.suite = $env:TestSuite
	
	$server = "localhost"
	$ipv4_addr = GetIPv4 $vmName $server
	
	# Update vmName
	$xml.config.VMs.vm.ipv4 = $ipv4_addr
	
	#GetIPv4  in utilFunctions.ps1
	
	# $deploymentData.Distro[0].Name = $env:DistroName
	# $deploymentData.Distro[0].OsImage = $env:DistroOsImage
	# if($env:DistroOsVHD)
	# {				
		# if (!($deploymentData.Distro[0].OsVHD))
		# {
			# $newNode = $xml.CreateElement("OsVHD")
			# $deploymentData.Distro[0].AppendChild($newNode)
		# }
		# $deploymentData.Distro[0].OsVHD = $env:DistroOsVHD
	# }

	
	# Update the config XML file for Cloud Testing
	# $UpdateEnvStatus = UpdateCICloudEnvironmentSettings $xml
	# if ($UpdateEnvStatus -eq $False)
	# {
		# Write-Host "Error: UpdateCICloudEnvironmentSettings failed."
		# exit
	# }
	
	

	
	# For debugging cloud cases in CI
	# if($env:DebugCases -and $env:DebugCases.Trim() -ne "")
	# {
		# $debugCycle = $xml.SelectSingleNode("/config/testCycles/Cycle[cycleName=`"DEBUG`"]")
		# if($debugCycle)
		# {
			# foreach($testcase in $debugCycle.test)
			# {
				# $testcase = $debugCycle.RemoveChild($testcase)
			# }
		# }
		# else
		# {
			# $debugCycle = $xml.CreateElement("Cycle")
			# $name = $xml.CreateElement("cycleName")
			# $name.InnerText = "DEBUG"
			# $name = $debugCycle.AppendChild($name)
			# $debugCycle = $xml.DocumentElement.testCycles.AppendChild($debugCycle)
		# }
		
		# foreach($cn in ($env:DebugCases).Trim().Split(","))
		# {
			# $debugCase = $xml.CreateElement("test")
			# $debugCaseName = $xml.CreateElement("Name")
			# $debugCaseName.InnerText = $cn.Trim()
			# $debugCaseName = $debugCase.AppendChild($debugCaseName)
			# $debugCase = $debugCycle.AppendChild($debugCase)
		# }
	# }

	$xml.Save("$newConfigFile")
}





"Prepare the xml for test"

#TODO: WS2012R2? WS2008R2?
$os_on_host = $env:HostOS
# $os_on_host = "WS2012R2"  #Just for test

# Copy certificate
# New-Item  -ItemType "Directory" BIS\WS2012R2\lisa\ssh
# Copy-Item CI\ssh\*   BIS\WS2012R2\lisa\ssh

New-Item  -ItemType "Directory" BIS\$os_on_host\lisa\ssh
Copy-Item CI\ssh\*   BIS\$os_on_host\lisa\ssh

# Copy tools
# New-Item  -ItemType "Directory" BIS\WS2012R2\lisa\bin
# Copy-Item CI\tools\*   BIS\WS2012R2\lisa\bin

New-Item  -ItemType "Directory" BIS\$os_on_host\lisa\bin
Copy-Item CI\tools\*   BIS\$os_on_host\lisa\bin


"PWD is $pwd -------------------"

$server = "localhost"
# $env:VMName="FreeBSD64xhx"  #Just for test
DoStartVM $env:VMName $server

# $ipaddr=GetIPv4 $env:VMName $server
# "IP is $ipaddr"
"******************************"



# Update config for CI Run
$XmlConfigFile = $env:XmlConfigFile
if ($XmlConfigFile -and (Test-Path "$pwd\BIS\$os_on_host\lisa\xml\freebsd\$XmlConfigFile"))
{
	CIUpdateConfig "$pwd\BIS\$os_on_host\lisa\xml\freebsd\$XmlConfigFile" "$pwd\BIS\$os_on_host\lisa" run.xml 
	
}
else
{
	#TODO
}











"Prepare the xml for test done"