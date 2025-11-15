# Project Structure

This document describes the organization of the Bedrock Global API deployment package.

## Directory Structure

```
dexter-global-genai-api/
├── README.md                          # Comprehensive deployment guide
├── QUICKSTART.md                      # Quick start guide (15 minutes)
├── PROJECT_STRUCTURE.md                # This file
├── .gitignore                         # Git ignore rules
│
└── cloudformation/
    ├── bedrock-global-api.yaml        # Main CloudFormation template
    ├── deploy.ps1                      # PowerShell deployment script (Windows)
    ├── deploy.sh                       # Bash deployment script (Linux/Mac)
    ├── parameters-template.json        # Example parameters file
    │
    └── lambda-routing-function/
        ├── index.py                    # Lambda function source code
        ├── requirements.txt            # Python dependencies
        └── routing-config.yaml         # Example routing configuration
```

## File Descriptions

### Root Level Files

#### `README.md`
Comprehensive documentation including:
- Architecture overview
- Prerequisites and setup
- Detailed deployment instructions
- Configuration guide
- API usage examples
- Troubleshooting
- Cost optimization

#### `QUICKSTART.md`
Condensed quick start guide for rapid deployment:
- Prerequisites checklist
- Step-by-step deployment (15 minutes)
- Common issues and solutions
- Next steps

#### `PROJECT_STRUCTURE.md`
This file - describes project organization.

#### `.gitignore`
Git ignore patterns for:
- AWS credentials and parameters
- Python cache files
- Lambda deployment packages
- IDE files
- Temporary files

### CloudFormation Directory

#### `bedrock-global-api.yaml`
**Main CloudFormation template** (~1300 lines)

Contains all AWS resources:
- Route 53 (hosted zone, DNS records)
- CloudFront (distribution, logging)
- API Gateway HTTP API (custom domain, authorizers, routes)
- AWS WAF (web ACL, IP sets, rules)
- Amazon Cognito (user pool, client)
- Amazon SQS (request queue, DLQ)
- AWS Lambda (routing function with inline code)
- IAM Roles (Lambda execution, API Gateway, DAX)
- Amazon DynamoDB (cache table)
- DynamoDB Accelerator (DAX cluster, subnet group, parameter group)
- VPC Resources (VPC, subnets, IGW, route tables - when DAX enabled)
- KMS Keys (SQS, DynamoDB encryption)
- CloudWatch (log groups, alarms, SNS topic)
- ACM Certificate (auto-created)

**Key Features**:
- Multi-region support
- Conditional resources (DAX, CloudFront, VPC)
- Comprehensive security (WAF, KMS, IAM)
- Full observability (CloudWatch, X-Ray)

#### `deploy.ps1`
**PowerShell deployment script** (Windows)

Interactive script that:
- Validates prerequisites (AWS CLI, credentials)
- Prompts for all required parameters
- Validates inputs (domain format, regions, etc.)
- Creates parameters JSON file
- Deploys CloudFormation stack
- Monitors deployment progress
- Displays stack outputs

**Usage**:
```powershell
.\deploy.ps1
.\deploy.ps1 -StackName my-stack -Region us-east-1
```

#### `deploy.sh`
**Bash deployment script** (Linux/Mac)

Same functionality as PowerShell script, adapted for Unix systems.

**Usage**:
```bash
chmod +x deploy.sh
./deploy.sh
./deploy.sh my-stack us-east-1
```

#### `parameters-template.json`
**Example parameters file**

JSON template showing all CloudFormation parameters with example values. Can be used for:
- Non-interactive deployments
- CI/CD pipelines
- Documentation reference

**Usage**:
```bash
# Edit with your values
aws cloudformation create-stack \
  --stack-name my-stack \
  --template-body file://bedrock-global-api.yaml \
  --parameters file://parameters-template.json \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
```

### Lambda Function Directory

#### `lambda-routing-function/index.py`
**Lambda function source code**

Production-ready Python code for:
- SQS event processing
- Request routing based on app name
- DynamoDB/DAX caching
- Bedrock agent invocation
- Error handling and logging

**Key Functions**:
- `handler()`: Main entry point
- `route_request()`: Determines routing based on app
- `invoke_bedrock_agent()`: Calls Bedrock agent
- `get_from_cache()` / `put_to_cache()`: Cache operations

**Note**: The CloudFormation template includes inline Lambda code. For production, consider:
1. Packaging this code with dependencies
2. Uploading to S3
3. Updating template to reference S3 location

#### `lambda-routing-function/requirements.txt`
**Python dependencies**

Required packages:
- `boto3`: AWS SDK
- `pyyaml`: YAML parsing for routing config
- `amazondax`: DAX client (optional, for DAX support)

#### `lambda-routing-function/routing-config.yaml`
**Example routing configuration**

YAML file showing how to configure routing rules:
- Agent assignments per application
- Knowledge base mappings
- Default agent configuration
- Advanced routing examples

**Usage**: Can be loaded from S3 or embedded in Lambda environment variables.

## Deployment Workflows

### Workflow 1: Interactive Script (Recommended)
```
1. Run deploy.ps1 or deploy.sh
2. Answer prompts
3. Wait for deployment
4. Configure DNS
5. Test API
```

### Workflow 2: Manual CloudFormation
```
1. Edit parameters-template.json
2. Run aws cloudformation create-stack
3. Monitor in Console
4. Configure DNS
5. Test API
```

### Workflow 3: CI/CD Pipeline
```
1. Store parameters in CI/CD secrets
2. Use parameters-template.json as base
3. Deploy via pipeline
4. Automated DNS configuration
5. Automated testing
```

## Customization Points

### 1. Lambda Function Code
- **Location**: `lambda-routing-function/index.py`
- **Customization**: Modify routing logic, add features
- **Deployment**: Package and upload to S3, update template

### 2. Routing Configuration
- **Location**: `lambda-routing-function/routing-config.yaml`
- **Customization**: Add app-specific routing rules
- **Deployment**: Upload to S3 or use environment variables

### 3. WAF Rules
- **Location**: `bedrock-global-api.yaml` (WAFWebACL resource)
- **Customization**: Add custom rules, modify rate limits
- **Deployment**: Update stack

### 4. CloudWatch Alarms
- **Location**: `bedrock-global-api.yaml` (Alarm resources)
- **Customization**: Adjust thresholds, add alarms
- **Deployment**: Update stack

### 5. IAM Policies
- **Location**: `bedrock-global-api.yaml` (IAM Role resources)
- **Customization**: Fine-tune permissions
- **Deployment**: Update stack

## Version Control

### Recommended Git Strategy

1. **Main branch**: Production-ready template
2. **Feature branches**: Customizations and improvements
3. **Tags**: Version releases (v1.0.0, v1.1.0, etc.)

### What to Commit
- ✅ CloudFormation templates
- ✅ Lambda source code
- ✅ Deployment scripts
- ✅ Documentation
- ✅ Example configurations

### What NOT to Commit
- ❌ `parameters-*.json` (contains sensitive data)
- ❌ AWS credentials
- ❌ `.env` files
- ❌ Lambda deployment packages (`.zip`)

## Maintenance

### Regular Tasks

1. **Update Dependencies**: Review `requirements.txt` quarterly
2. **Security Audits**: Review IAM policies monthly
3. **Cost Optimization**: Review CloudWatch metrics monthly
4. **Template Updates**: Keep CloudFormation template updated
5. **Documentation**: Update README as features change

### Monitoring Files

- CloudWatch Logs: `/aws/lambda/{env}-bedrock-api-routing`
- CloudFormation Events: Stack events in Console
- WAF Logs: CloudWatch Logs Insights

## Support Resources

- **Documentation**: README.md, QUICKSTART.md
- **AWS Documentation**: Links in README
- **CloudFormation Events**: Stack events for errors
- **CloudWatch Logs**: Application logs for debugging

---

**Last Updated**: 2024  
**Template Version**: 1.0.0

