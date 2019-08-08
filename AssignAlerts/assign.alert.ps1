########################################################################
# Assign-SCOMAlert.ps1
# Hugh Scott
# 2016/05/09
#
# Description:
#   Assign SCOM alerts based on rules in config file.  Basic assignment
# is done by management pack association.
#
# NOTE: The configuration file must be updated with entries from the current
# Active Directory environment.
#
# THIS CODE IS PROVIDED AS-IS WITH NO WARRANTIES EITHER EXPRESSED OR
# IMPLIED.
#
# Modifications:
# Date         Initials    Description
# 2016/05/09   HMS         -Original
# 2017/02/28   HMS    - Modified to write J64 - VDI to Custom Field 10
# 2018/02/20   HMS    - Modified to write Queue information to Owner field
#
########################################################################

function XpathExpression {
param (
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


[xml]$configFile= Get-Content "E:\Files\Configuration\OperationsManager\AssignAlerts\assign.alert.config"

[string]$logFileDate = (Get-Date).ToString("yyyy.MM")
[string]$managementServer = "MGR31.abcd.lcl"

[string]$logFile = "E:\Files\Log\OperationsManager\AssignAlerts\AssignAlerts.$logFileDate.log"

[string]$unroutedLogFile = "F:\Files\Log\OperationsManager\AssignAlerts\MissedAlerts.$logFileDate.log"

[bool]$logVerbose=$false

Import-Module OperationsManager
New-SCManagementGroupConnection $managementServer

###### VARIABLE FROM ORCHESTRATOR
$NewAlerts=Get-SCOMAlert -ResolutionState 0

ForEach($NewAlert in $NewAlerts){
    $unAssignedAlert = $NewAlert
    $mpClassId = $NewAlert.MonitoringClassId
    $mpClass = Get-SCOMClass -Id $mpClassId


    ###### VARIABLE ASSIGNMENT ######
    [string]$mpName = $mpClass.ManagementPackName
    [string]$alertName = $unAssignedAlert.Name
    [string]$displayName = $unassignedAlert.MonitoringObjectDisplayName

    $alertName = XPathExpression $AlertName

    ###### FIRST PASS; GET QUEUE ASSIGNMENT EXCEPTIONS BY ALERT NAME ######
    Try {
        $assignmentRule=$configFile.SelectSingleNode("//config/exceptions/exception[AlertName='$alertName' and @enabled='true']")
    }
    Catch [System.Exception] {
        $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
        $msg = "$timeNow : WARN : " + $_.Exception.Message
        Write-Host $msg
        Add-Content $unroutedLogFile $msg
    }
    if($assignmentRule){
        [string]$assignedTo=$assignmentRule.Owner
    } else {
	    ###### SECOND PASS; GET ALERT ASSIGNMENTS FROM OBJECT CLASS ######
                Try {
	        $assignmentRule=$configFile.SelectSingleNode("//config/rules/rule[managementPackName='$mpName' and @enabled='true']")
                }
                Catch [System.Exception] {
                    $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
                    $msg = "$timeNow : WARN : " + $_.Exception.Message
                    # Write-Host $msg
                    Add-Content $unroutedLogFile $msg
                }
	    if($assignmentRule){
		    [string]$assignedTo=$assignmentRule.Owner
	    } else {
		    [string]$assignedTo="Unassigned"
	    }
    }


    If($assignedTo -ne "Unassigned"){
        ####### ASSIGNMENT EXCEPTIONS #######



        ######## WRITE UPDATE TO ALERT ########
        $unAssignedAlert | Set-SCOMAlert -ResolutionState 5 -Owner $assignedTo -Comment "Service Desk Assignment By Orchestrator: $assignedTo"
        # Write-LogEntry
        If($logVerbose){
            $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
            $msg = "$timeNow : INFO : DisplayName: $displayName; AlertName: $alertName; Management Pack: $mpName; Owner: $assignedTo"
            # Write-Host $msg
            Add-Content $logFile $msg
        }

    } else {
        ####### UNASSIGNED ALERTS #######
        $unAssignedAlert | Set-SCOMAlert -ResolutionState 5 -Owner "Unassigned" -Comment "Service Desk Assignment By Orchestrator: Unassigned"
        # Write-LogEntry
        $timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
        $msg = "$timeNow : WARN : DisplayName: $displayName; AlertName: $alertName; Management Pack: $mpName; Owner: UNASSIGNED"
        # Write-Host $msg
        Add-Content $unroutedLogFile $msg
    }
}