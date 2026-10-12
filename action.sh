#!/system/bin/sh
# xzm 管理器 · 模块 Action 入口
MODDIR=${0%/*}
DATA_DIR=/data/adb/xzm_manager

# KernelSU / SukiSU / APatch 支持用 module WebUI，Action 仅做提示/兜底
echo "xzm 管理器"
echo "WebUI 入口：请通过管理器的模块 WebUI 打开"
echo "数据目录：$DATA_DIR"
echo "日志：$DATA_DIR/logs/module.log"

# 若管理器支持深链打开 WebUI，这里可扩展。
# 目前保持简单：打印信息。
