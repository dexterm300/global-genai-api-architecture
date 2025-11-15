"""
AWS Lambda function for routing Bedrock API requests.
Handles request routing, caching, and Bedrock agent/knowledge base invocation.

NOTE: This is the improved version with input validation, error handling,
and performance optimizations. The CloudFormation template contains
outdated inline code that should be replaced with this version.
See CODE_QUALITY_REVIEW.md for migration instructions.
"""

import json
import boto3
import os
import hashlib
import time
import yaml
from typing import Dict, Any, Optional, Tuple

# Initialize clients outside handler for performance
bedrock_runtime = None
dynamodb = None
dax_client = None
cache_table = None

def initialize_clients():
    """Initialize AWS clients (called once per container)"""
    global bedrock_runtime, dynamodb, dax_client, cache_table
    
    if bedrock_runtime is None:
        region = os.environ.get('AWS_REGION', 'us-east-1')
        bedrock_runtime = boto3.client('bedrock-runtime', region_name=region)
        dynamodb = boto3.resource('dynamodb', region_name=region)
        
        # Initialize DAX if endpoint is provided
        dax_endpoint = os.environ.get('DAX_ENDPOINT')
        if dax_endpoint:
            try:
                from amazondax import AmazonDaxClient
                dax_client = AmazonDaxClient(endpoints=[dax_endpoint], region_name=region)
            except ImportError:
                print("DAX client not available, using DynamoDB directly")
        
        # Get cache table
        table_name = os.environ.get('CACHE_TABLE_NAME')
        if table_name:
            cache_table = dynamodb.Table(table_name)

def load_routing_config() -> Dict[str, Any]:
    """Load routing configuration from environment or default"""
    config_str = os.environ.get('ROUTING_CONFIG', '{}')
    
    try:
        # Try to parse as YAML first
        if config_str.strip().startswith('{'):
            return json.loads(config_str)
        else:
            return yaml.safe_load(config_str)
    except Exception as e:
        print(f"Error parsing routing config: {e}, using defaults")
        return get_default_routing_config()

def get_default_routing_config() -> Dict[str, Any]:
    """Get default routing configuration"""
    agents = os.environ.get('BEDROCK_AGENTS', '').split(',')
    knowledge_bases = os.environ.get('KNOWLEDGE_BASES', '').split(',')
    default_agent = os.environ.get('DEFAULT_AGENT', agents[0] if agents else '')
    
    # Build routing rules from environment
    routing_rules = {}
    apps = os.environ.get('APPLICATIONS', '').split(',')
    
    for i, app in enumerate(apps):
        if app.strip():
            routing_rules[app.strip()] = {
                'agent': agents[i] if i < len(agents) and agents[i] else default_agent,
                'knowledge_base': knowledge_bases[i] if i < len(knowledge_bases) and knowledge_bases[i] else ''
            }
    
    return {
        'agents': [a for a in agents if a],
        'knowledge_bases': [kb for kb in knowledge_bases if kb],
        'default_agent': default_agent,
        'routing_rules': routing_rules
    }

def get_cache_key(request_body: Dict[str, Any], app_name: str) -> str:
    """Generate cache key from request"""
    key_string = f"{app_name}:{json.dumps(request_body, sort_keys=True)}"
    return hashlib.sha256(key_string.encode()).hexdigest()

def get_from_cache(cache_key: str) -> Optional[Dict[str, Any]]:
    """Retrieve from cache (DAX or DynamoDB)"""
    if not cache_table:
        return None
    
    try:
        if dax_client:
            response = dax_client.get_item(
                TableName=os.environ.get('CACHE_TABLE_NAME'),
                Key={'RequestHash': {'S': cache_key}}
            )
            if 'Item' in response:
                return json.loads(response['Item']['Response']['S'])
        else:
            response = cache_table.get_item(Key={'RequestHash': cache_key})
            if 'Item' in response:
                return json.loads(response['Item']['Response'])
    except Exception as e:
        print(f"Cache read error: {str(e)}")
    return None

def put_to_cache(cache_key: str, response_data: Dict[str, Any], ttl_seconds: int = 3600):
    """Store response in cache"""
    if not cache_table:
        return
    
    try:
        ttl = int(time.time()) + ttl_seconds
        item = {
            'RequestHash': cache_key,
            'Response': json.dumps(response_data),
            'TTL': ttl
        }
        
        if dax_client:
            dax_client.put_item(
                TableName=os.environ.get('CACHE_TABLE_NAME'),
                Item={
                    'RequestHash': {'S': cache_key},
                    'Response': {'S': json.dumps(response_data)},
                    'TTL': {'N': str(ttl)}
                }
            )
        else:
            cache_table.put_item(Item=item)
    except Exception as e:
        print(f"Cache write error: {str(e)}")

def route_request(app_name: str, request_body: Dict[str, Any], routing_config: Dict[str, Any]) -> Dict[str, str]:
    """Determine routing based on app and request"""
    rules = routing_config.get('routing_rules', {})
    app_config = rules.get(app_name, {})
    
    agent_id = app_config.get('agent') or routing_config.get('default_agent')
    kb_id = app_config.get('knowledge_base')
    
    return {
        'agent_id': agent_id,
        'knowledge_base_id': kb_id
    }

def invoke_bedrock_agent(agent_id: str, session_id: str, input_text: str) -> Dict[str, Any]:
    """Invoke Bedrock agent with input validation"""
    # Validate agent_id
    if not agent_id or not isinstance(agent_id, str) or len(agent_id) > 128:
        return {'statusCode': 400, 'body': json.dumps({'error': 'Invalid agent_id'}), 'cached': False}
    
    # Check if bedrock_runtime is initialized
    if bedrock_runtime is None:
        initialize_clients()
        if bedrock_runtime is None:
            return {'statusCode': 500, 'body': json.dumps({'error': 'Bedrock client not initialized'}), 'cached': False}
    
    try:
        response = bedrock_runtime.invoke_agent(
            agentId=agent_id,
            sessionId=session_id,
            inputText=input_text
        )
        
        result = ''
        for event in response.get('completion', []):
            if 'chunk' in event:
                chunk_bytes = event['chunk'].get('bytes', b'')
                if chunk_bytes:
                    try:
                        result += chunk_bytes.decode('utf-8')
                    except UnicodeDecodeError:
                        # Skip invalid UTF-8 sequences
                        continue
        
        return {'statusCode': 200, 'body': result, 'cached': False}
    except Exception as e:
        error_id = f"err-{int(time.time())}"
        print(f"Bedrock invocation error [{error_id}]: {type(e).__name__}: {str(e)}")
        # Don't expose internal error details
        return {'statusCode': 500, 'body': json.dumps({'error': 'Bedrock service error', 'error_id': error_id}), 'cached': False}

def invoke_bedrock_model(model_id: str, prompt: str) -> Dict[str, Any]:
    """Invoke Bedrock model directly with input validation"""
    # Validate model_id
    if not model_id or not isinstance(model_id, str) or len(model_id) > 128:
        return {'statusCode': 400, 'body': json.dumps({'error': 'Invalid model_id'}), 'cached': False}
    
    # Check if bedrock_runtime is initialized
    if bedrock_runtime is None:
        initialize_clients()
        if bedrock_runtime is None:
            return {'statusCode': 500, 'body': json.dumps({'error': 'Bedrock client not initialized'}), 'cached': False}
    
    try:
        body = json.dumps({
            "inputText": prompt,
            "textGenerationConfig": {
                "maxTokenCount": 4096,
                "temperature": 0.7,
                "topP": 0.9
            }
        })
        
        response = bedrock_runtime.invoke_model(
            modelId=model_id,
            contentType="application/json",
            accept="application/json",
            body=body
        )
        
        response_body = json.loads(response['body'].read())
        result = response_body.get('results', [{}])[0].get('outputText', '')
        
        return {'statusCode': 200, 'body': result, 'cached': False}
    except Exception as e:
        error_id = f"err-{int(time.time())}"
        print(f"Bedrock model invocation error [{error_id}]: {type(e).__name__}: {str(e)}")
        # Don't expose internal error details
        return {'statusCode': 500, 'body': json.dumps({'error': 'Bedrock service error', 'error_id': error_id}), 'cached': False}

def validate_input(app_name: str, input_text: str, session_id: str) -> Tuple[bool, Optional[str]]:
    """Validate and sanitize input parameters"""
    # Validate app_name: alphanumeric, hyphens, underscores only, max 64 chars
    if not app_name or not isinstance(app_name, str):
        return False, "Invalid app_name: must be a non-empty string"
    if len(app_name) > 64:
        return False, "Invalid app_name: exceeds maximum length of 64 characters"
    if not all(c.isalnum() or c in ('-', '_') for c in app_name):
        return False, "Invalid app_name: contains invalid characters"
    
    # Validate input_text: max 100KB
    if not input_text or not isinstance(input_text, str):
        return False, "Invalid input: must be a non-empty string"
    if len(input_text.encode('utf-8')) > 100 * 1024:  # 100KB limit
        return False, "Invalid input: exceeds maximum size of 100KB"
    
    # Validate session_id: alphanumeric, hyphens, underscores only, max 128 chars
    if not session_id or not isinstance(session_id, str):
        return False, "Invalid session_id: must be a non-empty string"
    if len(session_id) > 128:
        return False, "Invalid session_id: exceeds maximum length of 128 characters"
    if not all(c.isalnum() or c in ('-', '_') for c in session_id):
        return False, "Invalid session_id: contains invalid characters"
    
    return True, None

def handler(event, context):
    """Main Lambda handler"""
    # Initialize clients
    initialize_clients()
    
    # Load routing configuration
    routing_config = load_routing_config()
    
    try:
        # Parse SQS event
        records = event.get('Records', [])
        if not records:
            return {'statusCode': 400, 'body': json.dumps({'error': 'No records found'})}
        
        # Limit batch size to prevent resource exhaustion
        if len(records) > 10:
            records = records[:10]
        
        results = []
        for record in records:
            try:
                # Validate and parse JSON with size limit
                try:
                    body_str = record.get('body', '{}')
                    if len(body_str.encode('utf-8')) > 256 * 1024:  # 256KB limit per message
                        results.append({
                            'statusCode': 400,
                            'body': json.dumps({'error': 'Request body too large'}),
                            'cached': False
                        })
                        continue
                    body = json.loads(body_str)
                except json.JSONDecodeError as e:
                    results.append({
                        'statusCode': 400,
                        'body': json.dumps({'error': 'Invalid JSON format'}),
                        'cached': False
                    })
                    continue
                
                app_name = body.get('app_name', 'default')
                request_data = body.get('request', {})
                if not isinstance(request_data, dict):
                    request_data = {}
                session_id = body.get('session_id', f"session-{int(time.time())}")
                
                # Get input text first for validation
                input_text = request_data.get('input') or request_data.get('query') or request_data.get('prompt', '')
                
                # Validate inputs BEFORE cache check (to avoid caching invalid requests)
                is_valid, error_msg = validate_input(app_name, input_text, session_id)
                if not is_valid:
                    results.append({
                        'statusCode': 400,
                        'body': json.dumps({'error': error_msg}),
                        'cached': False,
                        'app_name': app_name
                    })
                    continue
                
                if not input_text:
                    results.append({
                        'statusCode': 400,
                        'body': json.dumps({'error': 'No input text provided'}),
                        'cached': False,
                        'app_name': app_name
                    })
                    continue
                
                # Check cache (only after validation passes)
                cache_key = get_cache_key(request_data, app_name)
                cached_response = get_from_cache(cache_key)
                
                if cached_response:
                    results.append({
                        'statusCode': 200,
                        'body': cached_response,
                        'cached': True,
                        'app_name': app_name
                    })
                    continue
                
                # Route request
                routing = route_request(app_name, request_data, routing_config)
                agent_id = routing.get('agent_id')
                
                if not agent_id:
                    results.append({
                        'statusCode': 400,
                        'body': json.dumps({'error': f'No agent configured for app: {app_name}'}),
                        'cached': False,
                        'app_name': app_name
                    })
                    continue
                
                # Invoke Bedrock
                response = invoke_bedrock_agent(agent_id, session_id, input_text)
                response['app_name'] = app_name
                
                # Cache successful responses
                if response['statusCode'] == 200:
                    cache_ttl = int(os.environ.get('CACHE_TTL', 3600))
                    put_to_cache(cache_key, response['body'], ttl_seconds=cache_ttl)
                
                results.append(response)
                
            except Exception as e:
                # Log full error for debugging but don't expose to client
                error_id = f"err-{int(time.time())}"
                print(f"Error processing record [{error_id}]: {type(e).__name__}: {str(e)}")
                results.append({
                    'statusCode': 500,
                    'body': json.dumps({'error': 'Internal server error', 'error_id': error_id}),
                    'cached': False
                })
        
        return {
            'statusCode': 200,
            'results': results,
            'processed_count': len(results)
        }
        
    except Exception as e:
        # Log full error for debugging but don't expose to client
        error_id = f"err-{int(time.time())}"
        print(f"Handler error [{error_id}]: {type(e).__name__}: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error', 'error_id': error_id})
        }

