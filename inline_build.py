#!/usr/bin/env python3
# 把 webroot 下 4 个 JS 内联进 index.html（SukiSU 实际加载的就是这个内联版）
# 用法: python3 inline_build.py   → 生成 webroot/index.html（内联）+ /tmp/inlined_index.html
import os, re

WEB = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'webroot')
JS = ['app-core.js', 'app-files.js', 'app-actions.js', 'app-lib.js']
SRC = os.path.join(WEB, 'index-src.html')   # 外部引用版源码（保留 <script src>）

# 若存在 index-src.html 优先用它作为模板，否则用当前 index.html（须是未内联版）
tmpl_path = SRC if os.path.exists(SRC) else os.path.join(WEB, 'index.html')
html = open(tmpl_path, encoding='utf-8').read()

parts = ["/* ===== %s ===== */\n" % j + open(os.path.join(WEB, j), encoding='utf-8').read() for j in JS]
js = "\n".join(parts)
# 去掉外链 script 标签，插入内联
html = re.sub(r'\s*<script src="app-[a-z]+\.js[^"]*"></script>', '', html)
html = html.replace('</body>', "<script>\n%s\n</script>\n</body>" % js)

open(os.path.join(WEB, 'index.html'), 'w', encoding='utf-8').write(html)
open('/tmp/inlined_index.html', 'w', encoding='utf-8').write(html)
print('内联版 %d 字节：webroot/index.html + /tmp/inlined_index.html' % len(html))
