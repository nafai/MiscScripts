# Joel Roth 2021
# 
# Grants read access on the NetFrameworkConfigurationKey container
#
# Resolves "System.Configuration.ConfigurationErrorsException: The RSA key container could not be opened" when using RsaProtectedConfigurationProvider and decrypting using an unprivileged user.


[Cmdletbinding()]
    param (
        [string]$Username = "CONTOSO\user.integration"
    )

$UserSID = [System.Security.Principal.NTAccount]::new($Username).Translate([System.Security.Principal.SecurityIdentifier]).Value
$NewAccessRule = [System.Security.AccessControl.FileSystemAccessRule]::new($UserSID,"Read","Allow")

$KeyIDDiscovery = & certutil -Silent -key NetFrameworkConfigurationKey
[string]$KeyIDDiscovery = $KeyIDDiscovery -join "`r`n"

if ($KeyIDDiscovery -match '\b([a-f0-9_-]+)\b')
{
    $KeyIDVal = $Matches[0]
    Write-Host "Found match: $KeyIDVal"
    $ResolvedPath = Join-Path -Path "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys" -ChildPath $KeyIDVal -Resolve -ErrorAction Stop
    $KeyFile = Get-Item $ResolvedPath -ErrorAction Stop
    $KeyFileACL = $KeyFile.GetAccessControl()
    $KeyFileACL.AddAccessRule($NewAccessRule)
    $KeyFile.SetAccessControl($KeyFileACL)
    Write-Host "Granted $($NewAccessRule.FileSystemRights) access to $($NewAccessRule.IdentityReference) on $ResolvedPath"
}
else
{
    Write-Host "Couldn't find NetFrameworkConfigurationKey."
}
