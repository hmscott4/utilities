<#
    .DESCRIPTION
        Escalate SCOM alerts based on rules in config file.  Note that this may require that the administrator add custom ResolutionStates to  SCOM.
    
    .NOTES
        THIS CODE IS PROVIDED AS-IS WITH NO WARRANTIES EITHER EXPRESSED OR IMPLIED.
#>

#region Configuration Information
# RETRIEVE CONFIGURATION FILE WITH RULES AND EXCEPTIONS
[xml]$configFile = Get-Content 'D:\Admin\Scripts\EscalateScomAlerts\escalate.alert.config'

# MANAGEMENT SERVER
[string]$managementServer = '.'

# LOG FILE
[string]$logFilePath = $configFile.config.settings.outputpath.name
[string]$fileName = "AlertEscalation." + (Get-Date -Format "yyyy.MM.dd") + ".log"
[string]$logFileName = Join-Path $logFilePath $fileName

#endregion Configuration Information

# Load the Operations Manager script API
$momApi = New-Object -ComObject MOM.ScriptAPI

#region Functions
function DateFieldReplace
{
    param
    (
        [string]$criteria,
        [int]$timeOffset
    )

    # INITIALIZE RETURN VALUE
    [string]$tmpString = ''

    # COMPUTE TIME OFFSET; CAST AS STRING VALUE
    [int]$m_timeOffset = - $timeOffset
    [datetime]$compareDate = (Get-Date).AddMinutes($m_timeOffset).ToUniversalTime()
    [string]$dateString = $compareDate.ToString("MM/dd/yyyy HH:mm:ss")

    if ($criteria -match "__LastModified__")
    {
        $tmpString = $criteria.Replace("__LastModified__", $dateString)
    } 
    elseif ($criteria -match "__TimeRaised__")
    {
        $tmpString = $criteria.Replace("__TimeRaised__", $dateString)
    } 
    else
    {
        $tmpString = $criteria
    }

    # REPLACE ESCAPED XML CHARACTERS
    $tmpString = $tmpString.Replace("&lt;", "<")
    $tmpString = $tmpString.Replace("&gt;", ">")

    Return $tmpString
}

function CleanPostPipelineFilter
{
    param
    (
        [string]
        $postPipelineFilter
    )

    [string]$tmpString = ""

    # REPLACE ESCAPED XML CHARACTERS
    $tmpString = $postPipelineFilter.Replace("&lt;", "<")
    $tmpString = $postPipelineFilter.Replace("&gt;", ">")

    Return $tmpString
}
#endregion Functions

if ( -not ( Get-Module -Name OperationsManager ) )
{
    Import-Module OperationsManager
}

#region Update Type Data

# Add a UnitMonitor property to the alert which contains the associated unit monitor object
$updateTypeDataUnitMonitorParameters = @{
    TypeName   = 'Microsoft.EnterpriseManagement.Monitoring.MonitoringAlert'
    MemberType = 'ScriptProperty'
    MemberName = 'UnitMonitor'
    Value      = {
        if ( $this.IsMonitorAlert )
        {
            function GetScomChildNodes
            {
                [CmdletBinding()]
                param
                (
                    [Parameter(Mandatory = $true)]
                    [System.Object]
                    $MonitoringHierarchyNode
                )

                # Create an array for the unit monitors
                $unitMonitors = @()

                foreach ( $childNode in $MonitoringHierarchyNode.ChildNodes )
                {
                    if ( $childNode.Item.GetType().FullName -eq 'Microsoft.EnterpriseManagement.Configuration.UnitMonitor' )
                    {
                        Write-Verbose -Message "Unit Monitor: $($childNode.Item.DisplayName)"
                        $unitMonitors += $childNode.Item
                    }
                    else
                    {
                        Write-Verbose -Message $childNode.Item.DisplayName
                        Write-Verbose -Message ($childNode.GetType().FullName)
                        GetScomChildNodes -MonitoringHierarchyNode $childNode.Item
                    }
                }

                return $unitMonitors
            }

            # Get the associated monitor from the alert
            if ( $this.IsMonitorAlert )
            {
                $monitor = Get-SCOMClassInstance -Id $this.MonitoringObjectId
            }
            else
            {
                Write-Verbose -Message ( 'The alert "{0}" is not a monitor alert.' -f $this.Name )
                exit
            }
    
            # Get the child nodes of the monitor
            $unitMonitors = @()
            foreach ( $childNode in $monitor.GetMonitorHierarchy().ChildNodes )
            {
                $unitMonitors += GetScomChildNodes -MonitoringHierarchyNode $childNode
            }

            # Get the unit monitor which generated the alert
            $unitMonitor = $unitMonitors | Where-Object -FilterScript { $_.Id -eq $this.MonitoringRuleId }

            return $unitMonitor
        }
    }
}
Update-TypeData @updateTypeDataUnitMonitorParameters

# Add a Monitor property to the alert which contains the associated unit monitor object
$updateTypeDataMonitorParameters = @{
    TypeName   = 'Microsoft.EnterpriseManagement.Monitoring.MonitoringAlert'
    MemberType = 'ScriptProperty'
    MemberName = 'Monitor'
    Value      = {
        Get-SCOMClassInstance -Id $this.MonitoringObjectId
    }
}
Update-TypeData @updateTypeDataMonitorParameters

# Add a HealthStateSuccess property to the alert which contains the associated unit monitor object
$updateTypeDataHealthStateSuccessParameters = @{
    TypeName   = 'Microsoft.EnterpriseManagement.Monitoring.MonitoringAlert'
    MemberType = 'ScriptProperty'
    MemberName = 'HealthStateSuccess'
    Value      = {
        return $this.UnitMonitor.OperationalStateCollection |
            Where-Object -FilterScript { $_.HealthState -eq 'Success' } |
            Select-Object -ExpandProperty Name
    }
}
Update-TypeData @updateTypeDataHealthStateSuccessParameters

#endregion Update Type Data

$Connection = New-SCManagementGroupConnection $managementServer -PassThru

If ($Connection.IsActive)
{
    # INITIALIZE AlertCount
    [int]$AlertCount = 0

    # Alert Storm Processing
    $alertStormRules = $configFile.SelectNodes("//config/alertStormRules/stormRule[@enabled='true']") | Sort-Object { $_.Sequence }

    foreach ( $alertStormRule in $alertStormRules )
    {
        # Get the new through assigned alerts and group them by the defined property
        $stormAlerts = Get-SCOMAlert -ResolutionState @(0..5) |
            Group-Object -Property $alertStormRule.Property |
            Where-Object -FilterScript { $_.Count -gt $alertStormRule.count }

        foreach ( $stormAlert in $stormAlerts )
        {
            # Get the alert name
            $alertName = $stormAlert.Group | Select-Object -ExpandProperty Name -Unique

            # Define the "ticket id"
            $ticketId = ( Get-Date -Format 'MM/dd/yyyy hh:mm:ss {0}' ) -f $alertName
            
            # Mark the alert as being part of an alert storm
            $stormAlert.Group | Set-SCOMAlert -ResolutionState 18 -Comment $alertStormRule.Comment -TicketId $ticketId
            
            # Get a unique list of monitoring objects
            $monitoringObjects = $stormAlert.Group |
                Select-Object -ExpandProperty MonitoringObjectFullName -Unique |
                Sort-Object
            
            # Define the string which will be passed in as the "script name" property for LogScriptEvent
            $stormDescription = "The alert ""$alertName"" was triggered $($stormAlert.Count) times for the following objects."
            
            # Define the event details
            $eventDetails = New-Object -TypeName System.Text.StringBuilder
            $eventDetails.AppendLine() > $null
            $eventDetails.AppendLine() > $null
            $monitoringObjects | ForEach-Object -Process { $eventDetails.AppendLine($_) > $null }
            $eventDetails.AppendLine() > $null
            $eventDetails.AppendLine("Internal ticket id: $ticketId") > $null

            # Raise an event indicating an alert storm was detected
            $momApi.LogScriptEvent($stormDescription, 9908, 2, $eventDetails.ToString())
        }
    }
    
    # PROCESS EXCEPTIONS FIRST
    $alertExceptions = $configFile.SelectNodes("//config/exceptions/exception[@enabled='true']") | Sort-Object { $_.Sequence }

    foreach ($exception in $alertExceptions)
    {
        # ASSIGN VALUES
        # Write-Host $exception.name
        [string]$criteria = $exception.Criteria.InnerText
        [int]$newResolutionState = $exception.NewResolutionState
        [string]$postPipelineFilter = $exception.PostPipelineFilter #.InnerText
        [string]$comment = $exception.Comment.InnerText
        [string]$name = $exception.Name

        # REPLACE TIME BASED CRITERIA
        if ($criteria -match "__TimeRaised__")
        {
            [int]$timeRaisedAge = $exception.TimeRaisedAge
            $criteria = DateFieldReplace $criteria $timeRaisedAge
        }
        if ($criteria -match "__LastModified__")
        {
            [int]$lastModifiedAge = $exception.LastModifiedAge
            $criteria = DateFieldReplace $criteria $lastModifiedAge
        }

        # COLLECT ALERTS BASED ON CRITERIA
        If ($postPipelineFilter -eq "")
        {
            $alerts = Get-SCOMAlert -Criteria $criteria 
        } 
        Else 
        {
            [string]$cleanString = CleanPostPipelineFilter $postPipelineFilter
            [scriptblock]$filter = [System.Management.Automation.ScriptBlock]::Create($cleanString)

            $alerts = Get-SCOMAlert -Criteria $criteria | Where-Object -FilterScript $filter
        }

        ### UPDATE MATCHING ALERTS TO NEW RESOLUTION STATE
        If ($alerts.Count -gt 0)
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
        $name = $null

    }

    # PROCESS RULES SECOND
    $alertRules = $configFile.SelectNodes("//config/rules/rule[@enabled='true']") | Sort-Object { $_.sequence }

    foreach ($rule in $alertRules)
    {
        # ASSIGN VALUES
        # Write-Host $rule.name
        [string]$criteria = $rule.Criteria.InnerText
        [int]$newResolutionState = $rule.NewResolutionState
        [string]$postPipelineFilter = $rule.PostPipelineFilter #.InnerText
        [string]$comment = $rule.Comment.InnerText
        [string]$name = $rule.name

        # REPLACE TIME BASED CRITERIA
        if ($criteria -match "__TimeRaised__")
        {
            [int]$timeRaisedAge = $rule.TimeRaisedAge
            $criteria = DateFieldReplace $criteria $timeRaisedAge
        }
        if ($criteria -match "__LastModified__")
        {
            [int]$lastModifiedAge = $rule.LastModifiedAge
            $criteria = DateFieldReplace $criteria $lastModifiedAge
        }

        # COLLECT ALERTS BASED ON CRITERIA
        if ( [System.String]::IsNullOrEmpty($postPipelineFilter) )
        {
            $alerts = Get-SCOMAlert -Criteria $criteria 
        } 
        else
        {
            [string]$cleanString = CleanPostPipelineFilter $postPipelineFilter
            [scriptblock]$filter = [System.Management.Automation.ScriptBlock]::Create($cleanString)

            $alerts = Get-SCOMAlert -Criteria $criteria | Where-Object -FilterScript $filter
        }

        ### UPDATE MATCHING ALERTS TO NEW RESOLUTION STATE
        If ($alerts.Count -gt 0)
        {
            $alerts | Set-SCOMAlert -ResolutionState $newResolutionState -Comment $Comment
            # Write-Host $criteria
            $AlertCount = $alerts.Count
            $msg = (Get-Date -Format "yyyy/MM/dd hh:mm:ss") + " : INFO : Updated $AlertCount alert(s) to resolution state $newResolutionState (Rule: $name)."
            # Write-Host "  : $msg"

            Add-Content $logFileName $msg
        }

        # RESET RULE VALUES
        $criteria = $null
        $newResolutionState = $null
        $postPipelineFilter = $null
        $comment = $null
        $name = $null
    }

}
Else
{
    $msg = (Get-Date -Format "yyyy/MM/dd hh:mm:ss") + " : ERROR : Unable to connect to Management Server"
    Add-Content $logFileName $msg
}