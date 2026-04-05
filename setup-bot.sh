#!/bin/bash
# setup-bot.sh - Auto installer Telegram Bot ZiVPN
# Untuk Debian & Ubuntu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Harus dijalankan sebagai root!${NC}"; exit 1
fi

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║      ZIVPN TELEGRAM BOT INSTALLER        ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─── INSTALL PYTHON DEPS ──────────────────────────────
echo -e "${YELLOW}[1/4] Installing Python dependencies...${NC}"
apt-get install -y python3 python3-pip sqlite3 2>/dev/null

pip3 install python-telegram-bot==20.7 aiohttp --break-system-packages 2>/dev/null || \
pip3 install python-telegram-bot==20.7 aiohttp 2>/dev/null

# ─── SALIN BOT.PY ────────────────────────────────────
echo -e "${YELLOW}[2/4] Installing bot files...${NC}"
mkdir -p /etc/zivpn-panel
cp /root/bot.py /etc/zivpn-panel/bot.py 2>/dev/null || \
    { echo -e "${RED}bot.py tidak ditemukan di /root/!${NC}"; exit 1; }

# ─── INPUT TOKEN & ADMIN ID ──────────────────────────
echo -e "${YELLOW}[3/4] Konfigurasi Bot...${NC}"
echo ""
read -p " Masukkan BOT TOKEN dari @BotFather : " BOT_TOKEN
read -p " Masukkan Telegram ID Admin Anda    : " ADMIN_ID

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
INSERT OR IGNORE INTO settings VALUES ('price_1day','3000');
INSERT OR IGNORE INTO settings VALUES ('price_7day','15000');
INSERT OR IGNORE INTO settings VALUES ('price_30day','50000');
INSERT OR IGNORE INTO settings VALUES ('qris_image','');
INSERT OR IGNORE INTO settings VALUES ('admin_id','');
INSERT OR IGNORE INTO settings VALUES ('bot_token','');
SQLEOF
fi

# Set token & admin
sqlite3 "$DB" "INSERT OR REPLACE INTO settings VALUES ('bot_token','$BOT_TOKEN');"
sqlite3 "$DB" "INSERT OR REPLACE INTO settings VALUES ('admin_id','$ADMIN_ID');"

# ─── BUAT SYSTEMD SERVICE UNTUK BOT ──────────────────
echo -e "${YELLOW}[4/4] Creating bot service...${NC}"
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

sleep 2

# ─── CEK STATUS ──────────────────────────────────────
if systemctl is-active --quiet zivpn-bot.service; then
    STATUS="${GREEN}${BOLD}● RUNNING${NC}"
else
    STATUS="${RED}${BOLD}● FAILED${NC}"
    echo -e "${RED}Bot gagal start. Cek log: journalctl -u zivpn-bot -n 20${NC}"
fi

echo -e "\n${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║      BOT TELEGRAM BERHASIL DIINSTALL     ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Status  : %-31s║\n" ""
echo "╠══════════════════════════════════════════╣"
echo "║  Perintah berguna:                       ║"
echo "║  • Cek log  : journalctl -u zivpn-bot -f ║"
echo "║  • Restart  : systemctl restart zivpn-bot║"
echo "║  • Stop     : systemctl stop zivpn-bot   ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${CYAN}Buka Telegram dan ketik /start di bot Anda!${NC}"
echo ""
echo -e "${YELLOW}Tip: Jalankan ${BOLD}zivpn-manager${NC}${YELLOW} untuk panel CLI${NC}"
