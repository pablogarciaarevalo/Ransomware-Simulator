Param(
   [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
   [String]$Cluster,
   [Parameter(Mandatory=$True, HelpMessage="The vserver name")]
   [String]$VserverName,
   [Parameter(Mandatory=$True, HelpMessage="The volume name")]
   [String]$VolumeName,
   [Parameter(Mandatory=$True, HelpMessage="The protocol name")]
   [ValidateSet("cifs","nfs")]
   [String]$Protocol,
   [Parameter(Mandatory=$True, HelpMessage="The snapshot name")]
   [String]$SnapshotName,
   [Parameter(Mandatory=$True, HelpMessage="The maximum difference count")]
   [Int]$MaxDiff,
   [Parameter(Mandatory=$False, HelpMessage="The application name")]
   [String]$ApplicationName="PowerShell",
   [Parameter(Mandatory=$False, HelpMessage="The application type")]
   [String]$ApplicationType="Data-Management",
   [Parameter(Mandatory=$False, HelpMessage="Speficies if the file time attribute is returned")]
   [Bool]$AttributeTime,
   [Parameter(Mandatory=$True, HelpMessage="The credentials to authenticate to the cluster")]
   [System.Management.Automation.PSCredential]$Credentials
)
#'------------------------------------------------------------------------------
Function Import-ManageOntap{
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The folder path to the 'manageontap.dll' file")]
      [String]$FolderPath
   )
   #'---------------------------------------------------------------------------
   #'Load the ManageONTAP.dll file
   #'---------------------------------------------------------------------------
   [String]$fileSpec = "$FolderPath\ManageOntap.dll"
   Try{
      [Reflection.Assembly]::LoadFile($fileSpec) | Out-Null
      Write-Host "Loaded file ""$fileSpec"""
   }Catch{
      Write-Warning -Message $("Failed loading file ""$fileSpec"". Error " + $_.Exception.Message)
      Return $False;
   }
   Return $True;
}#'End Function
#'------------------------------------------------------------------------------
Function ConvertFrom-UnixTimestamp{
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The UNIX timestamp")]  
      [String]$Timestamp
   )
   Get-Date -Date $((Get-Date -Date '1/1/1970') + ([System.TimeSpan]::FromSeconds($Timestamp))) -Uformat "%Y-%m-%d %H:%M:%S"
}#End Function
#'------------------------------------------------------------------------------
Function Get-NcSnapDiff{
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
      [String]$Cluster,
      [Parameter(Mandatory=$True, HelpMessage="The vserver name")]
      [String]$VserverName,
      [Parameter(Mandatory=$True, HelpMessage="The snapdiff session ID")]
      [String]$SessionId,
      [Parameter(Mandatory=$True, HelpMessage="The credentials to authenticate to the cluster")]
      [System.Management.Automation.PSCredential]$Credentials
   )
   [String]$username = $Credentials.GetNetworkCredential().Username
   [String]$password = $Credentials.GetNetworkCredential().Password
   [String]$zapiName = "snapdiff-iter-next"
   Try{
      [NetApp.Manage.NaServer]$naServer = New-Object NetApp.Manage.NaServer($Cluster,"1","31")
      $naServer.SetAdminUser($username, $password)
      $naServer.Vserver       = $VserverName
      $naServer.ServerType    = "FILER"       
      $naServer.TransportType = 'HTTPS'
      $naServer.Port          = 443
      $naElement = New-Object NetApp.Manage.naElement("$zapiName")
      $naElement.AddNewChild("session-id", $SessionId)
      Write-Host "Invoking ZAPI ""$zapiName"""
      [xml]$results = $naServer.InvokeElem($naElement)
   }Catch{
      Write-Warning -Message $("Failed invoking ""$zapiName"". Error " + $_.Exception.Message)
      Throw "Failed invoking ""$zapiName"""
   }
   #'---------------------------------------------------------------------------
   #'Return the properties in a custom object
   #'---------------------------------------------------------------------------
   [Array]$changeRecords = @();
   If($results.results.status -eq "passed"){
      ForEach($result In $results.results."snapshot-changes"."change-rec"){
         $record = [PsCustomObject]@{
            Inode          = $result.inode
            ChangeType     = $result."change-type"
            FileName       = $result.filename
            FileType       = $result.ftype
            Created        = $(ConvertFrom-UnixTimestamp -Timestamp $($result.crtime))
            Modified       = $(ConvertFrom-UnixTimestamp -Timestamp $($result.mtime))
            Accessed       = $(ConvertFrom-UnixTimestamp -Timestamp $($result.atime))
            Owner          = $result.owner
            Group          = $result.group
            FileAttributes = $result.fattr
            DosBits        = $result."dos-bits"
            Size           = $result.size
            Links          = $result.links
         }       
         [Array]$changeRecords += $record
      }
   }
   Return $changeRecords
}#'End Function
#'------------------------------------------------------------------------------
Function Start-NcSnapDiff{
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
      [String]$Cluster,
      [Parameter(Mandatory=$True, HelpMessage="The vserver name")]
      [String]$VserverName,
      [Parameter(Mandatory=$True, HelpMessage="The volume name")]
      [String]$VolumeName,
      [Parameter(Mandatory=$True, HelpMessage="The protocol name")]
      [ValidateSet("cifs","nfs")]
      [String]$Protocol,
      [Parameter(Mandatory=$True, HelpMessage="The snapshot name")]
      [String]$SnapshotName,
      [Parameter(Mandatory=$True, HelpMessage="The maximum difference count")]
      [Int]$MaxDiff,
      [Parameter(Mandatory=$False, HelpMessage="The application name")]
      [String]$ApplicationName="PowerShell",
      [Parameter(Mandatory=$False, HelpMessage="The application type")]
      [String]$ApplicationType="Data-Management",
      [Parameter(Mandatory=$False, HelpMessage="Speficies if the file time attribute is returned")]
      [Bool]$AttributeTime,
      [Parameter(Mandatory=$True, HelpMessage="The credentials to authenticate to the cluster")]
      [System.Management.Automation.PSCredential]$Credentials
   )
   [String]$username = $Credentials.GetNetworkCredential().Username
   [String]$password = $Credentials.GetNetworkCredential().Password
   [String]$zapiName = "snapdiff-iter-start"
   Try{
      [NetApp.Manage.NaServer]$naServer = New-Object NetApp.Manage.NaServer($Cluster,"1","31")
      $naServer.SetAdminUser($username, $password)
      $naServer.Vserver       = $VserverName
      $naServer.ServerType    = "FILER"       
      $naServer.TransportType = 'HTTPS'
      $naServer.Port          = 443
      $naElement = New-Object NetApp.Manage.naElement("$zapiName")
      $naElement.AddNewChild("volume", $VolumeName)
      $naElement.AddNewChild("file-access-protocol", $Protocol)
      If($AttributeTime){
         $naElement.AddNewChild("atime", $AttributeTime)
      }
      $naElement.AddNewChild("max-diffs", $MaxDiff)
      $naElement.AddNewChild("diff-snapshot", $SnapshotName)
      $naElement.AddNewChild("application-name", $ApplicationName)
      $naElement.AddNewChild("application-type", $ApplicationType)
      Write-Host "Invoking ZAPI ""$zapiName"""
      [xml]$result = $naServer.InvokeElem($naElement)
      $result.results
       Write-Host $result.GetElementById("session-id") -ForegroundColor Cyan
   }Catch{
      Write-Warning -Message $("Failed invoking ""$zapiName"". Error " + $_.Exception.Message)
      Throw "Failed invoking ""$zapiName"""
   }
   #'---------------------------------------------------------------------------
   #'Return the properties in a custom object
   #'---------------------------------------------------------------------------
   If($result.results.status -eq "passed"){
      [PsCustomObject]@{
         SessionId     = $($result.results."session-id").Trim();
         Status        = $result.results."status";
         SessionStatus = $result.results."session-status";
      }
   }
}#'End Function
#'------------------------------------------------------------------------------
Function Stop-NcSnapDiff{
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
      [String]$Cluster,
      [Parameter(Mandatory=$True, HelpMessage="The vserver name")]
      [String]$VserverName,
      [Parameter(Mandatory=$True, HelpMessage="The snapdiff session ID")]
      [String]$SessionId,
      [Parameter(Mandatory=$True, HelpMessage="The credentials to authenticate to the cluster")]
      [System.Management.Automation.PSCredential]$Credentials
   )
   [String]$username = $Credentials.GetNetworkCredential().Username
   [String]$password = $Credentials.GetNetworkCredential().Password
   [String]$zapiName = "snapdiff-iter-end"
   Try{
      [NetApp.Manage.NaServer]$naServer = New-Object NetApp.Manage.NaServer($Cluster,"1","31")
      $naServer.SetAdminUser($username, $password)
      $naServer.Vserver       = $VserverName;
      $naServer.ServerType    = "FILER"       
      $naServer.TransportType = 'HTTPS'
      $naServer.Port          = 443
      $naElement = New-Object NetApp.Manage.naElement("$zapiName")
      $naElement.AddNewChild("session-id", $SessionId)
      Write-Host "Invoking ZAPI ""$zapiName"""
      [xml]$result = $naServer.InvokeElem($naElement)
      If($result.results.status -eq "passed"){
         Return $True;
      }
   }Catch{
      Write-Warning -Message $("Failed invoking ""$zapiName"". Error " + $_.Exception.Message)
      Return $False;
   }
}#'End Function
#'------------------------------------------------------------------------------
Function Get-NcSnapDiffStatus{
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
      [String]$Cluster,
      [Parameter(Mandatory=$True, HelpMessage="The vserver name")]
      [String]$VserverName,
      [Parameter(Mandatory=$True, HelpMessage="The snapdiff session ID")]
      [String]$SessionId,
      [Parameter(Mandatory=$True, HelpMessage="The credentials to authenticate to the cluster")]
      [System.Management.Automation.PSCredential]$Credentials
   )
   [String]$username = $Credentials.GetNetworkCredential().Username
   [String]$password = $Credentials.GetNetworkCredential().Password
   [String]$zapiName = "snapdiff-iter-status"
   Try{
      [NetApp.Manage.NaServer]$naServer = New-Object NetApp.Manage.NaServer($Cluster,"1","31")
      $naServer.SetAdminUser($username, $password)
      $naServer.Vserver       = $VserverName;
      $naServer.ServerType    = "FILER"       
      $naServer.TransportType = 'HTTPS'
      $naServer.Port          = 443
      $naElement = New-Object NetApp.Manage.naElement("$zapiName")
      $naElement.AddNewChild("session-id", $SessionId)
      Write-Host "Invoking ZAPI ""$zapiName"""
      [xml]$result = $naServer.InvokeElem($naElement)
   }Catch{
      Write-Warning -Message $("Failed invoking ""$zapiName"". Error " + $_.Exception.Message)
      Return $False;
   }
   If($result.results.status -eq "passed"){
      [PsCustomObject]@{
         SessionStatus = $result.results."session-status";
      }
   }
}#'End Function
#'------------------------------------------------------------------------------
#'Import the manageontap.dll file.
#'------------------------------------------------------------------------------
[String]$scriptPath = Split-Path($MyInvocation.MyCommand.Path)
If(-Not(Import-ManageOntap -FolderPath $scriptPath)){
   Write-Warning -Message "The file ""$scriptPath\ManageOntap.dll"" does not exist"
   Break;
}
#'------------------------------------------------------------------------------
#'Start the snapdiff on the volume.
#'------------------------------------------------------------------------------
Try{
   [String]$command = "Start-NcSnapDiff -Cluster $Cluster -VserverName $VserverName -VolumeName $VolumeName -Protocol $Protocol -SnapshotName $SnapshotName -MaxDiff $MaxDiff -Credentials `$Credentials -ErrorAction Stop"
   $result = Invoke-Expression -Command $command -ErrorAction Stop
   Write-Host "Executed Command`: $command"
}Catch{
   Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
   Break;
}
[String]$sessionId = $result.SessionId
[String]$sessionId = $sessionId.Trim();
Start-Sleep -Seconds 5
#'------------------------------------------------------------------------------
#'Enumerate the snapdiff status for the session.
#'------------------------------------------------------------------------------
Try{
   [String]$command = "Get-NcSnapDiffStatus -Cluster $Cluster -VserverName $VserverName -SessionId $SessionId -Credentials `$Credentials -ErrorAction Stop"
   $result = Invoke-Expression -Command $command -ErrorAction Stop
   Write-Host "Executed Command`: $command"
}Catch{
   Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
   Break;
}
[String]$status = $result.SessionStatus
Write-Host "The status for Session ID ""$sessionId"" is ""$status"""
Start-Sleep -Seconds 5
#'------------------------------------------------------------------------------
#'Enumerate the snapdiff change records for the session.
#'------------------------------------------------------------------------------
If($status -eq "snapdiff_status_active"){
   Try{
      [String]$command = "Get-NcSnapDiff -Cluster $Cluster -VserverName $VserverName -SessionId $SessionId -Credentials `$Credentials -ErrorAction Stop"
      $changes = Invoke-Expression -Command $command -ErrorAction Stop
      Write-Host "Executed Command`: $command"
   }Catch{
      Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
      Break;
   }
   $changes
}
#'------------------------------------------------------------------------------
#'Stop the snapdiff session.
#'------------------------------------------------------------------------------
If($status -eq "snapdiff_status_active"){
   Try{
      [String]$command = "Stop-NcSnapDiff -Cluster $Cluster -VserverName $VserverName -SessionId $sessionId -Credentials `$Credentials -ErrorAction Stop"
      $result = Invoke-Expression -Command $command -ErrorAction Stop
      Write-Host "Executed Command`: $command"
   }Catch{
      Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
      Break;
   }
}
#'------------------------------------------------------------------------------