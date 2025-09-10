#!/bin/bash

# Home Automation Infrastructure Deployment Script
# This script deploys the home automation system with actual local settings

RESOURCE_GROUP_NAME="${1:-home-auto}"
LOCATION="${2:-eastus}"
TEMPLATE_FILE="${3:-main.bicep}"
PARAMETERS_FILE="${4:-main.parameters.local.json}"

echo "🏠 Home Automation Infrastructure Deployment"
echo "============================================="
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "⚠️ Not logged in to Azure. Logging in..."
    az login
    if [ $? -ne 0 ]; then
        echo "❌ Failed to login to Azure"
        exit 1
    fi
fi

ACCOUNT_INFO=$(az account show --query "{name:name, user:user.name, id:id}" -o json)
ACCOUNT_NAME=$(echo $ACCOUNT_INFO | jq -r '.name')
USER_NAME=$(echo $ACCOUNT_INFO | jq -r '.user')
SUBSCRIPTION_ID=$(echo $ACCOUNT_INFO | jq -r '.id')

echo "✅ Logged in to Azure as: $USER_NAME"
echo "📋 Subscription: $ACCOUNT_NAME ($SUBSCRIPTION_ID)"
echo ""

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
    echo "🆕 Creating resource group: $RESOURCE_GROUP_NAME"
    az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create resource group"
        exit 1
    fi
    echo "✅ Resource group created successfully"
else
    echo "✅ Resource group exists: $RESOURCE_GROUP_NAME"
fi

# Check if template and parameters files exist
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "❌ Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [ ! -f "$PARAMETERS_FILE" ]; then
    echo "❌ Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

echo "📄 Template file: $TEMPLATE_FILE"
echo "⚙️ Parameters file: $PARAMETERS_FILE"
echo ""

# Preview deployment changes
echo "🔍 Previewing deployment changes..."
az deployment group what-if \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMETERS_FILE"

if [ $? -ne 0 ]; then
    echo "❌ Failed to preview deployment"
    exit 1
fi

echo ""
read -p "Continue with deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

# Deploy infrastructure
echo ""
echo "🚀 Deploying infrastructure..."
DEPLOYMENT_NAME="home-auto-deployment-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMETERS_FILE" \
    --name "$DEPLOYMENT_NAME" \
    --verbose

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo ""
echo "✅ Infrastructure deployment completed successfully!"
echo ""

# Show deployment outputs
echo "📊 Deployment outputs:"
az deployment group show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$DEPLOYMENT_NAME" \
    --query "properties.outputs" \
    --output table

echo ""
echo "🎉 Next steps:"
echo "   1. Deploy door-fn: cd ../door-fn && func azure functionapp publish door-fn"
echo "   2. Deploy flume-fn: cd ../flume-fn && func azure functionapp publish flume-fn"
echo "   3. Test the system using the commands in the README.md"
echo ""
echo "✅ Home automation infrastructure is ready!"
