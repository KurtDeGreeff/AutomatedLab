$labName = 'MultiForest<SOME UNIQUE DATA>' #THIS NAME MUST BE GLOBALLY UNIQUE

$azurePublishingFile = '<PATH TO YOU AZURE PUBLISHING FILE>' #IF YOU HAVE NO PUBLISHING FILE, CALL Get-AzurePublishSettingsFile
$azureDefaultLocation = 'North Europe'

#--------------------------------------------------------------------------------------------------------------------
#----------------------- CHANGING ANYTHING BEYOND THIS LINE SHOULD NOT BE REQUIRED ----------------------------------
#----------------------- + EXCEPT FOR THE LINES STARTING WITH: REMOVE THE COMMENT TO --------------------------------
#----------------------- + EXCEPT FOR THE LINES CONTAINING A PATH TO AN ISO OR APP   --------------------------------
#--------------------------------------------------------------------------------------------------------------------

$labSources = Get-LabSourcesLocation

#create an empty lab template and define where the lab XML files and the VMs will be stored
New-LabDefinition -Name $labName -DefaultVirtualizationEngine Azure

Add-LabAzureSubscription -Path $azurePublishingFile -DefaultLocationName $azureDefaultLocation

#make the network definition
Add-LabVirtualNetworkDefinition -Name Forest1 -AddressSpace 192.168.41.0/24 -AzureProperties @{ DnsServers = '192.168.41.10'; ConnectToVnets = 'Forest2', 'Forest3'; LocationName = $azureDefaultLocation }
Add-LabVirtualNetworkDefinition -Name Forest2 -AddressSpace 192.168.42.0/24 -AzureProperties @{ DnsServers = '192.168.42.10'; ConnectToVnets = 'Forest1','Forest3'; LocationName = $azureDefaultLocation }
Add-LabVirtualNetworkDefinition -Name Forest3 -AddressSpace 192.168.43.0/24 -AzureProperties @{ DnsServers = '192.168.43.10'; ConnectToVnets = 'Forest1', 'Forest2'; LocationName = $azureDefaultLocation }

#and the domain definition with the domain admin account
Add-LabDomainDefinition -Name forest1.net -AdminUser Install -AdminPassword Somepass1
Add-LabDomainDefinition -Name a.forest1.net -AdminUser Install -AdminPassword Somepass1
Add-LabDomainDefinition -Name b.forest1.net -AdminUser Install -AdminPassword Somepass1
Add-LabDomainDefinition -Name forest2.net -AdminUser Install -AdminPassword Somepass2
Add-LabDomainDefinition -Name forest3.net -AdminUser Install -AdminPassword Somepass3

#defining default parameter values, as these ones are the same for all the machines
$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:ToolsPath'= "$labSources\Tools"
    'Add-LabMachineDefinition:OperatingSystem'= 'Windows Server 2012 R2 SERVERDATACENTER'
    'Add-LabMachineDefinition:VirtualizationHost' = 'Azure'
	'Add-LabMachineDefinition:Memory' = 512MB
}

#--------------------------------------------------------------------------------------------------------------------
Set-LabInstallationCredential -Username Install -Password Somepass1

#Now we define the domain controllers of the first forest. This forest has two child domains.
$roles = Get-LabMachineRoleDefinition -Role RootDC
$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain
Add-LabMachineDefinition -Name F1DC1 -IpAddress 192.168.41.10 -Network Forest1 -AzureProperties @{ CloudServiceName = "$labname-Forest1" } `
    -DomainName forest1.net -Roles $roles -PostInstallationActivity $postInstallActivity

$roles = Get-LabMachineRoleDefinition -Role FirstChildDC
$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName 'New-ADLabAccounts 2.0.ps1' -DependencyFolder $labSources\PostInstallationActivities\PrepareFirstChildDomain
Add-LabMachineDefinition -Name F1ADC1 -IpAddress 192.168.41.11 -Network Forest1 -AzureProperties @{ CloudServiceName = "$labname-Forest1" } `
    -DomainName a.forest1.net -Roles $roles -PostInstallationActivity $postInstallActivity

$roles = Get-LabMachineRoleDefinition -Role FirstChildDC
Add-LabMachineDefinition -Name F1BDC1 -IpAddress 192.168.41.12 -Network Forest1 -AzureProperties @{ CloudServiceName = "$labname-Forest1" } `
    -DomainName b.forest1.net -Roles $roles 

#--------------------------------------------------------------------------------------------------------------------
Set-LabInstallationCredential -Username Install -Password Somepass2

#The next forest is hosted on a single domain controller
$roles = Get-LabMachineRoleDefinition -Role RootDC
$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain
Add-LabMachineDefinition -Name F2DC1 -IpAddress 192.168.42.10 -Network Forest2  -AzureProperties @{ CloudServiceName = "$labname-Forest2" }`
    -DomainName forest2.net -Roles $roles -PostInstallationActivity $postInstallActivity

#--------------------------------------------------------------------------------------------------------------------
Set-LabInstallationCredential -Username Install -Password Somepass3

#like the third forest - also just one D
$roles = Get-LabMachineRoleDefinition -Role RootDC @{ DomainFunctionalLevel = 'Win2008R2'; ForestFunctionalLevel = 'Win2008R2' }
$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain
Add-LabMachineDefinition -Name F3DC1 -IpAddress 192.168.43.10 -Network Forest3  -AzureProperties @{ CloudServiceName = "$labname-Forest3" } `
    -DomainName forest3.net -Roles $roles -PostInstallationActivity $postInstallActivity

Install-Lab

#Now setup DNS forwarder and setup trusts. The script creates trusts between each forest created in the lab
& "$labSources\PostInstallationActivities\DnsAndTrustSetup\DnsAndTrustSetup.ps1"

#Install software to all lab machines
$packs = @()
$packs += Get-LabSoftwarePackage -Path $labSources\SoftwarePackages\ClassicShell.exe -CommandLine '/quiet ADDLOCAL=ClassicStartMenu'
$packs += Get-LabSoftwarePackage -Path $labSources\SoftwarePackages\Notepad++.exe -CommandLine /S
$packs += Get-LabSoftwarePackage -Path $labSources\SoftwarePackages\winrar.exe -CommandLine /S

Install-LabSoftwarePackages -Machine (Get-LabMachine -All) -SoftwarePackage $packs

Show-LabInstallationTime