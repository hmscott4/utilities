
# Assign SCOM Alerts
Hugh Scott
2019/07/16

PowerShell and Configuration File used to:
- Assign SCOM Alert Ownership (Owner field)
- Assignment made primarily based on Management Pack (from MonitoringObjectClass from the alert)
- Exceptions can be configured based on Alert Name

- Features:
 1. Automatically assign alert ownership based on object class of monitored object
 2. Alerts are automatically set to new resolution state 5 (need to add to SCOM configuration)
 
- Pre-requisite
 1. Add a new Alert Resolution State (5)
 2. Periodically review Missed Alerts log file to determine which Management Packs are not "hitting" for an alert

IMPORTANT:
Copy files to a single directory
Modify the configuration file as necessary
Review the configuration file and customize entries based on environment

NOTE: 
Config file was originally created for Rememdy Environment.  Entries for ProductHierarchy and OrganizationHierarchy are specific to Remedy and may not be needed.  They can be safely removed from the config file.
