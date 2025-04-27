#!/usr/bin/env bash
set -euo pipefail

# Check for dependencies: aws, jq, unzip
if ! command -v aws &>/dev/null; then
  echo "ERROR: aws CLI is not installed. Please install it and try again."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Please install it (e.g. brew install jq) and try again."
  exit 1
fi

if ! command -v unzip &>/dev/null; then
  echo "ERROR: unzip is not installed. Please install it (e.g. brew install unzip) and try again."
  exit 1
fi

# You can hard-code specific regions if desired, for example:
# REGIONS=("us-east-1" "us-west-2")
# Or dynamically discover them:
REGIONS=($(aws ec2 describe-regions --query "Regions[].RegionName" --output text))

for region in "${REGIONS[@]}"; do
  echo ">>> Processing region: $region"
  
  # Get all Lambda function names in this region
  FUNCTIONS=($(aws lambda list-functions \
    --region "$region" \
    --query "Functions[].FunctionName" \
    --output text))
  
  if [ ${#FUNCTIONS[@]} -eq 0 ]; then
    echo "No Lambda functions found in region: $region"
    continue
  fi

  # Create a directory for this region (if you want them grouped by region)
  mkdir -p "$region"
  
  for function_name in "${FUNCTIONS[@]}"; do
    echo "  - Downloading source for function: $function_name"
    
    # Create a subdirectory for each function to store source files
    function_dir="$region/$function_name"
    mkdir -p "$function_dir"
    
    # Get the presigned URL for the Lambda function code
    echo "    => Getting function details from AWS..."
    if ! code_url=$(aws lambda get-function \
      --region "$region" \
      --function-name "$function_name" \
      --query "Code.Location" \
      --output text 2>&1); then
      echo "    !! ERROR: Failed to get function details for $function_name"
      echo "    !! AWS CLI output: $code_url"
      continue
    fi
    
    # Download the ZIP
    echo "    => Downloading function code..."
    zip_file="$function_dir/source.zip"
    if ! curl -s -o "$zip_file" "$code_url"; then
      echo "    !! ERROR: Failed to download function code for $function_name"
      rm -f "$zip_file"
      continue
    fi
    
    # Unzip into the function's directory
    echo "    => Unzipping to $function_dir"
    if ! unzip -oq "$zip_file" -d "$function_dir"; then
      echo "    !! ERROR: Failed to unzip function code for $function_name"
      continue
    fi
    
    # Optional: Remove the ZIP after unzipping
    rm "$zip_file"
    
    # Find and process the main source file
    echo "    => Processing source files..."
    main_file=$(find "$function_dir" -type f \( -name "lambda_function.py" -o -name "index.js" -o -name "handler.js" -o -name "main.go" \) -print -quit)
    
    if [ -n "$main_file" ]; then
        # Get the file extension
        extension="${main_file##*.}"
        
        # Move and rename the main source file
        mv "$main_file" "$function_dir/${function_name}.${extension}"
        
        # Remove all other files and directories
        find "$function_dir" -mindepth 1 -maxdepth 1 ! -name "${function_name}.${extension}" -exec rm -rf {} +
    else
        echo "    !! WARNING: No main handler file found for $function_name"
        # Clean up the directory if no main file was found
        rm -rf "$function_dir"
    fi
    
    echo "    => Source code retrieved for $function_name"
  done

  echo "Finished region: $region"
done

echo "All done!"