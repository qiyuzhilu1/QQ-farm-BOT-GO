#!/usr/bin/env bash
# ============================================================
#  QQ Farm Bot GO 一键部署脚本（自动识别系统架构，安装对应Go版本）
#
#  用法:  sudo env PATH="/usr/local/go/bin:$PATH" bash install.sh
# ============================================================
set -e

# 优先加载手动安装的Go路径
export PATH="/usr/local/go/bin:$PATH"

cd "$(dirname "$0")"
SRC="$(pwd)"
DES=/opt/go-farm-bot

echo "=========================================="
echo " QQ Farm Bot GO 一键部署【自动识别架构安装Go】"
echo "=========================================="

# ---------------------- 自动识别系统架构 ----------------------
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        i386)    echo "386" ;;
        *)
            echo "❌ 不支持的CPU架构: $arch"
            exit 1
        ;;
    esac
}
GO_ARCH=$(get_arch)
echo "✅ 识别CPU架构: $GO_ARCH"
# -------------------------------------------------------------

# ---- 检测Go，不存在则自动下载对应架构Go ----
GO_CMD=$(command -v go || true)
if [[ -z "${GO_CMD}" ]]; then
  echo "⚠️ 未检测到 Go，开始自动下载安装最新稳定版 Go (${GO_ARCH})..."
  apt remove -y golang-go >/dev/null 2>&1 || true
  rm -rf /usr/local/go

  # 获取最新版本号，失败则固定1.25.0兜底
  LATEST_GO=$(curl -s --connect-timeout 10 https://go.dev/dl/?mode=json 2>/dev/null | grep -o '"version":"go[^"]*"' | head -1 | cut -d'"' -f4)
  if [[ -z "${LATEST_GO}" ]]; then
    echo "⚠️ 获取最新版本失败，使用兜底版本 go1.25.0"
    LATEST_GO="go1.25.0"
  fi
  GO_FILE="${LATEST_GO}.linux-${GO_ARCH}.tar.gz"
  DL_URL="https://dl.google.com/go/${GO_FILE}"

  echo "正在下载: ${DL_URL}"
  wget -q --connect-timeout 15 "${DL_URL}" -O "/tmp/${GO_FILE}"
  tar -C /usr/local -xzf "/tmp/${GO_FILE}"
  rm -f "/tmp/${GO_FILE}"

  # 写入全局环境变量
  echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
  export PATH="/usr/local/go/bin:$PATH"
  echo "✅ ${LATEST_GO} 安装完成！"
fi

# ---- 校验最低版本要求 ----
GO_VER=$(go version | awk '{print $3}' | sed 's/go//')
MIN_VER="1.21.0"
if ! printf '%s\n%s\n' "$MIN_VER" "$GO_VER" | sort -V -C; then
  echo "ERROR: 当前Go版本 go${GO_VER}，本项目最低要求 Go 1.21！"
  exit 1
fi
echo "✅ 检测到有效 Go 版本: go${GO_VER}"

# ---- 1. 构建前端（强制，不复用旧产物） ----
echo "[1/5] 构建前端..."
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "  未检测到 Node.js，尝试自动安装..."
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y nodejs npm >/dev/null 2>&1 || {
    echo "Node.js 安装失败，无法构建前端";
    exit 1;
  }
fi
cd "$SRC/web"
npm ci >/dev/null 2>&1 || npm install >/dev/null 2>&1
npm run build
cd "$SRC"

# ---- 2. 编译后端程序 ----
echo "[2/5] 编译程序..."
go build -o go-farm-bot .
BIN="$SRC/go-farm-bot"
echo "✅ 后端编译完成"

# ---- 3. 安装程序 + 图片素材 ----
echo "[3/5] 安装程序与素材到 $DES ..."
sudo mkdir -p "$DES"
sudo cp -rf "$BIN" "$SRC/game-config" "$DES/"
sudo chmod +x "$DES/go-farm-bot"

# ---- 4. 注册系统服务 ----
echo "[4/5] 注册并启动系统服务..."
sudo tee /etc/systemd/system/go-farm-bot.service >/dev/null <<'SVC'
[Unit]
Description=QQ Farm Bot Go
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/opt/go-farm-bot
ExecStart=/opt/go-farm-bot/go-farm-bot
Environment=ADMIN_PORT=3009
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
SVC
sudo systemctl daemon-reload
sudo systemctl enable --now go-farm-bot

# ---- 5. 完成 ----
echo "[5/5] 部署完成！"
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "访问地址: http://${IP:-<服务器IP>}:3009"
echo ""
echo "提示: 后续更新运行："
echo "sudo env PATH=\"/usr/local/go/bin:\$PATH\" bash install.sh"
#!/usr/bin/env bash
# ============================================================
#  QQ Farm Bot GO 一键部署脚本（优化版）
#
#  用法:  sudo bash install.sh
#
#  脚本会自动完成:
#    1. 构建前端（保证 embed 进二进制的是仓库当前版本，杜绝旧 dist 导致的样式丢失）
#    2. 编译后端程序
#    3. 安装到 /opt/go-farm-bot（自动带上 game-config 图片素材）
#    4. 注册并启动 systemd 服务
#    5. 打印访问地址
#  用户无需配置任何东西，部署完即可使用。
# ============================================================
set -e

# ==========【核心优化：强制优先加载手动安装的Go】==========
export PATH="/usr/local/go/bin:$PATH"
# ==========================================================

cd "$(dirname "$0")"
SRC="$(pwd)"
DES=/opt/go-farm-bot

echo "=========================================="
echo " QQ Farm Bot GO 一键部署【优化版】"
echo "=========================================="

# ---- 校验Go环境 & 最低版本要求 ----
GO_CMD=$(command -v go || true)
if [[ -z "${GO_CMD}" ]]; then
  echo "ERROR: 未检测到 Go，请先手动安装 Go 1.21 及以上版本！"
  exit 1
fi

GO_VER=$(go version | awk '{print $3}' | sed 's/go//')
MIN_VER="1.21.0"
if ! printf '%s\n%s\n' "$MIN_VER" "$GO_VER" | sort -V -C; then
  echo "ERROR: 当前Go版本 go${GO_VER}，本项目最低要求 Go 1.21！"
  exit 1
fi
echo "✅ 检测到有效 Go 版本: go${GO_VER}"

# ---- 1. 构建前端（强制，不复用旧产物） ----
echo "[1/5] 构建前端..."
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "  未检测到 Node.js，尝试自动安装..."
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y nodejs npm >/dev/null 2>&1 || {
    echo "Node.js 安装失败，无法构建前端";
    exit 1;
  }
fi
cd "$SRC/web"
npm ci >/dev/null 2>&1 || npm install >/dev/null 2>&1
npm run build
cd "$SRC"

# ---- 2. 编译后端程序（每次都重新编译，确保 embed 的就是刚构建的前端） ----
echo "[2/5] 编译程序..."
go build -o go-farm-bot .
BIN="$SRC/go-farm-bot"
echo "✅ 后端编译完成"

# ---- 3. 安装程序 + 图片素材 ----
echo "[3/5] 安装程序与素材到 $DES ..."
sudo mkdir -p "$DES"
sudo cp -rf "$BIN" "$SRC/game-config" "$DES/"
sudo chmod +x "$DES/go-farm-bot"

# ---- 4. 注册系统服务 ----
echo "[4/5] 注册并启动系统服务..."
sudo tee /etc/systemd/system/go-farm-bot.service >/dev/null <<'SVC'
[Unit]
Description=QQ Farm Bot Go
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/opt/go-farm-bot
ExecStart=/opt/go-farm-bot/go-farm-bot
Environment=ADMIN_PORT=3009
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
SVC
sudo systemctl daemon-reload
sudo systemctl enable --now go-farm-bot

# ---- 5. 完成 ----
echo "[5/5] 部署完成！"
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "访问地址: http://${IP:-<服务器IP>}:3009"
echo ""
echo "提示: 后续更新可重新运行  sudo bash install.sh "
