# GitHub Copilot Instructions

## Repository Overview

This is a home automation system built with Azure Functions, Service Bus, and Alexa Skills. The system manages virtual devices for home control and announcement broadcasting.

## Project Structure

- `/alexa-fn/` - Azure Function for Alexa skill backend
- `/alexa-skill/` - Alexa skill configuration and handlers
- `/door-fn/` - Azure Function for door sensor events
- `/flume-fn/` - Azure Function for water monitoring
- `/infra/` - Bicep templates for Azure infrastructure and deployment scripts
- `/tests/` - All test scripts and testing configurations

### File Organization Rules

**Root Level Files**: Only `README.md` should exist at the root level. All other files must be organized into appropriate subdirectories:

- **Infrastructure & Deployment**: All deployment scripts (e.g., `deploy-azure.ps1`) belong in `/infra/`
- **Testing**: All test scripts, configurations, and utilities belong in `/tests/`
- **Function Code**: Each Azure Function has its own directory with all related files
- **Documentation**: Project documentation should be in appropriate subdirectories or at root level only for main README

**Prohibited**: Creating new files directly at the root level (except README.md updates)

## Coding Guidelines

### Language and Framework Preferences

- **Python**: Use Python 3.11 for all Azure Functions
- **Infrastructure**: Use Bicep templates, not ARM or manual scripts
- **Dependencies**: Minimize external packages, prefer Azure SDK libraries
- **Error Handling**: Always include proper try/catch blocks and logging

### Architecture Patterns

- One Service Bus queue per device ID (all, bedroom, downstairs, upstairs)
- Stateless Azure Functions with dependency injection
- Configuration through environment variables and Key Vault
- RESTful API design with clear endpoint naming

## Azure-Only Architecture

### Core Principle: No AWS Services

- **Alexa Skills**: Backend hosted on Azure Functions, NOT AWS Lambda
- **All compute**: Azure Functions (Python 3.11) only
- **All messaging**: Azure Service Bus, NOT AWS SQS/SNS
- **All storage**: Azure Storage/Cosmos DB, NOT AWS S3/DynamoDB
- **All monitoring**: Azure Application Insights, NOT AWS CloudWatch

### Alexa Skill Integration

- Alexa skill backend runs on Azure Function App (`alexa-fn`)
- Skill endpoint points to Azure Function HTTP trigger
- No AWS Lambda functions or AWS services
- Use `deploy.ps1` in alexa-skill folder for Azure deployment

### Code Style

- Follow PEP 8 for Python code formatting
- Use descriptive function and variable names
- Include docstrings for all public functions
- Keep functions focused and single-purpose

## File Editing Preferences

### Markdown Files

When editing `.md` files, prefer PowerShell commands over `replace_string_in_file`:

```powershell
# Complete file replacement
Set-Content -Path "file.md" -Value $content -Encoding UTF8
```

### README Files as Notebooks

**Important**: README.md files in this project are structured as Jupyter-style notebooks with markdown cells. When creating or editing README files:

- **Structure**: Use markdown cells for different sections
- **Creation Method**: Prefer PowerShell `Set-Content` or `create_file` tool over notebook editing tools
- **Format**: Content should be valid markdown that can be rendered as documentation
- **Organization**: Break content into logical sections using cell boundaries

**Creation Pattern**:
```powershell
# Create comprehensive README with proper markdown structure
$content = @"
# Section Title

Content here...

## Subsection

More content...
"@
Set-Content -Path "README.md" -Value $content -Encoding UTF8
```

### Code Files

- Use `replace_string_in_file` for Python and configuration files
- Include 3-5 lines of context before/after changes
- Validate syntax after edits

### Python Azure Functions Configuration

For Python Azure Functions, follow the flume-fn pattern:

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
    "AzureWebJobsStorage": "",
    "sbcon": "Service Bus connection string (same as door-fn)"
  }
}
```

## Development Environment Setup

### Prerequisites

- Python 3.11 installed
- Azure Functions Core Tools v4
- PowerShell 7+ for Windows

### Initial Setup

1. **Clone and navigate to the project directory**:

```powershell
git clone <repository-url>
cd home-automation
```

2. **Create and activate Python virtual environment**:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

3. **Install dependencies**:

```powershell
pip install -r requirements.txt
```

### Daily Development Workflow

**IMPORTANT**: Always ensure you are in the virtual environment before starting development:

```powershell
# Navigate to project directory
cd C:\Users\srpadala\workspace\Home\home-automation

# Activate virtual environment
.\.venv\Scripts\Activate.ps1

# Verify virtual environment is active (should show (.venv) in prompt)
# Start Azure Functions
func start
```

### Terminal Management

- **Server Terminal**: Use one terminal for running unc start (keep this running)

- **Testing Terminal**: Open a NEW terminal for curl commands and testing:

```powershell
# In a new terminal window/tab
curl -X POST "http://localhost:7071/api/alexa_skill" -H "Content-Type: application/json" -d @test-payload.json
```

### Local Testing Best Practices

1. **Before starting development**:

   - Ensure virtual environment is activated: .\.venv\Scripts\Activate.ps1
   - Verify you're in the correct directory: pwd should show home-automation
   - Check Python packages: pip list should show azure-servicebus, azure-functions, etc.

2. **Starting the function app**:

```powershell
# In project root with virtual environment active
func start
```

3. **Testing endpoints**:

   - Use a separate terminal for curl commands
   - Test Service Bus functionality with proper authentication headers
   - Validate all three endpoints: /api/alexa_skill, /api/announce, /api/devices

### Troubleshooting Local Development

#### Module Import Errors

If you see "No module named 'azure.servicebus'" or similar:

```powershell
# Verify virtual environment is active
.\.venv\Scripts\Activate.ps1

# Reinstall packages
pip install --force-reinstall -r requirements.txt

# Check Azure Functions Core Tools version
func --version  # Should be 4.x
```

#### Virtual Environment Issues

```powershell
# Recreate virtual environment if needed
Remove-Item -Recurse -Force .venv
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

#### Azure Functions Runtime Issues

- Ensure Azure Functions Core Tools v4 is installed
- Verify local.settings.json exists with proper configuration
- Check that function_app.py is in the root directory

## Development Environment Setup

### Prerequisites

- Python 3.11 installed
- Azure Functions Core Tools v4
- PowerShell 7+ for Windows

### Initial Setup

1. **Clone and navigate to the project directory**:

```powershell
git clone <repository-url>
cd home-automation
```

2. **Create and activate Python virtual environment**:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

3. **Install dependencies**:

```powershell
pip install -r requirements.txt
```

### Daily Development Workflow

**IMPORTANT**: Always ensure you are in the virtual environment before starting development:

```powershell
# Navigate to project directory
cd C:\Users\srpadala\workspace\Home\home-automation

# Activate virtual environment
.\.venv\Scripts\Activate.ps1

# Verify virtual environment is active (should show (.venv) in prompt)
# Start Azure Functions
func start
```

### Terminal Management

- **Server Terminal**: Use one terminal for running `func start` (keep this running)

- **Testing Terminal**: Open a NEW terminal for curl commands and testing:

```powershell
# In a new terminal window/tab
curl -X POST "http://localhost:7071/api/alexa_skill" -H "Content-Type: application/json" -d @test-payload.json
```

### Local Testing Best Practices

1. **Before starting development**:

   - Ensure virtual environment is activated: `.\.venv\Scripts\Activate.ps1`
   - Verify you're in the correct directory: `pwd` should show `home-automation`
   - Check Python packages: `pip list` should show azure-servicebus, azure-functions, etc.

2. **Starting the function app**:

```powershell
# In project root with virtual environment active
func start
```

3. **Testing endpoints**:

   - Use a separate terminal for curl commands
   - Test Service Bus functionality with proper authentication headers
   - Validate all three endpoints: `/api/alexa_skill`, `/api/announce`, `/api/devices`

### Troubleshooting Local Development

#### Module Import Errors

If you see "No module named 'azure.servicebus'" or similar:

```powershell
# Verify virtual environment is active
.\.venv\Scripts\Activate.ps1

# Reinstall packages
pip install --force-reinstall -r requirements.txt

# Check Azure Functions Core Tools version
func --version  # Should be 4.x
```

#### Virtual Environment Issues

```powershell
# Recreate virtual environment if needed
Remove-Item -Recurse -Force .venv
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

#### Azure Functions Runtime Issues

- Ensure Azure Functions Core Tools v4 is installed
- Verify local.settings.json exists with proper configuration
- Check that function_app.py is in the root directory

## Development Environment Setup

### Prerequisites

- Python 3.11 installed
- Azure Functions Core Tools v4
- PowerShell 7+ for Windows

### Initial Setup

1. **Clone and navigate to the project directory**:
   `powershell
   git clone <repository-url>
   cd home-automation
   `
2. **Create and activate Python virtual environment**:
   `powershell
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   `
3. **Install dependencies**:
   `powershell
   pip install -r requirements.txt
   `

### Daily Development Workflow

**IMPORTANT**: Always ensure you are in the virtual environment before starting development:

`powershell

# Navigate to project directory

cd C:\Users\srpadala\workspace\Home\home-automation

# Activate virtual environment

.\.venv\Scripts\Activate.ps1

# Verify virtual environment is active (should show (.venv) in prompt)

# Start Azure Functions

func start
`

### Terminal Management

- **Server Terminal**: Use one terminal for running unc start (keep this running)
- **Testing Terminal**: Open a NEW terminal for curl commands and testing:
   `powershell
   # In a new terminal window/tab

   curl -X POST "http://localhost:7071/api/alexa_skill" -H "Content-Type: application/json" -d @test-payload.json
   `

### Local Testing Best Practices

1. **Before starting development**:

   - Ensure virtual environment is activated: .\.venv\Scripts\Activate.ps1
   - Verify you're in the correct directory: pwd should show home-automation
   - Check Python packages: pip list should show azure-servicebus, azure-functions, etc.

2. **Starting the function app**:
   `powershell

   # In project root with virtual environment active

   func start
   `

3. **Testing endpoints**:

   - Use a separate terminal for curl commands
   - Test Service Bus functionality with proper authentication headers
   - Validate all three endpoints: /api/alexa_skill, /api/announce, /api/devices

### Troubleshooting Local Development

#### Module Import Errors

If you see "No module named 'azure.servicebus'" or similar:
`powershell

# Verify virtual environment is active

.\.venv\Scripts\Activate.ps1

# Reinstall packages

pip install --force-reinstall -r requirements.txt

# Check Azure Functions Core Tools version

func --version  # Should be 4.x
`

#### Virtual Environment Issues

`powershell

# Recreate virtual environment if needed

Remove-Item -Recurse -Force .venv
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
`

#### Azure Functions Runtime Issues

- Ensure Azure Functions Core Tools v4 is installed
- Verify local.settings.json exists with proper configuration
- Check that function_app.py is in the root directory

## Infrastructure Requirements

### Service Bus Configuration

- Enable dead lettering on message expiration
- Set TTL to 60 minutes for announcement queues
- Use consistent naming: `announcements-{device}`

### Azure Functions

- Runtime: Python 3.11
- Consumption plan for cost optimization
- Application Insights for monitoring
- Managed identity for secure connections

### Security

- Store secrets in Key Vault, not app settings
- Use managed identities over connection strings
- Enable HTTPS only for all endpoints

## Testing Guidelines

- Test all API endpoints after changes
- Validate Bicep templates before deployment
- Check Service Bus connectivity after infrastructure changes
- Verify Alexa skill responses match expected format

## Deployment Process

## Deployment Process (Azure-Only)

1. **Infrastructure**: Deploy Azure resources with Bicep templates

```powershell
azd provision  # or manual: az deployment group create
```

2. **Function Apps**: Deploy all function code to Azure

```powershell
azd deploy     # Deploys door-fn, flume-fn, alexa-fn
```

3. **Alexa Skill**: Deploy skill backend to Azure (NOT AWS Lambda)

```powershell
cd alexa-skill
.\deploy.ps1   # Deploys to Azure Function App
```

4. **Validation**: Test all Azure endpoints

   - Verify Service Bus connectivity
   - Test Alexa skill responses
   - Check Application Insights logs

5. **Documentation**: Update any API documentation for changes

**Important**: This system runs entirely on Azure - no AWS services required!

## Common Issues and Solutions

### Service Bus Connection Failures

- Verify managed identity has Service Bus Data Owner role
- Check queue names are case-sensitive matches
- Ensure connection string format is correct

### Function App Deployment Errors

- Validate `requirements.txt` dependencies
- Check Python version compatibility
- Verify all environment variables are set

### Bicep Template Errors

- Use correct property names (e.g., `deadLetteringOnMessageExpiration`)
- Include proper resource dependencies
- Follow Azure naming conventions

### Alexa Skill Azure Deployment Issues

- Verify Azure Function App is responding to HTTP requests
- Check skill endpoint URL in Alexa Developer Console matches Azure Function
- Ensure Azure Function auth level is set to Function or Anonymous as needed
- Validate all environment variables are set in Azure Function App settings
- Test with Alexa Developer Console simulator before live device testing

## AWS Lambda Migration Notes

**This project has been fully migrated from AWS Lambda to Azure Functions:**

- Former `lambda/lambda_function.py` → Now handled by `alexa-fn/function_app.py`
- AWS deployment scripts removed in favor of `alexa-skill/deploy.ps1`
- No AWS CLI or Lambda runtime dependencies required
- All costs and services now consolidated on Azure platform
