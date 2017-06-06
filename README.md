# Invoke AutoShutdown

This script shutsdown/starts up resources based on the tags assigned to them in Azure.

Works with:

+ ARM VM's
+ Classic VM's
+ Stream Analytics Jobs

## How to set up

In Azure Automation make sure the following Variables exist.

|Name|value|type|
|---|---|---|
Default Azure Subscription| Subscription Name to apply to| Variable

Create the following Connections.

+ AzureRunAsConnection
+ AzureClassicRunAsConnection

Create the following certificates.

+ AzureClassicRunAsCertificate
+ AzureRunAsCertificate

Required Runbook Modules:

+ Azure
+ Azure.Storage
+ AzureRM.Automation
+ AzureRM.Compute
+ AzureRM.profile
+ AzureRM.Resources
+ AzureRM.Sql
+ AzureRM.Storage
+ AzureRM.StreamAnalytics
+ Microsoft.PowerShell.Core
+ Microsoft.PowerShell.Diagnostics
+ Microsoft.PowerShell.Management
+ Microsoft.PowerShell.Security
+ Microsoft.PowerShell.Utility
+ Microsoft.WSMan.Management
+ Orchestrator.AssetManagement.Cmdlets


## Tags

Tags should be called `AutoShutdownSchedule` like the following:

|Key|Value|
|---|----|
AutoShutdownSchedule| 8PM-> 5AM, Saturday, Sunday|

Where **shutdowntime** `->` **startuptime** and days of the week are comma seperated. The days specify full power down times.

Schedule Tag Examples
The easiest way to write the schedule is to say it first in words as a list of times the VM should be shut down, then translate that to the string equivalent. Remember, any time period not defined as a shutdown time is online time, so the runbook will start the VMs accordingly. Let’s look at some examples:

|Description |Tag value|
|---|---|
|Shut down from 10PM to 6 AM UTC every day|10pm -> 6am|
|Shut down from 10PM to 6 AM UTC every day (different format, same result as above)|22:00 -> 06:00
|Shut down from 8PM to 12AM and from 2AM to 7AM UTC every day (bringing online from 12-2AM for maintenance in between)|8PM -> 12AM, 2AM -> 7AM
|Shut down all day Saturday and Sunday (midnight to midnight)|Saturday, Sunday
|Shut down from 2AM to 7AM UTC every day and all day on weekends|2:00 -> 7:00, Saturday, Sunday
|Shut down on Christmas Day and New Year’s Day|December 25, January 1|
|Shut down from 2AM to 7AM UTC every day, and all day on weekends, and on Christmas Day|2:00 -> 7:00, Saturday, Sunday, December 25
|Shut down always – I don’t want this VM online, ever|0:00 -> 23:59:59
|Shutdown never - This can be applied to individual VM's to override the resource groups schedule| never

## Scheduling RunBook in Azure.

The run book should be scheduled to run once per hour.
