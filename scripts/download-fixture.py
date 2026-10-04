#!/usr/bin/env python3
"""Loopback-only Humstead download fixture; never contacts external services."""
import argparse
import hashlib
import http.server
import json
import pathlib
import threading
import time
import urllib.parse


def catalog(root, version):
    bundled = json.loads((root / 'Humstead/Resources/catalog.json').read_text())
    selected = ['snow-drift' if version == 1 else '2-hour-delay', 'forest']
    assets = []
    files = {}
    for original in bundled['assets']:
        if original['id'] not in selected:
            continue
        suffix = pathlib.Path(original['resource']).suffix
        path = 'audio/' + original['sha256'] + suffix
        source = root / 'Humstead/Resources/Audio' / original['resource']
        assert source.stat().st_size == original['byteLength']
        assert hashlib.sha256(source.read_bytes()).hexdigest() == original['sha256']
        files['/' + path] = source
        assets.append({
            'id': 'extra-' + original['id'], 'kind': original['kind'],
            'sha256': original['sha256'], 'byteLength': original['byteLength'],
            'codec': original['codec'], 'duration': original['duration'], 'path': path,
            'title': original['title'], 'creator': original['creator'],
            'originalSourceURL': original['sourceURL'],
            'creatorProfileURL': original.get('profileURL'), 'license': 'CC0',
            'licenseVersion': '1.0', 'licenseURL': original['licenseURL'],
            'attribution': original['attribution'], 'modification': original['modification'],
        })
    collections = []
    for kind, label in [('music', 'Extra Mellow'), ('ambience', 'Extra Forest')]:
        group = [a for a in assets if a['kind'] == kind]
        collection = {'id': 'extra-' + kind, 'kind': kind, 'version': version,
                      'label': label, 'assetIDs': [a['id'] for a in group],
                      'totalBytes': sum(a['byteLength'] for a in group)}
        if kind == 'music':
            collection['stationID'] = 'mellow'
        collections.append(collection)
    return {'schemaVersion': 1, 'catalogVersion': version,
            'collections': collections, 'assets': assets}, files


def serve(root, ready, port):
    versions = {n: catalog(root, n) for n in (1, 2)}
    objects = {path: file for _, files in versions.values() for path, file in files.items()}
    state = {'version': 1, 'enabled': True, 'revision': 1, 'edge_block': False,
             'fail_audio': 0, 'chunk_delay': 0, 'malformed_control': False,
             'corrupt_audio': False, 'large_catalog': False, 'large_control': False,
             'redirect_audio': False, 'control_delay': 0, 'requests': [], 'origin_reads': 0,
             'active_audio': 0, 'max_active_audio': 0}
    cache = set()
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *_):
            pass

        def respond(self, code, data, headers=None):
            self.send_response(code)
            self.send_header('Content-Length', str(len(data)))
            for key, value in (headers or {}).items():
                self.send_header(key, value)
            self.end_headers()
            if data:
                self.wfile.write(data)

        def do_POST(self):
            if self.path != '/__configure':
                return self.respond(404, b'')
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 16384:
                return self.respond(400, b'')
            try:
                change = json.loads(self.rfile.read(length))
                allowed = {'version', 'enabled', 'revision', 'edge_block', 'fail_audio',
                           'chunk_delay', 'malformed_control', 'corrupt_audio',
                           'large_catalog', 'large_control', 'redirect_audio', 'control_delay'}
                if set(change) - allowed:
                    return self.respond(400, b'')
                with lock:
                    state.update(change)
                self.respond(200, b'{}')
            except (ValueError, TypeError):
                self.respond(400, b'')

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            with lock:
                state['requests'].append({'path': path, 'monotonic': time.monotonic(),
                                          'if_none_match': self.headers.get('If-None-Match'),
                                          'cache_control': self.headers.get('Cache-Control')})
                current = dict(state)
            if path == '/__journal':
                return self.respond(200, json.dumps(current).encode())
            if path == '/control/v1.json':
                time.sleep(min(float(current['control_delay']), 6))
                data = (b'invalid' if current['malformed_control'] else
                        json.dumps({'downloadsEnabled': current['enabled'],
                                    'revision': current['revision']}).encode())
                if current['large_control']:
                    data = b' ' * 16385
                return self.respond(200, data, {'Cache-Control': 'no-store'})
            if path == '/catalog/v1.json':
                tag = '"fixture-' + str(current['version']) + '"'
                if self.headers.get('If-None-Match') == tag and not current['large_catalog']:
                    return self.respond(304, b'', {'ETag': tag})
                data = json.dumps(versions[current['version']][0]).encode()
                if current['large_catalog']:
                    data = b' ' * 2000001
                return self.respond(200, data, {'ETag': tag, 'Content-Type': 'application/json'})
            if path.startswith('/audio/'):
                if current['redirect_audio']:
                    return self.respond(302, b'', {'Location': 'https://example.invalid/audio'})
                if current['edge_block']:
                    return self.respond(403, b'edge denied')
                if path not in objects:
                    return self.respond(404, b'')
                if current['fail_audio'] > 0:
                    with lock:
                        state['fail_audio'] -= 1
                    return self.respond(503, b'try later')
                with lock:
                    if path not in cache:
                        state['origin_reads'] += 1
                        cache.add(path)
                    state['active_audio'] += 1
                    state['max_active_audio'] = max(state['max_active_audio'], state['active_audio'])
                file = objects[path]
                try:
                    self.send_response(200)
                    self.send_header('Content-Length', str(file.stat().st_size))
                    self.end_headers()
                    with file.open('rb') as source:
                        first = True
                        while chunk := source.read(65536):
                            if first and current['corrupt_audio']:
                                chunk = bytes([chunk[0] ^ 1]) + chunk[1:]
                            first = False
                            self.wfile.write(chunk)
                            self.wfile.flush()
                            if current['chunk_delay']:
                                time.sleep(min(float(current['chunk_delay']), 2))
                except (BrokenPipeError, ConnectionResetError):
                    pass
                finally:
                    with lock:
                        state['active_audio'] -= 1
                return
            self.respond(404, b'')

    server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
    ready.write_text(json.dumps({'origin': 'http://127.0.0.1:' + str(server.server_port)}))
    server.serve_forever()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=pathlib.Path, required=True)
    parser.add_argument('--ready', type=pathlib.Path, required=True)
    parser.add_argument('--port', type=int, default=0)
    args = parser.parse_args()
    serve(args.root.resolve(), args.ready, args.port)
