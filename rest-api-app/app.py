from flask import Flask, request, jsonify
import json
import time
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200

@app.route('/api/process', methods=['POST'])
def process_request():
    """
    Process JSON payload and sleep for specified duration
    Query param: sleep_time (in seconds, default: 0)
    """
    try:
        # Get sleep time from query parameter
        sleep_time = request.args.get('sleep_time', default=0, type=float)
        
        # Validate sleep time is reasonable (max 60 seconds)
        if sleep_time < 0:
            return jsonify({"error": "sleep_time must be non-negative"}), 400
        if sleep_time > 60:
            return jsonify({"error": "sleep_time cannot exceed 60 seconds"}), 400
        
        # Get and validate JSON payload
        if not request.is_json:
            return jsonify({"error": "Content-Type must be application/json"}), 400
        
        payload = request.get_json()
        
        if payload is None:
            return jsonify({"error": "Invalid JSON payload"}), 400
        
        logger.info(f"Received valid JSON payload with {len(str(payload))} characters")
        logger.info(f"Sleeping for {sleep_time} seconds")
        
        # Sleep for the specified duration
        time.sleep(sleep_time)
        
        # Return success response
        return jsonify({
            "status": "success",
            "message": "JSON validated and processed",
            "sleep_time": sleep_time,
            "payload_size": len(str(payload))
        }), 200
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return jsonify({"error": f"Invalid JSON: {str(e)}"}), 400
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500

@app.route('/', methods=['GET'])
def root():
    """Root endpoint with API documentation"""
    return jsonify({
        "service": "REST API Sleep Service",
        "version": "1.0.0",
        "endpoints": {
            "/health": "GET - Health check",
            "/api/process": "POST - Process JSON payload with optional sleep",
            "/": "GET - This documentation"
        },
        "usage": {
            "endpoint": "/api/process?sleep_time=5",
            "method": "POST",
            "content_type": "application/json",
            "example": {
                "curl": "curl -X POST 'http://localhost:8080/api/process?sleep_time=2' -H 'Content-Type: application/json' -d '{\"test\": \"data\"}'"
            }
        }
    }), 200

if __name__ == '__main__':
    # Run on port 8080 for OpenShift compatibility
    app.run(host='0.0.0.0', port=8080, debug=False)

# Made with Bob
