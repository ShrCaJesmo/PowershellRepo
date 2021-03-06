#Requires -RunAsAdministrator
# Name: Collect-LogScenario
# Description: Gathers logs for different troubleshooting scenarios and gathers them in a folder on the desktop for easy attachment. 
# Set the current scenario to the name of the desired scenario, copy-paste the whole thing or save it as new, then run it. 
# Either attach all the contents of the new folder, or Right-Click > Send-to > Compressed (zipped) file then attach that.
# Originally posted by read-0nly.github.io

#Current log-collecting scenario to run
param(
    [string]$CurrentScenario = "Minimal"
)

#Generate some values we'll need to generate filenames- the desktop path, the name of the new folder, the full path, the current hostname
$saveRoot = ([System.Environment]::GetFolderPath("DESKTOP"))
if($saveRoot -eq $null){
    $saveRoot = "C:\"
}
$saveHive = "Logs_" + ((get-date).toString("yy-MM-dd"))
$savePath = $saveRoot+"\"+$saveHive+"\"
[string]$hostname = hostname
#Up to how many days back do we go for events?
$dayRange = 15

#The different scenarios this supports - the gist of it is @(<Item Type>, <Item Payload>, <Save File (REG/EVT)>) 
#A scenario can and is usually called from another scenario - this will go through resulting scenario tree recursively. Take care not to define new scenarios that loop.
$Scenario = @{
	#Basic logs we usually need - Output of active policies, devmgmt evt logs, result of dsregcmd
	"Minimal"= @(
        @("Cmd",("mdmdiagnosticstool -area autopilot -cab `""+$SavePath+"mdmdiag.cab"+"`"")),
		@("Cmd",("dsregcmd /status | out-file """ +$savePath+"DSRegResult"+$hostname+".log"""))
	)
	"Bitlocker"= @(
	#Relevant logs when trying to manipulate bitlocker +Minimal
		@("Scenario", "Minimal"),
		@("Evt","Microsoft-Windows-BitLocker-API", ("BitlockerAPILogs-"+$hostname+".csv")),
		@("Evt","Microsoft-Windows-BitLocker-DrivePreparationTool", ("BitlockerPrepLogs-"+$hostname+".csv")),
		@("Cmd",("(Confirm-SecureBootUEFI) | out-file """ +$savePath+"SecureBootUEFI"+$hostname+".log""")),
		@("Cmd",("msinfo32 /report `""+ $savePath+"\msinfo.txt`"")),
		@("Cmd",("manage-bde -status >> `""+ $savePath+"\managebde.txt`"")),
		@("Cmd",(@"
    `$TPMversion='2.0';`$Query=('Select * from win32_tpm where SpecVersion like "'+`$TPMVersion+'"');`$NameSpace=`"root\cimv2\security\microsofttpm`";Get-WmiObject -Namespace `$Namespace -Query `$Query |  out-file 
"@ + "`"" +$savePath+"TPM"+$hostname+".log`""))		
	)
	"Download"= @(	
	#Relevant log if there's any download or upload of file (most app deployment) +Minimal
		@("Scenario", "Minimal"),
		@("Evt","Microsoft-Windows-Bits-Client", ("BitsLogs-"+$hostname+".csv"))
	)
	"ModernApp"= @(	
	#Relevant log for Modern App Deployment +Download+Minimal
		@("Scenario", "Download"),
		@("Evt","Microsoft-Windows-AppXDeployment", ("AppxLogs-"+$hostname+".csv"))
	)
	"Defender"= @(	
	#Relevant log for Windows Defender troubleshooting +Download+Minimal
		@("Scenario", "Download"),
		@("Evt","Microsoft-Windows-Windows Defender", (("DefenderLogs-"+$hostname+".csv")))
	)
	"IntuneManagementExtension"= @(	
	#Relevant log for Windows Defender troubleshooting +Download+Minimal
		@("Scenario", "Download"),
        @("Cmd", ("copy-item c:\programdata\microsoft\intunemanagementextension\logs `""+$savePath+"\`" -recurse"))
	)
}

#Recursive function to run through the log collection
function runScenario($ScenarioName){
    cd $savePath
	foreach($ScenarioItem in $Scenario[$ScenarioName]){
		switch($ScenarioItem[0]){
			#If it's a scenario entry, run the scenario
			"Scenario"{runScenario($ScenarioItem[1])}
			#If it's an event entry, pull the events from the provider specified in the last 15 days, output to the generated file name
			"Evt"{
				Get-WinEvent -ProviderName $ScenarioItem[1] | where-object {
					[datetime]$_.TimeCreated -gt (get-date).addDays(0-$dayRange)
				} | export-csv ($savePath + "\\" + $ScenarioItem[2])}
			#If it's a registry entry, pull the values from the path specified, output to the generated file name
			"Reg"{reg export $ScenarioItem[1] ($savePath + "\\" + $ScenarioItem[2])}
			#If it's a command, run the command stored as string (Make sure your command entries pipe to outfile)
			"Cmd"{invoke-expression $ScenarioItem[1]}
		}
	}	
}

#Make sure folder exists to receive output
if(-not [System.IO.Directory]::Exists($savePath)){mkdir ($savePath)}
#Run scenario from start, output to folder
runScenario($CurrentScenario)
