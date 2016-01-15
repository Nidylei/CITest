


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


	# Update vmName
	$vmName = $xml.config.VMs.vm.vmName
	"The vm name is $vmName before change"
	
	$xml.config.VMs.vm.vmName = $env:VMName
	
	
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
# $os_on_host = "WS2012R2"

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