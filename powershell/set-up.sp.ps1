param (
    [Parameter()]
     [string]$groupName,
     
    [Parameter()]
     [string]$sqlAdminName,
     
    [Parameter()]
     [string]$sqlAdminPrincipalId,

    [Parameter()]
     [string]$suffix
)

Write-Host "Creating SQL Server DemoSqlServer$suffix"

$sqlServer = az sql server create --enable-ad-only-auth --external-admin-principal-type User `
                                  --external-admin-name $sqlAdminName --external-admin-sid $sqlAdminPrincipalId -g $groupName `
                                  -n "DemoSqlServer$suffix" --assign-identity --identity-type SystemAssigned | ConvertFrom-Json

Write-Host "Creating SQL Server Db DemoDb"

$db = az sql db create -g $groupName -s $sqlServer.Name -n DemoDb --service-objective Basic -y | ConvertFrom-Json

Write-Host "Creating App Service Plan DemoAppSvcPlan"

$appSvcPlan = az appservice plan create -g $groupName -n DemoAppSvcPlan --is-linux --sku F1 | ConvertFrom-Json

Write-Host "Creating Web App DemoWebApp$suffix"

$webApp = az webapp create -g $groupName -p $appSvcPlan.Name -n "DemoWebApp$suffix" --assign-identity "[system]" --runtime "DOTNETCORE:7.0" | ConvertFrom-Json

Write-Host "Adding connection string $connstring"

$connstring = "Server=$($sqlServer.FullyQualifiedDomainName),1433;Database=$($db.Name);Authentication=Active Directory Default"
az webapp config connection-string set -g $groupName -n $webApp.Name -t SQLAzure --settings MyConnString=$connstring | Out-Null

Write-Host "Adding firewall exception - Allow Azure Services"

az sql server firewall-rule create -g $group.Name -s $sqlServer.Name -n "Allow Azure Services" --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 | Out-Null

& $PSScriptRoot/add-sql-user.ps1 -groupName $groupName -sqlServerHostName $sqlServer.FullyQualifiedDomainName -dbName $db.Name -principalName $webApp.Name -principalId $webApp.Identity.PrincipalId
