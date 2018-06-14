# Set-ServiceCredential.ps1
# Written by Bill Stewart (bstewart@iname.com)
#
# PowerShell script for setting credentials for one or more services on one or
# more computers.

#requires -version 2

<#
.SYNOPSIS
Sets start credentials for one or more services on one or more computers.

.DESCRIPTION
Sets start credentials for one or more services on one or more computers.

.PARAMETER ServiceName
Specifies one or more service names. You can specify either the Name or DisplayName property for the services. Wildcards are not supported.

.PARAMETER ComputerName
Specifies one or more computer names. The default is the current computer. This parameter accepts pipeline input containing computer names or objects with a ComputerName property.

.PARAMETER ServiceCredential
Specifies the credentials to use to start the service(s).

.PARAMETER ConnectionCredential
Specifies credentials that have permissions to change the service(s) on the computer(s).

.NOTES
Default confirm impact is High. To suppress the prompt, specify -Confirm:$false or set the $ConfirmPreference variable to "None".
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [parameter(Position=0,Mandatory=$true)]
    [String[]] $ServiceName,
  [parameter(Position=1,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
    $ComputerName,
  [parameter(Position=2,Mandatory=$true)]
    [Management.Automation.PSCredential] $ServiceCredential,
    [Management.Automation.PSCredential] $ConnectionCredential
)

begin {
  function Set-ServiceCredential {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
    param(
      $serviceName,
      $computerName,
      $serviceCredential,
      $connectionCredential
    )
    # Get computer name if passed by property name.
    if ( $computerName.ComputerName ) {
      $computerName = $computerName.ComputerName
    }
    # Empty computer name or . is local computer.
    if ( (-not $computerName) -or $computerName -eq "." ) {
      $computerName = [Net.Dns]::GetHostName()
    }
    $wmiFilter = "Name='{0}' OR DisplayName='{0}'" -f $serviceName
    $params = @{
      "Namespace" = "root\CIMV2"
      "Class" = "Win32_Service"
      "ComputerName" = $computerName
      "Filter" = $wmiFilter
      "ErrorAction" = "Stop"
    }
    if ( $connectionCredential ) {
      # Specify connection credentials only when not connecting to the local computer.
      if ( $computerName -ne [Net.Dns]::GetHostName() ) {
        $params.Add("Credential", $connectionCredential)
      }
    }
    try {
      $service = Get-WmiObject @params
    }
    catch [System.Management.Automation.RuntimeException],[System.Runtime.InteropServices.COMException] {
      Write-Error "Unable to connect to '$computerName' due to the following error: $($_.Exception.Message)"
      return
    }
    if ( -not $service ) {
      Write-Error "Unable to find service named '$serviceName' on '$computerName'."
      return
    }
    if ( $PSCmdlet.ShouldProcess("Service '$serviceName' on '$computerName'","Set credentials") ) {
      # See https://msdn.microsoft.com/en-us/library/aa384901.aspx
      $returnValue = ($service.Change($null,                 # DisplayName
        $null,                                               # PathName
        $null,                                               # ServiceType
        $null,                                               # ErrorControl
        $null,                                               # StartMode
        $null,                                               # DesktopInteract
        $serviceCredential.UserName,                         # StartName
        $serviceCredential.GetNetworkCredential().Password,  # StartPassword
        $null,                                               # LoadOrderGroup
        $null,                                               # LoadOrderGroupDependencies
        $null)).ReturnValue                                  # ServiceDependencies
      $errorMessage = "Error setting credentials for service '$serviceName' on '$computerName'"
      switch ( $returnValue ) {
        0  { Write-Verbose "Set credentials for service '$serviceName' on '$computerName'" }
        1  { Write-Error "$errorMessage - Not Supported" }
        2  { Write-Error "$errorMessage - Access Denied" }
        3  { Write-Error "$errorMessage - Dependent Services Running" }
        4  { Write-Error "$errorMessage - Invalid Service Control" }
        5  { Write-Error "$errorMessage - Service Cannot Accept Control" }
        6  { Write-Error "$errorMessage - Service Not Active" }
        7  { Write-Error "$errorMessage - Service Request timeout" }
        8  { Write-Error "$errorMessage - Unknown Failure" }
        9  { Write-Error "$errorMessage - Path Not Found" }
        10 { Write-Error "$errorMessage - Service Already Stopped" }
        11 { Write-Error "$errorMessage - Service Database Locked" }
        12 { Write-Error "$errorMessage - Service Dependency Deleted" }
        13 { Write-Error "$errorMessage - Service Dependency Failure" }
        14 { Write-Error "$errorMessage - Service Disabled" }
        15 { Write-Error "$errorMessage - Service Logon Failed" }
        16 { Write-Error "$errorMessage - Service Marked For Deletion" }
        17 { Write-Error "$errorMessage - Service No Thread" }
        18 { Write-Error "$errorMessage - Status Circular Dependency" }
        19 { Write-Error "$errorMessage - Status Duplicate Name" }
        20 { Write-Error "$errorMessage - Status Invalid Name" }
        21 { Write-Error "$errorMessage - Status Invalid Parameter" }
        22 { Write-Error "$errorMessage - Status Invalid Service Account" }
        23 { Write-Error "$errorMessage - Status Service Exists" }
        24 { Write-Error "$errorMessage - Service Already Paused" }
      }
    }
  }
}

process {
  foreach ( $computerNameItem in $ComputerName ) {
    foreach ( $serviceNameItem in $ServiceName ) {
      Set-ServiceCredential $serviceNameItem $computerNameItem $ServiceCredential $ConnectionCredential
    }
  }
}
