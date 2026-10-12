# xzm 管理器

全管理器兼容（KernelSU / SukiSU / APatch / Magisk）的双栏文件管理器 + Root 终端，浅色简约界面。

## 功能

- **双栏文件浏览**：左右两栏（手机竖屏自动改为单栏 + ⇄ 切换）
  - 单击文件夹进入，单击文件打开
  - 长按（手机）/ 点行尾 ⋯（电脑）弹出操作菜单
- **文件操作**：复制到对栏、移动到对栏、重命名、删除、新建、搜索
- **属性 / 权限**：查看属性（大小/属主/MD5）、修改权限（chmod）、修改属主（chown）
- **文本编辑器**：直接编辑文本/脚本文件，行号 + 查找
- **书签**：收藏常用目录
- **Root 终端**：内置 ttyd（端口 7681），点「启动终端」后在「新窗口打开」里用系统浏览器访问
  - 注：KernelSU WebUI 的 WebView 会拦截内嵌 http://127.0.0.1，因此终端用新窗口打开
- **环境诊断**：一键排查桥接/路径问题

## 安装

1. 把 `dist/xzm_manager-*.zip` 传到手机
2. KernelSU / Magisk / APatch → 模块 → 从本地安装 → 选 zip
3. **重启**
4. 打开模块 WebUI

## 目录结构

```
module.prop         模块元信息
customize.sh        安装脚本（兼容各管理器）
service.sh          开机脚本（准备数据目录、复制 ttyd）
action.sh           模块 Action 入口
uninstall.sh        卸载脚本
bin/xzmctl.sh       后端核心（JSON API）
bin/xzm-shell.sh    终端启动包装
bin/ttyd            ttyd 1.7.7 aarch64 静态二进制
webroot/index.html  WebUI（单文件，JS 已内联）
```

## 数据目录

`/data/adb/xzm_manager/` — 存放日志、偏好、终端状态等。

## 技术说明

- WebUI 通过 KernelSU 注入的 `window.ksu.exec`（回调式）执行 shell
- 兼容 npm 包 `kernelsu` 的 Promise 式 exec
- 电脑调试时（127.0.0.1）自动降级到本地预览服务器
- 后端 `xzmctl.sh` 用 `find` + `stat` 列目录，兼容 Android toybox
