# Joel Roth 2021

# Drive mapping script (by AD/LDAP group) that handles and logs overloaded drive letters

# Note the domain substitution on line 14

$AllMappings = @"
Group,Letter,Path
Domain Users,S,\\fs1.contoso.com\Folder1
HR-Department,L,\\fs1.contoso.com\Folder2
"@ | ConvertFrom-Csv

# Retrieve group membership
$MyGroupMembership = @([Security.Principal.WindowsIdentity]::GetCurrent() | Select-Object -ExpandProperty Groups | ForEach-Object { $_.Translate([Security.Principal.NTAccount]).Value }) -like "CONTOSO\*" -replace "CONTOSO\\",""

# Retrieve matching entries from mapping dictionary
$MyMappings = $AllMappings | Where-Object { $MyGroupMembership -contains $_.Group }
$MyMappings = $MyMappings | Sort-Object -Property Letter -Unique

# Excluded mappings because the drive letter was already used by an earlier entry
$ExcludedMappings = $AllMappings | Where-Object { $MyGroupMembership -contains $_.Group }
$ExcludedMappings = Compare-Object $MyMappings $ExcludedMappings -Property Group,Letter,Path | Where-Object { $_.SideIndicator -eq "=>" }

# The ResultSet tracks the results of each group the user's a member of for debug purposes 
$ResultSet = @()

foreach ($DriveToMap in $MyMappings)
{
    $Letter = $DriveToMap.Letter
    $Path = $DriveToMap.Path
    $result = ""
    
    # Check to see if drive is already mapped
    $CurrentMap = Get-PSDrive -Name $Letter -PSProvider FileSystem -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($($CurrentMap.DisplayRoot) -eq $Path)
    {
        Write-Debug "Drive $letter`: is already mapped to $path`. Skipping."
        $result = "Skipped"
    }
    else 
    {
        if ($null -ne $($CurrentMap.DisplayRoot))
        {
            Write-Debug "Drive $letter`: is already mapped to $CurrentMap. Unmapping it."
            Remove-SmbMapping -LocalPath "$Letter`:" -Force
            net use $("$letter`:") /delete     ## Alternate method

            $result = "Remapped"
        }

        Write-Debug "Mapping drive $letter`: to $Path"
        $DriveMapResult = New-SmbMapping -LocalPath "$letter`:" -RemotePath $path -Persistent:$true
        #$DriveMapResult = net use $("$letter`:") $path /persistent:yes     ## Alternate method
        
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

    # Add the result to the resultset
    $ResultSet += [PSCustomObject]@{
        Group = $DriveToMap.Group;
        Letter = $DriveToMap.Letter;
        Path = $DriveToMap.Path;
        Result = $result;
    }
}

# Add the excluded mappings (ambiguous drive letters) to the result set
foreach ($ExcludedMapping in $ExcludedMappings)
{
    $ResultSet += [PSCustomObject]@{
        Group = $ExcludedMapping.Group;
        Letter = $ExcludedMapping.Letter;
        Path = $ExcludedMapping.Path;
        Result = "ExcludedAmbiguousLetter";
    }
}

$LogFilename = "$env:TEMP\DriveMap_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ResultSet | Export-Csv -NoTypeInformation $LogFilename -Force
