#!/bin/sh
set -eu
codex_root="${CODEX_HOME:-$HOME/.codex}"
target="$codex_root/pets/bjut-yanxiaobei"
if [ -L "$target" ]; then printf '%s\n' '拒绝清理符号链接。'; exit 1; fi
printf '将删除原生燕小北素材：%s\n按回车继续，Ctrl+C 取消。\n' "$target"
read -r answer
if [ -d "$target" ]; then rm -R "$target"; fi
printf '%s\n' '原生素材已移除。请在 Codex 设置中切换其他宠物并刷新列表；备份、账号和其他宠物未删除。'
