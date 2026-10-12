#!/usr/bin/env python3
# xzm 管理器 · 打包脚本
# 1) 把 webroot 下 4 个 JS 内联进 index.html（生成单文件版本用于打包）
# 2) 生成可安装的 KernelSU 模块 zip
import os, zipfile, re

ROOT = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ROOT, 'webroot')
DIST = os.path.join(ROOT, 'dist')
JS_FILES = ['app-core.js', 'app-files.js', 'app-actions.js', 'app-lib.js']
MODULE_ITEMS = ['module.prop', 'action.sh', 'customize.sh', 'service.sh',
                'boot-completed.sh', 'uninstall.sh', 'bin', 'webroot', 'webroot-cgi',
                'payload', 'README.md']

def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()

def build_single_html():
    # 优先用外部引用版源码作为模板，避免重复内联
    _src = os.path.join(WEB, 'index-src.html')
    html = read(_src if os.path.exists(_src) else os.path.join(WEB, 'index.html'))
    parts = [f"/* ===== {j} ===== */\n" + read(os.path.join(WEB, j)) for j in JS_FILES]
    js = "\n".join(parts)
    html = re.sub(r'\s*<script src="app-[a-z]+\.js[^"]*"></script>', '', html)
    html = html.replace('</body>', f"<script>\n{js}\n</script>\n</body>")
    return html

def main():
    os.makedirs(DIST, exist_ok=True)
    ver = 'v1.0'
    for line in read(os.path.join(ROOT, 'module.prop')).splitlines():
        if line.startswith('version='):
            ver = line.split('=', 1)[1].strip()
    outzip = os.path.join(DIST, f'xzm_manager-{ver}.zip')
    single = build_single_html()

    with zipfile.ZipFile(outzip, 'w', zipfile.ZIP_DEFLATED) as z:
        for item in MODULE_ITEMS:
            src = os.path.join(ROOT, item)
            if not os.path.exists(src):
                print('  跳过（不存在）:', item)
                continue
            if os.path.isdir(src):
                for base, _, files in os.walk(src):
                    for fn in files:
                        fp = os.path.join(base, fn)
                        rel = os.path.relpath(fp, ROOT)
                        # webroot 下只保留单文件 index.html
                        if os.path.normpath(rel).startswith('webroot' + os.sep):
                            if os.path.normpath(rel) == os.path.normpath('webroot/index.html'):
                                z.writestr('webroot/index.html', single)
                            continue
                        z.write(fp, rel)
            else:
                z.write(src, item)
        if 'webroot/index.html' not in z.namelist():
            z.writestr('webroot/index.html', single)
        # 额外放一份单文件 html 到根，方便直接网页预览
        z.writestr('webroot/index-single.html', single)

    print(f'✅ 已生成: {outzip}  ({os.path.getsize(outzip)} 字节)')
    print('   包含文件:')
    with zipfile.ZipFile(outzip) as z:
        for n in z.namelist():
            print('     ', n)

if __name__ == '__main__':
    main()
