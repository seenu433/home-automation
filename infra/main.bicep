// Assign Storage Blob Data Contributor role to functionApp managed identity
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(functionApp.id, 'storage-blob-data-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Storage Blob Data Contributor role to flumeFunctionApp managed identity
resource flumeFunctionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(flumeFunctionApp.id, 'storage-blob-data-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: flumeFunctionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
param functionAppName string = 'door-fn'
param functionAppPlanName string = 'homeautomation'
param flumeFunctionAppName string = 'flume-fn'
param location string = resourceGroup().location
param storageAccountName string = 'homeautomation'

// Infrastructure component names
param logAnalyticsWorkspaceName string = 'home-auto'
param applicationInsightsName string = 'home-auto'
param serviceBusNamespaceName string = 'srini-home-automation'

// Application configuration parameters
@secure()
param authKey string
@secure()
param voiceMonkeyToken string
@secure()
param flumeUsername string
@secure()
param flumePassword string
@secure()
param flumeClientId string
@secure()
param flumeClientSecret string
param flumeTargetDeviceId string
param voiceMonkeyDevice string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

// Log Analytics workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Service Bus namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

// Service Bus queues
resource queueTriggerevents 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'triggerevents'
  parent: serviceBusNamespace
}
resource queueFrontDoorUnlocked 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'front_door_unlocked'
  parent: serviceBusNamespace
}
resource queueGarageDoorOpen 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'garage_door_open'
  parent: serviceBusNamespace
}
resource queueGarageOpen 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'garage_open'
  parent: serviceBusNamespace
}
resource queueDoorLeftOpen 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'door_left_open'
  parent: serviceBusNamespace
}
resource queueSlidingDoorRightOpen 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'sliding_door_right_open'
  parent: serviceBusNamespace
}


resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  dependsOn: [
    queueTriggerevents
    queueFrontDoorUnlocked
    queueGarageDoorOpen
    queueGarageOpen
    queueDoorLeftOpen
    queueSlidingDoorRightOpen
  ]
   properties: {
     reserved: true
     serverFarmId: appServicePlan.id
     siteConfig: {
       appSettings: [
         {
           name: 'AzureWebJobsStorage'
           value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
         }
         {
           name: 'FUNCTIONS_EXTENSION_VERSION'
           value: '~4'
         }
         {
           name: 'FUNCTIONS_WORKER_RUNTIME'
           value: 'dotnet-isolated'
         }
         {
           name: 'WEBSITE_RUN_FROM_PACKAGE'
           value: '1'
         }
         {
           name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
           value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
         }
         {
           name: 'WEBSITE_CONTENTSHARE'
           value: toLower(functionAppName)
         }
         {
           name: 'sbcon'
           value: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
         }
         {
           name: 'AuthKey'
           value: authKey
         }
         {
           name: 'VoiceMonkey__Token'
           value: voiceMonkeyToken
         }
         {
           name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
           value: applicationInsights.properties.InstrumentationKey
         }
         {
           name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
           value: applicationInsights.properties.ConnectionString
         }
         {
           name: 'FUNCTIONS_WORKER_RUNTIME_VERSION'
           value: '8.0'
         }
         {
           name: 'AzureFunctionsJobHost__logging__logLevel__default'
           value: 'Information'
         }
         {
           name: 'AzureFunctionsJobHost__logging__logLevel__Host'
           value: 'Information'
         }
         {
           name: 'AzureFunctionsJobHost__logging__logLevel__Function'
           value: 'Information'
         }
       ]
     }
   }
   identity: {
     type: 'SystemAssigned'
   }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${functionAppPlanName}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

output functionAppName string = functionApp.name

// Flume Python Function App
resource flumeFunctionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: flumeFunctionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(flumeFunctionAppName)
        }
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
        {
          name: 'FLUME_USERNAME'
          value: flumeUsername
        }
        {
          name: 'FLUME_PASSWORD'
          value: flumePassword
        }
        {
          name: 'FLUME_CLIENT_ID'
          value: flumeClientId
        }
        {
          name: 'FLUME_CLIENT_SECRET'
          value: flumeClientSecret
        }
        {
          name: 'FLUME_TARGET_DEVICE_ID'
          value: flumeTargetDeviceId
        }
        {
          name: 'VOICE_MONKEY_TOKEN'
          value: voiceMonkeyToken
        }
        {
          name: 'VOICE_MONKEY_DEVICE'
          value: voiceMonkeyDevice
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'AzureFunctionsJobHost__logging__logLevel__default'
          value: 'Information'
        }
        {
          name: 'AzureFunctionsJobHost__logging__logLevel__Host'
          value: 'Information'
        }
        {
          name: 'AzureFunctionsJobHost__logging__logLevel__Function'
          value: 'Information'
        }
        {
          name: 'PYTHON_ENABLE_WORKER_EXTENSIONS'
          value: '1'
        }
      ]
    }
  }
   identity: {
     type: 'SystemAssigned'
   }
}
output storageAccountName string = storageAccount.name

