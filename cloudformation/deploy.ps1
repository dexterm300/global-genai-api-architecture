# PowerShell Deployment Script for Bedrock Global API
# This script provides an interactive deployment experience with prompts for all required parameters

param(
    [string]$StackName = "",
    [string]$Region = "",
    [string]$Action = "create"
)

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success { Write-ColorOutput Green $args }
function Write-Error { Write-ColorOutput Red $args }
function Write-Info { Write-ColorOutput Cyan $args }
function Write-Warning { Write-ColorOutput Yellow $args }

# Check AWS CLI installation
function Test-AWSCLI {
    try {
        $null = aws --version
        return $true
    } catch {
        Write-Error "AWS CLI is not installed. Please install it from https://aws.amazon.com/cli/"
        return $false
    }
}

# Check AWS credentials
function Test-AWSCredentials {
    try {
        $null = aws sts get-caller-identity
        return $true
    } catch {
        Write-Error "AWS credentials not configured. Please run 'aws configure'"
        return $false
    }
}

# Prompt for input with validation
function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "",
        [scriptblock]$Validation = $null,
        [bool]$Required = $true
    )
    
    while ($true) {
        if ($DefaultValue) {
            $input = Read-Host "$Prompt [$DefaultValue]"
            if ([string]::IsNullOrWhiteSpace($input)) {
                $input = $DefaultValue
            }
        } else {
            $input = Read-Host $Prompt
        }
        
        if ([string]::IsNullOrWhiteSpace($input)) {
            if ($Required) {
                Write-Warning "This field is required. Please enter a value."
                continue
            } else {
                return ""
            }
        }
        
        if ($Validation) {
            $result = & $Validation $input
            if ($result -ne $true) {
                Write-Warning $result
                continue
            }
        }
        
        return $input
    }
}

# Validate domain name
function Test-DomainName {
    param([string]$Domain)
    if ($Domain -match '^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)*$') {
        return $true
    }
    return "Invalid domain name format"
}

# Validate region
function Test-Region {
    param([string]$Region)
    $validRegions = @('us-east-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1')
    if ($validRegions -contains $Region) {
        return $true
    }
    return "Invalid region. Must be one of: $($validRegions -join ', ')"
}

# Main deployment function
function Start-Deployment {
    Write-Info "=========================================="
    Write-Info "  Bedrock Global API Deployment Script"
    Write-Info "=========================================="
    Write-Output ""
    
    # Check prerequisites
    if (-not (Test-AWSCLI)) {
        exit 1
    }
    
    if (-not (Test-AWSCredentials)) {
        exit 1
    }
    
    # Get stack name
    if ([string]::IsNullOrWhiteSpace($StackName)) {
        $script:StackName = Get-UserInput -Prompt "Enter CloudFormation stack name" -DefaultValue "bedrock-global-api-prod" -Required $true
    } else {
        $script:StackName = $StackName
    }
    
    # Get region
    if ([string]::IsNullOrWhiteSpace($Region)) {
        $script:Region = Get-UserInput -Prompt "Enter primary AWS region" -DefaultValue "us-east-1" -Validation ${function:Test-Region} -Required $true
    } else {
        $script:Region = $Region
    }
    
    Write-Info "`n=== Basic Configuration ==="
    
    # Domain name
    $DomainName = Get-UserInput -Prompt "Enter custom domain name (e.g., api.example.com)" -Validation ${function:Test-DomainName} -Required $true
    
    # Environment
    $Environment = Get-UserInput -Prompt "Enter environment (dev/staging/prod)" -DefaultValue "prod" -Required $true
    while ($Environment -notin @('dev', 'staging', 'prod')) {
        Write-Warning "Environment must be one of: dev, staging, prod"
        $Environment = Get-UserInput -Prompt "Enter environment (dev/staging/prod)" -DefaultValue "prod" -Required $true
    }
    
    Write-Info "`n=== Multi-Region Configuration ==="
    
    # Secondary regions
    Write-Info "Enter secondary regions for multi-region failover (comma-separated)"
    Write-Info "Example: us-west-2,eu-west-1"
    $SecondaryRegions = Get-UserInput -Prompt "Secondary regions" -DefaultValue "us-west-2,eu-west-1" -Required $false
    
    Write-Info "`n=== Application Configuration ==="
    
    # Applications
    Write-Info "Enter application names (comma-separated)"
    Write-Info "Example: webapp1,webapp2,webapp3"
    $Applications = Get-UserInput -Prompt "Application names" -DefaultValue "webapp1,webapp2" -Required $true
    
    Write-Info "`n=== Bedrock Configuration ==="
    
    # Bedrock agents
    Write-Info "Enter Bedrock agent IDs (comma-separated)"
    Write-Info "Example: agent-12345,agent-67890"
    $BedrockAgents = Get-UserInput -Prompt "Bedrock agent IDs" -DefaultValue "" -Required $false
    
    # Knowledge bases
    Write-Info "Enter Bedrock knowledge base IDs (comma-separated)"
    Write-Info "Example: KB12345,KB67890"
    $KnowledgeBases = Get-UserInput -Prompt "Knowledge base IDs" -DefaultValue "" -Required $false
    
    Write-Info "`n=== Performance & Caching Configuration ==="
    
    # Cache TTL
    $CacheTTL = Get-UserInput -Prompt "Cache TTL in seconds" -DefaultValue "3600" -Required $true
    while (-not ($CacheTTL -match '^\d+$') -or [int]$CacheTTL -lt 60 -or [int]$CacheTTL -gt 86400) {
        Write-Warning "Cache TTL must be between 60 and 86400 seconds"
        $CacheTTL = Get-UserInput -Prompt "Cache TTL in seconds" -DefaultValue "3600" -Required $true
    }
    
    # Enable DAX
    $EnableDAX = Get-UserInput -Prompt "Enable DynamoDB Accelerator (DAX)? (true/false)" -DefaultValue "true" -Required $true
    while ($EnableDAX -notin @('true', 'false')) {
        Write-Warning "Must be 'true' or 'false'"
        $EnableDAX = Get-UserInput -Prompt "Enable DAX? (true/false)" -DefaultValue "true" -Required $true
    }
    
    $DAXNodeType = "dax.t3.small"
    $DAXClusterSize = 1
    
    if ($EnableDAX -eq 'true') {
        Write-Info "DAX Node Type options: dax.t3.small, dax.t3.medium, dax.r4.large, dax.r4.xlarge, dax.r4.2xlarge"
        $DAXNodeType = Get-UserInput -Prompt "DAX node type" -DefaultValue "dax.t3.small" -Required $true
        
        $DAXClusterSize = Get-UserInput -Prompt "DAX cluster size (number of nodes)" -DefaultValue "1" -Required $true
        while (-not ($DAXClusterSize -match '^\d+$') -or [int]$DAXClusterSize -lt 1 -or [int]$DAXClusterSize -gt 10) {
            Write-Warning "Cluster size must be between 1 and 10"
            $DAXClusterSize = Get-UserInput -Prompt "DAX cluster size" -DefaultValue "1" -Required $true
        }
    }
    
    # Enable CloudFront
    $EnableCloudFront = Get-UserInput -Prompt "Enable CloudFront? (true/false)" -DefaultValue "true" -Required $true
    while ($EnableCloudFront -notin @('true', 'false')) {
        Write-Warning "Must be 'true' or 'false'"
        $EnableCloudFront = Get-UserInput -Prompt "Enable CloudFront? (true/false)" -DefaultValue "true" -Required $true
    }
    
    Write-Info "`n=== Security Configuration ==="
    
    # WAF Allowed IPs
    Write-Info "Enter allowed IP addresses for WAF (comma-separated, CIDR format)"
    Write-Info "Example: 203.0.113.0/24,198.51.100.0/24"
    Write-Info "Leave empty to skip IP whitelist"
    $WAFAllowedIPs = Get-UserInput -Prompt "WAF allowed IPs" -DefaultValue "" -Required $false
    
    # Certificate ARN (optional)
    Write-Info "Enter ACM certificate ARN (leave empty to auto-create)"
    $CertificateArn = Get-UserInput -Prompt "Certificate ARN" -DefaultValue "" -Required $false
    
    # Build parameters JSON
    $parameters = @(
        @{ ParameterKey = "DomainName"; ParameterValue = $DomainName },
        @{ ParameterKey = "PrimaryRegion"; ParameterValue = $script:Region },
        @{ ParameterKey = "SecondaryRegions"; ParameterValue = $SecondaryRegions },
        @{ ParameterKey = "Environment"; ParameterValue = $Environment },
        @{ ParameterKey = "Applications"; ParameterValue = $Applications },
        @{ ParameterKey = "BedrockAgents"; ParameterValue = $BedrockAgents },
        @{ ParameterKey = "KnowledgeBases"; ParameterValue = $KnowledgeBases },
        @{ ParameterKey = "CacheTTL"; ParameterValue = $CacheTTL },
        @{ ParameterKey = "EnableDAX"; ParameterValue = $EnableDAX },
        @{ ParameterKey = "EnableCloudFront"; ParameterValue = $EnableCloudFront },
        @{ ParameterKey = "DAXNodeType"; ParameterValue = $DAXNodeType },
        @{ ParameterKey = "DAXClusterSize"; ParameterValue = $DAXClusterSize },
        @{ ParameterKey = "WAFAllowedIPs"; ParameterValue = $WAFAllowedIPs },
        @{ ParameterKey = "CertificateArn"; ParameterValue = $CertificateArn }
    )
    
    # Convert to JSON
    $parametersJson = $parameters | ConvertTo-Json -Depth 10
    
    # Save parameters to file
    $parametersFile = "parameters-$($script:StackName).json"
    $parametersJson | Out-File -FilePath $parametersFile -Encoding UTF8
    Write-Info "`nParameters saved to: $parametersFile"
    
    # Show summary
    Write-Info "`n=== Deployment Summary ==="
    Write-Output "Stack Name: $($script:StackName)"
    Write-Output "Region: $($script:Region)"
    Write-Output "Domain: $DomainName"
    Write-Output "Environment: $Environment"
    Write-Output "Applications: $Applications"
    Write-Output "Enable DAX: $EnableDAX"
    Write-Output "Enable CloudFront: $EnableCloudFront"
    Write-Output ""
    
    $confirm = Read-Host "Proceed with deployment? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Warning "Deployment cancelled."
        exit 0
    }
    
    # Deploy CloudFormation stack
    Write-Info "`n=== Deploying CloudFormation Stack ==="
    
    $templateFile = "bedrock-global-api.yaml"
    if (-not (Test-Path $templateFile)) {
        Write-Error "Template file not found: $templateFile"
        exit 1
    }
    
    try {
        if ($Action -eq "create" -or $Action -eq "update") {
            # Check if stack exists
            $stackExists = $false
            try {
                $null = aws cloudformation describe-stacks --stack-name $script:StackName --region $script:Region 2>$null
                $stackExists = $true
            } catch {
                $stackExists = $false
            }
            
            if ($stackExists -and $Action -eq "create") {
                Write-Warning "Stack already exists. Use 'update' action or delete the stack first."
                exit 1
            }
            
            if ($stackExists) {
                Write-Info "Updating existing stack..."
                aws cloudformation update-stack `
                    --stack-name $script:StackName `
                    --template-body file://$templateFile `
                    --parameters file://$parametersFile `
                    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND `
                    --region $script:Region
            } else {
                Write-Info "Creating new stack..."
                aws cloudformation create-stack `
                    --stack-name $script:StackName `
                    --template-body file://$templateFile `
                    --parameters file://$parametersFile `
                    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND `
                    --region $script:Region
            }
            
            Write-Success "`nStack deployment initiated!"
            Write-Info "Monitoring stack creation/update..."
            
            # Wait for stack operation to complete
            aws cloudformation wait stack-$($Action)-complete `
                --stack-name $script:StackName `
                --region $script:Region
            
            Write-Success "`nStack deployment completed successfully!"
            
            # Get outputs
            Write-Info "`n=== Stack Outputs ==="
            aws cloudformation describe-stacks `
                --stack-name $script:StackName `
                --region $script:Region `
                --query 'Stacks[0].Outputs' `
                --output table
            
        } elseif ($Action -eq "delete") {
            Write-Warning "This will delete the entire stack. Are you sure?"
            $confirmDelete = Read-Host "Type 'yes' to confirm deletion"
            if ($confirmDelete -eq "yes") {
                aws cloudformation delete-stack `
                    --stack-name $script:StackName `
                    --region $script:Region
                Write-Info "Stack deletion initiated..."
            } else {
                Write-Info "Deletion cancelled."
            }
        }
        
    } catch {
        Write-Error "Deployment failed: $_"
        exit 1
    }
}

# Run deployment
Start-Deployment

