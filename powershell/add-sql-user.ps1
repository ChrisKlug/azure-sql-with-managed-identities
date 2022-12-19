param (
    [Parameter()]
     [string]$groupName,
 
     [Parameter()]
     [string]$sqlServerHostName,
 
     [Parameter()]
     [string]$dbName,
 
     [Parameter()]
     [string]$principalName,
 
     [Parameter()]
     [string]$principalId
)

$sqlServerName = $sqlServerHostName.split(".")[0]

$myIp = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content

Write-Host "Adding firewall exception for $myIp"

$rule = az sql server firewall-rule create -g $groupName -s $sqlServerName -n SetUp --start-ip-address $myIp --end-ip-address $myIp | ConvertFrom-Json

Write-Host "Adding User $principalName ($principalId) to $sqlServerHostName"

$token = az account get-access-token --resource="https://database.windows.net" --query accessToken --output tsv
$query = "IF NOT EXISTS (SELECT [name] FROM [sys].[database_principals] WHERE [name] = N'$principalName')
            BEGIN
                CREATE USER [$principalName] FROM EXTERNAL PROVIDER WITH OBJECT_ID='$principalId'
            END"
Invoke-SqlCmd -ServerInstance $sqlServerHostName -Database $dbName -AccessToken $token -Query $query

Write-Host "Adding $principalName to db_owner"

$query = "ALTER ROLE db_owner ADD MEMBER [$principalName]"
Invoke-SqlCmd -ServerInstance $sqlServerHostName -Database $dbName -AccessToken $token -Query $query

Write-Host "Removing firewall exception for $myIp"

az sql server firewall-rule delete --ids $rule.Id