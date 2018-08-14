Import-Module ActiveDirectory
$oldSuffix = "pnl.com"
$newSuffix = "petenetlive.com"
$ou = "OU=Test,DC=pnl,DC=com"
$server = "DC-01"
Get-ADUser -SearchBase $ou -filter * | ForEach-Object {
$newUpn = $_.UserPrincipalName.Replace($oldSuffix,$newSuffix)
$_ | Set-ADUser -server $server -UserPrincipalName $newUpn
}