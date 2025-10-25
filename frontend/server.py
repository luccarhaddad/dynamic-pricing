#!/usr/bin/env python3
"""
Simple HTTP server to serve the frontend dashboard.
Run with: python3 server.py
Then open: http://localhost:3000
"""

import http.server
import socketserver
import os
import sys
from pathlib import Path

# Configuration
PORT = 3000
FRONTEND_DIR = Path(__file__).parent

class CustomHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(FRONTEND_DIR), **kwargs)
    
    def end_headers(self):
        # Add CORS headers to allow API calls
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()
    
    def do_OPTIONS(self):
        # Handle preflight requests
        self.send_response(200)
        self.end_headers()

def main():
    # Change to frontend directory
    os.chdir(FRONTEND_DIR)
    
    # Start server
    with socketserver.TCPServer(("", PORT), CustomHTTPRequestHandler) as httpd:
        print(f"🚀 Frontend server running at http://localhost:{PORT}")
        print(f"📁 Serving files from: {FRONTEND_DIR}")
        print(f"🌐 Open your browser and go to: http://localhost:{PORT}")
        print(f"⏹️  Press Ctrl+C to stop the server")
        print()
        
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n🛑 Server stopped")
            sys.exit(0)

if __name__ == "__main__":
    main()
