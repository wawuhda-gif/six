#!/bin/bash
# setup-bot.sh - Auto installer Telegram Bot ZiVPN
# Fixed Edition

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
LINE='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Harus dijalankan sebagai root!${NC}"; exit 1
fi

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║      ZIVPN TELEGRAM BOT INSTALLER        ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── [1/4] INSTALL DEPS ────────────────────────────────
echo -e "${YELLOW}${BOLD}[1/4] Installing Python dependencies...${NC}"
echo -e "${CYAN}${LINE}${NC}"
apt-get install -y -q python3 python3-pip sqlite3 2>/dev/null
pip3 install python-telegram-bot==20.7 aiohttp -q --break-system-packages 2>/dev/null || \
pip3 install python-telegram-bot==20.7 aiohttp -q 2>/dev/null
echo -e "${GREEN}✓ Dependencies OK${NC}\n"

# ── [2/4] SALIN BOT.PY ───────────────────────────────
echo -e "${YELLOW}${BOLD}[2/4] Installing bot files...${NC}"
echo -e "${CYAN}${LINE}${NC}"
mkdir -p /etc/zivpn-panel

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/bot.py" ]]; then
    cp "$SCRIPT_DIR/bot.py" /etc/zivpn-panel/bot.py
elif [[ -f "/root/bot.py" ]]; then
    cp /root/bot.py /etc/zivpn-panel/bot.py
else
    echo -e "${RED}bot.py tidak ditemukan!${NC}"; exit 1
fi
echo -e "${GREEN}✓ Bot file copied${NC}\n"

# ── [3/4] INPUT CONFIG ───────────────────────────────
echo -e "${YELLOW}${BOLD}[3/4] Konfigurasi Bot...${NC}"
echo -e "${CYAN}${LINE}${NC}"
echo ""
read -p "  Masukkan BOT TOKEN dari @BotFather : " BOT_TOKEN
echo -e "  ${CYAN}${LINE}${NC}"
read -p "  Masukkan Telegram ID Admin Anda    : " ADMIN_ID
echo -e "  ${CYAN}${LINE}${NC}"
echo ""

if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
    echo -e "${RED}Token dan Admin ID tidak boleh kosong!${NC}"; exit 1
fi

DB="/etc/zivpn-panel/users.db"

# Init DB jika belum ada
if [[ ! -f "$DB" ]]; then
    sqlite3 "$DB" <<SQLEOF
CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    max_login INTEGER DEFAULT 2,
    active_sessions INTEGER DEFAULT 0,
    expired_date TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    created_by TEXT DEFAULT 'admin',
    server_id TEXT DEFAULT 'vps1',
    status TEXT DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS servers (
    id TEXT PRIMARY KEY,
    name TEXT,
    ip TEXT,
    port INTEGER DEFAULT 5667,
    api_port INTEGER DEFAULT 2053,
    api_key TEXT,
    location TEXT,
    status TEXT DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS resellers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    telegram_id TEXT UNIQUE,
    username TEXT,
    balance REAL DEFAULT 0,
    active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
);
INSERT OR IGNORE INTO settings VALUES ('price_15day','5000');
INSERT OR IGNORE INTO settings VALUES ('price_30day','10000');
INSERT OR IGNORE INTO settings VALUES ('qris_image','');
INSERT OR IGNORE INTO settings VALUES ('admin_id','');
INSERT OR IGNORE INTO settings VALUES ('bot_token','');
SQLEOF
fi

sqlite3 "$DB" "INSERT OR REPLACE INTO settings VALUES ('bot_token','$BOT_TOKEN');"
sqlite3 "$DB" "INSERT OR REPLACE INTO settings VALUES ('admin_id','$ADMIN_ID');"
echo -e "${GREEN}✓ Konfigurasi disimpan${NC}\n"

# ── [4/4] SYSTEMD SERVICE ────────────────────────────
echo -e "${YELLOW}${BOLD}[4/4] Creating bot service...${NC}"
echo -e "${CYAN}${LINE}${NC}"

# Stop dulu jika sudah running
systemctl stop zivpn-bot.service 2>/dev/null

cat > /etc/systemd/system/zivpn-bot.service <<EOF
[Unit]
Description=ZiVPN Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn-panel
ExecStart=/usr/bin/python3 /etc/zivpn-panel/bot.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn-bot.service
systemctl start zivpn-bot.service

echo -e "${GREEN}✓ Service created & started${NC}\n"

# Tunggu bot ready
sleep 3

# Cek status
if systemctl is-active --quiet zivpn-bot.service; then
    BOT_STATUS="${GREEN}${BOLD}● RUNNING ✓${NC}"
    BOT_MSG="Bot berhasil berjalan!"
else
    BOT_STATUS="${RED}${BOLD}● FAILED ✗${NC}"
    BOT_MSG="Cek log: journalctl -u zivpn-bot -n 20"
fi

clear
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║       TELEGRAM BOT INSTALLER SELESAI     ║"
echo "╠══════════════════════════════════════════╣"
printf "║  %-44s║\n" ""
echo "  ╠══════════════════════════════════════════╣"
printf "║  Status Bot  : %-29s║\n" ""
echo "╠══════════════════════════════════════════╣"
echo "║  Perintah berguna:                       ║"
echo "╠══════════════════════════════════════════╣"
printf "║  %-44s║\n" "Cek log : journalctl -u zivpn-bot -f"
printf "║  %-44s║\n" "Restart : systemctl restart zivpn-bot"
printf "║  %-44s║\n" "Stop    : systemctl stop zivpn-bot"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

echo -ne "  Status Bot  : "; echo -e "$BOT_STATUS"
echo ""
echo -e "${CYAN}${LINE}${NC}"
echo -e "${CYAN}$BOT_MSG${NC}"
echo -e "${CYAN}${LINE}${NC}"
echo -e "${CYAN}Buka Telegram → ketik /start di bot Anda!${NC}"
echo -e "${CYAN}${LINE}${NC}"
echo ""
echo -e "${YELLOW}Tip: Ketik ${BOLD}zivpn-manager${NC}${YELLOW} untuk panel CLI${NC}"
echo -e "${CYAN}${LINE}${NC}"
