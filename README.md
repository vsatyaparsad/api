# api

# API Data Download Script

A robust Bash script for downloading data from APIs with advanced error handling, retry logic, and JSON/CSV processing capabilities.

## Overview

This script automates the process of retrieving data from APIs and saving it in JSON or CSV format. It includes features like:

- Configurable retry logic for transient errors
- Comprehensive error handling and logging
- JSON to CSV conversion with nested JSON support
- Proxy support
- Multiple authentication methods
- Detailed logging and diagnostics

## Prerequisites

The script requires the following tools to be installed:

- `bash` (version 4.0 or higher recommended)
- `curl` (for API requests)
- `jq` (for JSON processing)
- `snowsql` (for Snowflake database access)
- `md5sum` (for file integrity verification)
- Standard Unix utilities: `date`, `cut`, `grep`

## Configuration

The script uses a Snowflake database table for configuration. The table should have the following columns:

| Column Name    | Description                                   |
|----------------|-----------------------------------------------|
| API_ID         | Unique identifier for the API                 |
| API_BASE_URL   | Base URL for the API                          |
| OUTPUT_DIR     | Directory to save output files                |
| PROXY_HOST     | Proxy server hostname (if needed)             |
| PROXY_PORT     | Proxy server port                             |
| AUTH_TYPE      | Authentication type (BASIC or JSON)           |
| AUTH_FILE_PATH | Path to authentication file (for JSON auth)   |
| JSON_TO_CSV    | Flag to enable JSON to CSV conversion (Y/N)   |

## Usage

```bash
./API_shell.sh <api_id> <start_date> <end_date> [options]
```

### Required Arguments

- `api_id`: API identifier in the configuration database
- `start_date`: Start date in YYYY-MM-DD format
- `end_date`: End date in YYYY-MM-DD format

### Options

- `-h, --help`: Show help message

### Example

```bash
./API_shell.sh api123 2023-01-01 2023-01-31
```

## Authentication Methods

The script supports two authentication methods:

### Basic Authentication

Uses username/password encoded in base64. Configure API_USER and API_SECRET in the script.

### JSON Authentication

Uses a JSON file containing authentication details. The file should include `auth_key` and `auth_secret` fields.

## JSON to CSV Conversion

When enabled (JSON_TO_CSV = 'Y'), the script will:

1. Download data in JSON format
2. Convert it to CSV format
3. Save both JSON and CSV versions

The conversion supports:
- Nested JSON structures (flattened with dot notation)
- Arrays of objects
- Single objects
- Mixed object structures in arrays

## Error Handling

The script handles various error scenarios:

- Network connectivity issues
- API authentication failures
- Invalid API responses
- Malformed JSON
- HTTP error codes (4xx, 5xx)
- Missing configuration
- Missing dependencies

All errors are logged with detailed information to assist with troubleshooting.

## Logging

The script creates detailed logs with timestamps and log levels:

- INFO: General information about script execution
- WARN: Warning messages that don't stop execution
- ERROR: Error messages that cause the script to exit
- DEBUG: Detailed information for troubleshooting

Logs are saved to: `/path/to/logs/api_script_YYYYMMDD_HHMMSS.log`

## Customization

You can customize the script by modifying these configuration variables:

```bash
# Script configuration
MAX_RETRIES=3           # Number of retry attempts for failed API calls
RETRY_DELAY=5           # Delay in seconds between retry attempts
CURL_TIMEOUT=60         # Maximum time in seconds for API requests
CONNECT_TIMEOUT=30      # Connection timeout in seconds
JQ_MAX_DEPTH=100        # Maximum depth for JSON processing
```

## Security Considerations

- API credentials should be stored securely
- Consider encrypting the authentication file
- Review proxy settings for security implications
- Ensure proper file permissions on the script and output directory

## Troubleshooting

If you encounter issues:

1. Check the log file for detailed error messages
2. Verify API credentials and configuration
3. Ensure all dependencies are installed
4. Check network connectivity and proxy settings
5. Verify the API endpoint is accessible

## License

[Your License Information]

## Author

[Your Name/Organization]
