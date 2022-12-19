# Using Managed Identities to access Azure SQL, the right way

This repo contains code to demonstrate setting up Managed Identity access to Azure SQL, the right way.

## Known limitations

On PowerShell Core, it seems as though the random string generation isn't working for some reason. And `az ad signed-in-user show` returns different values. So, instead of `$currentUser.Id`, you have to use `$currentUser.ObjectId`

## PowerShell

This part shows how to set up the infrastructure using simple PowerShell scripts. This is probably not the recommended way, but a very simple way to get started.

### Set up infrastructure using your own account

For this section, you will use your own account to do everything. And as long as you have the required privileges, you should be good to go.

```powershell
> $group = az group create -g SqlDemo -l WestEurope | ConvertFrom-Json

> $currentUser = az ad signed-in-user show | ConvertFrom-Json

> $random = ([char[]]([char]'a'..[char]'z') + 0..9 | sort {get-random})[0..6] -join ''

> ./powershell/set-up.sp.ps1 -groupName $group.Name -sqlAdminName $currentUser.DisplayName -sqlAdminPrincipalId $currentUser.Id -suffix $random
```

And to remove it all, just run

```powershell
> az group delete -g SqlDemo -y
```

### Set up infrastructure using a service principal with Directory.Read.All permission

For this section, you will use a service principal with the required permissions added to it. Unfortunately, you will see that it fails when you try to add the SQL Server user, as it will not have the required permission. 

The reason for this, is that when you run a SQL command using a "real" user account, like you did before, it uses that accounts permissions. However, when you run it using a Service Principal, it uses the SQL Server's identity to do the directory look up. And in this case, that principal will not have the required permission...

```powershell
> $group = az group create -g SqlDemo -l WestEurope | ConvertFrom-Json

> $principal = az ad sp create-for-rbac --name SqlDemoUser --role owner --scopes $group.Id | ConvertFrom-Json

> $graph = az ad sp list --query "[?appDisplayName=='Microsoft Graph'].{AppId:appId, Id:id} | [0]" | ConvertFrom-Json

> $directoryReadPermission = az ad sp show --id $graph.AppId --query "appRoles[?value=='Directory.Read.All']" | ConvertFrom-Json

> az ad app permission add --id $principal.AppId --api $graph.AppId --api-permissions "$($directoryReadPermission.Id)=Role" | Out-Null

> az ad app permission admin-consent --id $principal.AppId

> az login --service-principal -u $principal.AppId -p $principal.Password --tenant $principal.Tenant

> $random = ([char[]]([char]'a'..[char]'z') + 0..9 | sort {get-random})[0..6] -join ''

> ./powershell/set-up.sp.ps1 -groupName $group.Name -sqlAdminName $principal.DisplayName -sqlAdminPrincipalId $principal.AppId -suffix $random
```

Add to remove the created resources, you need to run

```powershell
> az login # Revert to your own account

> az group delete -g SqlDemo -y

> az ad app delete --id $principal.AppId
```

### Set up infrastructure using a service principal for deployment, and a managed service identity for directory access

Now, you will set up a new managed identity with the correct permissions, and use that as the SQL Server principal. You will then set up a Service Principal that does not have any AD permissions, and use that to both deploy the infrastructure and set up the SQL user.

To create a Managed Identity to use as the SQL Server identity, you need to run the following commands. It will also add the Microsoft Graph API's __Directory.Read.All__ permission to the identity.

```powershell
> $currentUser = az ad signed-in-user show | ConvertFrom-Json

> $group = az group create -g SqlDemo -l WestEurope | ConvertFrom-Json

> $identity = az identity create --name SqlDemoIdentity -g $group.Name | ConvertFrom-Json

> $graph = az ad sp list --query "[?appDisplayName=='Microsoft Graph'].{AppId:appId, Id:id} | [0]" --all | ConvertFrom-Json

> $directoryReadPermission = az ad sp show --id $graph.AppId --query "appRoles[?value=='Directory.Read.All']" | ConvertFrom-Json

> az rest -m POST -u https://graph.microsoft.com/v1.0/servicePrincipals/$($identity.PrincipalId)/appRoleAssignments `
          --headers "{\`"Content-Type\`":\`"application/json\`"}" `
          --body "{\`"principalId\`": \`"$($identity.PrincipalId)\`", \`"resourceId\`": \`"$($graph.Id)\`", \`"appRoleId\`": \`"$($directoryReadPermission.id)\`"}" `
          | Out-Null

```

Next, you can create the Service Principal, log in as it, and deploy everything using the following commands.

```powershell
> $principal = az ad sp create-for-rbac --name SqlDemoUser --role owner --scopes $group.Id | ConvertFrom-Json

> az login --service-principal -u $principal.AppId -p $principal.Password --tenant $principal.Tenant

> $random = ([char[]]([char]'a'..[char]'z') + 0..9 | sort {get-random})[0..6] -join ''

> ./powershell/set-up.msi.ps1 -groupName $group.Name -msiName $identity.Name -msiPrincipalId $identity.Id -suffix $random
```

And to remove it, you just run

```powershell
> az login # Revert to your own account

> az group delete -g SqlDemo -y

> az ad app delete --id $principal.AppId
```

## Bicep

This part shows how to do the same thing as you just did with PowerShell, but using a Bicep template.

### Set up infrastructure using your own account

To start with, you will use your own account to do everything. And as long as you have the required privileges, you should be good to go.

Start by creating a resource group, and deploy the infrastructure using the Bicep template. Like this

```powershell
> $group = az group create -g SqlDemo -l WestEurope | ConvertFrom-Json

> $currentUser = az ad signed-in-user show | ConvertFrom-Json

> az deployment group create -n main --resource-group $group.Name `
        --template-file ./bicep/main.sp.bicep `
        --parameters sqlAdminLoginName="$($currentUser.UserPrincipalName)" `
                     sqlAdminPrincipalId="$($currentUser.Id)" `
        | Out-Null
```

Once the infrastructure is up and running, you can add the SQL Server user by running the following commands

```powershell
> $outputs = az deployment group show -g $group.Name -n main --query properties.outputs | ConvertFrom-Json

> ./powershell/add-sql-user.ps1 -groupName SqlDemo -sqlServerHostName $outputs.sqlServerHostName.value `
                     -dbName DemoDb -principalName $outputs.webAppName.value `
                     -principalId $outputs.webAppIdentityId.value
```

And to remove it all, you can just delete the resource group

```powershell
> az group delete -g SqlDemo -y 
```

### Set up infrastructure using a service principal with Directory.Read.All permission

Here, you will use a service principal, with the required permissions added to it, to do the work. Unfortunately, you will see that it fails when you try to add the SQL Server user, as it will not have the required permission. 

Once again, the reason for this, is that it uses the SQL Server's identity to do the directory look up. And that principal will not have the required permission...

```powershell
> $group = az group create -g SqlDemo -l WestEurope | ConvertFrom-Json

> $principal = az ad sp create-for-rbac --name SqlDemoUser --role owner --scopes $group.Id | ConvertFrom-Json

> $graph = az ad sp list --query "[?appDisplayName=='Microsoft Graph'].{AppId:appId, Id:id} | [0]" | ConvertFrom-Json

> $directoryReadPermission = az ad sp show --id $graph.AppId --query "appRoles[?value=='Directory.Read.All']" | ConvertFrom-Json

> az ad app permission add --id $principal.AppId --api $graph.AppId --api-permissions "$($directoryReadPermission.Id)=Role" | Out-Null

> az ad app permission admin-consent --id $principal.AppId

> az login --service-principal -u $principal.AppId -p $principal.Password --tenant $principal.Tenant

> az deployment group create -n main --resource-group $group.Name `
        --template-file ./bicep/main.sp.bicep `
        --parameters sqlAdminLoginName="$($principal.DisplayName)" `
                     sqlAdminPrincipalId="$($principal.AppId)" `
        | Out-Null
```

Once the infrastructure has been deployed, you can try to add the SQL Server user by running the following commands

```powershell
> $outputs = az deployment group show -g $group.Name -n main --query properties.outputs | ConvertFrom-Json

> ./powershell/add-sql-user.ps1 -groupName SqlDemo -sqlServerHostName $outputs.sqlServerHostName.value `
                     -dbName DemoDb -principalName $outputs.webAppName.value `
                     -principalId $outputs.webAppIdentityId.value
```

But, as mentioned, this will fail with the error

> Server identity does not have Azure Active Directory Readers permission

To remove the created resources, just log back in as yourself, and then delete the resource group and service principal

```powershell
> az login # Revert to your own account

> az group delete -g SqlDemo -y

> az ad app delete --id $principal.AppId
```

### Set up infrastructure using a service principal for deployment, and a managed service identity for directory access

The last version assigns a managed identity with the correct permissions as the SQL Server principal. This allows you to use a Service Principal without any AD permissions to both deploy the infrastructure and set up the SQL user.

To create a Managed Identity to use as the SQL Server identity, you need to run the following commands. It will also add the Microsoft Graph API's __Directory.Read.All__ permission to the identity.

```powershell
> $group = az group create -g SqlDemo -l WestEurope | ConvertFrom-Json

> $identity = az identity create --name SqlDemoIdentity -g $group.Name | ConvertFrom-Json

> $graph = az ad sp list --query "[?appDisplayName=='Microsoft Graph'].{AppId:appId, Id:id} | [0]" --all | ConvertFrom-Json

> $directoryReadPermission = az ad sp show --id $graph.AppId --query "appRoles[?value=='Directory.Read.All']" | ConvertFrom-Json

> az rest -m POST -u https://graph.microsoft.com/v1.0/servicePrincipals/$($identity.PrincipalId)/appRoleAssignments `
          --headers "{\`"Content-Type\`":\`"application/json\`"}" `
          --body "{\`"principalId\`": \`"$($identity.PrincipalId)\`", \`"resourceId\`": \`"$($graph.Id)\`", \`"appRoleId\`": \`"$($directoryReadPermission.id)\`"}" `
          | Out-Null

```

Next, you can create the Service Principal, log in as it, and deploy the infrastructure using the following commands.

```powershell
> $principal = az ad sp create-for-rbac --name SqlDemoUser --role owner --scopes $group.Id | ConvertFrom-Json

> az login --service-principal -u $principal.AppId -p $principal.Password --tenant $principal.Tenant

> az deployment group create -n main --resource-group $group.Name `
        --template-file ./bicep/main.msi.bicep `
        --parameters sqlAdminLoginName="$($principal.DisplayName)" `
                     sqlAdminPrincipalId="$($principal.AppId)" `
                     sqlServerMsiName="$($identity.name)" `
        | Out-Null
```

And finally, you can add the SQL Server user, using the same service principal, by running

```powershell
> $outputs = az deployment group show -g $group.Name -n main --query properties.outputs | ConvertFrom-Json

> ./powershell/add-sql-user.ps1 -groupName SqlDemo -sqlServerHostName $outputs.sqlServerHostName.value `
                     -dbName DemoDb -principalName $outputs.webAppName.value `
                     -principalId $outputs.webAppIdentityId.value
```

And to clean up all the generated resources, you can just run

```powershell
> az login # Revert to your own account

> az group delete -g SqlDemo -y

> az ad app delete --id $principal.AppId
```