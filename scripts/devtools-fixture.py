#!/usr/bin/env python3
"""Local, synthetic fixture for manual devtools verification. No external traffic.
Run: python3 scripts/devtools-fixture.py, then open http://127.0.0.1:8766.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGE = b'''<!doctype html><html lang="en"><meta charset="utf-8"><title>Checkout - Devtools fixture</title>
<style>body{font:15px/1.5 system-ui;max-width:760px;margin:64px auto;padding:24px;color:#18181b;background:#fafafa}h1{font-size:28px;margin:0}p{color:#4e4e56}button{font:inherit;padding:8px 14px;margin:6px 8px 6px 0;border:1px solid #c8c8cd;border-radius:6px;background:white;cursor:pointer}button:focus-visible{outline:2px solid #0e8f80}section{padding:24px 0;border-bottom:1px solid #dedee1}pre{white-space:pre-wrap;font:12px/1.6 ui-monospace,monospace}@media(prefers-color-scheme:dark){body{color:#f4f4f5;background:#1e1e21}p{color:#a6a6ae}button{color:#f4f4f5;background:#26262a;border-color:#3e3e44}section{border-color:#303035}}</style>
<h1>Checkout</h1><p>Synthetic local debugging fixture. No orders or payments are submitted.</p>
<section><h2>Order summary</h2><p>3 items &middot; $128.00</p><button id="checkout" aria-label="Complete order">Complete order</button><button id="load">Load cart</button><button id="xhr">Send XHR</button></section>
<section><h2>Console &amp; storage</h2><button id="logs">Generate messages</button><button id="burst">Add 100 logs</button><button id="storage">Update storage</button><button id="large">Fetch large JSON</button></section><pre id="result">Enable detailed capture in Network, then reproduce a request.</pre>
<script>
const show = value => document.querySelector('#result').textContent=JSON.stringify(value,null,2);
const logs=()=>{console.log('Cart loaded', {items:3,total:128});console.info('API base', location.origin);console.warn('Shipping address is missing');for(let i=0;i<3;i++)console.error(new TypeError("Cannot read properties of undefined (reading 'total')"));console.debug('debug trace', undefined);};
document.querySelector('#logs').onclick=logs;
document.querySelector('#burst').onclick=()=>{for(let i=0;i<100;i++)console.log('Background event '+i)};
document.querySelector('#checkout').onclick=async()=>show(await(await fetch('/api/checkout',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Fixture':'yes'},body:JSON.stringify({items:3,shippingAddress:null})})).json());
document.querySelector('#load').onclick=async()=>show(await(await fetch('/api/cart?currency=USD')).json());
document.querySelector('#large').onclick=async()=>{const response=await fetch('/api/large');const data=await response.json();show({received:data.value.length})};
document.querySelector('#xhr').onclick=()=>{const request=new XMLHttpRequest();request.open('GET','/api/cart?source=xhr');request.onload=()=>show(JSON.parse(request.responseText));request.send()};
document.querySelector('#storage').onclick=()=>{localStorage.setItem('cart',JSON.stringify({items:3,total:128}));sessionStorage.setItem('checkout-step','shipping');document.cookie='fixture=checkout; SameSite=Lax; path=/';show({storage:'updated'})};
localStorage.setItem('cart',JSON.stringify({items:3,total:128}));sessionStorage.setItem('checkout-step','shipping');logs();
</script></html>'''

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/large'):
            self.reply(200, json.dumps({'value': 'x' * 100000}).encode(), 'application/json')
        elif self.path.startswith('/api/'):
            self.reply(200, json.dumps({'items': [{'sku': 'nano-01', 'count': 3}], 'total': 128, 'currency': 'USD'}).encode(), 'application/json')
        else:
            self.reply(200, PAGE, 'text/html; charset=utf-8')

    def do_POST(self):
        self.rfile.read(min(65536, int(self.headers.get('content-length', 0))))
        self.reply(422, json.dumps({'error': 'Missing shipping address', 'field': 'shippingAddress'}).encode(), 'application/json')

    def reply(self, status, data, content_type):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

if __name__ == '__main__':
    print('Synthetic devtools fixture: http://127.0.0.1:8766', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8766), Handler).serve_forever()
