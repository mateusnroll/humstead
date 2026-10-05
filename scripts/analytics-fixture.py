#!/usr/bin/env python3
import argparse
import http.server
import json
import pathlib
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument('--ready', required=True)
parser.add_argument('--port', type=int, default=0)
args = parser.parse_args()
lock = threading.Lock()
state = {'delay': 0, 'status': 200, 'oversize': False, 'requests': []}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, status, body=b'{}', headers=None):
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path == '/__journal':
            with lock:
                body = json.dumps({'requests': state['requests']}).encode()
            self.respond(200, body)
        elif self.path == '/redirected':
            with lock:
                state['requests'].append({'path': self.path})
            self.respond(200)
        else:
            self.respond(404)

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 <= length <= 16384:
                return self.respond(413)
            body = json.loads(self.rfile.read(length))
        except (ValueError, json.JSONDecodeError):
            return self.respond(400)
        if self.path == '/__configure':
            if not isinstance(body, dict) or set(body) - {'delay', 'status', 'oversize', 'reset'}:
                return self.respond(400)
            if not isinstance(body.get('delay', 0), (int, float)) or not 0 <= body.get('delay', 0) <= 10:
                return self.respond(400)
            with lock:
                if body.pop('reset', False):
                    state['requests'] = []
                    state.update(delay=0, status=200, oversize=False)
                state.update(body)
            return self.respond(200)
        if self.path != '/i/v0/e':
            return self.respond(404)
        with lock:
            state['requests'].append({'path': self.path, 'method': 'POST', 'headers': dict(self.headers), 'body': body})
            state['requests'] = state['requests'][-200:]
            delay, status, oversize = state['delay'], state['status'], state['oversize']
        time.sleep(delay)
        self.respond(status, b'x' * 16385 if oversize else b'{}', {'Location': '/redirected', 'Set-Cookie': 'fixture=forbidden'})


server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
server.daemon_threads = True
pathlib.Path(args.ready).write_text(json.dumps({'origin': 'http://127.0.0.1:' + str(server.server_port)}))
server.serve_forever()
