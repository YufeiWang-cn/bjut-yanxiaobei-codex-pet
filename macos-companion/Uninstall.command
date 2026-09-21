#!/bin/sh
set -eu
cd "$(dirname "$0")"
printf '%s\n' '燕小北卸载：先在菜单栏右键燕小北，关闭“登录时启动”，再退出桌宠。'
printf '%s\n' '按回车继续清除燕小北本地设置；按 Ctrl+C 取消。'
read -r answer
data="$HOME/Library/Application Support/BJUT-YanXiaoBei"
if [ -L "$data" ]; then printf '%s\n' '数据目录是链接，已拒绝删除。'; exit 1; fi
if [ -d "$data" ]; then rm -R -i "$data"; fi
printf '%s\n' '本地设置已清除。现在可将燕小北 .app 与解压文件夹移入废纸篓。Codex 数据不会删除。'
