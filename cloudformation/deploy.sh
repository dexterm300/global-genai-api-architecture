#!/bin/bash

# Bash Deployment Script for Bedrock Global API
# This script provides an interactive deployment experience with prompts for all required parameters

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Functions for colored output
print_success() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }
print_info() { echo -e "${CYAN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }

# Check AWS CLI installation
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it from https://aws.amazon.com/cli/"
        exit 1
    fi
}

# Check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
}

# Validate domain name
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)*$ ]]; then
        return 0
    else
        echo "Invalid domain name format"
        return 1
    fi
}

# Validate region
validate_region() {
    local region=$1
    local valid_regions=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1")
    for valid_region in "${valid_regions[@]}"; do
        if [ "$region" == "$valid_region" ]; then
            return 0
        fi
    done
    echo "Invalid region. Must be one of: ${valid_regions[*]}"
    return 1
}

# Get user input with validation
get_user_input() {
    local prompt=$1
    local default=$2
    local required=${3:-true}
    local validator=$4
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " input
            if [ -z "$input" ]; then
                input=$default
            fi
        else
            read -p "$prompt: " input
        fi
        
        if [ -z "$input" ]; then
            if [ "$required" == "true" ]; then
                print_warning "This field is required. Please enter a value."
                continue
            else
                echo ""
                return
            fi
        fi
        
        if [ -n "$validator" ]; then
            if ! $validator "$input"; then
                continue
            fi
        fi
        
        echo "$input"
        return
    done
}

# Main deployment function
main() {
    print_info "=========================================="
    print_info "  Bedrock Global API Deployment Script"
    print_info "=========================================="
    echo ""
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    
    # Get parameters
    STACK_NAME=${1:-$(get_user_input "Enter CloudFormation stack name" "bedrock-global-api-prod")}
    REGION=${2:-$(get_user_input "Enter primary AWS region" "us-east-1" true validate_region)}
    
    print_info "\n=== Basic Configuration ==="
    
    DOMAIN_NAME=$(get_user_input "Enter custom domain name (e.g., api.example.com)" "" true validate_domain)
    ENVIRONMENT=$(get_user_input "Enter environment (dev/staging/prod)" "prod" true)
    
    while [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; do
        print_warning "Environment must be one of: dev, staging, prod"
        ENVIRONMENT=$(get_user_input "Enter environment (dev/staging/prod)" "prod" true)
    done
    
    print_info "\n=== Multi-Region Configuration ==="
    print_info "Enter secondary regions for multi-region failover (comma-separated)"
    print_info "Example: us-west-2,eu-west-1"
    SECONDARY_REGIONS=$(get_user_input "Secondary regions" "us-west-2,eu-west-1" false)
    
    print_info "\n=== Application Configuration ==="
    print_info "Enter application names (comma-separated)"
    print_info "Example: webapp1,webapp2,webapp3"
    APPLICATIONS=$(get_user_input "Application names" "webapp1,webapp2" true)
    
    print_info "\n=== Bedrock Configuration ==="
    print_info "Enter Bedrock agent IDs (comma-separated)"
    print_info "Example: agent-12345,agent-67890"
    BEDROCK_AGENTS=$(get_user_input "Bedrock agent IDs" "" false)
    
    print_info "Enter Bedrock knowledge base IDs (comma-separated)"
    print_info "Example: KB12345,KB67890"
    KNOWLEDGE_BASES=$(get_user_input "Knowledge base IDs" "" false)
    
    print_info "\n=== Performance & Caching Configuration ==="
    CACHE_TTL=$(get_user_input "Cache TTL in seconds" "3600" true)
    
    while ! [[ "$CACHE_TTL" =~ ^[0-9]+$ ]] || [ "$CACHE_TTL" -lt 60 ] || [ "$CACHE_TTL" -gt 86400 ]; do
        print_warning "Cache TTL must be between 60 and 86400 seconds"
        CACHE_TTL=$(get_user_input "Cache TTL in seconds" "3600" true)
    done
    
    ENABLE_DAX=$(get_user_input "Enable DynamoDB Accelerator (DAX)? (true/false)" "true" true)
    while [[ ! "$ENABLE_DAX" =~ ^(true|false)$ ]]; do
        print_warning "Must be 'true' or 'false'"
        ENABLE_DAX=$(get_user_input "Enable DAX? (true/false)" "true" true)
    done
    
    DAX_NODE_TYPE="dax.t3.small"
    DAX_CLUSTER_SIZE=1
    
    if [ "$ENABLE_DAX" == "true" ]; then
        print_info "DAX Node Type options: dax.t3.small, dax.t3.medium, dax.r4.large, dax.r4.xlarge, dax.r4.2xlarge"
        DAX_NODE_TYPE=$(get_user_input "DAX node type" "dax.t3.small" true)
        
        DAX_CLUSTER_SIZE=$(get_user_input "DAX cluster size (number of nodes)" "1" true)
        while ! [[ "$DAX_CLUSTER_SIZE" =~ ^[0-9]+$ ]] || [ "$DAX_CLUSTER_SIZE" -lt 1 ] || [ "$DAX_CLUSTER_SIZE" -gt 10 ]; do
            print_warning "Cluster size must be between 1 and 10"
            DAX_CLUSTER_SIZE=$(get_user_input "DAX cluster size" "1" true)
        done
    fi
    
    ENABLE_CLOUDFRONT=$(get_user_input "Enable CloudFront? (true/false)" "true" true)
    while [[ ! "$ENABLE_CLOUDFRONT" =~ ^(true|false)$ ]]; do
        print_warning "Must be 'true' or 'false'"
        ENABLE_CLOUDFRONT=$(get_user_input "Enable CloudFront? (true/false)" "true" true)
    done
    
    print_info "\n=== Security Configuration ==="
    print_info "Enter allowed IP addresses for WAF (comma-separated, CIDR format)"
    print_info "Example: 203.0.113.0/24,198.51.100.0/24"
    print_info "Leave empty to skip IP whitelist"
    WAF_ALLOWED_IPS=$(get_user_input "WAF allowed IPs" "" false)
    
    print_info "Enter ACM certificate ARN (leave empty to auto-create)"
    CERTIFICATE_ARN=$(get_user_input "Certificate ARN" "" false)
    
    # Create parameters file
    PARAMETERS_FILE="parameters-${STACK_NAME}.json"
    
    cat > "$PARAMETERS_FILE" <<EOF
[
  {
    "ParameterKey": "DomainName",
    "ParameterValue": "$DOMAIN_NAME"
  },
  {
    "ParameterKey": "PrimaryRegion",
    "ParameterValue": "$REGION"
  },
  {
    "ParameterKey": "SecondaryRegions",
    "ParameterValue": "$SECONDARY_REGIONS"
  },
  {
    "ParameterKey": "Environment",
    "ParameterValue": "$ENVIRONMENT"
  },
  {
    "ParameterKey": "Applications",
    "ParameterValue": "$APPLICATIONS"
  },
  {
    "ParameterKey": "BedrockAgents",
    "ParameterValue": "$BEDROCK_AGENTS"
  },
  {
    "ParameterKey": "KnowledgeBases",
    "ParameterValue": "$KNOWLEDGE_BASES"
  },
  {
    "ParameterKey": "CacheTTL",
    "ParameterValue": "$CACHE_TTL"
  },
  {
    "ParameterKey": "EnableDAX",
    "ParameterValue": "$ENABLE_DAX"
  },
  {
    "ParameterKey": "EnableCloudFront",
    "ParameterValue": "$ENABLE_CLOUDFRONT"
  },
  {
    "ParameterKey": "DAXNodeType",
    "ParameterValue": "$DAX_NODE_TYPE"
  },
  {
    "ParameterKey": "DAXClusterSize",
    "ParameterValue": "$DAX_CLUSTER_SIZE"
  },
  {
    "ParameterKey": "WAFAllowedIPs",
    "ParameterValue": "$WAF_ALLOWED_IPS"
  },
  {
    "ParameterKey": "CertificateArn",
    "ParameterValue": "$CERTIFICATE_ARN"
  }
]
EOF
    
    print_info "\nParameters saved to: $PARAMETERS_FILE"
    
    # Show summary
    print_info "\n=== Deployment Summary ==="
    echo "Stack Name: $STACK_NAME"
    echo "Region: $REGION"
    echo "Domain: $DOMAIN_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Applications: $APPLICATIONS"
    echo "Enable DAX: $ENABLE_DAX"
    echo "Enable CloudFront: $ENABLE_CLOUDFRONT"
    echo ""
    
    read -p "Proceed with deployment? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_warning "Deployment cancelled."
        exit 0
    fi
    
    # Deploy CloudFormation stack
    print_info "\n=== Deploying CloudFormation Stack ==="
    
    TEMPLATE_FILE="bedrock-global-api.yaml"
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
        print_info "Updating existing stack..."
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body file://"$TEMPLATE_FILE" \
            --parameters file://"$PARAMETERS_FILE" \
            --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --region "$REGION"
        
        print_success "\nStack update initiated!"
        print_info "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION"
    else
        print_info "Creating new stack..."
        aws cloudformation create-stack \
            --stack-name "$STACK_NAME" \
            --template-body file://"$TEMPLATE_FILE" \
            --parameters file://"$PARAMETERS_FILE" \
            --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --region "$REGION"
        
        print_success "\nStack creation initiated!"
        print_info "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION"
    fi
    
    print_success "\nStack deployment completed successfully!"
    
    # Get outputs
    print_info "\n=== Stack Outputs ==="
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output table
}

# Run main function
main "$@"

