#!/bin/zsh
set -eu
cd -- "${0:A:h}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  printf '\n需要 Node.js 22.12 或更新版本。请按 README / docs/MACOS.md 安装后重试。\n'
  read -r '?按回车退出…'
  exit 1
fi
if ! node -e 'const [major,minor]=process.versions.node.split(".").map(Number);process.exit(major>22||major===22&&minor>=12?0:1)'; then
  printf '\nNode.js 版本过低，请升级到 22.12 或更新版本。\n'
  exit 1
fi
if [[ ! -d node_modules/electron ]]; then
  printf '\n首次使用：请先在此目录运行 npm ci。此脚本不会自动联网安装。\n'
  read -r '?按回车退出…'
  exit 1
fi
npm run prepare-assets
# Detach the desktop process; closing this Terminal does not close the pet.
pet_data_dir="${YANXIAOBEI_DATA_DIR:-$HOME/Library/Application Support/BJUT-YanXiaoBei}"
mkdir -p "$pet_data_dir"
nohup ./node_modules/.bin/electron . > "$pet_data_dir/launcher.log" 2>&1 < /dev/null &
printf '\n燕小北已在后台启动。可以关闭此终端窗口；退出请用桌宠菜单。\n'
