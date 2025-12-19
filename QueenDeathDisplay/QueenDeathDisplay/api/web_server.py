#!/usr/bin/env python3
"""
Simple web server for Queen Death Display real-time data
Serves JSON data and HTML interface
"""

import http.server
import socketserver
import json
import os
import sys
import time
import socket
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# Configuration
DEFAULT_PORT = 8080
DATA_FILE = Path(__file__).parent / "data.json"
HTML_FILE = Path(__file__).parent / "index.html"

def is_port_available(port):
    """Check if a port is available"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(('', port))
            return True
        except OSError:
            return False

def is_server_running(port):
    """Check if our server is already running on this port"""
    try:
        import urllib.request
        response = urllib.request.urlopen(f'http://localhost:{port}/api/status', timeout=1)
        if response.status == 200:
            return True
    except:
        pass
    return False

def find_available_port(start_port, max_attempts=10):
    """Find an available port starting from start_port"""
    for i in range(max_attempts):
        port = start_port + i
        if is_port_available(port):
            return port
    return None

class QueenDeathDisplayHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        if path == "/" or path == "/index.html":
            self.serve_html()
        elif path == "/api/data" or path == "/data.json":
            self.serve_json()
        elif path == "/api/status":
            self.serve_status()
        elif path == "/api/export-csv":
            self.serve_csv()
        elif path == "/favicon.ico":
            # Return empty 204 No Content for favicon requests to prevent 404 errors
            self.send_response(204)
            self.end_headers()
            return
        else:
            self.send_error(404, "Not Found")
    
    def serve_html(self):
        """Serve the HTML interface"""
        try:
            html_path = Path(__file__).parent / "index.html"
            if html_path.exists():
                with open(html_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-type', 'text/html; charset=utf-8')
                self.send_header('Cache-Control', 'no-cache')
                self.end_headers()
                self.wfile.write(content.encode('utf-8'))
            else:
                # Fallback: serve a simple HTML page with instructions
                error_html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Queen Death Display - File Not Found</title>
    <style>
        body {{ font-family: Arial, sans-serif; padding: 20px; background: #1a1a2e; color: #e0e0e0; }}
        .error {{ background: rgba(255, 68, 68, 0.2); padding: 20px; border-radius: 10px; border: 2px solid #ff4444; }}
    </style>
</head>
<body>
    <div class="error">
        <h1>HTML File Not Found</h1>
        <p>Expected location: {html_path}</p>
        <p>Please ensure index.html exists in the same directory as web_server.py</p>
    </div>
</body>
</html>"""
                self.send_response(200)
                self.send_header('Content-type', 'text/html; charset=utf-8')
                self.end_headers()
                self.wfile.write(error_html.encode('utf-8'))
        except Exception as e:
            error_html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Queen Death Display - Error</title>
    <style>
        body {{ font-family: Arial, sans-serif; padding: 20px; background: #1a1a2e; color: #e0e0e0; }}
        .error {{ background: rgba(255, 68, 68, 0.2); padding: 20px; border-radius: 10px; border: 2px solid #ff4444; }}
    </style>
</head>
<body>
    <div class="error">
        <h1>Error Serving HTML</h1>
        <p>{str(e)}</p>
    </div>
</body>
</html>"""
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(error_html.encode('utf-8'))
    
    def serve_json(self):
        """Serve the JSON data file"""
        try:
            if DATA_FILE.exists():
                # Read and parse JSON
                with open(DATA_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
                # Add server timestamp
                data['serverTimestamp'] = time.time()
                data['serverTimestampISO'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
                
                json_str = json.dumps(data, indent=2)
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json; charset=utf-8')
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json_str.encode('utf-8'))
            else:
                # Return empty data if file doesn't exist yet
                empty_data = {
                    'timestamp': 0,
                    'serverTimestamp': time.time(),
                    'queens': {'total': None, 'killed': 0, 'remaining': None},
                    'timers': {'graceRemaining': None, 'queenETA': None},
                    'teamKills': {},
                    'leaderboard': [],
                    'deathMessages': [],
                }
                json_str = json.dumps(empty_data, indent=2)
                self.send_response(200)
                self.send_header('Content-type', 'application/json; charset=utf-8')
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json_str.encode('utf-8'))
        except json.JSONDecodeError as e:
            self.send_error(500, f"Invalid JSON: {str(e)}")
        except Exception as e:
            self.send_error(500, f"Error serving JSON: {str(e)}")
    
    def serve_status(self):
        """Serve server status"""
        status = {
            'running': True,
            'dataFileExists': DATA_FILE.exists(),
            'dataFileAge': None,
            'serverTime': time.time(),
        }
        
        if DATA_FILE.exists():
            status['dataFileAge'] = time.time() - DATA_FILE.stat().st_mtime
        
        json_str = json.dumps(status, indent=2)
        self.send_response(200)
        self.send_header('Content-type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json_str.encode('utf-8'))
    
    def serve_csv(self):
        """Generate and serve CSV leaderboard file"""
        try:
            if not DATA_FILE.exists():
                self.send_error(404, "No data file found")
                return
            
            # Read JSON data
            with open(DATA_FILE, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            leaderboard = data.get('leaderboard', [])
            
            if len(leaderboard) == 0:
                self.send_error(404, "No leaderboard data available")
                return
            
            # Generate CSV content
            import csv
            import io
            
            output = io.StringIO()
            writer = csv.writer(output)
            
            # Write header
            writer.writerow(['Rank', 'Player Name', 'Team ID', 'Kills'])
            
            # Write leaderboard entries
            for rank, entry in enumerate(leaderboard, 1):
                player_name = entry.get('name', 'Unknown').replace(',', ' ')
                team_id = entry.get('teamID', 0)
                kills = entry.get('kills', 0)
                writer.writerow([rank, player_name, int(team_id), int(kills)])
            
            csv_content = output.getvalue()
            output.close()
            
            # Generate filename with timestamp
            timestamp = time.strftime('%Y%m%d_%H%M%S', time.gmtime())
            filename = f'queen_kills_leaderboard_{timestamp}.csv'
            
            # Send CSV file
            self.send_response(200)
            self.send_header('Content-type', 'text/csv; charset=utf-8')
            self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(csv_content.encode('utf-8'))
            
        except Exception as e:
            self.send_error(500, f"Error generating CSV: {str(e)}")
    
    def log_message(self, format, *args):
        """Override to show all requests for debugging"""
        # Log all requests to help debug
        message = format % args
        print(f"[Server] {message}")
        super().log_message(format, *args)

def main():
    # Parse command line arguments for port
    port = DEFAULT_PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Invalid port number: {sys.argv[1]}")
            print(f"Usage: python web_server.py [port]")
            sys.exit(1)
    
    # Check if port is available
    if not is_port_available(port):
        # Check if it's our own server already running
        if is_server_running(port):
            print(f"Queen Death Display Web Server is already running!")
            print(f"Server is available at: http://localhost:{port}/")
            print(f"\nIf you want to start a new instance on a different port, use:")
            print(f"  python web_server.py {port + 1}")
            sys.exit(0)
        
        # Port is in use by something else
        print(f"Port {port} is already in use by another application.")
        alternative = find_available_port(port + 1)
        if alternative:
            print(f"Using alternative port: {alternative}")
            port = alternative
        else:
            print("Could not find an available port. Please close other applications using ports or specify a different port.")
            print(f"Usage: python web_server.py [port]")
            sys.exit(1)
    
    # Ensure data directory exists
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    
    # Change to the script directory to serve files
    os.chdir(Path(__file__).parent)
    
    try:
        with socketserver.TCPServer(("", port), QueenDeathDisplayHandler) as httpd:
            print(f"Queen Death Display Web Server")
            print(f"================================")
            print(f"Server running on http://localhost:{port}/")
            print(f"Data file: {DATA_FILE} (exists: {DATA_FILE.exists()})")
            print(f"HTML file: {HTML_FILE} (exists: {HTML_FILE.exists()})")
            print(f"")
            print(f"Open in browser: http://localhost:{port}/")
            print(f"API endpoint: http://localhost:{port}/api/data")
            print(f"Press Ctrl+C to stop")
            print()
            
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\nShutting down server...")
                httpd.shutdown()
    except OSError as e:
        print(f"Error starting server: {e}")
        print(f"Port {port} may be in use. Try a different port:")
        print(f"  python web_server.py {port + 1}")
        sys.exit(1)

if __name__ == "__main__":
    main()

