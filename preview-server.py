#!/usr/bin/env python3
# xzm 管理器 · 本机预览服务器（仅调试用，不属于模块）
# 提供一个 /__shell__ 端点，把前端的 shell 调用转发到本机 bash
# 这样在电脑浏览器里就能预览真实界面与交互。
import http.server, socketserver, subprocess, os, sys, json

ROOT = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ROOT, 'webroot')
MODDIR = ROOT

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self,*a,**k):
        super().__init__(*a, directory=WEB, **k)

    def end_headers(self):
        # 开发期禁用缓存，避免浏览器用旧 JS
        self.send_header('Cache-Control','no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma','no-cache')
        self.send_header('Expires','0')
        super().end_headers()

    def do_POST(self):
        if self.path == '/__shell__':
            n = int(self.headers.get('Content-Length','0'))
            cmd = self.rfile.read(n).decode('utf-8','replace')
            # 输入方向映射：真机路径 → 本机路径
            cmd = cmd.replace('/data/adb/modules/xzm_manager', MODDIR)
            for sub in ['prefs','logs','run','state','scripts','edit','archive','bin']:
                os.makedirs(f'/tmp/xzm-preview-data/{sub}', exist_ok=True)
            cmd = cmd.replace('/data/adb/xzm_manager', '/tmp/xzm-preview-data')
            cmd = cmd.replace('/sdcard', '/tmp/xzm-preview-data/sdcard')
            os.makedirs('/tmp/xzm-preview-data/sdcard/Download', exist_ok=True)
            cmd = "export XZM_DATA_DIR=/tmp/xzm-preview-data; " + cmd
            try:
                r = subprocess.run(['bash','-c',cmd], capture_output=True, timeout=30)
                out = r.stdout.decode('utf-8','replace') + r.stderr.decode('utf-8','replace')
            except Exception as e:
                out = str(e)
            # 输出方向映射：本机路径 → 真机路径（模拟真机行为，避免二次改写）
            out = out.replace('/tmp/xzm-preview-data/sdcard', '/sdcard')
            out = out.replace('/tmp/xzm-preview-data', '/data/adb/xzm_manager')
            out = out.replace(MODDIR, '/data/adb/modules/xzm_manager')
            self.send_response(200)
            self.send_header('Content-Type','text/plain; charset=utf-8')
            self.send_header('Content-Length', str(len(out.encode())))
            self.end_headers()
            self.wfile.write(out.encode())
            return
        self.send_error(404)

    def log_message(self,*a): pass

PORT = int(sys.argv[1]) if len(sys.argv)>1 else 8899
# 放点示例文件
sd = '/tmp/xzm-preview-data/sdcard'
os.makedirs(sd+'/Download', exist_ok=True)
os.makedirs(sd+'/DCIM', exist_ok=True)
os.makedirs(sd+'/Pictures', exist_ok=True)
open(sd+'/notes.md','w').write('# 示例笔记\nhello xzm\n')
open(sd+'/install.sh','w').write('#!/system/bin/sh\necho hi\n')
open(sd+'/Download/setup.zip','wb').write(b'PK\x03\x04'+b'0'*2048)
print(f'xzm 预览服务器: http://127.0.0.1:{PORT}/index.html')
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('127.0.0.1',PORT), H) as httpd:
    httpd.serve_forever()
