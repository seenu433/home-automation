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
param alexaFunctionAppName string = 'alexa-fn'
param location string = resourceGroup().location
param storageAccountName string = 'homeautomation'

// Infrastructure component names
param logAnalyticsWorkspaceName string = 'home-auto'
param applicationInsightsName string = 'home-auto'
param serviceBusNamespaceName string = 'srini-home-automation'

// Application configuration parameters
@secure()
param flumeUsername string
@secure()
param flumePassword string
@secure()
param flumeClientId string
@secure()
param flumeClientSecret string
param flumeTargetDeviceId string

// Alexa configuration parameters
// Smart Home Skill OAuth Configuration (for AcceptGrant authorization code exchange)
@secure()
param alexaSmartHomeClientId string
@secure()
param alexaSmartHomeClientSecret string
param alexaSmartHomeRedirectUri string

// LWA (Login with Amazon) Configuration (for API authentication and testing)
@secure()
param alexaLwaClientId string
@secure()
param alexaLwaClientSecret string

param alexaEventGatewayUrl string = 'https://api.amazonalexa.com/v3/events'

// Key Vault configuration parameters
param keyVaultName string = 'kv-home-auto'
param keyVaultSku string = 'standard'

// Account linking authentication parameters
param allowedUserId string = ''
param bypassAuth bool = false

// DoorEvent behavior configuration
param doorEventSilentMode bool = false

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
  name: 'sliding_door_left_open'
  parent: serviceBusNamespace
}
resource queueSlidingDoorRightOpen 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'sliding_door_right_open'
  parent: serviceBusNamespace
}

// Announcement queues for Alexa virtual devices
resource queueAnnouncementsAll 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'announcements-all'
  parent: serviceBusNamespace
  properties: {
    defaultMessageTimeToLive: 'PT60M'  // 60 minutes TTL
    maxSizeInMegabytes: 1024
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
}
resource queueAnnouncementsBedroom 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'announcements-bedroom'
  parent: serviceBusNamespace
  properties: {
    defaultMessageTimeToLive: 'PT60M'  // 60 minutes TTL
    maxSizeInMegabytes: 1024
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
}
resource queueAnnouncementsDownstairs 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'announcements-downstairs'
  parent: serviceBusNamespace
  properties: {
    defaultMessageTimeToLive: 'PT60M'  // 60 minutes TTL
    maxSizeInMegabytes: 1024
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
}
resource queueAnnouncementsUpstairs 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'announcements-upstairs'
  parent: serviceBusNamespace
  properties: {
    defaultMessageTimeToLive: 'PT60M'  // 60 minutes TTL
    maxSizeInMegabytes: 1024
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
}

// Azure Key Vault for secure token storage
resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'  // Can be restricted later for production
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'  // Can be restricted later for production
    }
  }
  tags: {
    Environment: 'Development'
    Project: 'HomeAutomation'
    Purpose: 'OAuthTokenStorage'
  }
}

// Key Vault Secrets for OAuth configuration
resource keyVaultSecretClientId 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  name: 'oauth-client-id'
  parent: keyVault
  properties: {
    value: alexaSmartHomeClientId
    contentType: 'application/json'
  }
}

resource keyVaultSecretClientSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  name: 'oauth-client-secret'
  parent: keyVault
  properties: {
    value: alexaSmartHomeClientSecret
    contentType: 'application/json'
  }
}

// Key Vault role assignments for Function Apps
resource keyVaultRoleAssignmentAlexa 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, alexaFunctionApp.id, 'Key Vault Secrets Officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: alexaFunctionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultRoleAssignmentDoor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets Officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultRoleAssignmentFlume 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, flumeFunctionApp.id, 'Key Vault Secrets Officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: flumeFunctionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Alexa Function App for Custom Skill (Deploy First)
resource alexaFunctionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: alexaFunctionAppName
  location: location
  kind: 'functionapp,linux'
  dependsOn: [
    queueTriggerevents
    queueFrontDoorUnlocked
    queueGarageDoorOpen
    queueGarageOpen
    queueDoorLeftOpen
    queueSlidingDoorRightOpen
    queueAnnouncementsAll
    queueAnnouncementsBedroom
    queueAnnouncementsDownstairs
    queueAnnouncementsUpstairs
  ]
  properties: {
    reserved: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      alwaysOn: false
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(alexaFunctionAppName)
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
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
        {
          name: 'sbcon'
          value: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
        }
        {
          name: 'DOOR_FN_BASE_URL'
          value: 'https://${functionAppName}.azurewebsites.net'
        }
        {
          name: 'DOOR_FN_API_KEY'
          value: 'placeholder-will-be-updated-post-deployment'
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
          name: 'ALEXA_SMART_HOME_CLIENT_ID'
          value: alexaSmartHomeClientId
        }
        {
          name: 'ALEXA_SMART_HOME_CLIENT_SECRET'
          value: alexaSmartHomeClientSecret
        }
        {
          name: 'ALEXA_SMART_HOME_REDIRECT_URI'
          value: alexaSmartHomeRedirectUri
        }
        {
          name: 'ALEXA_LWA_CLIENT_ID'
          value: alexaLwaClientId
        }
        {
          name: 'ALEXA_LWA_CLIENT_SECRET'
          value: alexaLwaClientSecret
        }
        {
          name: 'ALEXA_EVENT_GATEWAY_URL'
          value: alexaEventGatewayUrl
        }
        {
          name: 'AZURE_KEY_VAULT_URL'
          value: keyVault.properties.vaultUri
        }
        {
          name: 'TOKEN_STORAGE_TYPE'
          value: 'azure_key_vault'
        }
        {
          name: 'ALLOWED_USER_ID'
          value: allowedUserId
        }
        {
          name: 'BYPASS_AUTH'
          value: string(bypassAuth)
        }
        {
          name: 'DOOR_EVENT_SILENT_MODE'
          value: string(doorEventSilentMode)
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

// Door Function App (Deploy Second)
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
   properties: {
     reserved: true
     serverFarmId: appServicePlan.id
     siteConfig: {
       linuxFxVersion: 'DOTNET|8.0'
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
           value: 'dotnet'
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
           name: 'ALEXA_FN_BASE_URL'
           value: 'https://${alexaFunctionAppName}.azurewebsites.net'
         }
         {
           name: 'ALEXA_FN_API_KEY'
           value: 'placeholder-will-be-updated-post-deployment'
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

// Flume Python Function App (Deploy Third)
resource flumeFunctionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: flumeFunctionAppName
  location: location
  kind: 'functionapp,linux'
  dependsOn: [
    functionApp
  ]
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
          name: 'ALEXA_FN_BASE_URL'
          value: 'https://${alexaFunctionAppName}.azurewebsites.net'
        }
        {
          name: 'ALEXA_FN_API_KEY'
          value: 'placeholder-will-be-updated-post-deployment'
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

// Assign Storage Blob Data Contributor role to alexaFunctionApp managed identity
resource alexaFunctionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(alexaFunctionApp.id, 'storage-blob-data-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: alexaFunctionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}



output storageAccountName string = storageAccount.name
output alexaFunctionAppName string = alexaFunctionApp.name
output alexaFunctionAppUrl string = 'https://${alexaFunctionApp.properties.defaultHostName}'
output doorFunctionAppName string = functionApp.name
output flumeFunctionAppName string = flumeFunctionApp.name
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output serviceBusNamespace string = serviceBusNamespace.name

