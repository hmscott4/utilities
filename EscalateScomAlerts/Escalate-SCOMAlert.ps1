########################################################################
# Escalate-SCOMAlert.ps1
# Hugh Scott
# 2016/05/09
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
# 2018/05/09   HMS         -Original
#
########################################################################
[xml]$configFile= Get-Content "escalate.alert.config"

[string]$managementServer = $configFile.config.settings.managementserver.name

Import-Module OperationsManager
New-SCManagementGroupConnection $managementServer

# Esclation Rules
$esclationRules = $configFile.SelectNodes("//config/rules/rule[@enabled='true']")

foreach($rule in $esclationRules)
{
    # Write-Host $rule.name
    [int]$minutes=-$rule.AgeInMinutes
    [datetime]$compareDate = (Get-Date).AddMinutes($minutes)
    [string]$criteria = $rule.criteria
    [int]$newResolutionState = $rule.NewResolutionState

    $alerts = get-scomalert -Criteria $criteria | where-object {$_.TimeRaised -lt $compareDate.ToUniversalTime()}

    foreach($alert in $alerts)
    {
        # $alert | set-scomalert -ResolutionState $newResolutionState
        # write-host $alert.name
    }
}


