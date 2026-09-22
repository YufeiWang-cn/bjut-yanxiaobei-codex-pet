#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$(basename "$script_dir")" = "macos-companion" ]; then
  install_root=$(dirname "$script_dir")
else
  install_root=$script_dir
fi
if [ ! -f "$install_root/VERSION.txt" ] || [ ! -f "$install_root/macos-companion/main.cjs" ] || [ -d "$install_root/.git" ]; then
  /usr/bin/osascript -e 'display alert "燕小北卸载失败" message "没有找到完整的发布目录，或当前目录是源码仓库。请不要手动删除未知目录。" as critical' >/dev/null
  exit 1
fi
choice=$(/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  activate
  set resultButton to button returned of (display dialog "请选择是否保留燕小北的设置和缓存。\n\n保留设置：只将桌宠核心文件移入废纸篓。\n全部清除：同时删除设置和缓存。" with title "卸载燕小北" buttons {"取消", "全部清除", "保留设置"} default button "保留设置" cancel button "取消" with icon caution)
end tell
return resultButton
APPLESCRIPT
) || exit 0
data="$HOME/Library/Application Support/BJUT-YanXiaoBei"
if [ "$choice" = "全部清除" ] && [ -e "$data" ]; then
  if [ -L "$data" ] || [ "$(basename "$data")" != "BJUT-YanXiaoBei" ]; then
    /usr/bin/osascript -e 'display alert "燕小北卸载失败" message "本地数据目录路径异常，未执行删除。" as critical' >/dev/null
    exit 1
  fi
  /bin/rm -rf -- "$data"
fi
/usr/bin/osascript -e 'tell application "System Events" to if exists login item "BJUT YanXiaoBei" then delete login item "BJUT YanXiaoBei"' >/dev/null 2>&1 || true
/usr/bin/osascript - "$install_root" <<'APPLESCRIPT'
on run argv
  tell application "Finder" to delete POSIX file (item 1 of argv)
end run
APPLESCRIPT
/usr/bin/osascript -e 'display notification "桌宠核心文件已移入废纸篓。Codex 数据未受影响。" with title "燕小北卸载完成"' >/dev/null
