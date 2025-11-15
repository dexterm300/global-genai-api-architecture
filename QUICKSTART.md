# Quick Start Guide - Bedrock Global API

This guide will get you up and running in **15 minutes**.

## Prerequisites Checklist

- [ ] AWS account with admin access
- [ ] AWS CLI installed (`aws --version`)
- [ ] AWS credentials configured (`aws configure`)
- [ ] Domain name registered (e.g., `example.com`)
- [ ] Bedrock agent(s) created in AWS Console

## Step-by-Step Deployment

### 1. Prepare Your Environment (2 minutes)

```bash
# Clone or download the repository
cd cloudformation

# Verify AWS access
aws sts get-caller-identity
```

### 2. Run Interactive Deployment (5 minutes)

**Windows:**
```powershell
.\deploy.ps1
```

**Linux/Mac:**
```bash
chmod +x deploy.sh
./deploy.sh
```

### 3. Answer Prompts

The script will ask for:

1. **Stack Name**: `bedrock-global-api-prod` (or your choice)
2. **Region**: `us-east-1` (recommended)
3. **Domain**: `api.yourdomain.com`
4. **Environment**: `prod`
5. **Applications**: `webapp1,webapp2` (your app names)
6. **Bedrock Agents**: `agent-12345,agent-67890` (your agent IDs)
7. **Knowledge Bases**: `KB12345,KB67890` (optional)
8. **Cache TTL**: `3600` (1 hour, default)
9. **Enable DAX**: `true` (for production) or `false` (for testing)
10. **Enable CloudFront**: `true` (recommended)

### 4. Wait for Deployment (10-15 minutes)

The script will:
- Create all AWS resources
- Wait for stack completion
- Display outputs

**Expected Output:**
```
Stack deployment completed successfully!

=== Stack Outputs ===
ApiGatewayUrl: https://xxxxx.execute-api.us-east-1.amazonaws.com/prod
CloudFrontUrl: xxxxx.cloudfront.net
CognitoUserPoolId: us-east-1_xxxxx
...
```

### 5. Configure DNS (5 minutes)

1. **Get Hosted Zone ID** from CloudFormation outputs
2. **Go to Route 53 Console** → Your hosted zone
3. **Copy the 4 nameservers**
4. **Update at your domain registrar**:
   - Go to your registrar (GoDaddy, Namecheap, etc.)
   - Find DNS/Nameserver settings
   - Replace with Route 53 nameservers
5. **Wait 5-60 minutes** for DNS propagation

### 6. Test Your API (2 minutes)

```bash
# Get a Cognito token first (see README for details)
TOKEN="your-jwt-token"

# Test the API
curl -X POST https://api.yourdomain.com/api/v1/chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-app-name: webapp1" \
  -d '{
    "input": "Hello, how are you?",
    "session_id": "test-session-123"
  }'
```

## Common First-Time Issues

### Issue: "Stack creation failed"

**Solution**: Check CloudFormation events:
```bash
aws cloudformation describe-stack-events \
  --stack-name bedrock-global-api-prod \
  --region us-east-1 \
  --max-items 10
```

### Issue: "Certificate validation pending"

**Solution**: 
- Check Route 53 for validation records
- Ensure nameservers are updated
- Wait up to 72 hours (usually 5-60 minutes)

### Issue: "No agent configured"

**Solution**:
- Verify Bedrock agent IDs are correct
- Check agent exists in Bedrock Console
- Ensure agent is in same region as deployment

## Next Steps

1. **Create Cognito Users** (see README)
2. **Configure Routing** (edit `routing-config.yaml`)
3. **Set Up Monitoring** (CloudWatch dashboards)
4. **Review Security** (WAF rules, IAM policies)

## Need Help?

- See full [README.md](README.md) for detailed documentation
- Check CloudWatch logs for errors
- Review CloudFormation stack events

## Cost Estimate

**First Month (Testing)**:
- ~$50-100 (with DAX disabled)
- ~$200-300 (with DAX enabled)

**Production (Moderate Traffic)**:
- ~$300-500/month

See README for cost optimization tips.

---

**Deployment Time**: ~15 minutes  
**Total Setup Time**: ~30 minutes (including DNS)

