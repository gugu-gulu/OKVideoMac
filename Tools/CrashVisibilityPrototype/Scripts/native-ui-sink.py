#!/usr/bin/env python3
"""Loopback-only sink for manual native-window acceptance; no external service or UI automation."""
import gzip,http.server,json,pathlib,sys,threading,time
root=pathlib.Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
lock=threading.Lock();receipts=[]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        data=self.rfile.read(int(self.headers['Content-Length']))
        if self.headers.get('Content-Encoding')=='gzip':data=gzip.decompress(data)
        # Persist only synthetic event identity and field names, never the full request.
        lines=data.splitlines();event=json.loads(lines[2])
        with lock:
            receipts.append({'eventID':event.get('event_id'),'keys':sorted(event)})
            (root/'receipts.json').write_text(json.dumps(receipts,indent=2))
        time.sleep(2)
        self.send_response(200);self.end_headers()
        try:self.wfile.write(b'{}')
        except (BrokenPipeError,ConnectionResetError):pass
    def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
(root/'sink.json').write_text(json.dumps({'port':server.server_port}))
(root/'receipts.json').write_text('[]')
server.serve_forever()
