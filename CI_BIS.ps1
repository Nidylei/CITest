
"Prepare the xml for test"

#TODO: WS2012R2? WS2008R2?
$os_on_host = "WS2012R2"

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

"Prepare the xml for test done"