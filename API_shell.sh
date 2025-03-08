#!/bin/bash
# Script configuration
MAX_RETRIES=3
RETRY_DELAY=5
CURL_TIMEOUT=60
CONNECT_TIMEOUT=30
JQ_MAX_DEPTH=100

# Maximum depth for JSON processing to prevent excessive recursion
# Limits JSON nesting to 100 levels to avoid memory/CPU issues from malformed responses

# Log file configuration
LOG_FILE="/path/to/logs/api_script_$(date +%Y%m%d_%H%M%S).log"
LOG_DIR=$(dirname "$LOG_FILE")

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to write logs with log levels
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] - $message" >> "$LOG_FILE"
    # Also print to console if needed
    echo "$timestamp [$level] - $message"
}

# Function to display script usage
show_usage() {
    echo "Usage: $0 <api_id> <start_date> <end_date> [options]"
    echo ""
    echo "Required arguments:"
    echo "  api_id       - API identifier in the configuration database"
    echo "  start_date   - Start date in YYYY-MM-DD format"
    echo "  end_date     - End date in YYYY-MM-DD format"
    echo ""
    echo "Options:"
    echo "  -h, --help   - Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 api123 2023-01-01 2023-01-31"
    exit 1
}

# Parse command line options
while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -h|--help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
    shift
done

# Initialize logging
log "INFO" "Script started"
log "INFO" "Initializing variables and configurations"

# Function to handle errors with logging
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Function to handle warnings
warn() {
    log "WARN" "$1"
}

# Function to cleanup temporary files
cleanup() {
    log "INFO" "Performing cleanup..."
    rm -f "${HEADER_FILE}" 2>/dev/null
    rm -f "${TMP_RESPONSE_FILE}" 2>/dev/null
    rm -f "${FLAT_JSON_FILE}" 2>/dev/null
}

# Set trap for cleanup on script exit
trap cleanup EXIT INT TERM

# Function to check required commands
check_requirements() {
    local missing_commands=()
    
    for cmd in curl jq date cut grep snowsql md5sum; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        error_exit "Missing required commands: ${missing_commands[*]}"
    fi
}

# Check for required commands
check_requirements

# Function to make API request with retries
make_api_request() {
    local retry_count=0
    local success=false
    local tmp_response=""
    
    while [ $retry_count -lt $MAX_RETRIES ] && [ "$success" = false ]; do
        if [ $retry_count -gt 0 ]; then
            log "WARN" "Retrying API request (Attempt $((retry_count + 1)) of $MAX_RETRIES)"
            sleep $RETRY_DELAY
        fi
        
        # Make the API request
        tmp_response=$(curl -s -w "%{http_code}" -x "${PROXY_HOST}:${PROXY_PORT}" \
            -X GET "${API_BASE_URL}/data/${API_ID}" \
            -H "$AUTH_HEADER" \
            -H "Content-Type: application/json" \
            -H "Proxy-Connection: keep-alive" \
            --connect-timeout $CONNECT_TIMEOUT \
            --max-time $CURL_TIMEOUT \
            -D "${HEADER_FILE}" \
            -d "{
                \"start_date\": \"${START_DATE}\",
                \"end_date\": \"${END_DATE}\"
            }")
        
        local status="${tmp_response:(-3)}"
        
        # Check if retry is needed
        case $status in
            429|500|502|503|504)
                retry_count=$((retry_count + 1))
                log "WARN" "Received status $status, attempt $retry_count of $MAX_RETRIES"
                ;;
            *)
                success=true
                break
                ;;
        esac
    done
    
    echo "$tmp_response"
}

# Function to validate configuration
validate_config() {
    local missing_configs=()
    
    [ -z "$API_BASE_URL" ] && missing_configs+=("API_BASE_URL")
    [ -z "$OUTPUT_DIR" ] && missing_configs+=("OUTPUT_DIR")
    [ -z "$AUTH_TYPE" ] && missing_configs+=("AUTH_TYPE")
    
    if [ ${#missing_configs[@]} -ne 0 ]; then
        error_exit "Missing required configurations: ${missing_configs[*]}"
    fi
}

# Function to handle API errors
handle_api_error() {
    local http_code=$1
    local response=$2
    
    # Check for specific HTTP status codes
    case $http_code in
        400)
            error_exit "Bad Request - The API request was malformed. Response: $response"
            ;;
        401)
            error_exit "Unauthorized - Authentication failed. Please check your credentials. Response: $response"
            ;;
        403)
            error_exit "Forbidden - You don't have permission to access this resource. Response: $response"
            ;;
        404)
            error_exit "Not Found - The requested resource was not found. Response: $response"
            ;;
        429)
            error_exit "Too Many Requests - API rate limit exceeded. Please try again later. Response: $response"
            ;;
        500)
            error_exit "Internal Server Error - The API server encountered an error. Response: $response"
            ;;
        502)
            error_exit "Bad Gateway - The API server received an invalid response. Response: $response"
            ;;
        503)
            error_exit "Service Unavailable - The API server is temporarily unavailable. Response: $response"
            ;;
        504)
            error_exit "Gateway Timeout - The API server timed out. Response: $response"
            ;;
        *)
            error_exit "API Error (HTTP $http_code) - Unexpected error occurred. Response: $response"
            ;;
    esac
}

# Log script parameters
log "INFO" "Script parameters:"
log "INFO" "API ID: $1"
log "INFO" "Start Date: $2" 
log "INFO" "End Date: $3"

# API Authentication
API_USER="your_api_username"
API_SECRET="your_api_secret"

# Check if required parameters are provided
if [ $# -lt 3 ]; then
    log "ERROR" "Missing required parameters"
    show_usage
fi

# Get parameters from command line arguments
API_ID=$1
START_DATE=$2
END_DATE=$3

# Validate date format
validate_date() {
    if ! date -d "$1" >/dev/null 2>&1; then
        error_exit "Invalid date format for $1. Please use YYYY-MM-DD format."
    fi
}

# Validate dates
validate_date "$START_DATE"
validate_date "$END_DATE"

# Validate date range
if [[ $(date -d "$END_DATE" +%s) -lt $(date -d "$START_DATE" +%s) ]]; then
    error_exit "End date must be after start date"
fi

# Set default dates if null
if [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
    CURRENT_DATE=$(date +%Y-%m-%d)
    START_DATE=$CURRENT_DATE
    END_DATE=$CURRENT_DATE
    log "INFO" "No dates provided, using current date: $CURRENT_DATE"
fi

# Query Snowflake for configuration details
log "INFO" "Retrieving configuration from database for API ID: $API_ID"
CONFIG_QUERY="SELECT API_BASE_URL, OUTPUT_DIR, PROXY_HOST, PROXY_PORT, AUTH_TYPE, AUTH_FILE_PATH, JSON_TO_CSV FROM API_CONFIG_TABLE WHERE API_ID='$API_ID'"
CONFIG_RESULT=$(snowsql -q "$CONFIG_QUERY")

# Check if configuration was found
if [ -z "$CONFIG_RESULT" ]; then
    error_exit "No configuration found for API ID: $API_ID"
fi

# Parse configuration values from Snowflake query result
API_BASE_URL=$(echo "$CONFIG_RESULT" | grep "API_BASE_URL" | cut -d'|' -f2)
OUTPUT_DIR=$(echo "$CONFIG_RESULT" | grep "OUTPUT_DIR" | cut -d'|' -f2)
PROXY_HOST=$(echo "$CONFIG_RESULT" | grep "PROXY_HOST" | cut -d'|' -f2)
PROXY_PORT=$(echo "$CONFIG_RESULT" | grep "PROXY_PORT" | cut -d'|' -f2)
AUTH_TYPE=$(echo "$CONFIG_RESULT" | grep "AUTH_TYPE" | cut -d'|' -f2)
AUTH_FILE_PATH=$(echo "$CONFIG_RESULT" | grep "AUTH_FILE_PATH" | cut -d'|' -f2)
JSON_TO_CSV=$(echo "$CONFIG_RESULT" | grep "JSON_TO_CSV" | cut -d'|' -f2)

log "INFO" "Configuration loaded successfully"
log "INFO" "API Base URL: $API_BASE_URL"
log "INFO" "Output Directory: $OUTPUT_DIR"
log "INFO" "Authentication Type: $AUTH_TYPE"
log "INFO" "JSON to CSV Conversion: ${JSON_TO_CSV:-Disabled}"

# Set up authentication based on type
if [ "$AUTH_TYPE" = "BASIC" ]; then
    log "INFO" "Using Basic authentication for API request"
    AUTH_TOKEN=$(echo -n "${API_USER}:${API_SECRET}" | base64)
    AUTH_HEADER="Authorization: Basic ${AUTH_TOKEN}"
elif [ "$AUTH_TYPE" = "JSON" ]; then
    if [ -f "$AUTH_FILE_PATH" ]; then
        log "INFO" "Using JSON authentication file from: $AUTH_FILE_PATH"
        # Read JSON file content for later use in API calls
        AUTH_JSON=$(cat "$AUTH_FILE_PATH")
        # Extract necessary fields from AUTH_JSON for authentication
        AUTH_KEY=$(echo "$AUTH_JSON" | jq -r '.auth_key')
        AUTH_SECRET=$(echo "$AUTH_JSON" | jq -r '.auth_secret')
        AUTH_HEADER="X-Auth-Key: ${AUTH_KEY}\nX-Auth-Secret: ${AUTH_SECRET}"
    else
        error_exit "Authentication JSON file not found at: $AUTH_FILE_PATH"
    fi
else
    error_exit "Invalid authentication type: $AUTH_TYPE"
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
log "INFO" "Created output directory: $OUTPUT_DIR"

# Define output file
OUTPUT_FILE="${OUTPUT_DIR}/api_data_${API_ID}_${START_DATE}_${END_DATE}.json"

# Create temporary files
HEADER_FILE=$(mktemp)
TMP_RESPONSE_FILE=$(mktemp)
FLAT_JSON_FILE=$(mktemp)

# Validate configuration before proceeding
validate_config

# Make API request with retry logic
log "INFO" "Making API request..."
response=$(make_api_request)

# Extract HTTP status code and response body
HTTP_STATUS="${response:(-3)}"
RESPONSE_BODY="${response:0:-3}"

# Log response headers for debugging
log "DEBUG" "API Response Headers:"
cat "${HEADER_FILE}"

# Function to convert JSON to CSV with nested support
json_to_csv() {
    local json_file=$1
    local csv_file=$2
    
    log "INFO" "Starting JSON to CSV conversion..."
    
    # Function to flatten nested JSON
    # This will convert nested structures like {a: {b: 1}} to {"a.b": 1}
    if jq -e '. | select(type == "array" and (.[0] | type == "object"))' "$json_file" > /dev/null; then
        log "INFO" "Detected JSON array of objects"
        # Flatten array of objects
        jq -r '[.[] | reduce (to_entries[]) as {$key, $value} ({};
            if ($value | type) == "object" then
                reduce ($value | to_entries[]) as {$k, $v} (.;
                    .[$key + "." + $k] = $v)
            else
                .[$key] = $value
            end
        )]' "$json_file" > "$FLAT_JSON_FILE"
        
        # Get all unique keys from all objects (in case objects have different structures)
        local headers=$(jq -r '[ .[] | keys[] ] | unique | join(",")' "$FLAT_JSON_FILE")
        
        # Create CSV with headers
        echo "$headers" > "$csv_file"
        
        # Convert each flattened object to CSV row, maintaining header order
        jq -r --arg headers "$headers" '
            def get_values($keys):
              reduce ($keys | split(","))[]) as $k (.;
                if .[$k] then .[$k] else null end
              );
            .[] | [get_values($headers)] | @csv
        ' "$FLAT_JSON_FILE" >> "$csv_file"
        
        local row_count=$(wc -l < "$csv_file")
        row_count=$((row_count - 1))  # Subtract header row
        log "INFO" "Successfully converted JSON array to CSV with $row_count data rows"
        return 0
        
    elif jq -e '. | select(type == "object")' "$json_file" > /dev/null; then
        log "INFO" "Detected single JSON object"
        # Flatten single object
        jq -r 'reduce (to_entries[]) as {$key, $value} ({};
            if ($value | type) == "object" then
                reduce ($value | to_entries[]) as {$k, $v} (.;
                    .[$key + "." + $k] = $v)
            else
                .[$key] = $value
            end
        )' "$json_file" > "$FLAT_JSON_FILE"
        
        # Get headers from flattened object
        local headers=$(jq -r 'keys | join(",")' "$FLAT_JSON_FILE")
        
        # Create CSV with headers
        echo "$headers" > "$csv_file"
        
        # Convert flattened object to CSV row
        jq -r '[.[] | tostring] | @csv' "$FLAT_JSON_FILE" >> "$csv_file"
        
        log "INFO" "Successfully converted JSON object to CSV (1 data row)"
        return 0
    else
        log "ERROR" "JSON structure not suitable for CSV conversion"
        return 1
    fi
}

# Process response
if [ $? -eq 0 ]; then
    if [[ $HTTP_STATUS =~ ^2[0-9][0-9]$ ]]; then
        if [ -z "$RESPONSE_BODY" ]; then
            error_exit "Empty response received from API"
        fi

        # Save raw response for debugging
        echo "$RESPONSE_BODY" > "${TMP_RESPONSE_FILE}"
        log "DEBUG" "Raw response saved to temporary file"
        
        # Process JSON response
        if echo "$RESPONSE_BODY" | jq empty > /dev/null 2>&1; then
            # Check for API-specific errors
            ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.error // empty')
            ERROR_CODE=$(echo "$RESPONSE_BODY" | jq -r '.error_code // empty')
            
            if [ ! -z "$ERROR_MSG" ] || [ ! -z "$ERROR_CODE" ]; then
                error_exit "API Error - Code: $ERROR_CODE, Message: $ERROR_MSG"
            fi

            log "INFO" "Detected JSON response format"
            JSON_FILE="${OUTPUT_DIR}/api_data_${API_ID}_${START_DATE}_${END_DATE}.json"
            
            # Validate JSON structure before saving
            if ! echo "$RESPONSE_BODY" | jq -e 'type == "object" or type == "array"' > /dev/null; then
                error_exit "Invalid JSON structure in response"
            fi
            
            # Get JSON structure info for logging
            JSON_TYPE=$(echo "$RESPONSE_BODY" | jq -r 'type')
            if [ "$JSON_TYPE" = "array" ]; then
                ARRAY_SIZE=$(echo "$RESPONSE_BODY" | jq -r 'length')
                log "INFO" "JSON structure: Array with $ARRAY_SIZE elements"
            else
                OBJECT_KEYS=$(echo "$RESPONSE_BODY" | jq -r 'keys | length')
                log "INFO" "JSON structure: Object with $OBJECT_KEYS keys"
            fi
            
            # Pretty print JSON to file with max depth protection
            echo "$RESPONSE_BODY" | jq --max-depth $JQ_MAX_DEPTH '.' > "$JSON_FILE"
            log "INFO" "Data successfully saved as formatted JSON to $JSON_FILE"
            
            # Convert to CSV only if JSON_TO_CSV flag is 'Y'
            if [ "${JSON_TO_CSV^^}" = "Y" ]; then
                log "INFO" "JSON to CSV conversion is enabled"
                CSV_FILE="${OUTPUT_DIR}/api_data_${API_ID}_${START_DATE}_${END_DATE}.csv"
                if json_to_csv "$JSON_FILE" "$CSV_FILE"; then
                    log "INFO" "Additionally created CSV version at $CSV_FILE"
                    
                    # Log CSV file size
                    CSV_SIZE=$(stat -f%z "$CSV_FILE" 2>/dev/null || stat -c%s "$CSV_FILE")
                    log "INFO" "CSV file size: $CSV_SIZE bytes"
                    
                    # Calculate and log checksum for both files
                    JSON_CHECKSUM=$(md5sum "$JSON_FILE" | cut -d' ' -f1)
                    CSV_CHECKSUM=$(md5sum "$CSV_FILE" | cut -d' ' -f1)
                    log "INFO" "JSON file checksum (MD5): $JSON_CHECKSUM"
                    log "INFO" "CSV file checksum (MD5): $CSV_CHECKSUM"
                else
                    log "WARN" "Could not create CSV version - JSON structure not suitable for conversion"
                fi
            else
                log "INFO" "JSON to CSV conversion is disabled"
                # Calculate and log checksum for JSON file only
                JSON_CHECKSUM=$(md5sum "$JSON_FILE" | cut -d' ' -f1)
                log "INFO" "JSON file checksum (MD5): $JSON_CHECKSUM"
            fi
            
            # Log response size
            FILE_SIZE=$(stat -f%z "$JSON_FILE" 2>/dev/null || stat -c%s "$JSON_FILE")
            log "INFO" "JSON file size: $FILE_SIZE bytes"
        else
            # Handle CSV response
            if echo "$RESPONSE_BODY" | grep -q '^[^,]*,[^,]*' && echo "$RESPONSE_BODY" | grep -q $'\n'; then
                log "INFO" "Detected CSV response format"
                OUTPUT_FILE="${OUTPUT_DIR}/api_data_${API_ID}_${START_DATE}_${END_DATE}.csv"
                echo "$RESPONSE_BODY" > "$OUTPUT_FILE"
                
                # Validate CSV structure
                CSV_LINES=$(wc -l < "$OUTPUT_FILE")
                CSV_COLUMNS=$(head -n1 "$OUTPUT_FILE" | tr ',' '\n' | wc -l)
                log "INFO" "CSV structure: $CSV_LINES rows, $CSV_COLUMNS columns"
                
                if [ "$CSV_LINES" -lt 2 ]; then
                    warn "CSV file contains less than 2 lines, might be incomplete"
                fi
                
                # Calculate and log checksum
                CSV_CHECKSUM=$(md5sum "$OUTPUT_FILE" | cut -d' ' -f1)
                log "INFO" "CSV file checksum (MD5): $CSV_CHECKSUM"
                
                # Log file size
                CSV_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE")
                log "INFO" "CSV file size: $CSV_SIZE bytes"
                
                log "INFO" "Data successfully saved as CSV to $OUTPUT_FILE"
            else
                error_exit "Invalid or unsupported response format. See ${TMP_RESPONSE_FILE} for raw response"
            fi
        fi
        
        log "INFO" "API data download completed successfully"
    else
        handle_api_error "$HTTP_STATUS" "$RESPONSE_BODY"
    fi
else
    error_exit "Failed to fetch data for API ID: $API_ID. Please check proxy settings and API endpoint"
fi

exit 0
