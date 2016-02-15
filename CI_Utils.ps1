
$logfile = ".\test.log"

########################################################################
#
# LogMsg()
#
########################################################################
function LogMsg([int]$level, [string]$msg, [string]$colorFlag)
{
    <#
    .Synopsis
        Write a message to the log file and the console.
    .Description
        Add a time stamp and write the message to the test log.  In
        addition, write the message to the console.  Color code the
        text based on the level of the message.
    .Parameter level
        Debug level of the message
    .Parameter msg
        The message to be logged
    .Example
        LogMsg 3 "Info: This is a test"
    #>

    if ($level -le $dbgLevel)
    {
        $now = [Datetime]::Now.ToString("MM/dd/yyyy HH:mm:ss : ")
        ($now + $msg) | out-file -encoding ASCII -append -filePath $logfile
        
        $color = "White"
        if ( $msg.StartsWith("Error"))
        {
            $color = "Red"
        }
        elseif ($msg.StartsWith("Warn"))
        {
            $color = "Yellow"
        }
        else
        {
            $color = "Gray"
        }

		#Print info in specified color
		if( $colorFlag )
		{
			$color = $colorFlag
		}
        
        write-host -f $color "$msg"
    }
}


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
"The stauts is $hvState "
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







########################################################################
#
# SendFileToVMUntilTimeout()
# Default time-out: 600 seconds
########################################################################
function SendFileToVMUntilTimeout([System.Xml.XmlElement] $vm, [string] $localFile, [string] $remoteFile, [string] $toolsParentDir, [string] $Timeout="600")
{
    LogMsg 3 "Info: Send file from $($vm.hvServer) to $($vm.vmName) in $Timeout seconds"

    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey

	if (-not (Test-Path $toolsParentDir\tools\pscp.exe))  {
        Write-Error -Message "File $toolsParentDir\tools\pscp.exe not found" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }
	
    $process = Start-Process $toolsParentDir\tools\pscp -ArgumentList "-i $toolsParentDir\ssh\${sshKey} ${localFile} root@${hostname}:${remoteFile}" -PassThru -NoNewWindow  -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    while(!$process.hasExited)
    {
        sleep 3
        $Timeout -= 1
        if ($Timeout -le 0)
        {
            LogMsg 3 "Info: Killing process for sending files from $($vm.hvServer) to $($vm.vmName)"
            $process.Kill()
            LogMsg 0 "Error: Send files from $($vm.hvServer) to $($vm.vmName) failed for time-out"
			
			return 1
        }
    }

	sleep 3
    LogMsg 0 "Info: Send files from $($vm.hvServer) to $($vm.vmName) successfully"
	
    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return 0
}



########################################################################
#
# GetFileFromVMUntilTimeout()
# Default time-out: 600 seconds
########################################################################
function GetFileFromVMUntilTimeout([System.Xml.XmlElement] $vm, [string] $remoteFile, [string] $localFile,  [string] $toolsParentDir, [string] $Timeout="600")
{
    LogMsg 3 "Info: Get files from $($vm.vmName) to $($vm.hvServer) in $Timeout seconds"
	
    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey
    
	if (-not (Test-Path $toolsParentDir\tools\pscp.exe))  {
        Write-Error -Message "File $toolsParentDir\tools\pscp.exe not found" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }
   
    $process = Start-Process $toolsParentDir\tools\pscp -ArgumentList "-i $toolsParentDir\ssh\${sshKey} root@${hostname}:${remoteFile} ${localFile}" -PassThru -NoNewWindow  -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    while(!$process.hasExited)
    {
        sleep 3
        $Timeout -= 1
        if ($Timeout -le 0)
        {
            LogMsg 3 "Info: Killing process for getting files from $($vm.vmName) to $($vm.hvServer)"
            $process.Kill()
            LogMsg 0 "Error: Get files from $($vm.vmName) to $($vm.hvServer) failed for time-out"
			
			return 1
        }
    }

	sleep 3
    LogMsg 0 "Info: Get files from $($vm.vmName) to $($vm.hvServer) successfully"
    
    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return 0
}



#####################################################################
#
# SendCommandToVMUntilTimeout()
#
#####################################################################
function SendCommandToVMUntilTimeout([System.Xml.XmlElement] $vm, [string] $command, [string] $toolsParentDir, [string] $commandTimeout)
{
    <#
    .Synopsis
        Run a command on a remote system.
    .Description
        Use SSH to run a command on a remote system.                                                                                                                                                               
    .Parameter vm
        The XML object representing the VM to copy from.
    .Parameter command
        The command to be run on the remote system.
    .ReturnValue
        True if the file was successfully copied, false otherwise.
    #>

    $retVal = $False

    $vmName = $vm.vmName
    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey

    $process = Start-Process $toolsParentDir\tools\plink -ArgumentList "-i $toolsParentDir\ssh\${sshKey} root@${hostname} ${command}" -PassThru -NoNewWindow -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
	LogMsg 3 "Info: Set Command = '$command' can be finished within $commandTimeout seconds."
    while(!$process.hasExited)
    {
        LogMsg 8 "Waiting 1 second to check the process status for Command = '$command'."
        sleep 1
        $commandTimeout -= 1
        if ($commandTimeout -le 0)
        {
            LogMsg 3 "Killing process for Command = '$command'."
            $process.Kill()
            LogMsg 0 "Error: Send command to VM $vmName timed out for Command = '$command'"
        }
    }

    if ($commandTimeout -gt 0)
    {
        $retVal = $True
        LogMsg 3 "Info: $vmName successfully sent command to VM. Command = '$command'"
    }
    
    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}
 

########################################################################
# CheckErrorLogInFile()
#$fileName: Full path of file
########################################################################
function CheckErrorLogInFile([string] $fileName)
{
	if (! (test-path $fileName))
    {
        LogMsg 0 "Error: '$fileName' does not exist."
        return 1
    }
	
    $checkError = Get-Content $fileName | select-string -pattern "Error"
	if( $checkError -eq $null )
	{
	    LogMsg 3 "Info: there is no any error in $fileName"    "Green" 
		return 0
	}

    LogMsg 0 "Info: found error in $fileName" 
	return 1
}




#####################################################################
#
# TestPort
#
#####################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
	<#
	.Synopsis
    	Check to see if a specific TCP port is open on a server.
    .Description
        Try to create a TCP connection to a specific port (22 by default)
        on the specified server. If the connect is successful return
        true, false otherwise.
	.Parameter Host
    	The name of the host to test
    .Parameter Port
        The port number to test. Default is 22 if not specified.
    .Parameter Timeout
        Timeout value in seconds
    .Example
        Test-Port $serverName
    .Example
        Test-Port $serverName -port 22 -timeout 5
	#>

    $retVal = $False
    $timeout = $to * 1000

    #
    # Try an async connect to the specified machine/port
    #
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)

    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

    # Check to see if the connection is done
    if($connected)
    {
        #
        # Close our connection
        #
        try
        {
            $sts = $tcpclient.EndConnect($iar)
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
            $msg = $_.Exception.Message
        }

        #if($sts)
        #{
        #    $retVal = $true
        #}
    }
    $tcpclient.Close()

    return $retVal
}






#Wait VM boot completely until time out
function WaitVMBootFinish([System.Xml.XmlElement] $vm)
{
	LogMsg 3 "Info: Wait VM $($vm.vmName) booting ..." 

	$TotalTime = 36
	do
	{
		$sts = TestPort $vm.ipv4 -port 22 -timeout 5
		if ($sts)
		{
			LogMsg 3 "Info: VM $($vm.vmName) boots successfully" 
			break
		}
		sleep 5
		$TotalTime -= 1		
	} while( $TotalTime -gt 0 )
	
	if( $TotalTime -lt 0 )
	{
		LogMsg 3 "Error: VM $($vm.vmName) boots failed for time-out"
		return 1
	}
	
	return 0
}


#Create a snapshot(checkpoint) 
function CreateSnapshot([String]$vmName, [String]$hvServer, [String]snapshotName)
{
	#To create a snapshot named ICABase
	checkpoint-vm -Name $vmName -Snapshotname  $snapshotName -ComputerName $hvServer  -Confirm:$False
	if ($? -eq "True")
    {
		LogMsg 3 "Info: create snapshot $snapshotName on $vmName VM successfully"
    }
    else
    {
		LogMsg 0 "Error: create snapshot $snapshotName on $vmName VM failed"
        return 1
    }

	return 0
}

#Delete all snapshots(checkpoints) on VM
function DeleteSnapshot([String]$vmName, [String]$hvServer)
{
	LogMsg 3 "Info : Get state of $vmName before delete snapshot"
	$v = Get-VM  -Name $vmName -ComputerName $hvServer
    if ($v -eq $null)
    {
        LogMsg 0 "Error: VM cannot find the VM $vmName on $hvServer server"
        return 1
    } 
	
    # If the VM is not stopped, try to stop it
    if ($v.State -ne "Off")
    {
        LogMsg 3 "Info : $vmName is not in a stopped state - stopping VM"
        Stop-VM -Name $vmName -ComputerName $hvServer -force | out-null

        $v = Get-VM $vmName -ComputerName $hvServer
        if ($v.State -ne "Off")     
        {
            LogMsg 0 "Error: ResetVM is unable to stop $vmName has been disabled"
            return 1
        }
    }
	
	
	#delete snapshot
	LogMsg 3 "Info : $vmName to delete snapshot"
	$sts = Remove-VMSnapshot  $vmName -ComputerName $hvServer
	if( $sts -eq "False" )
	{
	     LogMsg 0 "Error: delete snapshot of $vmName on $hvServer server  failed"
		 return 1
	}
	
	#Make sure delete snapshot successfully
	LogMsg 3 "Info : Make sure delete snapshot successfully on $vmName"
	$timeout = 30
	do
	{
	    sleep 1
	    $snap = Get-VMSnapshot $vmName -ComputerName $hvServer
		$timeout -= 1
	}while( $snap.name -and ( $timeout -gt 0 ) )
	
	if( $timeout -le 0 )
	{
	     LogMsg 0 "Error: delete snapshot of $vmName on $hvServer server failed"
		 return 1
	}
	else
	{
		 LogMsg 3 "Info: delete snapshot of $vmName on $hvServer server successfully"
	}
	
	
    return 0
}




