# Joel Roth 2021
#
# Retrieve encryption status, encrypt, or decrypt a .NET config file.
#
# Works on Web.Config files and .exe.config files. Uses arbitrary paths so you don't need to use aspnet_regiis.exe with
# registered sites.
#
# I made some slight changes to it (renamed functions and whatnot) before posting it to GitHub, but I haven't fully 
# tested them. Please note that there's some section validation in Get-ConfigEncryptionStatus() that you may need to 
# tweak for your own sections.

Function Get-ConfigEncryptionStatus
{
    [cmdletbinding()]
    Param (
        [Parameter( Mandatory=$true,
        ValueFromPipeline=$true,
        HelpMessage="Path to a .config file")]
        [ValidateScript({
            If ($(Test-Path -LiteralPath $_) -ne $true)
            {
                Throw "Path $_ does not exist"
            }
            elseif ($(Get-Content $_).Length -eq 0)
            {
                Throw "Could not open $_ for reading"
            }
             elseif ($null -eq $([xml]$(Get-Content $_)))
            {
                Throw "The above command should have thrown an exception"
            }
            else
            {
                $True
            }
        })]
        [string]$Path,
        [Parameter( Mandatory=$true,
        ValueFromPipeline=$true,
        HelpMessage="Section to inspect: appSettings, connectionStrings, CRNBC.ServiceFramework, system.web/identity")]
        [ValidateSet("appSettings","connectionStrings","CRNBC.ServiceFramework","system.web/identity")]
        [string]$Section
    )

    $FileMap = [System.Configuration.ExeConfigurationFileMap]::new()
    $FileMap.ExeConfigFilename = $Path

    $config = [System.Configuration.ConfigurationManager]::OpenMappedExeConfiguration($FileMap,0,$false)

    if ($config.HasFile -ne $true)
    {
        Throw "Could not parse file."
    }

    if ($config.GetSection($Section).SectionInformation.IsProtected -eq $true)
    {
        Return "Encrypted"
    }
    else 
    {
        Return "Unencrypted"
    }
}

Function Invoke-EncryptConfigFile
{
    [cmdletbinding()]
    Param (
        [Parameter( Mandatory=$true,
        ValueFromPipeline=$true,
        HelpMessage="Path to a config file")][string]$Path,
        [Parameter( Mandatory=$true,
        ValueFromPipeline=$true,
        HelpMessage="Section to encrypt")][string]$Section        
    )

    # Validate file
    $status = Get-ConfigEncryptionStatus -Path $Path -Section $Section
    if ($status -eq "Unencrypted")
    {
        $FileMap = [System.Configuration.ExeConfigurationFileMap]::new()
        $FileMap.ExeConfigFilename = $path

        $config = [System.Configuration.ConfigurationManager]::OpenMappedExeConfiguration($FileMap,0,$false)

        $config.GetSection($section).SectionInformation.ProtectSection("RsaProtectedConfigurationProvider")

        $config.Save()

        $newstatus = Get-ConfigEncryptionStatus -Path $Path -Section $Section
        if ($newstatus -ne "Encrypted")
        {
            Throw "Tried to encrypt, but couldn't verify!"
        }
        else
        {
            Return $true
        }
    }
    else 
    {
        Throw "$path can't be encrypted."
    }
  
}

Function Invoke-DecryptConfigFile
{
    [cmdletbinding()]
    Param (
        [Parameter( Mandatory=$true,
        ValueFromPipeline=$true,
        HelpMessage="Path to a config file")][string]$Path,
        [Parameter( Mandatory=$true,
        ValueFromPipeline=$true,
        HelpMessage="Section to encrypt")][string]$Section        
    )

    # Validate file
    $status = Get-ConfigEncryptionStatus -Path $Path -Section $Section
    if ($status -eq "Encrypted")
    {
        $FileMap = [System.Configuration.ExeConfigurationFileMap]::new()
        $FileMap.ExeConfigFilename = $path

        $config = [System.Configuration.ConfigurationManager]::OpenMappedExeConfiguration($FileMap,0,$false)

        $config.GetSection($section).SectionInformation.UnprotectSection()

        $config.Save()

        $newstatus = Get-ConfigEncryptionStatus -Path $Path -Section $Section
        if ($newstatus -ne "Unencrypted")
        {
            Throw "Tried to decrypt, but couldn't verify!"
        }
        else
        {
            Return $true
        }
    }
    else 
    {
        Throw "$path was already encrypted."
    }

}

$EncryptConfigManifest = @"
Servername,Path,Section
prd-server01,C:\inetpub\wwwroot\blah\Web.config,appSettings
prd-server02,E:\Program Files\Microsoft Dynamics CRM\CRMWeb\Web.config,connectionStrings
prd-server02,E:\Program Files\Microsoft Dynamics CRM\Server\bin\CrmAsyncService.exe.config,connectionStrings
"@ | ConvertFrom-Csv | Where-Object { $_.ServerName -eq $env:computername }

$DecryptConfigManifest = @"
Servername,Path,Section
prd-server03,C:\inetpub\wwwroot\blah\Web.config,appSettings
"@ | ConvertFrom-Csv | Where-Object { $_.ServerName -eq $env:computername }

Start-Transcript -Path "$env:windir\Logs\ConfigFile.log" -Append -Force -IncludeInvocationHeader

foreach ($AvailableFile in $EncryptConfigManifest)
{
    $Path = $AvailableFile.Path
    $Section = $AvailableFile.Section
    $Status = Get-ConfigEncryptionStatus -Path $Path -Section $Section
    if ($status -eq "Unencrypted")
    {
        Write-Host "Encrypting: $path($section)"
        $result = Invoke-EncryptConfigFile -Path $path -Section $section -ErrorAction Continue # -Debug
        Write-Host "- Result: $result"
    }
    else
    {
        Write-Host "Skipping: $path($section) $status"
    }
}

foreach ($AvailableFile in $DecryptConfigManifest)
{
    $Path = $AvailableFile.Path
    $Section = $AvailableFile.Section
    $Status = Get-ConfigEncryptionStatus -Path $Path -Section $Section
    if ($status -eq "Encrypted")
    {
        Write-Host "Decrypting: $path($section)"
        $result = Invoke-DecryptConfigFile -Path $path -Section $section -ErrorAction Continue # -Debug
        Write-Host "- Result: $result"
    }
}

Stop-Transcript
