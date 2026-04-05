#!/bin/bash
# Zivpn UDP Module installer
# Creator Zahid Islam
# Extended: Multi-VPS + Telegram Bot + Auto Install

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
LINE='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Script harus dijalankan sebagai root!${NC}"; exit 1
fi

OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    echo -e "${RED}OS tidak didukung. Hanya Debian dan Ubuntu.${NC}"; exit 1
fi

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║      ZIVPN UDP INSTALLER v1.4.9          ║"
echo "║   Multi-VPS + Telegram Bot Edition       ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── [1/8] UPDATE ──────────────────────────────────────
echo -e "${YELLOW}${BOLD}[1/8] Updating server...${NC}"
echo -e "${CYAN}${LINE}${NC}"
apt-get update -y -q && apt-get upgrade -y -q
apt-get install -y -q curl wget openssl iptables ufw python3 python3-pip sqlite3 net-tools jq
echo -e "${GREEN}✓ Update selesai${NC}\n"

# ── [2/8] STOP SERVICE LAMA ───────────────────────────
systemctl stop zivpn.service 1>/dev/null 2>/dev/null

# ── [3/8] DOWNLOAD BINARY ─────────────────────────────
echo -e "${YELLOW}${BOLD}[2/8] Downloading ZiVPN binary...${NC}"
echo -e "${CYAN}${LINE}${NC}"
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
    -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn
mkdir -p /etc/zivpn
wget -q https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json \
    -O /etc/zivpn/config.json
echo -e "${GREEN}✓ Binary downloaded${NC}\n"

# ── [4/8] GENERATE CERT ───────────────────────────────
echo -e "${YELLOW}${BOLD}[3/8] Generating SSL certificate...${NC}"
echo -e "${CYAN}${LINE}${NC}"
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" \
    -out "/etc/zivpn/zivpn.crt" 2>/dev/null
echo -e "${GREEN}✓ Certificate generated${NC}\n"

# ── [5/8] SYSCTL TUNING ───────────────────────────────
echo -e "${YELLOW}${BOLD}[4/8] Tuning network performance...${NC}"
echo -e "${CYAN}${LINE}${NC}"
sysctl -w net.core.rmem_max=16777216 1>/dev/null 2>/dev/null
sysctl -w net.core.wmem_max=16777216 1>/dev/null 2>/dev/null
sysctl -w net.core.netdev_max_backlog=5000 1>/dev/null 2>/dev/null
cat > /etc/sysctl.d/99-zivpn.conf <<EOF
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.netdev_max_backlog=5000
EOF
sysctl -p /etc/sysctl.d/99-zivpn.conf 1>/dev/null 2>/dev/null
echo -e "${GREEN}✓ Network tuning done${NC}\n"

# ── [6/8] SYSTEMD SERVICE ─────────────────────────────
echo -e "${YELLOW}${BOLD}[5/8] Creating systemd service...${NC}"
echo -e "${CYAN}${LINE}${NC}"
cat > /etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}✓ Service created${NC}\n"

# ── [6/8] CONFIG PASSWORD AUTO DEFAULT ────────────────
echo -e "${YELLOW}${BOLD}[6/8] Configuring ZiVPN...${NC}"
echo -e "${CYAN}${LINE}${NC}"
python3 -c "
import json
try:
    with open('/etc/zivpn/config.json') as f:
        d = json.load(f)
except:
    d = {}
d['config'] = ['zi']
with open('/etc/zivpn/config.json','w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null
echo -e "${GREEN}✓ Default password: zi${NC}\n"

# ── INIT DATABASE ─────────────────────────────────────
mkdir -p /etc/zivpn-panel/backups
sqlite3 /etc/zivpn-panel/users.db <<SQLEOF
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

# ── SIMPAN INFO VPS ───────────────────────────────────
VPS_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
VPS_ID="vps_$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
VPS_HOSTNAME=$(hostname)

sqlite3 /etc/zivpn-panel/users.db \
    "INSERT OR REPLACE INTO servers (id, name, ip, port, location, status) \
     VALUES ('$VPS_ID','$VPS_HOSTNAME','$VPS_IP',5667,'Auto Detect','active');"

cat > /etc/zivpn-panel/panel.conf <<EOF
VPS_ID=$VPS_ID
VPS_IP=$VPS_IP
VPS_HOSTNAME=$VPS_HOSTNAME
INSTALL_DATE=$(date +%Y-%m-%d)
EOF

# ── [7/8] START SERVICE & FIREWALL ────────────────────
echo -e "${YELLOW}${BOLD}[7/8] Starting services & firewall...${NC}"
echo -e "${CYAN}${LINE}${NC}"
systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service

NET_IF=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -D PREROUTING -i "$NET_IF" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null
iptables -t nat -A PREROUTING -i "$NET_IF" -p udp --dport 6000:19999 -j DNAT --to-destination :5667

ufw allow 22/tcp         1>/dev/null 2>/dev/null
ufw allow 5667/udp       1>/dev/null 2>/dev/null
ufw allow 6000:19999/udp 1>/dev/null 2>/dev/null
ufw allow 2053/tcp       1>/dev/null 2>/dev/null
echo "y" | ufw enable    1>/dev/null 2>/dev/null
echo -e "${GREEN}✓ Service & firewall OK${NC}\n"

# ── [8/8] INSTALL MANAGER ─────────────────────────────
echo -e "${YELLOW}${BOLD}[8/8] Installing panel manager...${NC}"
echo -e "${CYAN}${LINE}${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/zivpn-manager.sh" /usr/local/bin/zivpn-manager
chmod +x /usr/local/bin/zivpn-manager

pip3 install python-telegram-bot==20.7 aiohttp -q --break-system-packages 2>/dev/null || \
pip3 install python-telegram-bot==20.7 aiohttp -q 2>/dev/null
echo -e "${GREEN}✓ Panel manager installed${NC}\n"

sleep 2
ZIVPN_STATUS=$(systemctl is-active zivpn.service)

rm -f zi.* 2>/dev/null

clear
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║       ✓  ZIVPN UDP INSTALLED             ║"
echo "╠══════════════════════════════════════════╣"
printf "║  VPS ID   : %-29s║\n" "$VPS_ID"
printf "║  IP       : %-29s║\n" "$VPS_IP"
printf "║  ZiVPN    : %-29s║\n" "$ZIVPN_STATUS"
echo "║  Port UDP : 5667                         ║"
echo "║  Range    : 6000-19999                   ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Harga 15 Hari : Rp 5.000               ║"
echo "║  Harga 30 Hari : Rp 10.000              ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Panel CLI  : zivpn-manager              ║"
echo "║  Setup Bot  : bash setup-bot.sh          ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
