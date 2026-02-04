#!/usr/bin/env python3
"""
Generate JSON payloads of specific sizes for JMeter testing
"""
import json
import sys
import random
import string

def generate_random_string(length):
    """Generate a random string of specified length"""
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_payload(target_size_bytes):
    """
    Generate a JSON payload of approximately the target size in bytes
    
    Args:
        target_size_bytes: Target size in bytes
        
    Returns:
        JSON string of approximately the target size
    """
    # Start with a base structure
    payload = {
        "timestamp": "${__time(yyyy-MM-dd'T'HH:mm:ss.SSS'Z',)}",
        "test_id": "${__UUID()}",
        "iteration": "${__threadNum()}-${__counter(FALSE,)}",
        "data": []
    }
    
    # Calculate overhead from the base structure
    base_json = json.dumps(payload, separators=(',', ':'))
    base_size = len(base_json.encode('utf-8'))
    
    # Calculate how much data we need to add
    remaining_size = target_size_bytes - base_size
    
    if remaining_size <= 0:
        return json.dumps(payload, indent=2)
    
    # Add data entries to reach target size
    # Each entry has some overhead, so we'll add chunks
    chunk_size = 100  # Size of each data string
    num_chunks = max(1, remaining_size // (chunk_size + 20))  # +20 for JSON overhead
    
    # Generate data chunks
    for i in range(num_chunks):
        payload["data"].append({
            "id": i,
            "value": "x" * chunk_size
        })
    
    # Fine-tune to get closer to target size
    current_json = json.dumps(payload, separators=(',', ':'))
    current_size = len(current_json.encode('utf-8'))
    
    if current_size < target_size_bytes:
        # Add padding field to reach exact size
        padding_needed = target_size_bytes - current_size - 20  # -20 for field overhead
        if padding_needed > 0:
            payload["padding"] = "p" * padding_needed
    
    return json.dumps(payload, indent=2)

def main():
    if len(sys.argv) != 2:
        print("Usage: generate_payload.py <size_in_bytes>")
        print("Example: generate_payload.py 1024")
        sys.exit(1)
    
    try:
        target_size = int(sys.argv[1])
        if target_size <= 0:
            raise ValueError("Size must be positive")
        
        payload = generate_payload(target_size)
        print(payload)
        
        # Print actual size to stderr for verification
        actual_size = len(payload.encode('utf-8'))
        print(f"\n# Target: {target_size} bytes, Actual: {actual_size} bytes", file=sys.stderr)
        
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

# Made with Bob
