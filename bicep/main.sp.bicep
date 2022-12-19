param location string = resourceGroup().location
param sqlAdminLoginName string
param sqlAdminPrincipalId string

var suffix = uniqueString(resourceGroup().id)

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: 'DemoSqlServer${suffix}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: sqlAdminLoginName
      principalType: 'User'
      sid: sqlAdminPrincipalId
      tenantId: subscription().tenantId
    }
  }

  resource db 'databases@2021-11-01' = {
    name: 'DemoDb'
    location: location
    sku: {
      name: 'Basic'
    }
  }

  resource SQLAllowAllWindowsAzureIps 'firewallRules@2021-11-01' = {
    name: 'Allow Azure Services'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
}

resource appSvcPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'DemoAppSvcPlan'
  location: location
  kind: 'app,linux'
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
}

resource webApplication 'Microsoft.Web/sites@2022-03-01' = {
  name: 'DemoWebApp${suffix}'
  location: location
  tags: {
    'hidden-related:${resourceGroup().id}/providers/Microsoft.Web/serverfarms/${appSvcPlan.name}': 'Resource'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appSvcPlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|7.0'
      connectionStrings: [
        {
          name: 'MyConnString'
          type: 'SQLServer'
          connectionString: 'Server=${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlServer::db.name};Authentication=Active Directory Default'
        }
      ]
    }
  }
}

output sqlServerHostName string = sqlServer.properties.fullyQualifiedDomainName
output webAppName string = webApplication.name
output webAppIdentityId string = webApplication.identity.principalId
