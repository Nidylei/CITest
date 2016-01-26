

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
    #>
	
    $errMsg = $null
    $addr = GetIPv4ViaKVP $vmName $server
    if (-not $addr)
    {
		#TODO
    }
	
    return $addr
}


function DoStartVM([String] $vmName, [String] $server)
{
    <#
    .Description
        To start a vm and wait it boot completely if the vm is existed
    .Parameter vmName
        Name of the VM to start
    .Parameter server
        Name of the server hosting the VM
    #>
	
    $v = Get-VM $vmName -ComputerName $server 2>null
	if( -not $v  )
	{
		Write-Error "Error: the vm $vmName doesn't exist!"
		return 1
	}
	
	# Check the VM is whether in the running state
    $hvState = $v.State
    if ($hvState -eq "Running")
    {
		return 0
    }

    # Start the VM and wait for the Hyper-V to be running
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
		Write-Error "Error:failed to start the vm $vmName"
		return 1
    }
    else
    {
		Write-Output "Go to sleep 60 to wait the vm boot successfully"
		sleep 60
		Write-Output "Start vm $vmName successfully."
    }

	return 0
}


Function CIUpdateConfig([string]$originalConfigFile, [string]$CIFolder, [string]$newConfigFileName)
{
	<#
	Usage:
		CIUpdateConfig $originalConfigFile $CIFolder $newConfigFileName
	Description:
		This is a function to update cloud configuration for CI job.
	#>
	
	$newConfigFile = "$CIFolder\$newConfigFileName"
    
    # The $newConfigFileName is a copy of $originalConfigFile. All changes will be written into the $newConfigFileName
    Copy-Item $originalConfigFile $newConfigFile

	[xml]$xml = Get-Content "$newConfigFile"
	
	# Update vmName
	$xml.config.VMs.vm.vmName = $env:VMName
	
	# Update test suite
	$xml.config.VMs.vm.suite = $env:TestSuite
	
	# Update test hvServer
	$server = "localhost"
	$xml.config.VMs.vm.hvServer = $server
	
	# Update ipv4 address
	$ipv4_addr = GetIPv4 $env:VMName $server
	$xml.config.VMs.vm.ipv4 = [string]$ipv4_addr

	if($env:DebugCases -and $env:DebugCases.Trim() -ne "")
	{
		$debugCycle = $xml.SelectSingleNode("/config/testSuites/suite[suiteName=`"debug`"]")
		if($debugCycle)
		{
			foreach($testcase in $debugCycle.suiteTests)
			{
				$testcase = $debugCycle.RemoveChild($testcase)
			}
		}
		else
		{
			$debugCycle = $xml.CreateElement("suite")
			$name = $xml.CreateElement("suiteName")
			$name.InnerText = "DEBUGxhx"
			$name = $debugCycle.AppendChild($name)
			$debugCycle = $xml.DocumentElement.testSuites.AppendChild($debugCycle)
		}
		
		$debugCase = $xml.CreateElement("suiteTests")
		foreach($cn in ($env:DebugCases).Trim().Split(","))
		{
			$debugCaseName = $xml.CreateElement("suiteTest")
			$debugCaseName.InnerText = $cn.Trim()
			$debugCaseName = $debugCase.AppendChild($debugCaseName)
			$debugCase = $debugCycle.AppendChild($debugCase)
		}
	}

	$xml.Save("$newConfigFile")
}





"Begin to prepare the xml for test"
"-------------------------------------------------"

# Copy certificate
$os_on_host = $env:HostOS
$sshDir = "$pwd" +"\BIS\$os_on_host\lisa\ssh"
$status = Test-Path $sshDir  
if( $status -ne "True" )
{
	New-Item  -ItemType "Directory" $sshDir
}
Copy-Item CI\ssh\*   $sshDir

# Copy tools
$binDir = "$pwd" + "\BIS\$os_on_host\lisa\bin"
$status = Test-Path $binDir 
if( $status -ne "True" )
{
	New-Item  -ItemType "Directory" $binDir
}
Copy-Item CI\tools\*   $binDir


"The vm name is:  $env:VMName"
$sts = DoStartVM $env:VMName "localhost"
if($sts[-1] -ne 0)
{
	return 1
}


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
"-------------------------------------------------"






