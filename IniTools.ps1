# Joel Roth 2020
# Tools to work with INI files, making them searchable by stanza name and being able to modify target lines.

Function Get-DeserializedIni
{
    [CmdletBinding()]Param(
        [string]$Contents
    )
    
    $stanza = ""
    $LineNumber = 0
    foreach ($line in ($contents -split "\r?\n"))
    {
        $LineNumber += 1
        if ($line.trim()[0] -eq '[')
        {
            $Stanza = $line -replace "\[","" -replace "\]",""
        }
        
        if ((($line -split "#")[0]) -like "*=*")
        {
            # KV pair
            [PSCustomObject]@{
                LineNumber = $LineNumber
                RawContent = $line
                Stanza = $Stanza
                Key = ((($line -split "#")[0]) -split "=")[0].Trim()
                Value = ((($line -split "#")[0]) -split "=")[1].Trim()
            }
        }
        else 
        {
            # Comment, empty line, or something else.
            [PSCustomObject]@{
                LineNumber = $LineNumber
                RawContent = $line
                Stanza = $Stanza
                Key = "N/A"
                Value = "N/A"
            }
        }
    }
}

Function Update-IniKV
{
    [CmdletBinding()]Param(
        [string]$Path,
        [string]$Stanza,
        [string]$Key,
        [string]$NewValue,
        [switch]$WhatIf
    )

    $Contents = Get-Content $path -Raw
    $DeserializedIni = Get-DeserializedIni -Contents $Contents

    $DeserializedIni | Where-Object { $_.Stanza -eq $stanza -and $_.Key -eq $key } | % {
        if ($_.Value -eq $NewValue)
        {
            Write-Debug "[$stanza].$Key is already $NewValue. Skipping."
        }
        else 
        {
            $ContentsByLine = ($contents -split "\r?\n")
            $NewLineContents = $_.Key+"="+$NewValue

            Write-Debug "Line: $($_.LineNumber); Old: $($ContentsByLine[$_.LineNumber -1]); New: $NewLineContents"

            $ContentsByLine[$_.LineNumber -1] = $NewLineContents
            $ContentsByLine | Out-File -LiteralPath $Path -Encoding ascii -WhatIf:$WhatIf
        }
    }
}

# Example use case: Add an SSTP VPN connection and change some properties that are only accessible from the INI/PBK file.
#$VPNProps = Add-VpnConnection -Name "INSERT_NAME_HERE" -ServerAddress "INSERT_ADDRESS_HERE" -EncryptionLevel Maximum -SplitTunneling:$true -TunnelType Sstp -RememberCredential:$false -PassThru
#$RasLocation = "$env:appdata\Microsoft\Network\Connections\Pbk\rasphone.pbk"
#
#Update-IniKV -Path $RasLocation -Stanza $VPNProps.Name -Key "UseRasCredentials" -NewValue "0"
#Update-IniKV -Path $RasLocation -Stanza $VPNProps.Name -Key "DisableClassBasedDefaultRoute" -NewValue "1"
#Update-IniKV -Path $RasLocation -Stanza $VPNProps.Name -Key "CacheCredentials" -NewValue "1"
#Update-IniKV -Path $RasLocation -Stanza $VPNProps.Name -Key "IpNBTFlags" -NewValue "0"
