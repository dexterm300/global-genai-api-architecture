# AWS Bedrock Global API - CloudFormation Deployment

A production-ready, multi-region AWS architecture for deploying a global API endpoint for Amazon Bedrock with authentication, caching, asynchronous processing, and comprehensive observability.

## Architecture Overview

This solution provides a complete, scalable infrastructure for routing API requests from multiple web applications to Amazon Bedrock agents and knowledge bases. The architecture includes:

- **Route 53**: Multi-region latency-based routing with health checks
- **CloudFront**: Global content delivery and caching
- **API Gateway (HTTP API)**: Cost-optimized RESTful API endpoint
- **AWS WAF**: Web application firewall with OWASP Top 10 protection
- **Amazon Cognito**: User authentication and authorization
- **Amazon SQS**: Asynchronous request processing with DLQ
- **AWS Lambda**: Intelligent request routing to Bedrock resources
- **Amazon DynamoDB**: Response caching with TTL
- **DynamoDB Accelerator (DAX)**: Ultra-low latency cache access
- **Amazon Bedrock**: AI/ML model and agent invocation
- **CloudWatch & X-Ray**: Comprehensive monitoring and tracing

## Prerequisites

Before deploying this solution, ensure you have:

### 1. AWS Account Setup

- An active AWS account with appropriate permissions
- AWS CLI installed and configured ([Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- AWS credentials configured (`aws configure`)

### 2. Required AWS Permissions

Your AWS user/role needs permissions for:
- CloudFormation (full access)
- IAM (create roles and policies)
- Route 53 (create hosted zones and records)
- API Gateway (create and manage APIs)
- Lambda (create functions and event sources)
- SQS (create queues)
- DynamoDB (create tables)
- Cognito (create user pools)
- CloudFront (create distributions)
- WAF (create web ACLs)
- ACM (request certificates)
- KMS (create keys)
- CloudWatch (create logs and alarms)
- EC2 (create VPC resources for DAX)
- Bedrock (invoke models and agents)

**Recommended**: Use an IAM user with AdministratorAccess for initial deployment, then restrict permissions post-deployment.

### 3. Domain Name

- A registered domain name (e.g., `example.com`)
- Access to your domain's DNS settings (for Route 53 hosted zone delegation)

### 4. Bedrock Resources

- Bedrock agents created in your AWS account
- Knowledge bases configured (optional)
- Note: Agent IDs and Knowledge Base IDs will be required during deployment

### 5. System Requirements

- **Windows**: PowerShell 5.1+ or Windows PowerShell
- **Linux/Mac**: Bash shell
- Internet connection for AWS API calls

## Quick Start

### Step 1: Clone or Download the Repository

```bash
git clone <repository-url>
cd dexter-global-genai-api
cd cloudformation
```

Or download and extract the ZIP file to your local machine.

### Step 2: Choose Your Deployment Method

You have three deployment options:

#### Option A: Interactive Script (Recommended for First-Time Deployment)

**Windows (PowerShell):**
```powershell
.\deploy.ps1
```

**Linux/Mac (Bash):**
```bash
chmod +x deploy.sh
./deploy.sh
```

The script will prompt you for all required parameters interactively.

#### Option B: Manual CloudFormation Deployment

1. Edit `parameters-template.json` with your values
2. Deploy using AWS CLI:

```bash
aws cloudformation create-stack \
  --stack-name bedrock-global-api-prod \
  --template-body file://bedrock-global-api.yaml \
  --parameters file://parameters-template.json \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --region us-east-1
```

#### Option C: AWS Console

1. Open AWS CloudFormation Console
2. Click "Create stack" → "With new resources"
3. Upload `bedrock-global-api.yaml`
4. Enter parameters manually
5. Acknowledge IAM capabilities
6. Create stack

### Step 3: Follow Interactive Prompts

If using the interactive script, you'll be prompted for:

1. **Stack Name**: Unique name for your CloudFormation stack (e.g., `bedrock-global-api-prod`)
2. **Primary Region**: AWS region for primary deployment (e.g., `us-east-1`)
3. **Domain Name**: Your custom domain (e.g., `api.example.com`)
4. **Environment**: `dev`, `staging`, or `prod`
5. **Secondary Regions**: Comma-separated list for multi-region (e.g., `us-west-2,eu-west-1`)
6. **Applications**: Comma-separated application names (e.g., `webapp1,webapp2`)
7. **Bedrock Agents**: Comma-separated agent IDs (e.g., `agent-12345,agent-67890`)
8. **Knowledge Bases**: Comma-separated KB IDs (e.g., `KB12345,KB67890`)
9. **Cache TTL**: Cache expiration in seconds (default: 3600)
10. **Enable DAX**: `true` or `false` (default: `true`)
11. **Enable CloudFront**: `true` or `false` (default: `true`)
12. **WAF Allowed IPs**: Optional IP whitelist (CIDR format)
13. **Certificate ARN**: Optional existing ACM certificate ARN

### Step 4: Wait for Deployment

The deployment typically takes **15-30 minutes** depending on:
- Number of regions
- DAX cluster size
- Certificate validation time

Monitor progress:
```bash
aws cloudformation describe-stacks --stack-name <your-stack-name> --region <region>
```

### Step 5: Configure DNS

After deployment completes:

1. **Get your Route 53 Hosted Zone ID** from CloudFormation outputs
2. **Update your domain's nameservers** at your domain registrar:
   - Go to your domain registrar (e.g., GoDaddy, Namecheap)
   - Find DNS/Nameserver settings
   - Replace existing nameservers with the Route 53 nameservers
   - Nameservers are shown in Route 53 console for your hosted zone

3. **Wait for DNS propagation** (typically 5-60 minutes)

### Step 6: Verify Deployment

1. **Check CloudFormation Outputs**:
   ```bash
   aws cloudformation describe-stacks \
     --stack-name <your-stack-name> \
     --region <region> \
     --query 'Stacks[0].Outputs'
   ```

2. **Test API Endpoint**:
   ```bash
   curl https://<your-domain>/api/v1/chat
   ```

3. **Check CloudWatch Logs**:
   - API Gateway logs: `/aws/apigateway/<environment>-bedrock-api`
   - Lambda logs: `/aws/lambda/<environment>-bedrock-api-routing`

## Detailed Configuration Guide

### Parameter Reference

| Parameter | Description | Required | Default | Example |
|-----------|-------------|----------|---------|----------|
| `DomainName` | Custom domain for API | Yes | - | `api.example.com` |
| `PrimaryRegion` | Primary AWS region | Yes | `us-east-1` | `us-east-1` |
| `SecondaryRegions` | Secondary regions for failover | No | `us-west-2,eu-west-1` | `us-west-2,eu-west-1` |
| `Environment` | Environment name | Yes | `prod` | `dev`, `staging`, `prod` |
| `Applications` | Application names | Yes | - | `webapp1,webapp2` |
| `BedrockAgents` | Bedrock agent IDs | No | - | `agent-12345,agent-67890` |
| `KnowledgeBases` | Knowledge base IDs | No | - | `KB12345,KB67890` |
| `CacheTTL` | Cache TTL in seconds | Yes | `3600` | `3600` |
| `EnableDAX` | Enable DAX cluster | Yes | `true` | `true`, `false` |
| `EnableCloudFront` | Enable CloudFront | Yes | `true` | `true`, `false` |
| `DAXNodeType` | DAX node instance type | Yes* | `dax.t3.small` | `dax.t3.small` |
| `DAXClusterSize` | Number of DAX nodes | Yes* | `1` | `1-10` |
| `WAFAllowedIPs` | IP whitelist (CIDR) | No | - | `203.0.113.0/24` |
| `CertificateArn` | Existing ACM cert ARN | No | - | Auto-created if empty |

*Required only if `EnableDAX` is `true`

### Creating Bedrock Agents

Before deployment, create your Bedrock agents:

1. **Navigate to Amazon Bedrock Console**
2. **Go to Agents** section
3. **Create Agent**:
   - Provide agent name and description
   - Select foundation model (e.g., Claude)
   - Configure instructions and knowledge bases
   - Save and note the Agent ID

4. **Get Agent ID**:
   ```bash
   aws bedrock-agent list-agents --region us-east-1
   ```

### Configuring Routing

The Lambda function routes requests based on application name. Configure routing in one of two ways:

#### Method 1: Environment Variables (Automatic)

The template automatically configures routing based on:
- `Applications` parameter → application names
- `BedrockAgents` parameter → agent IDs (matched by index)
- `KnowledgeBases` parameter → KB IDs (matched by index)

Example:
- Applications: `webapp1,webapp2`
- Agents: `agent-1,agent-2`
- Result: `webapp1` → `agent-1`, `webapp2` → `agent-2`

#### Method 2: Custom Routing Configuration

1. **Edit `lambda-routing-function/routing-config.yaml`**
2. **Upload to S3** (or use Lambda environment variables)
3. **Update Lambda function** to load from S3

See `lambda-routing-function/routing-config.yaml` for detailed examples.

### Setting Up Cognito Users

After deployment, create users in Cognito:

1. **Get User Pool ID** from CloudFormation outputs
2. **Create user via AWS CLI**:
   ```bash
   aws cognito-idp admin-create-user \
     --user-pool-id <pool-id> \
     --username user@example.com \
     --user-attributes Name=email,Value=user@example.com \
     --message-action SUPPRESS
   ```

3. **Set temporary password**:
   ```bash
   aws cognito-idp admin-set-user-password \
     --user-pool-id <pool-id> \
     --username user@example.com \
     --password <temporary-password> \
     --permanent
   ```

4. **Get authentication token**:
   ```bash
   aws cognito-idp initiate-auth \
     --auth-flow USER_PASSWORD_AUTH \
     --client-id <client-id> \
     --auth-parameters USERNAME=user@example.com,PASSWORD=<password>
   ```

## API Usage

### Authentication

All API requests require a JWT token from Cognito:

```bash
# Get token (see Cognito setup above)
TOKEN="<your-jwt-token>"

# Make API request
curl -X POST https://api.example.com/api/v1/chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-app-name: webapp1" \
  -d '{
    "input": "What is the weather today?",
    "session_id": "session-12345"
  }'
```

### Request Format

```json
{
  "input": "Your question or prompt here",
  "session_id": "unique-session-id",
  "metadata": {
    "user_id": "user-123",
    "context": "additional context"
  }
}
```

### Response Format

```json
{
  "statusCode": 200,
  "body": "Response from Bedrock agent",
  "cached": false,
  "app_name": "webapp1"
}
```

### Headers

- `Authorization`: Bearer token (required)
- `x-app-name`: Application name for routing (required)
- `Content-Type`: `application/json` (required)

## Monitoring and Observability

### CloudWatch Dashboards

Access pre-configured dashboards:
1. Open CloudWatch Console
2. Navigate to Dashboards
3. Look for stack-specific dashboards

### Key Metrics

- **SQS Queue Depth**: `ApproximateNumberOfMessagesVisible`
- **Lambda Errors**: `Errors` metric
- **Lambda Duration**: `Duration` metric
- **API 4xx/5xx Errors**: `4XXError`, `5XXError` metrics
- **Bedrock Invocation Latency**: Custom metric

### CloudWatch Alarms

The following alarms are automatically created:

- `{env}-sqs-queue-depth`: Alerts when queue depth > 1000
- `{env}-lambda-errors`: Alerts when errors > 10 in 5 minutes
- `{env}-lambda-duration`: Alerts when duration > 250 seconds
- `{env}-api-4xx-errors`: Alerts when 4xx errors > 50
- `{env}-api-5xx-errors`: Alerts when 5xx errors > 10

### X-Ray Tracing

Enable X-Ray in your requests:
```bash
curl -X POST https://api.example.com/api/v1/chat \
  -H "X-Amzn-Trace-Id: Root=1-5e272390-8c398be0373ec1525338a8b2" \
  ...
```

View traces in X-Ray Console.

## Troubleshooting

### Common Issues

#### 1. Certificate Validation Fails

**Problem**: ACM certificate stuck in "Pending validation"

**Solution**:
- Check Route 53 hosted zone for validation records
- Ensure DNS nameservers are correctly configured
- Wait up to 72 hours for validation

#### 2. Lambda Function Errors

**Problem**: Lambda function fails with "No agent configured"

**Solution**:
- Verify `BedrockAgents` parameter includes valid agent IDs
- Check Lambda environment variables
- Review CloudWatch logs: `/aws/lambda/{env}-bedrock-api-routing`

#### 3. API Gateway 403 Errors

**Problem**: Requests return 403 Forbidden

**Solution**:
- Verify JWT token is valid and not expired
- Check `x-app-name` header matches configured applications
- Review WAF logs for blocked requests

#### 4. DAX Connection Errors

**Problem**: Lambda cannot connect to DAX cluster

**Solution**:
- Verify Lambda is in same VPC as DAX
- Check security group rules allow port 8111
- Ensure DAX subnet group includes Lambda subnets

#### 5. SQS Messages Not Processing

**Problem**: Messages stuck in queue

**Solution**:
- Check Lambda function errors in CloudWatch
- Verify SQS event source mapping is enabled
- Review DLQ for failed messages

### Debugging Steps

1. **Check CloudFormation Events**:
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name <stack-name> \
     --region <region>
   ```

2. **Review Lambda Logs**:
   ```bash
   aws logs tail /aws/lambda/<function-name> --follow
   ```

3. **Test SQS Queue**:
   ```bash
   aws sqs receive-message --queue-url <queue-url>
   ```

4. **Verify IAM Permissions**:
   ```bash
   aws iam get-role-policy \
     --role-name <role-name> \
     --policy-name <policy-name>
   ```

## Cost Optimization

### Estimated Monthly Costs

**Small Deployment** (1 region, no DAX, low traffic):
- API Gateway: ~$3.50 per million requests
- Lambda: ~$0.20 per million requests
- CloudFront: ~$0.085 per GB
- DynamoDB: Pay-per-request pricing
- **Total**: ~$50-100/month for low traffic

**Production Deployment** (3 regions, DAX, high traffic):
- API Gateway: ~$35 per million requests
- Lambda: ~$2 per million requests
- CloudFront: ~$0.85 per GB
- DynamoDB: ~$1.25 per million requests
- DAX: ~$50-200/month (depending on node type)
- **Total**: ~$300-500/month for moderate traffic

### Cost Optimization Tips

1. **Use HTTP API** instead of REST API (already configured) ✅
2. **Enable CloudFront caching** to reduce origin requests
3. **Optimize Lambda memory** based on actual usage
4. **Use DynamoDB on-demand** for variable workloads
5. **Consider DAX only for high-traffic scenarios**
6. **Set appropriate cache TTL** to balance freshness vs. cost
7. **Use SQS batching** to reduce Lambda invocations

## Security Best Practices

### Implemented Security Features

✅ **TLS 1.2+** enforced on all endpoints
✅ **KMS encryption** for SQS and DynamoDB
✅ **WAF** with OWASP Top 10 protection
✅ **Cognito** for authentication
✅ **IAM roles** with least privilege
✅ **VPC endpoints** for private connectivity (when DAX enabled)
✅ **CloudWatch Logs** encryption
✅ **API Gateway** request validation

### Additional Recommendations

1. **Enable MFA** for Cognito users
2. **Rotate API keys** regularly
3. **Monitor WAF logs** for attack patterns
4. **Use AWS Secrets Manager** for sensitive configs
5. **Enable CloudTrail** for API auditing
6. **Implement rate limiting** per user/application
7. **Regular security audits** of IAM policies

## Updating the Stack

### Update Existing Stack

**Using Interactive Script**:
```bash
./deploy.sh <stack-name> <region> update
```

**Using AWS CLI**:
```bash
aws cloudformation update-stack \
  --stack-name <stack-name> \
  --template-body file://bedrock-global-api.yaml \
  --parameters file://parameters-updated.json \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --region <region>
```

### Updating Lambda Function Code

1. **Package Lambda code**:
   ```bash
   cd lambda-routing-function
   pip install -r requirements.txt -t .
   zip -r ../lambda-function.zip .
   ```

2. **Upload to S3**:
   ```bash
   aws s3 cp lambda-function.zip s3://<bucket>/lambda-function.zip
   ```

3. **Update CloudFormation template** to reference S3 location

## Deleting the Stack

**Warning**: This will delete all resources including data in DynamoDB.

```bash
aws cloudformation delete-stack \
  --stack-name <stack-name> \
  --region <region>
```

Or use the interactive script:
```bash
./deploy.sh <stack-name> <region> delete
```

## Support and Resources

### Documentation

- [AWS Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [API Gateway HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)
- [CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)

### Getting Help

1. Check CloudFormation stack events for errors
2. Review CloudWatch logs for application errors
3. Consult AWS documentation for service-specific issues
4. Open an issue in the repository (if applicable)

## License

This project is provided as-is for deployment purposes. Ensure compliance with AWS service terms and your organization's policies.

## Changelog

### Version 1.0.0
- Initial release
- Multi-region support
- DAX integration
- CloudFront distribution
- Comprehensive monitoring

---

**Last Updated**: 2025
**Maintained By**: Dexter M.


