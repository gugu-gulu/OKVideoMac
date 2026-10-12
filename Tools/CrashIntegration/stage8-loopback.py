from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import json,time
p=Path('/private/tmp/OKVideoMac-CrashIntegration/stage8-loopback.jsonl')
class Handler(BaseHTTPRequestHandler):
 def do_POST(self):
  n=int(self.headers.get('Content-Length','0')); data=self.rfile.read(n)
  with p.open('a') as f:f.write(json.dumps({'time':time.time(),'bytes':len(data),'status':503})+'\n')
  self.send_response(503);self.end_headers();self.wfile.write(b'retry later')
 def log_message(self,*a):pass
ThreadingHTTPServer(('127.0.0.1',9482),Handler).serve_forever()
