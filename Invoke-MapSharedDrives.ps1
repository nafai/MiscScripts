# Joel Roth 2021
#
# Drive mapping script (by AD/LDAP group) that handles and logs overloaded drive letters
#

[CmdletBinding(SupportsShouldProcess)]Param(
    # Drive mapping manifest with the parameters: Group, Letter, Path
    [array]$MappingIndex = $(@"
Group,Letter,Path
Domain Users,S,\\fs1.contoso.com\Folder1
HR-Department,L,\\fs1.contoso.com\Folder2
"@ | ConvertFrom-Csv),
    # User identity to use (defaults to current user, or specify UPN of another user account)
    [string]$UserPrincipalName,
    # Don't unmap letters that are already mapped somewhere
    [switch]$DontUnmap,
    # Don't map anything, just show what would be done
    [switch]$ShowEffectiveMappingsOnly,
    # Log resulting actions to a file in the user's temp folder
    [string]$LogFilename = "$env:TEMP\DriveMap_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    # Restart Windows Explorer if there are any changes
    [switch]$RestartExplorer
)

# Retrieve group membership
if ($UserPrincipalName -eq "")
{
    # Current user principal
    $ResolvedGroupMembership = [Security.Principal.WindowsIdentity]::GetCurrent().Groups.Where({$_.Value -like "S-1-5-21-*"}).Foreach({$_.Translate([Security.Principal.NTAccount]).Value}) -replace "^[^\\]+\\",""
    
    # Cheating to get the Netbios name (for -ShowEffectiveMappingsOnly)
    $UserPrincipalName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}
else
{
    try
    {
        # Specify a UPN to run or test against a different user
        $ResolvedGroupMembership = [Security.Principal.WindowsIdentity]::new($UserPrincipalName).Groups.Where({$_.Value -like "S-1-5-21-*"}).Foreach({$_.Translate([Security.Principal.NTAccount]).Value}) -replace "^[^\\]+\\",""
    }
    catch
    {
        Throw "Could not retrieve group membership for $UserPrincipalName"
    }
}


# Retrieve matching entries from mapping dictionary
$MyMappings = $MappingIndex | Where-Object { $ResolvedGroupMembership -contains $_.Group }
$MyMappings = $MyMappings | Sort-Object -Property Letter -Unique

# Excluded mappings because the drive letter was already used by an earlier entry
$ExcludedMappings = $MappingIndex | Where-Object { $ResolvedGroupMembership -contains $_.Group }
$ExcludedMappings = Compare-Object $MyMappings $ExcludedMappings -Property Group,Letter,Path | Where-Object { $_.SideIndicator -eq "=>" }

$CurrentMappings = $(Get-PSDrive).Where({$_.Provider -like "Microsoft.PowerShell.Core\FileSystem"}) | select Name,DisplayRoot

if ($ShowEffectiveMappingsOnly)
{
    Write-Host "User $($UserPrincipalName)'s full group membership:"
    $ResolvedGroupMembership.ForEach({[PSCustomObject]@{Group=$_}}) | Format-Wide -AutoSize

    Write-Host "The following drives will be mapped:"
    $MyMappings | Format-Table -AutoSize

    Write-Host "The following drives have ambiguous letters and will be skipped:"
    $ExcludedMappings | Format-Table -AutoSize

    Write-Host "The following drives are already mapped on this computer:"
    $CurrentMappings | Format-Table -AutoSize
    
    Return
}


# The ResultSet tracks the results of each group the user's a member of for debug purposes 
$ResultSet = @()
$ChangesPendingExplorerRestart = $false

foreach ($DriveToMap in $MyMappings)
{
    $Letter = $DriveToMap.Letter
    $Path = $DriveToMap.Path
    $result = ""
    
    # Check to see if drive is already mapped
    $CurrentMap = $CurrentMappings.Where({$_.Name -eq $letter}) | Select-Object -First 1 Name,DisplayRoot

    if ($CurrentMap.DisplayRoot -eq $Path)
    {
        Write-Debug "Drive $letter`: is already mapped to $path`. Skipping."
        $result = "Skipped"
    }
    else 
    {
        if ($null -eq $($CurrentMap.DisplayRoot))
        {
            Write-Debug "Driver $letter isn't currently mapped."
        }
        elseif ($DontUnmap)
        {
            Write-Debug "Drive $letter`: is already mapped to $CurrentMap. Won't unmap because of -DontUnmap."
            $result = "WontRemap"
        }
        else
        {
            Write-Debug "Drive $letter`: is already mapped to $CurrentMap. Unmapping it."
            
            # Unmap 2 different ways
            Remove-SmbMapping -LocalPath "$Letter`:" -Force
            net use $("$letter`:") /delete

            $result = "Remapped"
            $ChangesPendingExplorerRestart = $true
        }

        if ($result -ne "WontRemap")
        {
            Write-Debug "Mapping drive $letter`: to $Path"
            $DriveMapResult = New-SmbMapping -LocalPath "$letter`:" -RemotePath $path -Persistent:$true
            #$DriveMapResult = net use $("$letter`:") $path /persistent:yes
            
            if ($null -ne $DriveMapResult)
            {
                Write-Debug "Successfully mapped drive $letter`: to $path."
                if ($result -eq "") { $result = "Mapped" }
            }
            else
            {
                Write-Debug "There was a problem mapping drive $letter`: to $path."
                $result = "FailedToMap"
                $DriveMapResult | fl -Property *
    
            }
        }
    }

    # Add the result to the resultset
    $ResultSet += [PSCustomObject]@{
        Group = $DriveToMap.Group;
        Letter = $DriveToMap.Letter;
        Path = $DriveToMap.Path;
        Result = $result;
    }
}

# Add the excluded mappings (ambiguous drive letters) to the end of the result set
foreach ($ExcludedMapping in $ExcludedMappings)
{
    $ResultSet += [PSCustomObject]@{
        Group = $ExcludedMapping.Group;
        Letter = $ExcludedMapping.Letter;
        Path = $ExcludedMapping.Path;
        Result = "ExcludedAmbiguousLetter";
    }
}

$ResultSet | Export-Csv -NoTypeInformation $LogFilename -Force

if ($ChangesPendingExplorerRestart)
{
    taskkill.exe --% /IM explorer.exe /FI "USERNAME eq %userdomain%\%username%" /F
    Start-Process "explorer.exe" -UseNewEnvironment
}
