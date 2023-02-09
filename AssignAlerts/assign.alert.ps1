<#
    .SYNOPSIS
        Assign SCOM alerts based on rules in config file.

    .DESCRIPTION
        Assign SCOM alerts based on rules in config file.  Basic assignment is done by management pack association.
    
    .NOTES
        NOTE: The configuration file must be updated with entries from the current Active Directory environment.

        THIS CODE IS PROVIDED AS-IS WITH NO WARRANTIES EITHER EXPRESSED OR IMPLIED.
#>

#region Script Parameters

[xml]$configFile = Get-Content 'D:\Admin\Scripts\AssignAlerts\assign.alert.config'

[string]$logFileDate = (Get-Date).ToString("yyyy.MM")
[string]$managementServer = '.'

[string]$logFile = "D:\Admin\Scripts\AssignAlerts\Logs\AssignAlerts.$logFileDate.log"

[string]$unroutedLogFile = "D:\Admin\Scripts\AssignAlerts\Logs\MissedAlerts.$logFileDate.log"

[bool]$logVerbose = $false

#endregion Script Parameters

function XpathExpression
{
    param
    (
        [string]$value
    )

    if ($value.Contains("'"))
    {
        return '\' + $value + '\';
    }
    elseif ($value.Contains('\'))
    {
        return """" + $value + """"
    }
    else
    {
        return $value;
    }
}

Import-Module OperationsManager
New-SCManagementGroupConnection $managementServer

###### VARIABLE FROM ORCHESTRATOR
$newAlerts = Get-SCOMAlert -ResolutionState 0

foreach ($newAlert in $newAlerts)
{
    $unAssignedAlert = $newAlert
    $mpClassId = $newAlert.MonitoringClassId
    $mpClass = Get-SCOMClass -Id $mpClassId


    ###### VARIABLE ASSIGNMENT ######
    [string]$mpName = $mpClass.ManagementPackName
    [string]$alertName = $unAssignedAlert.Name
    [string]$displayName = $unassignedAlert.MonitoringObjectDisplayName

    $alertName = XPathExpression $AlertName

    ###### FIRST PASS; GET QUEUE ASSIGNMENT EXCEPTIONS BY ALERT NAME ######
    try
    {
        $assignmentRule = $configFile.SelectSingleNode("
            //config/exceptions/exception[
                AlertName='$alertName'
                and @enabled='true'
                and contains(
                    '$($unAssignedAlert.($assignmentRule.AlertProperty))',
                    AlertPropertyContains
                )
            ]"
        )
    }
    catch [System.Exception]
    {
        $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
        $msg = "$timeNow : WARN : " + $_.Exception.Message
        Write-Host $msg
        Add-Content $unroutedLogFile $msg
    }

    if ($assignmentRule)
    {
        [string]$assignedTo = $assignmentRule.Owner
    }
    else
    {
        ###### SECOND PASS; GET ALERT ASSIGNMENTS FROM OBJECT CLASS ######
        try
        {
            $assignmentRule = $configFile.SelectSingleNode("//config/rules/rule[managementPackName='$mpName' and @enabled='true']")
        }
        catch [System.Exception]
        {
            $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
            $msg = "$timeNow : WARN : " + $_.Exception.Message
            # Write-Host $msg
            Add-Content $unroutedLogFile $msg
        }

        if ($assignmentRule)
        {
            [string]$assignedTo = $assignmentRule.Owner
        }
        else
        {
            [string]$assignedTo = "Unassigned"
        }
    }

    # Define a comment for Set-SCOMAlert
    $comment = 'Alert automation assigned to: {0}'

    if ($assignedTo -ne "Unassigned")
    {
        ######## WRITE UPDATE TO ALERT ########
        $unAssignedAlert | Set-SCOMAlert -ResolutionState 5 -Owner $assignedTo -Comment ( $comment -f $assignedTo )
        
        # Write-LogEntry
        if ($logVerbose)
        {
            $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
            $msg = "$timeNow : INFO : DisplayName: $displayName; AlertName: $alertName; Management Pack: $mpName; Owner: $assignedTo"
            # Write-Host $msg
            Add-Content $logFile $msg
        }
    }
    else
    {
        ####### UNASSIGNED ALERTS #######
        $unAssignedAlert | Set-SCOMAlert -ResolutionState 5 -Owner "Unassigned" -Comment ( $comment -f 'Unassigned' )
        # Write-LogEntry
        $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
        $msg = "$timeNow : WARN : DisplayName: $displayName; AlertName: $alertName; Management Pack: $mpName; Owner: UNASSIGNED"
        # Write-Host $msg
        Add-Content $unroutedLogFile $msg
    }
}