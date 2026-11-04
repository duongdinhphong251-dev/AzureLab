"""Exercise a running API; create and delete only this run's temporary product."""
import argparse
import json
import struct
import urllib.error
import urllib.request
import uuid
import zlib


def png():
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 2, 2, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress((b'\x00' + b'\x80\x40\xc0' * 2) * 2)) + chunk(b'IEND', b''))


def run(base):
    def call(path, method='GET', data=None, content_type='application/json', expected=200):
        if isinstance(data, dict): data = json.dumps(data).encode()
        request = urllib.request.Request(base.rstrip('/') + path, data=data, method=method,
                                         headers={'Content-Type': content_type})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                status, headers, body = response.status, response.headers, response.read()
        except urllib.error.HTTPError as error:
            status, headers, body = error.code, error.headers, error.read()
        assert status == expected, f'{method} {path}: expected {expected}, got {status}: {body[:300]!r}'
        if 'application/json' in headers.get('Content-Type', ''): return json.loads(body)
        return body

    def multipart(content):
        boundary = 'azurelab-' + uuid.uuid4().hex
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="test.png"\r\n'
                f'Content-Type: image/png\r\n\r\n').encode() + content + f'\r\n--{boundary}--\r\n'.encode()
        return body, f'multipart/form-data; boundary={boundary}'

    call('/api/health'); call('/api/ready')
    print('PASS: health and readiness')
    item = None
    try:
        fields = {'name': 'Smoke test ' + uuid.uuid4().hex[:8], 'category': 'Test', 'description': 'Disposable test product', 'price': '123.45', 'stock': 3}
        item = call('/api/products', 'POST', fields, expected=201)
        path = '/api/products/' + item['id']
        assert call(path)['price'] == '123.45'
        assert call('/api/products?q=' + urllib.parse.quote(fields['name']))['total'] == 1
        print('PASS: create, read and search')
        edit = dict(fields, price='234.56', version=item['version'])
        item = call(path, 'PUT', edit)
        call(path, 'PUT', edit, expected=409)
        print('PASS: update and stale-write protection')
        body, kind = multipart(png())
        item = call(path + f'/image?version={item["version"]}', 'POST', body, kind)
        picture = call(path + '/image?download=true')
        assert picture.startswith(b'\xff\xd8') or picture.startswith(b'\x89PNG')
        invalid, kind = multipart(b'<script>not an image</script>')
        call(path + f'/image?version={item["version"]}', 'POST', invalid, kind, expected=415)
        print('PASS: upload/download and invalid-image rejection')
        call(path + f'?version={item["version"]}', 'DELETE', expected=204)
        item = None
        call(path, expected=404)
        print('PASS: delete')
    finally:
        if item:
            path = '/api/products/' + item['id']
            latest = call(path)
            call(path + f'?version={latest["version"]}', 'DELETE', expected=204)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://localhost:8080')
    run(parser.parse_args().url)
