#!/bin/bash
# Zivpn UDP Module installer
# Creator Zahid Islam
# Extended by: Multi-VPS Panel + Telegram Bot Support

# ─────────────────────────────────────────────
#   COLOR
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────
#   CEK ROOT
# ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Script ini harus dijalankan sebagai root!${NC}"
    exit 1
fi

# ─────────────────────────────────────────────
#   CEK OS (Debian / Ubuntu only)
# ─────────────────────────────────────────────
OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
OS_VER=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    echo -e "${RED}OS tidak didukung. Hanya Debian dan Ubuntu.${NC}"
    exit 1
fi

echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════╗"
echo "║      ZIVPN UDP INSTALLER v1.4.9        ║"
echo "║   Multi-VPS + Telegram Bot Edition     ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# ─────────────────────────────────────────────
#   UPDATE & INSTALL DEPS
# ─────────────────────────────────────────────
echo -e "${YELLOW}[1/8] Updating server...${NC}"
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget openssl iptables ufw python3 python3-pip sqlite3 net-tools jq

# ─────────────────────────────────────────────
#   STOP SERVICE LAMA
# ─────────────────────────────────────────────
systemctl stop zivpn.service 1>/dev/null 2>/dev/null

# ─────────────────────────────────────────────
#   DOWNLOAD ZIVPN BINARY
# ─────────────────────────────────────────────
echo -e "${YELLOW}[2/8] Downloading UDP Service...${NC}"
wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
    -O /usr/local/bin/zivpn 1>/dev/null 2>/dev/null
chmod +x /usr/local/bin/zivpn
mkdir -p /etc/zivpn
wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json \
    -O /etc/zivpn/config.json 1>/dev/null 2>/dev/null

# ─────────────────────────────────────────────
#   GENERATE CERT
# ─────────────────────────────────────────────
echo -e "${YELLOW}[3/8] Generating cert files...${NC}"
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" \
    -out "/etc/zivpn/zivpn.crt"

# ─────────────────────────────────────────────
#   SYSCTL TUNING
# ─────────────────────────────────────────────
echo -e "${YELLOW}[4/8] Tuning network...${NC}"
sysctl -w net.core.rmem_max=16777216 1>/dev/null 2>/dev/null
sysctl -w net.core.wmem_max=16777216 1>/dev/null 2>/dev/null
sysctl -w net.core.netdev_max_backlog=5000 1>/dev/null 2>/dev/null
sysctl -w net.ipv4.udp_mem="65536 131072 262144" 1>/dev/null 2>/dev/null

# Persist sysctl
cat > /etc/sysctl.d/99-zivpn.conf <<EOF
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.netdev_max_backlog=5000
net.ipv4.udp_mem=65536 131072 262144
EOF

# ─────────────────────────────────────────────
#   SYSTEMD SERVICE
# ─────────────────────────────────────────────
echo -e "${YELLOW}[5/8] Creating systemd service...${NC}"
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

# ─────────────────────────────────────────────
#   INPUT PASSWORD
# ─────────────────────────────────────────────
echo -e "${YELLOW}[6/8] Configuring passwords...${NC}"
echo -e "${CYAN}ZIVPN UDP Passwords${NC}"
read -p "Enter passwords separated by commas, example: pass1,pass2 (Press enter for Default 'zi'): " input_config

if [ -n "$input_config" ]; then
    IFS=',' read -r -a config <<< "$input_config"
    if [ ${#config[@]} -eq 1 ]; then
        config+=("${config[0]}")
    fi
else
    config=("zi")
fi

new_config_str="\"config\": [$(printf "\"%s\"," "${config[@]}" | sed 's/,$//')]"
sed -i -E "s/\"config\": *\[.*\]/${new_config_str}/g" /etc/zivpn/config.json

# ─────────────────────────────────────────────
#   START SERVICE
# ─────────────────────────────────────────────
echo -e "${YELLOW}[7/8] Starting ZiVPN service...${NC}"
systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service

# ─────────────────────────────────────────────
#   FIREWALL / IPTABLES
# ─────────────────────────────────────────────
NET_IF=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -A PREROUTING -i "$NET_IF" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
ufw allow 6000:19999/udp
ufw allow 5667/udp
ufw allow 22/tcp
ufw allow 2053/tcp
echo "y" | ufw enable

# ─────────────────────────────────────────────
#   BUAT DIREKTORI PANEL
# ─────────────────────────────────────────────
mkdir -p /etc/zivpn-panel
mkdir -p /etc/zivpn-panel/backups

# ─────────────────────────────────────────────
#   INIT DATABASE SQLite
# ─────────────────────────────────────────────
echo -e "${YELLOW}[8/8] Initializing database...${NC}"
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
INSERT OR IGNORE INTO settings VALUES ('price_1day','3000');
INSERT OR IGNORE INTO settings VALUES ('price_7day','15000');
INSERT OR IGNORE INTO settings VALUES ('price_30day','50000');
INSERT OR IGNORE INTO settings VALUES ('qris_image','');
INSERT OR IGNORE INTO settings VALUES ('admin_id','');
INSERT OR IGNORE INTO settings VALUES ('bot_token','');
SQLEOF

# ─────────────────────────────────────────────
#   SIMPAN INFO VPS
# ─────────────────────────────────────────────
VPS_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
VPS_ID="vps_$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"

sqlite3 /etc/zivpn-panel/users.db \
    "INSERT OR REPLACE INTO servers (id, name, ip, port, api_port, location, status) \
     VALUES ('$VPS_ID', '$(hostname)', '$VPS_IP', 5667, 2053, 'Auto Detect', 'active');"

# Simpan info ke file config
cat > /etc/zivpn-panel/panel.conf <<EOF
VPS_ID=$VPS_ID
VPS_IP=$VPS_IP
VPS_HOSTNAME=$(hostname)
INSTALL_DATE=$(date +%Y-%m-%d)
EOF

# ─────────────────────────────────────────────
#   SALIN SCRIPT MANAGER
# ─────────────────────────────────────────────
cp /root/zivpn-manager.sh /usr/local/bin/zivpn-manager 2>/dev/null || true
chmod +x /usr/local/bin/zivpn-manager 2>/dev/null || true

# ─────────────────────────────────────────────
#   INSTALL PYTHON BOT DEPENDENCIES
# ─────────────────────────────────────────────
pip3 install python-telegram-bot==20.7 aiohttp requests --break-system-packages 2>/dev/null || \
pip3 install python-telegram-bot==20.7 aiohttp requests 2>/dev/null

# ─────────────────────────────────────────────
#   CLEANUP
# ─────────────────────────────────────────────
rm -f zi.* 2>/dev/null

# ─────────────────────────────────────────────
#   DONE
# ─────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}"
echo "╔════════════════════════════════════════╗"
echo "║       ZIVPN UDP INSTALLED ✓            ║"
echo "╠════════════════════════════════════════╣"
printf "║  VPS ID   : %-27s║\n" "$VPS_ID"
printf "║  IP       : %-27s║\n" "$VPS_IP"
echo "║  Port     : 5667 (UDP)                 ║"
echo "║  Range    : 6000-19999 (UDP)           ║"
echo "╠════════════════════════════════════════╣"
echo "║  Panel    : zivpn-manager              ║"
echo "║  Bot      : setup-bot.sh               ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${CYAN}Jalankan ${BOLD}bash setup-bot.sh${NC}${CYAN} untuk install Telegram Bot${NC}"
echo -e "${CYAN}Jalankan ${BOLD}zivpn-manager${NC}${CYAN} untuk panel manajemen akun${NC}"
