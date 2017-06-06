workflow Invoke-Autoshutdown {
    param (
    [string]$AzureSubscriptionName ="Default",
    [bool]$Simulate = $true
    )
    Function Test-ScheduleEntry {
                    param(
                        [Object]$timeRanges
                    )   
                        # Initialize variables
                        $result = @()
                        foreach($timeRange in $timeRanges){
                            $rangeStart, $rangeEnd, $parsedDay = $null
                            $currentTime = (Get-Date).ToUniversalTime()
                            $midnight = $currentTime.AddDays(1).Date            
        
                                try{
                                    # Parse as range if contains '->'
                                    if($TimeRange -like "*->*"){
                                        $timeRangeComponents = $TimeRange -split "->" | foreach {$_.Trim()}
                                        if($timeRangeComponents.Count -eq 2){
                                            $rangeStart = Get-Date $timeRangeComponents[0]
                                            $rangeEnd = Get-Date $timeRangeComponents[1]
                            
                                            # Check for crossing midnight
                                            if($rangeStart -gt $rangeEnd){
                                                # If current time is between the start of range and midnight tonight, interpret start time as earlier today and end time as tomorrow
                                                if($currentTime -ge $rangeStart -and $currentTime -lt $midnight){
                                                    $rangeEnd = $rangeEnd.AddDays(1)
                                                }
                                                # Otherwise interpret start time as yesterday and end time as today   
                                                else{
                                                    $rangeStart = $rangeStart.AddDays(-1)
                                                }
                                            }
                                        }   
                                        else{
                                            Write-Output "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'" 
                                        }
                                    }         
                                    ELSEIF ($timerange -eq "never"){
                                        return $false
                                    }
                                    ELSEIF ($timerange -eq "bypass"){
                                        return $false
                                    }

                                    # Otherwise attempt to parse as a full day entry, e.g. 'Monday' or 'December 25' 
                                    else{
                                        # If specified as day of week, check if today
                                        if([System.DayOfWeek].GetEnumValues() -contains $TimeRange){
                                            if($TimeRange -eq (Get-Date).DayOfWeek){
                                                $parsedDay = Get-Date "00:00"
                                            }
                                            else{
                                                # Skip detected day of week that isn't today
                                            }
                                        }
                                        # Otherwise attempt to parse as a date, e.g. 'December 25'
                                        else{
                                            $parsedDay = Get-Date $TimeRange
                                        }
                        
                                        if($parsedDay -ne $null){
                                            $rangeStart = $parsedDay # Defaults to midnight
                                            $rangeEnd = $parsedDay.AddHours(23).AddMinutes(59).AddSeconds(59) # End of the same day
                                        }
                                    }
                                }
                                catch{
                                    # Record any errors and return false by default
                                    Write-Output "`tWARNING: Exception encountered while parsing time range. Details: $($_.Exception.Message). 
                                    Check the syntax of entry, e.g. '<StartTime> -> <EndTime>', or days/dates like 'Sunday' and 'December 25'"   
                                    return $false
                                }
                
                                # Check if current time falls within range
                                if($currentTime -ge $rangeStart -and $currentTime -le $rangeEnd){
                                    $result += New-object psobject -Property @{
                                        "timerange" = $timerange
                                        "shutdown" = $true
                                    }
                                }
                                else{
                                    $result += New-object psobject -Property @{
                                        "timerange" = $timerange
                                        "shutdown" = $false
                                    }
                                }
                            }
                    return $result | select-object Timerange,shutdown
    }
    # Write out time.
    $StartTime = (Get-Date).ToUniversalTime()
    Write-Output "[$($StartTime.ToString("dddd, yyyy MMM dd HH:mm:ss"))]Starting Script"
    Write-Output "Script Version 1.0"
    if ($Simulate -eq $true){
        Write-Output "Running in simulate mode... no machines will be harmed."
    }
    # Get Azure runbook automation variables.
    if($AzureSubscriptionName -eq "Default"){
        $AzureSubscriptionName = Get-AutomationVariable -Name "Default Azure Subscription"
    }
    if($AzureSubscriptionName.Length -gt 1){
        Write-Output "Using Subscription $AzureSubscriptionName "
    }
    else {
        throw "No Subscription Specified."
    }

    # Begin Azure Login
    #Login to AzureRM
    $connectionName = "AzureRunAsConnection"
    try {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection= Get-AutomationConnection -Name $connectionName         

        Write-Output "Signing in to Azure..."
        Add-AzureRmAccount `
         -ServicePrincipal `
         -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
        Write-Output "Setting context to $AzuresubscriptionName"     
        Set-AzureRmContext -SubscriptionName $AzureSubscriptionName           
    }
    catch {
        if (!$servicePrincipalConnection){
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } 
        else {
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }
    try {
        # Get the connection "AzureRunAsConnection "
        $connectionName = "AzureClassicRunAsConnection"
        $servicePrincipalConnection= Get-AutomationConnection -Name $connectionName   
        Write-Output "Signing in to Azure Classic..."
        $classicCert = Get-AutomationCertificate $servicePrincipalConnection.CertificateAssetName
        Set-AzureSubscription -SubscriptionName $AzureSubscriptionName -SubscriptionId $servicePrincipalConnection.SubscriptionId -Certificate $classicCert 
        $subsilent = (Select-AzureSubscription -SubscriptionName $AzureSubscriptionName)         
    }
    catch {
        if (!$servicePrincipalConnection){
            $ErrorMessage = "Classic Connection $connectionName not found."
            throw $ErrorMessage
        } 
        else {
            Write-Error -Message $_.Exception
        }
    }
    # Set Subscription
    $subsilent = (Select-AzureRmSubscription -SubscriptionName $AzureSubscriptionName)
    # Get all resource manager VM's.
    $resourceManagerVMs = Get-AzureRmVM -WarningAction SilentlyContinue
    # Get all Classic VM's
    $ClassicVMs = Get-AzureService
    # Get resource groups that are tagged for automatic shutdown of resources
	$taggedResourceGroups = @(Get-AzureRmResourceGroup | where {$_.Tags.Keys -contains "AutoShutdownSchedule" | sort Name })
    # Get all Stream jobs in the subscription
    $streamjobs = Get-AzureRmStreamAnalyticsJob -NoExpand

    # Initialize Variables for VM's to be shutdown and VM's for startup.
    $VMstoshutdown = @()
    $ClassicVMstoshutdown = @()
    $VMStostartup = @()
    $ClassicVMstostartup = @()
    $StreamJobstoshutdown = @()
    $StreamJobstostartup = @()
    # Check for Classic VM's in tagged resourcegroups
    foreach ($VM in $ClassicVMs){
        if ($taggedResourceGroups.ResourceGroupName -contains $VM.ExtendedProperties.ResourceGroup){
            Write-Output "[$($VM.ServiceName)] is classic VM tagged via resourcegroup"
            $schedule = (($taggedResourceGroups | where {$_.Resourcegroupname -eq "$($VM.ExtendedProperties.ResourceGroup)"}).Tags).AutoShutdownSchedule
            $timeRangeList = @($schedule -split "," | foreach {$_.Trim()})
            $Schedules = Test-ScheduleEntry -TimeRanges $timeRangeList 
            $MatchedSchedules = $Schedules| where {$_.shutdown -eq $true -and $_.timerange -notcontains "bypass" -and $_.timerange -notcontains "never"}
            # If the VM matches a schedule add to the shutdown object
            $classicVM = Get-AzureVM -ServiceName $VM.ServiceName
            if ($MatchedSchedules -ne $null) {
                $ClassicVMstoshutdown += $ClassicVM
            }
            Elseif ($notags -eq $true){
                # Nothing to do as VM isn't tagged.
            }
            # If it doesn't match a schedule the machine must be started.
            Else {
                $ClassicVMStostartup += $ClassicVM
            }
            }
    }
    # Check ARM VMs for tags
    foreach ($VM in $resourceManagerVMs) {
        $schedule = $null
        $notags = $null
        # Check for direct tag or group-inherited tag
        if(($vm.Tags | Where-Object {$_.Keys -eq "AutoShutdownSchedule"})){
            # The VM has a direct tag so we will prefer that.
            Write-Output "[$($VM.Name)]Found direct tag using direct tag rather than parent resourcegroup"
            $schedule = ($vm.tags.AutoShutdownSchedule)
        }
        elseif(($taggedResourceGroups.Resourcegroupname) -contains $vm.ResourceGroupName){
            # The VM is indirectly tagged via resource group.
            Write-Output "[$($vm.Name)]Found ResourceGroupParentTag."
            $schedule = (($taggedResourceGroups | where {$_.ResourceGroupName -eq $vm.ResourceGroupName}).Tags).AutoShutdownSchedule
        }
        Else {
            # No direct or inherited tag. Skip this VM.
            Write-Output "[$($vm.Name)]No tag found."
            $notags = $true
        }

        # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
		$timeRangeList = @($schedule -split "," | foreach {$_.Trim()})

        # See if any schedule times are matched to the current time.
        $MatchedSchedules = $null
        # Have to run function inside an inline script since workflows in Azure won't pickup inline functions.
        $Schedules = Test-ScheduleEntry -TimeRanges $timeRangeList 
        $MatchedSchedules = $Schedules| where {$_.shutdown -eq $true -and $_.timerange -notcontains "bypass" -and $_.timerange -notcontains "never"}
        # If the VM matches a schedule add to the shutdown object
        if ($MatchedSchedules -ne $null) {
            $VMstoshutdown += $VM
        }
        Elseif ($notags -eq $true){
            # Nothing to do as VM isn't tagged.
        }
        # If it doesn't match a schedule the machine must be started.
        Else {
            $VMStostartup += $VM
        }
    }
    #Check Streamjob tags
    foreach ($job in $streamjobs) {
        $schedule = $null
        $notags = $null
         # Check for direct tag or group-inherited tag
        if(($job.Tags | Where-Object {$_.Keys -eq "AutoShutdownSchedule"})){
            # The VM has a direct tag so we will prefer that.
            Write-Output "[$($job.JobName)]Found direct tag using direct tag rather than parent resourcegroup"
            $schedule = ($job.tags.AutoShutdownSchedule)
        }
        elseif(($taggedResourceGroups.Resourcegroupname) -contains $job.ResourceGroupName){
            # The VM is indirectly tagged via resource group.
            Write-Output "[$($job.jobName)]Found ResourceGroupParentTag."
            $schedule = (($taggedResourceGroups | where {$_.ResourceGroupName -eq $job.ResourceGroupName}).Tags).AutoShutdownSchedule
        }
        Else {
            # No direct or inherited tag. Skip this VM.
            Write-Output "[$($job.jobName)]No tag found."
            $notags = $true
        }

        # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
		$timeRangeList = @($schedule -split "," | foreach {$_.Trim()})

        # See if any schedule times are matched to the current time.
        $MatchedSchedules = $null
        # Have to run function inside an inline script since workflows in Azure won't pickup inline functions.
        $Schedules = Test-ScheduleEntry -TimeRanges $timeRangeList 
        $MatchedSchedules = $Schedules| where {$_.shutdown -eq $true -and $_.timerange -notcontains "bypass" -and $_.timerange -notcontains "never"}
        # If the VM matches a schedule add to the shutdown object
        if ($MatchedSchedules -ne $null) {
            $StreamJobstoshutdown += $job
        }
        Elseif ($notags -eq $true){
            # Nothing to do as VM isn't tagged.
        }
        # If it doesn't match a schedule the machine must be started.
        Else {
            $StreamJobstostartup += $job
        }
    }
    # Loop through the object in parallel and shutdown VM's.
    foreach -parallel ($vm in $VMstoshutdown){
        if ($Simulate -eq $true){
            Write-Output "[$($vm.Name)] would be shut down. No action taken as running in simulate mode."
        }
        Else {
            # Obtain Current Powerstate.
            $powerstate = (((Get-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status -WarningAction SilentlyContinue).Statuses.Code) |
                         select-string -Pattern "(?<=PowerState\/)[A-z]+").Matches.Value
            # If currently running send a shutdown command
            if ($powerstate -eq "Running"){
                Write-Output "[$($VM.Name)]Shutting down VM"
                $VM | Stop-AzureRmVM -Force
            }
            Else {
                Write-Output "[$($VM.NAme)] is already shutdown"
            }
        }
    }
    # Loop through the groups in parallel and start VM's.
    foreach -parallel ($vm in $VMStostartup){
        if ($Simulate -eq $true){
            Write-Output "[$($vm.Name)] would be started. No action taken as running in simulate mode."
        }
        Else {
            # Obtain Current Powerstate.
            $powerstate = (((Get-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status -WarningAction SilentlyContinue).Statuses.Code) |
                         select-string -Pattern "(?<=PowerState\/)[A-z]+").Matches.Value
            # If currently running send a shutdown command
            if ($powerstate -ne "Running"){
                Write-Output "[$($VM.Name)]Starting VM"
                $VM | Start-AzureRmVM
            }
            Else {
                Write-Output "[$($VM.NAme)] is already in running state."
            }
        }
    }
    #Loop through the classic VM's in parallel to shutdown.
    foreach -parallel ($vm in $ClassicVMstoshutdown){
        if ($Simulate -eq $true){
            Write-Output "[$($vm.Name)] would be shut down. No action taken as running in simulate mode."
        }
        Else {
            # Obtain Current Powerstate.
            $powerstate = (((Get-AzureVM -Name $VM.Name -ServiceName $VM.ServiceName ).Status))
            # If currently running send a shutdown command
            if ($powerstate -like "Ready*"){
                Write-Output "[$($VM.Name)]Shutting down VM"
                $VM | Stop-AzureVM -Force
            }
            Else {
                Write-Output "[$($VM.Name)] is already shutdown"
            }
        }
    }
    # Loop through the groups in parallel and start VM's.
    foreach -parallel ($vm in $ClassicVMStostartup){
        if ($Simulate -eq $true){
            Write-Output "[$($vm.Name)] would be started. No action taken as running in simulate mode."
        }
        Else {
            # Obtain Current Powerstate.
            $powerstate = (((Get-AzureVM -Name $VM.Name -ServiceName $VM.ServiceName).Status))
            # If currently running send a shutdown command
            if ($powerstate -notlike "Ready*"){
                Write-Output "[$($VM.Name)]Starting VM"
                $VM | Start-AzureVM
            }
            Else {
                Write-Output "[$($VM.NAme)] is already in running state."
            }
        }
    }
    foreach -parallel  ($job in $Streamjobstoshutdown){
        if ($Simulate -eq $true){
            Write-Output "[$($job.jobName)] would be shutdown. No action taken as running in simulate mode."
        }
        Else {
            # Obtain Current Powerstate.
            $powerstate = $job.JobState
            # If currently running send a shutdown command
            if ($powerstate -eq "Running"){
                Write-Output "[$($Job.jobName)]Stopping StreamJob"
                Stop-AzureRmStreamAnalyticsJob -name $($job.JobName) -ResourceGroupName $($job.ResourceGroupName)
            }
            Else {
                Write-Output "[$($Job.jobName)] is already in stopped state."
            }
        }
    }    
    foreach -parallel ($job in $Streamjobstostartup){
        if ($Simulate -eq $true){
            Write-Output "[$($job.jobName)] would be started. No action taken as running in simulate mode."
        }
        Else {
            # Obtain Current Powerstate.
            $powerstate = $job.JobState
            # If currently running send a shutdown command
            if ($powerstate -ne "Running"){
                Write-Output "[$($Job.jobName)]Starting StreamJob"
                Start-AzureRmStreamAnalyticsJob -name $($job.JobName) -ResourceGroupName $($job.Resourcegroupname)
            }
            Else {
                Write-Output "[$($Job.jobName)] is already in running state."
            }
        }
    }
    Write-Output "ARM VM's shutdown: $($VMstoshutdown.count)"
    Write-Output "Classic VM's shutdown: $($ClassicVMstoshutdown.count)"
    Write-Output "StreamJobs Shutdown:$($streamjobstoshutdown.count)"
    Write-Output "ARM VM's started: $($VMstostartup.count)"
    Write-Output "Classic VM's started: $($ClassicVMstostartup.count)"
    Write-Output "StreamJobs started:$($streamjobstostartup.count)"
    Write-Output "Runbook finished [Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $StartTime)))]"
}
