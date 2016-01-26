

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
		#TODO
		"Warning: Cannot get ipv4 from kvp."
    }
	
    return $addr
}


function DoStartVM([String] $vmName, [String] $server)
{
    # Check the VM is whether in the running state
    $v = Get-VM $vmName -ComputerName $server 2>null
    # $v = Get-VM $vmName -ComputerName $server  
	if( -not $v  )
	{
		Write-Error "Error: the vm $vmName doesn't exist!"
		return 1
	}
	
    $hvState = $v.State
    if ($hvState -eq "Running")
    {
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

<#
Usage:
	CIUpdateConfig $originalConfigFile $CIFolder $newConfigFileName
Description:
	This is a function to update cloud configuration for CI job.
#>
Function CIUpdateConfig([string]$originalConfigFile, [string]$CIFolder, [string]$newConfigFileName)
{
	$newConfigFile = "$CIFolder\$newConfigFileName"
    
    # The $newConfigFileName is a copy of $originalConfigFile. All changes will be written into the $newConfigFileName
    Copy-Item $originalConfigFile $newConfigFile

	[xml]$xml = Get-Content "$newConfigFile"


	$vmName = $xml.config.VMs.vm.vmName
	"The vm name is $vmName before change"
	$TestSuite = $xml.config.VMs.vm.suite
	"The test suite is $suite before change"
	"--------------------------------------------------"
	
	# Update vmName
	$xml.config.VMs.vm.vmName = $env:VMName
	
	# Update test suite
	$xml.config.VMs.vm.suite = $env:TestSuite
	
	# Update test hvServer
	$server = "localhost"
	$xml.config.VMs.vm.hvServer = $server
	
	# Update ipv4
	$ipv4_addr = GetIPv4 $env:VMName $server
	$xml.config.VMs.vm.ipv4 = [string]$ipv4_addr




	# "--------------------------just for test-------------------------------"
	# $newConfigFile = "D:\CI\workspace\CI.BIS2012R2Test\BIS\WS2012R2\lisa\run.xml"
	# [xml]$xml = Get-Content "D:\CI\workspace\CI.BIS2012R2Test\BIS\WS2012R2\lisa\run.xml"
	
	# if(1)
	if($env:DebugCases -and $env:DebugCases.Trim() -ne "")
	{
		$debugCycle = $xml.SelectSingleNode("/config/testSuites/suite[suiteName=`"debug`"]")
		if($debugCycle)
		{
		
			foreach($testcase in $debugCycle.suiteTests.suiteTest)  #Just for test
			{
				"Test cases are $testcase"
			}
			
			foreach($testcase in $debugCycle.suiteTests)
			{
				$testcase = $debugCycle.RemoveChild($testcase)
			}
			
			# $RemoveList = $xml.config.testSuites.suite | Where-Object {$_.suiteName -eq "debug2"}
			# $xml.config.testSuites.RemoveChild($RemoveList)

		}
		else
		{
		    # "Run here ....1..."
			$debugCycle = $xml.CreateElement("suite")
			$name = $xml.CreateElement("suiteName")
			$name.InnerText = "DEBUGxhx"
			$name = $debugCycle.AppendChild($name)
			$debugCycle = $xml.DocumentElement.testSuites.AppendChild($debugCycle)
		}
		
	
		# $DebugCases = "testcase1,testcase2,testcase3,CheckMemoryCapacity-5GB,4K_AddDynamicVHDX_SCSIDrive_Multi"
		# $DebugCases = "testcase1,testcase2,testcase3"
		
		$debugCase = $xml.CreateElement("suiteTests")
		foreach($cn in ($env:DebugCases).Trim().Split(","))
		{
			 # "Run here ....2..."
		
			$debugCaseName = $xml.CreateElement("suiteTest")
			$debugCaseName.InnerText = $cn.Trim()
			$debugCaseName = $debugCase.AppendChild($debugCaseName)
			$debugCase = $debugCycle.AppendChild($debugCase)
		}
	}

	$xml.Save("$newConfigFile")
}





"Prepare the xml for test"

$os_on_host = $env:HostOS
# $os_on_host = "WS2012R2"  #Just for test

# Copy certificate
New-Item  -ItemType "Directory" BIS\$os_on_host\lisa\ssh
Copy-Item CI\ssh\*   BIS\$os_on_host\lisa\ssh

# Copy tools
New-Item  -ItemType "Directory" BIS\$os_on_host\lisa\bin
Copy-Item CI\tools\*   BIS\$os_on_host\lisa\bin


"PWD is $pwd -------------------"   #Just for test

# $env:VMName="FreeBSD64xhx2"  #Just for test
$sts = DoStartVM $env:VMName "localhost"
if($sts[-1] -ne 0)
{
	return 1
}


#Just for test
# $ipaddr=GetIPv4 $env:VMName $server
# "IP is $ipaddr"
# "******************************"



# Update config for CI Run
$XmlConfigFile = $env:XmlConfigFile
if ($XmlConfigFile -and (Test-Path "$pwd\BIS\$os_on_host\lisa\xml\freebsd\$XmlConfigFile"))
{
	CIUpdateConfig "$pwd\BIS\$os_on_host\lisa\xml\freebsd\$XmlConfigFile" "$pwd\BIS\$os_on_host\lisa" run.xml 
	
}
else
{
	#TODO
	# CIUpdateConfig "$pwd\BIS\$os_on_host\lisa\xml\freebsd\$XmlConfigFile" "$pwd\BIS\$os_on_host\lisa" run.xml   #Just for test
}











"Prepare the xml for test done"