<#
.SYNOPSIS
Sets data source credentials for Reporting Services data sources based on configuration file.

.DESCRIPTION
Sets data source credentials for Reporting Services data sources based on configuration file.

.PARAMETER ManagementGroup
Specifies a Management Group which must be configured in the associated configuration file.

.PARAMETER ServerName
Specifies the servername hosting the datasources to be managed.

.PARAMETER DataSourceName
Specifies the DataSourceName to be managed.

.EXAMPLES
  .\Manage-DataSourcesByGroup.ps1 -ManagementGroup "FOO" -ServerName "DnsHostName" -InstanceName "Default" -DataSourceName "DataSource"
  .\Manage-DataSourcesByGroup.ps1 -ManagementGroup "FOO" -ServerName "DnsHostName" -InstanceName "Default" -UserName "UserName"

  Supports -WhatIf
  Supports -Verbose

.NOTES
THIS SOFTWARE IS PROVIDED AS-IS.  THERE IS NO WARRANTY EITHER EXPRESSED OR IMPLIED

.HISTORY
2017/12/11    HMS    New script

#>
[CmdletBinding(SupportsShouldProcess=$true)]
param (
	[Parameter(Mandatory=$true)]
	[string]$ManagementGroup,
	[Parameter(Mandatory=$true)]
	[string]$ServerName,
	[Parameter(Mandatory=$true)]
	[string]$InstanceName,
	[Parameter(Mandatory=$false)]
	[string]$DataSourceName="ALL",
	[Parameter(Mandatory=$false)]
	[string]$UserName="",
	[Parameter(Mandatory=$false)] 
	[string]$ConfigFile="OpsMgrConfig.config"
)

function ChangeDataSourcePassword {
    param (
        [string]$reportServerURI,
        [string]$dataSourceName,
        [Management.Automation.PSCredential]$dataSourceCredential
    )

    [string]$userName = $dataSourceCredential.UserName
    # $password = "password" #UpdatedPassword
    $uri = "{0}/ReportService2010.asmx?WSDL" -f $reportServerURI
 
    $reporting = New-WebServiceProxy -uri $uri -UseDefaultCredential -namespace "ReportingWebService"
    $DataSourceRefs = $reporting.ListChildren('/', $true) | Where-Object {$_.TypeName -eq "DataSource" -and $_.Name -eq $dataSourceName}
 
    If($DataSourceRefs){
        foreach($DataSourceRef in $DataSourceRefs){

            $dataSourceObj = $reporting.GetDataSourceContents($DataSourceRef.path)[0]

            If($DataSourceObj.UserName -eq $userName){
                If($WhatIfPreference.IsPresent){
                    $msg = "  WHATIF: Updating password for UserName {0} on DataSource {1}" -f $userName, $dataSourceName
                    write-verbose $msg
                } Else {
                    $DataSourceObj.Password = $dataSourceCredential.GetNetworkCredential().Password
                    Try{
                        $reporting.SetDataSourceContents($DataSourceRef.Path, $dataSourceObj)
                        $msg = "  ACTION: Updating password for UserName {0} on DataSource {1}" -f $userName, $dataSourceName
                        write-verbose $msg
                    } Catch {
                        $msg = $_.Exception.Message
                        write-verbose $msg
                    }
                }
            } Else {
                $msg = "  USER NAME MISMATCH: The username on data source {0} does not match the username in the config file [DataSource={1}, Config={2}]." -f $dataSourceName, $DataSourceObj.UserName, $userName
                write-verbose $msg
            }

        }
    } Else {
        $msg = "  NOT FOUND: No matching data sources found for {0}" -f $dataSourceName
        write-verbose $msg
    }
}

##### BEGIN MAIN SCRIPT #####

If(Test-Path $ConfigFile){
    [xml]$config= Get-content $ConfigFile
} else {
    Throw "Configuration file is missing!"
}

# DECLARE VARIABLES FOR STRING COMPARISON
[string]$upperCase="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
[string]$lowerCase="abcdefghijklmnopqrstuvwxyz"

# UPDATE ALL PARAMETERS TO LOWER CASE
$ManagementGroup = $ManagementGroup.ToLower()
$ServerName = $ServerName.ToLower()
$InstanceName = $InstanceName.ToLower()
$DataSourceName = $DataSourceName.ToLower()
$UserName = $UserName.ToLower()

# RETRIEVE SERVER URI
[string]$xPathServerInfo = "/configuration/ManagementGroup[translate(@name, '" + $upperCase + "','" + $lowerCase + "') = '" + $managementGroup + "']/rsServers/rsServer[contains(translate(@name, '" + $upperCase + "','" + $lowerCase + "'), '" + $ServerName + "') and translate(@instance, '" + $upperCase + "','" + $lowerCase + "') = '" + $InstanceName + "' and @active='True']"
$rsServer = $config.SelectNodes($xPathServerInfo)
[System.Uri]$rsServerURI = $rsServer.uri

# EXTRACT THE LIST OF DATA SOURCES BASED ON PARAMETERS PROVIDED
If($UserName.Length -gt 0){
    [string]$xPathDataSource = "/configuration/ManagementGroup[translate(@name, '" + $upperCase + "','" + $lowerCase + "') = '" + $managementGroup + "']/rsServers/rsServer[contains(translate(@name, '" + $upperCase + "','" + $lowerCase + "'), '" + $ServerName + "') and translate(@instance, '" + $upperCase + "','" + $lowerCase + "') = '" + $InstanceName + "' and @active='True']/rsDataSources/dataSource[translate(@userName, '" + $upperCase + "','" + $lowerCase + "') = '" + $UserName + "' and @active='True']"
} Else {
    If($DataSourceName -eq "all") {
        [string]$xPathDataSource = "/configuration/ManagementGroup[translate(@name, '" + $upperCase + "','" + $lowerCase + "') = '" + $managementGroup + "']/rsServers/rsServer[contains(translate(@name, '" + $upperCase + "','" + $lowerCase + "'), '" + $ServerName + "') and translate(@instance, '" + $upperCase + "','" + $lowerCase + "') = '" + $InstanceName + "' and @active='True']/rsDataSources/dataSource[@active='True']"
    } Else {
        [string]$xPathDataSource = "/configuration/ManagementGroup[translate(@name, '" + $upperCase + "','" + $lowerCase + "') = '" + $managementGroup + "']/rsServers/rsServer[contains(translate(@name, '" + $upperCase + "','" + $lowerCase + "'), '" + $ServerName + "') and translate(@instance, '" + $upperCase + "','" + $lowerCase + "') = '" + $InstanceName + "' and @active='True']/rsDataSources/dataSource[translate(@name, '" + $upperCase + "','" + $lowerCase + "') = '" + $DataSourceName + "' and @active='True']"
    }
}
$dataSources = $config.SelectNodes($xPathDataSource)

[string]$currentUser=""
If($dataSources){
    $msg = "Found {0} data sources for RS Instance {1}\{2} in configuration file." -f $dataSources.Count, $ServerName, $InstanceName
    Write-Verbose $msg


    foreach($dataSource in $dataSources){
        If($dataSource.UserName -ne $currentUser){
            $newCred = Get-Credential -UserName $dataSource.userName -Message "Enter password:"
        }

        ChangeDataSourcePassword $rsServerURI $dataSource.Name $newCred
        $currentUser = $dataSource.UserName
    }
}



