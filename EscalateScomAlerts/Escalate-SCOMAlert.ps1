########################################################################
# Escalate-SCOMAlert.ps1
# Hugh Scott
# 2018/07/09
#
# Description:
#   Escalate SCOM alerts based on rules in config file.  Note that this
# may require that the administrator add custom ResolutionStates to 
# SCOM.
#
# THIS CODE IS PROVIDED AS-IS WITH NO WARRANTIES EITHER EXPRESSED OR
# IMPLIED.
#
# Modifications:
# Date         Initials    Description
# 2018/07/09   HMS         -Original
# 2018/07/10   HMS         -Updated; added postPipelineFilter
#
########################################################################

function DateFieldReplace {
param (
    [string]$criteria,
    [int]$timeOffset
)

    # INITIALIZE RETURN VALUE
    [string]$tmpString = ""

    # COMPUTE TIME OFFSET; CAST AS STRING VALUE
    [int]$m_timeOffset = -$timeOffset
    [datetime]$compareDate = (Get-Date).AddMinutes($m_timeOffset).ToUniversalTime()
    [string]$dateString = $compareDate.ToString("MM/dd/yyyy HH:mm:ss")

    If($criteria -match "__LastModified__")
    {
        $tmpString = $criteria.Replace("__LastModified__", $dateString)
    } 
    ElseIf($criteria -match "__TimeRaised__")
    {
        $tmpString = $criteria.Replace("__TimeRaised__", $dateString)
    } 
    Else
    {
        $tmpString = $criteria
    }

    # REPLACE ESCAPED XML CHARACTERS
    $tmpString = $tmpString.Replace("&lt;","<")
    $tmpString = $tmpString.Replace("&gt;",">")

    Return $tmpString

}

function CleanPostPipelineFilter {
param ([string]$postPipelineFilter)
    [string]$tmpString = ""

    # REPLACE ESCAPED XML CHARACTERS
    $tmpString = $postPipelineFilter.Replace("&lt;","<")
    $tmpString = $postPipelineFilter.Replace("&gt;",">")

    Return $tmpString
}

# RETRIEVE CONFIGURATION FILE WITH RULES AND EXCEPTIONS
[xml]$configFile= Get-Content "E:\Files\Configuration\OperationsManager\AlertEscalation\escalate.alert.config"

# MANAGEMENT SERVER
[string]$managementServer = "MGR31.abcd.lcl"

# LOG FILE
[string]$logFilePath = $configFile.config.settings.outputpath.name
[string]$fileName = "AlertEscalation." + (Get-Date -Format "yyyy.MM.dd") + ".log"
[string]$logFileName = Join-Path $logFilePath $fileName

Import-Module OperationsManager
$Connection = New-SCManagementGroupConnection $managementServer -PassThru

If($Connection.IsActive)
{
    # INITIALIZE AlertCount
    [int]$AlertCount = 0

    # PROCESS EXCEPTIONS FIRST
    $alertExceptions = $configFile.SelectNodes("//config/exceptions/exception[@enabled='true']") | Sort-Object {$_.Sequence}

    foreach($exception in $alertExceptions)
    {
        # ASSIGN VALUES
        # Write-Host $exception.name
        [string]$criteria = $exception.Criteria.InnerText
        [int]$newResolutionState = $exception.NewResolutionState
        [string]$postPipelineFilter = $exception.PostPipelineFilter.InnerText
        [string]$comment = $exception.Comment.InnerText
        [string]$name = $exception.Name

        # REPLACE TIME BASED CRITERIA
        if($criteria -match "__TimeRaised__")
        {
            [int]$timeRaisedAge = $exception.TimeRaisedAge
            $criteria = DateFieldReplace $criteria $timeRaisedAge
        }
        if($criteria -match "__LastModified__")
        {
            [int]$lastModifiedAge = $exception.LastModifiedAge
            $criteria = DateFieldReplace $criteria $lastModifiedAge
        }

        # COLLECT ALERTS BASED ON CRITERIA
        If($postPipelineFilter -eq "")
        {
            $alerts = Get-SCOMAlert -Criteria $criteria 
        } 
        Else 
        {
            [string]$cleanString=CleanPostPipelineFilter $postPipelineFilter
            [scriptblock]$filter=[System.Management.Automation.ScriptBlock]::Create($cleanString)

            $alerts = Get-SCOMAlert -Criteria $criteria | Where-Object -FilterScript $filter
        }

        ### UPDATE MATCHING ALERTS TO NEW RESOLUTION STATE
        If($alerts.Count -gt 0)
        {
            $alerts | Set-SCOMAlert -ResolutionState $newResolutionState -Comment $Comment
            # Write-Host $criteria
            $AlertCount = $alerts.Count
            $msg = (Get-Date -Format "yyyy/MM/dd hh:mm:ss") + " : INFO : Updated $AlertCount alert(s) to resolution state $newResolutionState (Exception: $name)."
            # Write-Host "  : $msg"
            Add-Content $logFileName $msg
        }
     

        # RESET EXCEPTION VALUES
        $criteria = $null
        $newResolutionState = $null
        $postPipelineFilter = $null
        $comment = $null
        $name=$null

    }

    # PROCESS RULES SECOND
    $alertRules = $configFile.SelectNodes("//config/rules/rule[@enabled='true']") | Sort-Object {$_.sequence}

    foreach($rule in $alertRules){
        # ASSIGN VALUES
        # Write-Host $rule.name
        [string]$criteria = $rule.Criteria.InnerText
        [int]$newResolutionState = $rule.NewResolutionState
        [string]$postPipelineFilter = $rule.PostPipelineFilter.InnerText
        [string]$comment = $rule.Comment.InnerText
        [string]$name=$rule.name

        # REPLACE TIME BASED CRITERIA
        if($criteria -match "__TimeRaised__")
        {
            [int]$timeRaisedAge = $rule.TimeRaisedAge
            $criteria = DateFieldReplace $criteria $timeRaisedAge
        }
        if($criteria -match "__LastModified__")
        {
            [int]$lastModifiedAge = $rule.LastModifiedAge
            $criteria = DateFieldReplace $criteria $lastModifiedAge
        }

        # COLLECT ALERTS BASED ON CRITERIA
        If($postPipelineFilter -eq "")
        {
            $alerts = Get-SCOMAlert -Criteria $criteria 
        } 
        Else 
        {
            [string]$cleanString=CleanPostPipelineFilter $postPipelineFilter
            [scriptblock]$filter=[System.Management.Automation.ScriptBlock]::Create($cleanString)

            $alerts = Get-SCOMAlert -Criteria $criteria | Where-Object -FilterScript $filter
        }

        ### UPDATE MATCHING ALERTS TO NEW RESOLUTION STATE
        If($alerts.Count -gt 0)
        {
            $alerts | Set-SCOMAlert -ResolutionState $newResolutionState -Comment $Comment
            # Write-Host $criteria
            $AlertCount = $alerts.Count
            $msg = (Get-Date -Format "yyyy/MM/dd hh:mm:ss") + " : INFO : Updated $AlertCount alert(s) to resolution state $newResolutionState (Exception: $name)."
            # Write-Host "  : $msg"

            Add-Content $logFileName $msg
        }

        # RESET RULE VALUES
        $criteria = $null
        $newResolutionState = $null
        $postPipelineFilter = $null
        $comment = $null
        $name=$null
    }

}
Else
{
    $msg = (Get-Date -Format "yyyy/MM/dd hh:mm:ss") + " : ERROR : Unable to connect to Management Server"
    Add-Content $logFileName $msg
}