#!/bin/bash
# ════════════════════════════════════════════════════════════
#   MAX PANEL — Premium VPS Tunneling Panel
#   Creator : MAX Team
#   Ketik   : menu-max  untuk membuka panel
#   Support : Debian (all) & Ubuntu (all)
#   Repo    : https://github.com/chanelog/max
# ════════════════════════════════════════════════════════════
#
#   Protokol terinstall:
#     • OpenSSH (22)                • Dropbear (109/143)
#     • Stunnel SSL (990/446/110/444)
#     • WebSocket SSH/V2Ray via Nginx
#         - Non-TLS: 80, 8080, 2086, 8880
#         - TLS    : 443, 2083, 2087, 8443
#     • OpenVPN (TCP 1194 / UDP 2200)
#     • Xray-core VMess/VLess/Trojan + Shadowsocks (8388)
#     • Trojan-Go (2096)           • BadVPN UDPGW (7100/7200/7300)
#     • Hysteria 2 (5300/7300/36712)
#     • SlowDNS (53 / 5300)        • WireGuard (51820)
#     • OHP (8081) — opsional
#
# ════════════════════════════════════════════════════════════

# ── CEK ROOT ─────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n\033[1;31m  ✘  Jalankan sebagai root!\033[0m\n"
        exit 1
    fi
}

# ── CEK OS — HANYA DEBIAN & UBUNTU ─────────────────────────────────────────────────────────
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "\n\033[1;31m  ✘  OS tidak dikenali! Script ini hanya untuk Debian & Ubuntu.\033[0m\n"
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null
    local os_name os_like
    os_name=$(echo "${ID}" | tr '[:upper:]' '[:lower:]')
    os_like=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')

    if [[ "$os_name" != "debian" && "$os_name" != "ubuntu" ]] \
       && [[ "$os_like" != *"debian"* && "$os_like" != *"ubuntu"* ]]; then
        echo ""
        echo -e "\033[1;31m  ─────────────────────────────────────────────────────────\033[0m"
        echo -e "  ✘  OS TIDAK DIDUKUNG!"
        echo -e "  OS kamu : \033[1;33m${PRETTY_NAME:-$ID}\033[0m"
        echo -e "  Script ini hanya mendukung:"
        echo -e "  \033[1;32m✔\033[0m  Debian (semua versi)"
        echo -e "  \033[1;32m✔\033[0m  Ubuntu (semua versi)"
        echo -e "\033[1;31m  ─────────────────────────────────────────────────────────\033[0m"
        echo ""
        exit 1
    fi

    OS_NAME="${PRETTY_NAME:-$ID $VERSION_ID}"
    OS_ID="$os_name"
    export OS_NAME OS_ID
}

# ════════════════════════════════════════════════════════════
#  KONSTANTA & PATH — Hindari bentrok dengan ogh-ziv
# ════════════════════════════════════════════════════════════
DIR="/etc/maxpanel"
LOGDIR="/var/log/maxpanel"
BACKUPDIR="/root/maxpanel-backup"

# Config & DB
THEMEF="$DIR/theme.conf"
DOMF="$DIR/domain.conf"
BOTF="$DIR/bot.conf"
STRF="$DIR/store.conf"
MLDB="$DIR/maxlogin.db"      # format: username|maxdevice
LIMITF="$DIR/limit.conf"     # max total user
VERSIONF="$DIR/version.txt"
TG_TMP="/tmp/maxpanel-tg"    # working dir untuk file Telegram (config/backup)
TG_UPD_OFFSET="$DIR/tg-upd-offset"  # offset getUpdates terakhir

# User databases per protokol
SSH_DB="$DIR/ssh-users.db"           # user|pass|exp|maxlogin
VMESS_DB="$DIR/vmess-users.db"       # user|uuid|exp|maxlogin
VLESS_DB="$DIR/vless-users.db"       # user|uuid|exp|maxlogin
TROJAN_DB="$DIR/trojan-users.db"     # user|password|exp|maxlogin
TROJANGO_DB="$DIR/trojango-users.db" # user|password|exp|maxlogin
OVPN_DB="$DIR/openvpn-users.db"      # user|pass|exp|maxlogin
WG_DB="$DIR/wireguard-users.db"      # user|pubkey|privkey|ip|exp|maxlogin
HY_DB="$DIR/hysteria-users.db"       # user|password|exp|maxlogin
SS_DB="$DIR/ss-users.db"             # user|password|exp|maxlogin
SLOW_DB="$DIR/slowdns-users.db"      # user|pass|exp|maxlogin

# Path config service
XRAY_CFG="/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CRT="/etc/xray/xray.crt"
XRAY_KEY="/etc/xray/xray.key"
XRAY_LOG="/var/log/xray/access.log"

TROJANGO_DIR="/etc/trojan-go"
TROJANGO_CFG="$TROJANGO_DIR/config.json"
TROJANGO_BIN="/usr/local/bin/trojan-go"

HY_DIR="/etc/hysteria"
HY_CFG="$HY_DIR/config.yaml"
HY_BIN="/usr/local/bin/hysteria"

WG_DIR="/etc/wireguard"
WG_CFG="$WG_DIR/wg0.conf"
WG_CLIENT_DIR="$DIR/wg-clients"

SLOW_DIR="/etc/slowdns"
SLOW_BIN="/usr/local/bin/sldns-server"

UDPGW_BIN="/usr/local/bin/badvpn-udpgw"
WS_DIR="/etc/maxpanel/ws"
WS_BIN="/usr/local/bin/ws-max"
OHP_BIN="/usr/local/bin/ohpserver"

# URLs binary
XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64"
TROJAN_GO_URL="https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip"
UDPGW_URL="https://raw.githubusercontent.com/chanelog/max/main/udpgw"
SLOWDNS_URL="https://raw.githubusercontent.com/khaledagn/AGN-UDP/main/sldns-server"
OHP_URL="https://github.com/nopnopro/script/raw/master/file/ohpserver"

SCRIPT_VERSION="1.8"
SCRIPT_URL="https://raw.githubusercontent.com/chanelog/max/main/setup-max.sh"
VERSION_URL="https://raw.githubusercontent.com/chanelog/max/main/version-max.txt"

# ════════════════════════════════════════════════════════════
#  TEMA — 15 PREMIUM (struktur identik dengan ogh-ziv)
# ════════════════════════════════════════════════════════════
load_theme() {
    local theme=1
    [[ -f "$THEMEF" ]] && theme=$(cat "$THEMEF" 2>/dev/null)

    case "$theme" in
        2)  A1='\033[38;5;51m';  A2='\033[1;36m';        A3='\033[0;36m'
            A4='\033[38;5;123m'; AL='\033[38;5;87m';     AT='\033[1;37m'
            THEME_NAME="ARCTIC CYAN" ;;
        3)  A1='\033[38;5;46m';  A2='\033[1;32m';        A3='\033[38;5;40m'
            A4='\033[38;5;118m'; AL='\033[38;5;82m';     AT='\033[1;37m'
            THEME_NAME="MATRIX GREEN" ;;
        4)  A1='\033[38;5;220m'; A2='\033[38;5;226m';    A3='\033[38;5;214m'
            A4='\033[38;5;208m'; AL='\033[38;5;228m';    AT='\033[1;37m'
            THEME_NAME="ROYAL GOLD" ;;
        5)  A1='\033[38;5;196m'; A2='\033[1;31m';        A3='\033[38;5;203m'
            A4='\033[38;5;197m'; AL='\033[38;5;204m';    AT='\033[1;37m'
            THEME_NAME="CRIMSON RED" ;;
        6)  A1='\033[38;5;213m'; A2='\033[38;5;218m';    A3='\033[38;5;219m'
            A4='\033[38;5;211m'; AL='\033[38;5;225m';    AT='\033[1;37m'
            THEME_NAME="SAKURA PINK" ;;
        7)  A1='\033[1;37m';     A2='\033[1;37m';        A3='\033[38;5;51m'
            A4='\033[1;33m';     AL='\033[38;5;196m';    AT='\033[1;37m'
            THEME_NAME="RAINBOW" ;;
        8)  A1='\033[38;5;27m';  A2='\033[38;5;33m';     A3='\033[38;5;39m'
            A4='\033[38;5;45m';  AL='\033[38;5;81m';     AT='\033[1;37m'
            THEME_NAME="OCEAN BLUE" ;;
        9)  A1='\033[38;5;202m'; A2='\033[38;5;208m';    A3='\033[38;5;214m'
            A4='\033[38;5;220m'; AL='\033[38;5;215m';    AT='\033[1;37m'
            THEME_NAME="SUNSET ORANGE" ;;
        10) A1='\033[38;5;239m'; A2='\033[38;5;245m';    A3='\033[38;5;250m'
            A4='\033[38;5;153m'; AL='\033[38;5;189m';    AT='\033[1;37m'
            THEME_NAME="MIDNIGHT" ;;
        11) A1='\033[38;5;35m';  A2='\033[38;5;41m';     A3='\033[38;5;48m'
            A4='\033[38;5;85m';  AL='\033[38;5;121m';    AT='\033[1;37m'
            THEME_NAME="EMERALD" ;;
        12) A1='\033[38;5;99m';  A2='\033[38;5;105m';    A3='\033[38;5;111m'
            A4='\033[38;5;183m'; AL='\033[38;5;189m';    AT='\033[1;37m'
            THEME_NAME="LAVENDER" ;;
        13) A1='\033[38;5;210m'; A2='\033[38;5;216m';    A3='\033[38;5;222m'
            A4='\033[38;5;217m'; AL='\033[38;5;224m';    AT='\033[1;37m'
            THEME_NAME="ROSE GOLD" ;;
        14) A1='\033[38;5;195m'; A2='\033[38;5;231m';    A3='\033[38;5;159m'
            A4='\033[38;5;123m'; AL='\033[38;5;255m';    AT='\033[38;5;231m'
            THEME_NAME="ICE WHITE" ;;
        15) A1='\033[38;5;129m'; A2='\033[38;5;135m';    A3='\033[38;5;141m'
            A4='\033[38;5;201m'; AL='\033[38;5;171m';    AT='\033[1;37m'
            THEME_NAME="NEON PURPLE" ;;
        *)  A1='\033[38;5;135m'; A2='\033[1;35m';        A3='\033[38;5;141m'
            A4='\033[1;33m';     AL='\033[38;5;141m';    AT='\033[38;5;231m'
            THEME_NAME="VIOLET" ;;
    esac

    NC='\033[0m'; BLD='\033[1m'; DIM='\033[2m'; IT='\033[3m'
    W='\033[1;37m'; LG='\033[1;32m'; LR='\033[1;31m'; LC='\033[1;36m'; Y='\033[1;33m'
    export A1 A2 A3 A4 AL AT NC BLD DIM IT W LG LR LC Y THEME_NAME
}

# ════════════════════════════════════════════════════════════
#  UTILS — Helper functions
# ════════════════════════════════════════════════════════════
_DASH="───────────────────────────────────────────────────────────────"

ok()    { echo -e "  ${A2}✔${NC}  $*"; }
inf()   { echo -e "  ${A3}➜${NC}  $*"; }
warn()  { echo -e "  ${A4}⚠${NC}  $*"; }
err()   { echo -e "  \033[1;31m✘${NC}  $*"; }
pause() { echo ""; echo -ne "  ${DIM}╰─ [ Enter ] kembali ke menu...${NC}"; read -r; }

_top()  { echo -e "  ${A1}${_DASH}${NC}"; }
_bot()  { echo -e "  ${A1}${_DASH}${NC}"; }
_sep()  { echo -e "  ${A1}${_DASH}${NC}"; }
_btn()  { printf "  %b\n" "$1"; }

# ════════════════════════════════════════════════════════════
#  IDEMPOTENT CONFIG-BLOCK HELPER
# ────────────────────────────────────────────────────────────
#  _apply_block <marker> <file>  → stdin = body
#  Hapus block lama yang dibrackit `# >>> MAXPANEL-<marker> >>>`
#  / `# <<< MAXPANEL-<marker> <<<` lalu tulis ulang.
#  Aman untuk dipanggil berkali-kali (re-run installer).
# ════════════════════════════════════════════════════════════
_apply_block() {
    local marker="$1" file="$2"
    [[ -z "$marker" || -z "$file" ]] && return 1
    [[ ! -f "$file" ]] && { mkdir -p "$(dirname "$file")"; : > "$file"; }
    # Hapus block lama dengan marker yang sama (idempotent)
    sed -i "/^# >>> MAXPANEL-${marker} >>>$/,/^# <<< MAXPANEL-${marker} <<<$/d" "$file" 2>/dev/null
    # Append block baru
    {
        echo ""
        echo "# >>> MAXPANEL-${marker} >>>"
        cat
        echo "# <<< MAXPANEL-${marker} <<<"
    } >> "$file"
}

get_ip() {
    local ip
    for src in \
        "curl -s4 --max-time 5 ifconfig.me" \
        "curl -s4 --max-time 5 icanhazip.com" \
        "curl -s4 --max-time 5 api.ipify.org"
    do
        ip=$(eval "$src" 2>/dev/null | tr -d '[:space:]')
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return; }
    done
    hostname -I 2>/dev/null | awk '{print $1}'
}

get_domain() {
    if [[ -f "$DOMF" ]]; then
        cat "$DOMF" 2>/dev/null
    else
        get_ip
    fi
}

get_iface() {
    ip -4 route ls 2>/dev/null | awk '/default/ {print $5; exit}'
}

rand_pass() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12; }
rand_uuid() {
    if command -v uuidgen &>/dev/null; then uuidgen
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
    else cat /etc/maxpanel/.fallback-uuid 2>/dev/null || \
         python3 -c "import uuid;print(uuid.uuid4())" 2>/dev/null
    fi
}

# Tanggal expired (Asia/Jakarta, format YYYY-MM-DD)
mk_exp() {
    local days="${1:-30}"
    TZ="Asia/Jakarta" date -d "+${days} days" +"%Y-%m-%d"
}

# Hitung sisa hari sampai expired
days_left() {
    local exp="$1"
    local exp_ts now_ts
    exp_ts=$(TZ="Asia/Jakarta" date -d "${exp} 23:59:59" +%s 2>/dev/null || echo 0)
    now_ts=$(TZ="Asia/Jakarta" date +%s)
    local diff=$(( (exp_ts - now_ts) / 86400 ))
    [[ $diff -lt 0 ]] && diff=0
    echo "$diff"
}

# Cek expired
is_expired() {
    local exp="$1"
    local today
    today=$(TZ="Asia/Jakarta" date +%Y-%m-%d)
    [[ "$today" > "$exp" ]] && return 0 || return 1
}

# Validasi binary terdownload
verify_binary() {
    local path="$1" minsize="${2:-100000}"
    [[ ! -f "$path" ]] && return 1
    local sz; sz=$(stat -c%s "$path" 2>/dev/null || echo 0)
    [[ "$sz" -lt "$minsize" ]] && return 1
    return 0
}

# Download dengan fallback wget -> curl
dl() {
    local url="$1" out="$2"
    if wget --tries=3 --timeout=30 -q -O "$out" "$url" 2>/dev/null && [[ -s "$out" ]]; then
        return 0
    fi
    rm -f "$out" 2>/dev/null
    if curl -fsSL --retry 3 --max-time 30 -o "$out" "$url" 2>/dev/null && [[ -s "$out" ]]; then
        return 0
    fi
    rm -f "$out" 2>/dev/null
    return 1
}

# Pesan service (cek status)
is_up() {
    local svc="$1"
    systemctl is-active --quiet "$svc" 2>/dev/null
}

svc_badge() {
    local svc="$1"
    if is_up "$svc"; then printf '%b' "${LG}●${NC}"
    else                  printf '%b' "${LR}●${NC}"
    fi
}

# Hitung total user semua protokol
total_users_all() {
    local t=0 f cnt
    for f in "$SSH_DB" "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$TROJANGO_DB" \
             "$OVPN_DB" "$WG_DB" "$HY_DB" "$SS_DB" "$SLOW_DB"; do
        if [[ -f "$f" ]]; then
            cnt=$(grep -c '' "$f" 2>/dev/null)
            cnt="${cnt//[[:space:]]/}"
            [[ "$cnt" =~ ^[0-9]+$ ]] && t=$(( t + cnt ))
        fi
    done
    echo "$t"
}

# Hitung expired users
exp_users_all() {
    local t=0 f td
    td=$(TZ="Asia/Jakarta" date +%Y-%m-%d)
    for f in "$SSH_DB" "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$TROJANGO_DB" \
             "$OVPN_DB" "$WG_DB" "$HY_DB" "$SS_DB" "$SLOW_DB"; do
        [[ -f "$f" ]] || continue
        t=$(( t + $(awk -F'|' -v d="$td" '$3<d{c++}END{print c+0}' "$f" 2>/dev/null) ))
    done
    echo "$t"
}

# ════════════════════════════════════════════════════════════
#  MAXLOGIN HELPERS
# ════════════════════════════════════════════════════════════
get_maxlogin() {
    local u="$1"
    grep "^${u}|" "$MLDB" 2>/dev/null | cut -d'|' -f2 | head -1
}

set_maxlogin() {
    local u="$1" ml="$2"
    mkdir -p "$DIR"
    touch "$MLDB"
    sed -i "/^${u}|/d" "$MLDB" 2>/dev/null
    echo "${u}|${ml}" >> "$MLDB"
}

del_maxlogin() {
    local u="$1"
    sed -i "/^${u}|/d" "$MLDB" 2>/dev/null
}

# ════════════════════════════════════════════════════════════
#  TELEGRAM HELPER
# ════════════════════════════════════════════════════════════
# Load BOT_TOKEN/CHAT_ID dari $BOTF. Return 0 kalau lengkap, 1 kalau belum di-setup.
_tg_load() {
    [[ ! -f "$BOTF" ]] && return 1
    # shellcheck disable=SC1090
    source "$BOTF" 2>/dev/null
    [[ -n "${BOT_TOKEN:-}" && -n "${CHAT_ID:-}" ]] || return 1
    return 0
}

# Pesan HTML ke chat default. Aman dipanggil walau bot belum di-setup.
tg_send_text() {
    _tg_load || return 0
    local msg="$1"
    curl -s --max-time 20 -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${msg}" \
        -d "parse_mode=HTML" \
        -d "disable_web_page_preview=true" &>/dev/null
}

# Kirim file sebagai document, optional HTML caption.
tg_send_file() {
    _tg_load || return 0
    local file="$1" caption="${2:-}"
    [[ ! -s "$file" ]] && return 1
    if [[ -n "$caption" ]]; then
        curl -s --max-time 120 -X POST \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${file}" \
            -F "caption=${caption}" \
            -F "parse_mode=HTML" &>/dev/null
    else
        curl -s --max-time 120 -X POST \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${file}" &>/dev/null
    fi
}

# Compat alias — script existing memanggil _tg_send.
_tg_send() { tg_send_text "$@"; }

# Notifikasi akun: TYPE, HTML_BODY, [config_file...] (sampai 4 attachment)
tg_notify_account() {
    local type="$1" body="$2"; shift 2
    _tg_load || return 0
    tg_send_text "$body"
    local f
    for f in "$@"; do
        [[ -n "$f" && -s "$f" ]] && tg_send_file "$f" "<b>${type}</b> — config"
    done
}

# Polling getUpdates untuk restore-from-telegram.
# Cari document terbaru yang dikirim user ke bot, return file_id|file_name.
tg_get_latest_document() {
    _tg_load || return 1
    local offset=0
    [[ -f "$TG_UPD_OFFSET" ]] && offset=$(cat "$TG_UPD_OFFSET" 2>/dev/null || echo 0)
    local resp
    resp=$(curl -s --max-time 30 \
        "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${offset}&timeout=20&allowed_updates=%5B%22message%22%5D")
    [[ -z "$resp" ]] && return 1
    # Pakai python utk parsing JSON (sudah dependency wajib).
    python3 - "$resp" "$CHAT_ID" "$TG_UPD_OFFSET" <<'PYTG' 2>/dev/null
import sys, json
resp_raw, chat_id, off_path = sys.argv[1], str(sys.argv[2]), sys.argv[3]
try:
    data = json.loads(resp_raw)
except Exception:
    sys.exit(2)
if not data.get("ok"):
    sys.exit(3)
items = data.get("result", []) or []
if not items:
    sys.exit(4)
# Update offset ke update_id+1 paling akhir
last_id = items[-1].get("update_id", 0)
with open(off_path, "w") as f:
    f.write(str(int(last_id) + 1))
# Cari document terbaru dari chat ini
best = None
for it in items:
    m = it.get("message") or it.get("channel_post") or {}
    ch = m.get("chat", {}).get("id")
    if str(ch) != chat_id:
        continue
    doc = m.get("document")
    if doc and doc.get("file_id"):
        best = doc
if not best:
    sys.exit(5)
fid  = best.get("file_id", "")
name = best.get("file_name", "telegram-upload")
print(f"{fid}|{name}")
PYTG
}

# Download file dari Telegram (pakai file_id) ke path lokal.
# Usage: tg_download_file <file_id> <out_path>
tg_download_file() {
    _tg_load || return 1
    local fid="$1" out="$2"
    [[ -z "$fid" || -z "$out" ]] && return 1
    local meta path
    meta=$(curl -s --max-time 20 \
        "https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${fid}")
    path=$(echo "$meta" | python3 -c \
        'import sys,json; d=json.load(sys.stdin); print(d.get("result",{}).get("file_path",""))' 2>/dev/null)
    [[ -z "$path" ]] && return 1
    curl -s --max-time 300 -o "$out" \
        "https://api.telegram.org/file/bot${BOT_TOKEN}/${path}"
    [[ -s "$out" ]]
}

# Tulis isi multi-baris ke file sementara di $TG_TMP, echo pathnya.
# Usage: path=$(_tg_tmpfile "vmess-user.txt" "line1" "line2" ...)
_tg_tmpfile() {
    mkdir -p "$TG_TMP" 2>/dev/null
    local name="$1"; shift
    local out="$TG_TMP/${name}"
    : > "$out"
    local ln
    for ln in "$@"; do
        printf '%s\n' "$ln" >> "$out"
    done
    echo "$out"
}

# Brand display untuk Telegram body.
_tg_brand() {
    local b="MAX PANEL"
    if [[ -f "$STRF" ]]; then
        # shellcheck disable=SC1090
        source "$STRF" 2>/dev/null
        b="${BRAND:-MAX PANEL}"
    fi
    echo "$b"
}

# ════════════════════════════════════════════════════════════
#  BANNER / LOGO  — MAX PANEL ASCII
# ════════════════════════════════════════════════════════════
draw_logo() {
    local cur_theme L1 L2 L3 L4 L5
    cur_theme=$(cat "$THEMEF" 2>/dev/null || echo 1)
    if [[ "$cur_theme" == "7" ]]; then
        L1='\033[38;5;196m'; L2='\033[38;5;214m'; L3='\033[38;5;226m'
        L4='\033[38;5;82m';  L5='\033[38;5;51m'
    else
        L1="$AL"; L2="$AL"; L3="$A3"; L4="$AL"; L5="$A3"
    fi
    echo ""
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${L1}${BLD}  ███╗   ███╗ █████╗ ██╗  ██╗    ██████╗  █████╗ ███╗   ██╗ ${NC}"
    echo -e "  ${L2}${BLD}  ████╗ ████║██╔══██╗╚██╗██╔╝    ██╔══██╗██╔══██╗████╗  ██║ ${NC}"
    echo -e "  ${L3}${BLD}  ██╔████╔██║███████║ ╚███╔╝     ██████╔╝███████║██╔██╗ ██║ ${NC}"
    echo -e "  ${L4}${BLD}  ██║╚██╔╝██║██╔══██║ ██╔██╗     ██╔═══╝ ██╔══██║██║╚██╗██║ ${NC}"
    echo -e "  ${L5}${BLD}  ██║ ╚═╝ ██║██║  ██║██╔╝ ██╗    ██║     ██║  ██║██║ ╚████║ ${NC}"
    echo -e "  ${DIM}  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝ ${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${A4}             ✦  * MAX PREMIUM TUNNELING PANEL *  ✦      ${NC}"
    echo -e "  ${DIM}       +---------------- ${A2}[ ALL-IN-ONE ]${DIM} ---------------+  ${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
}

# ════════════════════════════════════════════════════════════
#  INFO VPS — HTML Panel Style, 2 kolom + stats
# ════════════════════════════════════════════════════════════
draw_vps() {
    local ip domain ram_u ram_t cpu du dt du_pct os hn total expc now_time now_date
    ip=$(get_ip)
    domain=$(get_domain)
    ram_u=$(free -m 2>/dev/null | awk '/^Mem/{print $3}')
    ram_t=$(free -m 2>/dev/null | awk '/^Mem/{print $2}')
    cpu=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{printf "%.1f",$2}' || echo "0.0")
    du=$(df -h / 2>/dev/null | awk 'NR==2{print $3}')
    dt=$(df -h / 2>/dev/null | awk 'NR==2{print $2}')
    du_pct=$(df / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    # shellcheck disable=SC1091
    os=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "Linux")
    hn=$(hostname)
    total=$(total_users_all)
    expc=$(exp_users_all)
    now_time=$(TZ="Asia/Jakarta" date "+%H:%M")
    now_date=$(TZ="Asia/Jakarta" date "+%d/%m/%Y")

    local ram_pct=0
    [[ "$ram_t" -gt 0 ]] 2>/dev/null && ram_pct=$(( ram_u * 100 / ram_t ))

    local brand="MAX PANEL"
    if [[ -f "$STRF" ]]; then
        # shellcheck disable=SC1090
        source "$STRF" 2>/dev/null
        brand="${BRAND:-MAX PANEL}"
    fi

    local tema_display
    if [[ "${THEME_NAME:-}" == "RAINBOW" ]]; then
        tema_display="\033[38;5;196mR\033[38;5;208mA\033[38;5;226mI\033[38;5;82mN\033[38;5;51mB\033[38;5;171mO\033[38;5;213mW\033[0m"
    else
        tema_display="${AL}${THEME_NAME}${NC}"
    fi

    echo ""
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${A4}◈${NC} ${BLD}${A4}INFO VPS${NC}  ${DIM}${now_time}  │  ${now_date}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"

    local os_short domain_short
    os_short=$(echo "$os" | cut -c1-14)
    domain_short=$(echo "$domain" | cut -c1-18)

    _btn "  ${DIM}HOST    ${NC}${A1}│${NC} ${A3}$(printf '%-16s' "$hn")${NC}  ${DIM}OS    ${NC}${A1}│${NC} ${W}${os_short}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    _btn "  ${DIM}IP ADDR ${NC}${A1}│${NC} ${A3}$(printf '%-16s' "$ip")${NC}  ${DIM}DOMAIN  ${NC}${A1}│${NC} ${W}${domain_short}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    _btn "  ${DIM}USER    ${NC}${A1}│${NC} ${Y}$(printf '%-16s' "$total")${NC}  ${DIM}BRAND   ${NC}${A1}│${NC} ${A4}${brand}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"

    _mini_bar() {
        local pct=${1:-0}
        local filled=$(( pct * 10 / 100 ))
        [[ $filled -gt 10 ]] && filled=10
        local empty=$(( 10 - filled ))
        local color
        if   [[ $pct -ge 80 ]]; then color="$LR"
        elif [[ $pct -ge 60 ]]; then color="$Y"
        else                         color="$LG"
        fi
        local bar=""
        local i
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty;  i++)); do bar+="░"; done
        printf "${color}%s${NC}" "$bar"
    }

    local cpu_pct=${cpu%.*}
    [[ -z "$cpu_pct" || "$cpu_pct" == "?" ]] && cpu_pct=0
    local cpu_col ram_col dsk_col
    if [[ $cpu_pct -ge 80 ]]; then cpu_col="$LR"
    elif [[ $cpu_pct -ge 60 ]]; then cpu_col="$Y"
    else cpu_col="$LG"; fi
    if [[ $ram_pct -ge 80 ]]; then ram_col="$LR"
    elif [[ $ram_pct -ge 60 ]]; then ram_col="$Y"
    else ram_col="$A3"; fi
    local dsk_pct=${du_pct:-0}
    if [[ $dsk_pct -ge 80 ]]; then dsk_col="$LR"
    elif [[ $dsk_pct -ge 60 ]]; then dsk_col="$Y"
    else dsk_col="$Y"; fi

    local cpu_bar ram_bar disk_bar
    cpu_bar=$(_mini_bar "$cpu_pct")
    ram_bar=$(_mini_bar "$ram_pct")
    disk_bar=$(_mini_bar "$dsk_pct")

    _btn "  ${DIM}CPU${NC} ${cpu_col}${cpu}%${NC}  ${cpu_bar}  ${A1}│${NC}  ${DIM}RAM${NC} ${ram_col}${ram_u}/${ram_t}MB${NC}  ${ram_bar}"
    echo -e "  ${A1}${_DASH}${NC}"
    _btn "  ${DIM}DISK${NC} ${dsk_col}${du}/${dt}${NC}  ${disk_bar}"
    echo -e "  ${A1}${_DASH}${NC}"

    # Service status row
    local ssh_b dr_b stun_b xray_b tgo_b hy_b ovpn_b wg_b
    ssh_b=$(svc_badge ssh);        dr_b=$(svc_badge dropbear)
    stun_b=$(svc_badge stunnel4);  xray_b=$(svc_badge xray)
    tgo_b=$(svc_badge trojan-go);  hy_b=$(svc_badge hysteria-server)
    ovpn_b=$(svc_badge openvpn);   wg_b=$(svc_badge "wg-quick@wg0")
    _btn "  ${DIM}SSH${NC}${ssh_b} ${DIM}DR${NC}${dr_b} ${DIM}STN${NC}${stun_b} ${DIM}XRY${NC}${xray_b} ${DIM}TGO${NC}${tgo_b} ${DIM}HY${NC}${hy_b} ${DIM}OVPN${NC}${ovpn_b} ${DIM}WG${NC}${wg_b}"
    echo -e "  ${A1}${_DASH}${NC}"

    _btn "  ${DIM}AKUN${NC} ${A3}${total}${NC}  ${A1}│${NC}  ${DIM}EXP${NC} ${LR}${expc}${NC}  ${A1}│${NC}  ${DIM}TEMA${NC}  ${tema_display}"
    echo -e "  ${A1}${_DASH}${NC}"
    echo ""
}

show_header() {
    clear
    load_theme
    draw_logo
    draw_vps
}

# ════════════════════════════════════════════════════════════
#  ACCOUNT BOX — Tampilan info akun yang baru dibuat
# ════════════════════════════════════════════════════════════
show_box_ssh() {
    local u="$1" p="$2" exp="$3" maxl="${4:-2}"
    local ip dom
    ip=$(get_ip); dom=$(get_domain)
    local brand="MAX PANEL"
    [[ -f "$STRF" ]] && { # shellcheck disable=SC1090
        source "$STRF" 2>/dev/null; brand="${BRAND:-MAX PANEL}"; }
    echo ""
    echo -e "  ${LG}✅ Akun SSH/OpenSSH — ${brand}${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Username${NC} : ${BLD}${W}%s${NC}\n" "$u"
    printf  "  ${A1}│${NC} 🔑 ${DIM}Password${NC} : ${BLD}${A3}%s${NC}\n" "$p"
    echo -e "  ${A1}├─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 🖥  ${DIM}IP Publik${NC} : ${LG}%s${NC}\n" "$ip"
    printf  "  ${A1}│${NC} 🌐 ${DIM}Host    ${NC} : ${W}%s${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🔌 ${DIM}Port SSH ${NC}: ${Y}22${NC}\n"
    printf  "  ${A1}│${NC} 🔌 ${DIM}Dropbear ${NC}: ${Y}109, 143${NC}\n"
    printf  "  ${A1}│${NC} 🔒 ${DIM}SSH SSL  ${NC}: ${Y}990, 446, 110, 444${NC}\n"
    printf  "  ${A1}│${NC} 🔌 ${DIM}WS HTTP  ${NC}: ${Y}80, 8080, 2086, 8880 (/ws-ssh)${NC}\n"
    printf  "  ${A1}│${NC} 🔒 ${DIM}WS HTTPS ${NC}: ${Y}443, 2083, 2087, 8443 (/ws-ssh)${NC}\n"
    printf  "  ${A1}│${NC} 📡 ${DIM}OpenVPN  ${NC}: ${Y}TCP 1194 / UDP 2200${NC}\n"
    printf  "  ${A1}│${NC} 📡 ${DIM}UDPGW    ${NC}: ${Y}7100, 7200, 7300${NC}\n"
    echo -e "  ${A1}├─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 🔒 ${DIM}MaxLogin${NC} : ${Y}%s device${NC}\n" "$maxl"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""
}

show_box_xray() {
    local proto="$1" u="$2" id="$3" exp="$4" maxl="${5:-2}"
    local ip dom uuid="$id"
    ip=$(get_ip); dom=$(get_domain)
    local brand="MAX PANEL"
    [[ -f "$STRF" ]] && { # shellcheck disable=SC1090
        source "$STRF" 2>/dev/null; brand="${BRAND:-MAX PANEL}"; }
    echo ""
    echo -e "  ${LG}✅ Akun ${proto} — ${brand}${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Remark   ${NC}: ${BLD}${W}%s${NC}\n" "$u"
    case "$proto" in
        VMess|VLess) printf  "  ${A1}│${NC} 🔑 ${DIM}UUID     ${NC}: ${A3}%s${NC}\n" "$uuid" ;;
        Trojan|*)    printf  "  ${A1}│${NC} 🔑 ${DIM}Password ${NC}: ${A3}%s${NC}\n" "$uuid" ;;
    esac
    echo -e "  ${A1}├─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 🌐 ${DIM}Host    ${NC} : ${W}%s${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🖥  ${DIM}IP       ${NC}: ${LG}%s${NC}\n" "$ip"
    case "$proto" in
        VMess)
            printf  "  ${A1}│${NC} 🔒 ${DIM}Port TLS ${NC}: ${Y}443, 2083, 2087, 8443${NC}\n"
            printf  "  ${A1}│${NC} 🔌 ${DIM}Port HTTP${NC}: ${Y}80, 8080, 2086, 8880${NC}\n"
            printf  "  ${A1}│${NC} 🛣  ${DIM}Path     ${NC}: ${Y}/vmess${NC}\n" ;;
        VLess)
            printf  "  ${A1}│${NC} 🔒 ${DIM}Port TLS ${NC}: ${Y}443, 2083, 2087, 8443${NC}\n"
            printf  "  ${A1}│${NC} 🔌 ${DIM}Port HTTP${NC}: ${Y}80, 8080, 2086, 8880${NC}\n"
            printf  "  ${A1}│${NC} 🔒 ${DIM}gRPC TLS ${NC}: ${Y}443, 2083, 2087, 8443${NC}\n"
            printf  "  ${A1}│${NC} 🛣  ${DIM}WS Path  ${NC}: ${Y}/vless${NC}\n"
            printf  "  ${A1}│${NC} 🛣  ${DIM}gRPC SVC ${NC}: ${Y}vless-grpc${NC}\n" ;;
        Trojan)
            printf  "  ${A1}│${NC} 🔒 ${DIM}Port TLS ${NC}: ${Y}443, 2083, 2087, 8443${NC}\n"
            printf  "  ${A1}│${NC} 🔒 ${DIM}gRPC TLS ${NC}: ${Y}443, 2083, 2087, 8443${NC}\n"
            printf  "  ${A1}│${NC} 🛣  ${DIM}WS Path  ${NC}: ${Y}/trojan-ws${NC}\n"
            printf  "  ${A1}│${NC} 🛣  ${DIM}gRPC SVC ${NC}: ${Y}trojan-grpc${NC}\n" ;;
    esac
    echo -e "  ${A1}├─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 🔒 ${DIM}MaxLogin${NC} : ${Y}%s device${NC}\n" "$maxl"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — Dependencies
# ════════════════════════════════════════════════════════════
install_deps() {
    inf "Update apt & install dependensi inti..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq \
        wget curl jq unzip zip tar net-tools dropbear stunnel4 openvpn easy-rsa \
        vnstat htop iftop bmon screen tmux cron rsyslog uuid-runtime sudo lsb-release \
        fail2ban git build-essential libssl-dev python3 python3-pip dnsutils socat \
        figlet toilet boxes lolcat speedtest-cli wireguard wireguard-tools resolvconf \
        qrencode bc iptables iptables-persistent netfilter-persistent ca-certificates \
        gnupg2 lsof psmisc openssl python3-websockify 2>/dev/null || true
    # retry sekali lagi tanpa fail-on-missing untuk paket opsional
    apt-get install -y -qq nginx jq 2>/dev/null || true
    ok "Dependensi terpasang"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — SSH + Dropbear + Stunnel
# ════════════════════════════════════════════════════════════
install_ssh() {
    inf "Konfigurasi OpenSSH (port 22 only — 80/443/2086/2087 dihandle Nginx, 990/446/110/444 oleh Stunnel)..."
    # FIX: SSH cukup di port 22. Port 80 = Nginx, port 443 = Nginx.
    # Pakai marker idempotent agar re-run aman dan tidak menumpuk baris Port.
    # Pertama: pastikan ada "Port 22" baseline di sshd_config (cari atau set)
    if ! grep -qE '^Port[[:space:]]+22$' /etc/ssh/sshd_config 2>/dev/null; then
        sed -i 's/^#\?Port .*/Port 22/' /etc/ssh/sshd_config 2>/dev/null
        grep -qE '^Port[[:space:]]+22$' /etc/ssh/sshd_config 2>/dev/null || \
            echo "Port 22" >> /etc/ssh/sshd_config
    fi
    # Bersihkan baris "Port 80" / "Port 443" jika ada (sisa install lama)
    sed -i '/^Port[[:space:]]\+80$/d'  /etc/ssh/sshd_config 2>/dev/null
    sed -i '/^Port[[:space:]]\+443$/d' /etc/ssh/sshd_config 2>/dev/null
    # PermitRoot login & password auth (sesuaikan)
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    ok "OpenSSH siap: 22 (80/443/2086/2087 dilayani Nginx-WS, 990/446/110/444 oleh Stunnel)"

    # ── Dropbear ─────────────────────────────────────────────────────────
    inf "Konfigurasi Dropbear (port 109, 143)..."
    if [[ -f /etc/default/dropbear ]]; then
        sed -i 's/^NO_START=.*/NO_START=0/' /etc/default/dropbear
        # Hapus semua baris DROPBEAR_PORT (termasuk yang di-comment) lalu tambah baru
        sed -i '/^#\?DROPBEAR_PORT=/d' /etc/default/dropbear
        echo 'DROPBEAR_PORT=109' >> /etc/default/dropbear
        # Hapus semua baris DROPBEAR_EXTRA_ARGS lalu tambah baru
        sed -i '/^#\?DROPBEAR_EXTRA_ARGS=/d' /etc/default/dropbear
        echo 'DROPBEAR_EXTRA_ARGS="-p 143"' >> /etc/default/dropbear
    fi
    # Generate DSS host key jika belum ada
    if [[ ! -f /etc/dropbear/dropbear_dss_host_key ]]; then
        mkdir -p /etc/dropbear
        dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key &>/dev/null || true
    fi
    # Pastikan /bin/false dan /usr/sbin/nologin ada di /etc/shells
    grep -qx '/bin/false'         /etc/shells 2>/dev/null || echo '/bin/false'         >> /etc/shells
    grep -qx '/usr/sbin/nologin'  /etc/shells 2>/dev/null || echo '/usr/sbin/nologin'  >> /etc/shells
    systemctl enable dropbear &>/dev/null
    systemctl restart dropbear 2>/dev/null
    ok "Dropbear siap: 109, 143"

    # ── Stunnel SSL ─────────────────────────────────────────────────────────
    # FIX: port 443 dihandle Nginx (TLS termination). Stunnel listen di 990, 446, 110, 444
    # (matching tampilan panel app). Forward: 990/110 → Dropbear:109, 446/444 → OpenSSH:22.
    inf "Konfigurasi Stunnel SSL (990,446,110,444)..."
    mkdir -p /etc/stunnel
    if [[ ! -s /etc/stunnel/stunnel.pem ]]; then
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/C=ID/ST=JKT/L=Jakarta/O=MAX/OU=Panel/CN=maxpanel" \
            -keyout /etc/stunnel/key.pem -out /etc/stunnel/cert.pem &>/dev/null
        cat /etc/stunnel/key.pem /etc/stunnel/cert.pem > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/key.pem /etc/stunnel/stunnel.pem
        chmod 644 /etc/stunnel/cert.pem
    fi
    mkdir -p /var/run/stunnel4
    chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || true
    cat > /etc/stunnel/stunnel.conf <<'STUN'
cert = /etc/stunnel/stunnel.pem
pid = /var/run/stunnel4/stunnel.pid
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear-ssl-990]
accept = 990
connect = 127.0.0.1:109

[openssh-ssl-446]
accept = 446
connect = 127.0.0.1:22

[dropbear-ssl-110]
accept = 110
connect = 127.0.0.1:109

[openssh-ssl-444]
accept = 444
connect = 127.0.0.1:22
STUN
    chmod 600 /etc/stunnel/stunnel.pem 2>/dev/null
    # Aktifkan stunnel
    sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
    [[ -f /etc/default/stunnel4 ]] || echo "ENABLED=1" > /etc/default/stunnel4
    systemctl enable stunnel4 &>/dev/null
    # Kill proses lama dulu sebelum restart
    pkill -9 stunnel4 2>/dev/null; rm -f /var/run/stunnel4/stunnel.pid
    sleep 1
    systemctl restart stunnel4 2>/dev/null
    ok "Stunnel SSL siap: 990, 446, 110, 444"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — Xray-core (VMess/VLess/Trojan/Shadowsocks)
# ════════════════════════════════════════════════════════════
install_xray() {
    inf "Install Xray-core..."
    mkdir -p /etc/xray /var/log/xray
    touch "$XRAY_LOG" /var/log/xray/error.log
    if [[ ! -x "$XRAY_BIN" ]] || ! "$XRAY_BIN" version &>/dev/null; then
        local tmp; tmp=$(mktemp -d)
        if dl "$XRAY_URL" "$tmp/xray.zip"; then
            unzip -qo "$tmp/xray.zip" -d "$tmp" 2>/dev/null
            if [[ -f "$tmp/xray" ]] && verify_binary "$tmp/xray" 1000000; then
                install -m755 "$tmp/xray" "$XRAY_BIN"
                ok "Xray-core terpasang: $("$XRAY_BIN" version 2>/dev/null | head -1 | awk '{print $2}')"
            else
                err "Binary Xray rusak atau terlalu kecil"
                rm -rf "$tmp"; return 1
            fi
        else
            err "Gagal download Xray-core dari $XRAY_URL"
            rm -rf "$tmp"; return 1
        fi
        rm -rf "$tmp"
    else
        ok "Xray-core sudah terpasang — skip download"
    fi

    # SSL cert — self-signed default (akan di-replace oleh acme jika domain di-set)
    if [[ ! -s "$XRAY_CRT" ]]; then
        local dom; dom=$(get_domain)
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -subj "/CN=${dom}" \
            -keyout "$XRAY_KEY" -out "$XRAY_CRT" &>/dev/null
        # FIX: private key WAJIB 600. Certificate publik boleh 644.
        chmod 644 "$XRAY_CRT"
        chmod 600 "$XRAY_KEY"
    fi

    # Konfigurasi Xray
    # FIX: konsolidasi ke 5 inbound (10001-10005) + SS @ 8388 sesuai spec port architecture.
    # Semua WS/gRPC inbound listen di 127.0.0.1, TLS terminasi di Nginx pada port 443.
    inf "Tulis konfigurasi Xray (5 inbound + SS)..."
    cat > "$XRAY_CFG" <<'XCFG'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error":  "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 10001, "listen": "127.0.0.1", "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}},
      "sniffing": {"enabled": true, "destOverride": ["http","tls"]},
      "tag": "vmess-ws"
    },
    {
      "port": 10002, "listen": "127.0.0.1", "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vless"}},
      "sniffing": {"enabled": true, "destOverride": ["http","tls"]},
      "tag": "vless-ws"
    },
    {
      "port": 10003, "listen": "127.0.0.1", "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/trojan-ws"}},
      "tag": "trojan-ws"
    },
    {
      "port": 10004, "listen": "127.0.0.1", "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "vless-grpc"}},
      "tag": "vless-grpc"
    },
    {
      "port": 10005, "listen": "127.0.0.1", "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "trojan-grpc"}},
      "tag": "trojan-grpc"
    },
    {
      "port": 8388, "protocol": "shadowsocks",
      "settings": {
        "clients": [],
        "network": "tcp,udp"
      },
      "tag": "ss-2022"
    }
  ],
  "outbounds": [
    {"protocol": "freedom",   "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
XCFG

    # Systemd service
    cat > /etc/systemd/system/xray.service <<XEOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=$XRAY_BIN run -c $XRAY_CFG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
XEOF
    systemctl daemon-reload
    systemctl enable xray &>/dev/null
    systemctl restart xray 2>/dev/null
    sleep 1
    if is_up xray; then ok "Xray-core service aktif"
    else warn "Xray belum aktif — coba: journalctl -u xray -n 20"
    fi
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — Trojan-Go (port 2096)
# ════════════════════════════════════════════════════════════
install_trojan_go() {
    inf "Install Trojan-Go..."
    mkdir -p "$TROJANGO_DIR"
    if [[ ! -x "$TROJANGO_BIN" ]]; then
        local tmp; tmp=$(mktemp -d)
        if dl "$TROJAN_GO_URL" "$tmp/trojan-go.zip"; then
            unzip -qo "$tmp/trojan-go.zip" -d "$tmp" 2>/dev/null
            if [[ -f "$tmp/trojan-go" ]] && verify_binary "$tmp/trojan-go" 1000000; then
                install -m755 "$tmp/trojan-go" "$TROJANGO_BIN"
                ok "Trojan-Go terpasang"
            else
                err "Binary Trojan-Go rusak"
                rm -rf "$tmp"; return 1
            fi
        else
            err "Gagal download Trojan-Go"
            rm -rf "$tmp"; return 1
        fi
        rm -rf "$tmp"
    else
        ok "Trojan-Go sudah terpasang — skip"
    fi

    # SSL
    if [[ ! -s "$TROJANGO_DIR/server.crt" ]]; then
        local dom; dom=$(get_domain)
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -subj "/CN=${dom}" \
            -keyout "$TROJANGO_DIR/server.key" \
            -out    "$TROJANGO_DIR/server.crt" &>/dev/null
        # FIX: private key 600, cert 644
        chmod 644 "$TROJANGO_DIR/server.crt"
        chmod 600 "$TROJANGO_DIR/server.key"
    fi

    cat > "$TROJANGO_CFG" <<'TGCFG'
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 2096,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": [],
  "ssl": {
    "cert": "/etc/trojan-go/server.crt",
    "key":  "/etc/trojan-go/server.key",
    "sni":  "",
    "alpn": ["http/1.1"]
  },
  "websocket": {
    "enabled": true,
    "path": "/trojan-go",
    "host": ""
  },
  "router": {"enabled": false}
}
TGCFG

    cat > /etc/systemd/system/trojan-go.service <<TGEOF
[Unit]
Description=Trojan-Go Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=$TROJANGO_BIN -config $TROJANGO_CFG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
TGEOF
    systemctl daemon-reload
    systemctl enable trojan-go &>/dev/null
    systemctl restart trojan-go 2>/dev/null
    is_up trojan-go && ok "Trojan-Go aktif di port 2096" || warn "Trojan-Go gagal start"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — Hysteria 2 (UDP 36712 + range)
# ════════════════════════════════════════════════════════════
install_hysteria() {
    inf "Install Hysteria 2..."
    mkdir -p "$HY_DIR"
    if [[ ! -x "$HY_BIN" ]]; then
        local tmp; tmp=$(mktemp -d)
        if dl "$HYSTERIA_URL" "$tmp/hysteria"; then
            if verify_binary "$tmp/hysteria" 1000000; then
                install -m755 "$tmp/hysteria" "$HY_BIN"
                ok "Hysteria 2 terpasang"
            else
                err "Binary Hysteria rusak"
                rm -rf "$tmp"; return 1
            fi
        else
            err "Gagal download Hysteria"
            rm -rf "$tmp"; return 1
        fi
        rm -rf "$tmp"
    else
        ok "Hysteria sudah terpasang — skip"
    fi

    if [[ ! -s "$HY_DIR/server.crt" ]]; then
        local dom; dom=$(get_domain)
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -subj "/CN=${dom}" \
            -keyout "$HY_DIR/server.key" \
            -out    "$HY_DIR/server.crt" &>/dev/null
        # FIX: private key 600, cert 644
        chmod 644 "$HY_DIR/server.crt"
        chmod 600 "$HY_DIR/server.key"
    fi

    cat > "$HY_CFG" <<'HYCFG'
listen: :36712
tls:
  cert: /etc/hysteria/server.crt
  key:  /etc/hysteria/server.key
auth:
  type: userpass
  userpass:
    maxpanel: "maxpanel2024"
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
quic:
  initStreamReceiveWindow:     8388608
  maxStreamReceiveWindow:      8388608
  initConnReceiveWindow:      20971520
  maxConnReceiveWindow:       20971520
HYCFG

    cat > /etc/systemd/system/hysteria-server.service <<HYEOF
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=$HY_BIN server -c $HY_CFG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
HYEOF

    # Range port UDP via iptables (5300, 7300, 36712 + fwd 6000-19999)
    local IFACE; IFACE=$(get_iface)
    iptables -I INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null
    iptables -I INPUT -p udp --dport 5300  -j ACCEPT 2>/dev/null
    iptables -I INPUT -p udp --dport 7300  -j ACCEPT 2>/dev/null
    # Redirect range UDP ke port 36712 hysteria (opsional)
    while iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 6000:19999 \
        -j DNAT --to-destination :36712 2>/dev/null; do :; done
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 \
        -j DNAT --to-destination :36712 2>/dev/null
    netfilter-persistent save &>/dev/null

    systemctl daemon-reload
    systemctl enable hysteria-server &>/dev/null
    systemctl restart hysteria-server 2>/dev/null
    is_up hysteria-server && ok "Hysteria 2 aktif (36712 + redirect 6000-19999)" \
                          || warn "Hysteria belum aktif — cek log"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — BadVPN UDPGW (7100/7200/7300)
# ════════════════════════════════════════════════════════════
install_udpgw() {
    inf "Install BadVPN UDPGW..."
    if [[ ! -x "$UDPGW_BIN" ]]; then
        # Cek file lokal di repo dulu
        if [[ -f "$(dirname "$0")/udpgw" ]] && verify_binary "$(dirname "$0")/udpgw" 100000; then
            install -m755 "$(dirname "$0")/udpgw" "$UDPGW_BIN"
            ok "Pakai binary udpgw dari repo"
        elif [[ -f /home/max/udpgw ]] && verify_binary /home/max/udpgw 100000; then
            install -m755 /home/max/udpgw "$UDPGW_BIN"
            ok "Pakai binary udpgw dari /home/max/"
        else
            local tmp; tmp=$(mktemp)
            if dl "$UDPGW_URL" "$tmp" && verify_binary "$tmp" 100000; then
                install -m755 "$tmp" "$UDPGW_BIN"
                ok "BadVPN UDPGW terpasang"
            else
                err "Gagal download udpgw — coba kompile manual"
                rm -f "$tmp"; return 1
            fi
            rm -f "$tmp"
        fi
    else
        ok "udpgw sudah terpasang — skip"
    fi

    for port in 7100 7200 7300; do
        cat > "/etc/systemd/system/badvpn-udpgw-${port}.service" <<UDPGW_EOF
[Unit]
Description=BadVPN UDPGW Port ${port}
After=network.target

[Service]
Type=simple
User=root
ExecStart=$UDPGW_BIN --listen-addr 127.0.0.1:${port} --max-clients 500 --max-connections-for-client 10
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UDPGW_EOF
        systemctl enable "badvpn-udpgw-${port}" &>/dev/null
        systemctl restart "badvpn-udpgw-${port}" 2>/dev/null
    done
    ok "UDPGW siap pada port 7100, 7200, 7300"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — OpenVPN (TCP 1194 / UDP 2200)
# ════════════════════════════════════════════════════════════
install_openvpn() {
    inf "Install OpenVPN (TCP 1194 + UDP 2200)..."
    if ! command -v openvpn &>/dev/null; then
        apt-get install -y -qq openvpn easy-rsa &>/dev/null
    fi
    mkdir -p /etc/openvpn/server /etc/openvpn/easy-rsa /etc/openvpn/client

    if [[ ! -s /etc/openvpn/server/ca.crt ]]; then
        # Buat PKI baru pakai easy-rsa
        local ER=/etc/openvpn/easy-rsa
        if [[ -d /usr/share/easy-rsa ]]; then
            cp -r /usr/share/easy-rsa/* "$ER/" 2>/dev/null
        fi
        cd "$ER" || return 1
        export EASYRSA_BATCH=1
        export EASYRSA_REQ_CN="MAX-CA"
        ./easyrsa init-pki &>/dev/null
        ./easyrsa --batch build-ca nopass &>/dev/null
        ./easyrsa --batch gen-req server nopass &>/dev/null
        ./easyrsa --batch sign-req server server &>/dev/null
        ./easyrsa gen-dh &>/dev/null
        openvpn --genkey secret /etc/openvpn/server/ta.key &>/dev/null
        cp "$ER/pki/ca.crt"          /etc/openvpn/server/ca.crt
        cp "$ER/pki/issued/server.crt" /etc/openvpn/server/server.crt
        cp "$ER/pki/private/server.key" /etc/openvpn/server/server.key
        cp "$ER/pki/dh.pem"          /etc/openvpn/server/dh.pem
        # FIX: lock down semua private key OpenVPN ke 600 (server.key, ta.key, CA private key)
        chmod 600 /etc/openvpn/server/server.key /etc/openvpn/server/ta.key 2>/dev/null
        chmod 644 /etc/openvpn/server/ca.crt /etc/openvpn/server/server.crt /etc/openvpn/server/dh.pem 2>/dev/null
        chmod 600 "$ER/pki/private/ca.key" "$ER/pki/private/server.key" 2>/dev/null
        chmod -R go-rwx "$ER/pki/private" 2>/dev/null
        cd - >/dev/null || true
        ok "OpenVPN PKI dibuat"
    else
        ok "OpenVPN PKI sudah ada — skip"
    fi

    # Config server TCP 1194
    cat > /etc/openvpn/server/tcp.conf <<'OVPNTCP'
port 1194
proto tcp
dev tun
ca   /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key  /etc/openvpn/server/server.key
dh   /etc/openvpn/server/dh.pem
tls-auth /etc/openvpn/server/ta.key 0
server 10.200.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/server/ipp-tcp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-128-CBC
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-tcp-status.log
log    /var/log/openvpn-tcp.log
verb 3
plugin /usr/lib/openvpn/openvpn-plugin-auth-pam.so login
duplicate-cn
script-security 3
client-cert-not-required
username-as-common-name
OVPNTCP

    cat > /etc/openvpn/server/udp.conf <<'OVPNUDP'
port 2200
proto udp
dev tun1
ca   /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key  /etc/openvpn/server/server.key
dh   /etc/openvpn/server/dh.pem
tls-auth /etc/openvpn/server/ta.key 0
server 10.201.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/server/ipp-udp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-128-CBC
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-udp-status.log
log    /var/log/openvpn-udp.log
verb 3
plugin /usr/lib/openvpn/openvpn-plugin-auth-pam.so login
duplicate-cn
script-security 3
client-cert-not-required
username-as-common-name
OVPNUDP

    # Forwarding & NAT
    sed -i 's|^#\?net.ipv4.ip_forward.*|net.ipv4.ip_forward=1|' /etc/sysctl.conf 2>/dev/null
    # FIX idempotent: pastikan ip_forward via marker block (re-run aman)
    _apply_block "OPENVPN-FORWARD" /etc/sysctl.conf <<'OVPNSC'
net.ipv4.ip_forward=1
OVPNSC
    sysctl -p &>/dev/null
    local IFACE; IFACE=$(get_iface)
    iptables -t nat -C POSTROUTING -s 10.200.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -s 10.200.0.0/24 -o "$IFACE" -j MASQUERADE
    iptables -t nat -C POSTROUTING -s 10.201.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -s 10.201.0.0/24 -o "$IFACE" -j MASQUERADE
    netfilter-persistent save &>/dev/null

    systemctl enable openvpn-server@tcp openvpn-server@udp &>/dev/null
    systemctl restart openvpn-server@tcp 2>/dev/null
    systemctl restart openvpn-server@udp 2>/dev/null
    ok "OpenVPN siap: TCP 1194 + UDP 2200"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — WireGuard (UDP 51820)
# ════════════════════════════════════════════════════════════
install_wireguard() {
    inf "Install WireGuard (UDP 51820)..."
    if ! command -v wg &>/dev/null; then
        apt-get install -y -qq wireguard wireguard-tools &>/dev/null
    fi
    mkdir -p "$WG_DIR" "$WG_CLIENT_DIR"
    chmod 700 "$WG_DIR"

    if [[ ! -s "$WG_DIR/server_private.key" ]]; then
        local privk pubk
        privk=$(wg genkey)
        pubk=$(echo "$privk" | wg pubkey)
        # Write key dengan umask ketat agar tidak race-condition 644 sebelum chmod
        ( umask 077; echo "$privk" > "$WG_DIR/server_private.key" )
        echo "$pubk"  > "$WG_DIR/server_public.key"
        chmod 600 "$WG_DIR/server_private.key"
        chmod 644 "$WG_DIR/server_public.key"
    fi

    local IFACE SPRIV
    IFACE=$(get_iface)
    SPRIV=$(cat "$WG_DIR/server_private.key")

    cat > "$WG_CFG" <<WGCFG
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $SPRIV
SaveConfig = false
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE
WGCFG
    chmod 600 "$WG_CFG"

    sed -i 's|^#\?net.ipv4.ip_forward.*|net.ipv4.ip_forward=1|' /etc/sysctl.conf
    # FIX idempotent: marker block utk ip_forward (boleh overlap dengan OpenVPN, sed di atas tetap normalize)
    _apply_block "WG-FORWARD" /etc/sysctl.conf <<'WGSC'
net.ipv4.ip_forward=1
WGSC
    sysctl -p &>/dev/null
    systemctl enable wg-quick@wg0 &>/dev/null
    systemctl restart wg-quick@wg0 2>/dev/null
    is_up "wg-quick@wg0" && ok "WireGuard aktif di UDP 51820" || warn "WireGuard belum aktif"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — SlowDNS (port 53 + 5300)
# ════════════════════════════════════════════════════════════
install_slowdns() {
    inf "Install SlowDNS server..."
    mkdir -p "$SLOW_DIR"
    if [[ ! -x "$SLOW_BIN" ]]; then
        if dl "$SLOWDNS_URL" "$SLOW_BIN"; then
            chmod +x "$SLOW_BIN"
            if ! verify_binary "$SLOW_BIN" 100000; then
                warn "Binary SlowDNS terlalu kecil — mungkin gagal download"
                rm -f "$SLOW_BIN"
            else
                ok "Binary SlowDNS terpasang"
            fi
        else
            warn "Gagal download SlowDNS server — fitur akan dinonaktifkan"
        fi
    else
        ok "SlowDNS sudah terpasang — skip"
    fi

    # Generate keypair (kalau binary mendukung -gen-key)
    if [[ -x "$SLOW_BIN" ]] && [[ ! -s "$SLOW_DIR/server.priv" ]]; then
        "$SLOW_BIN" -gen-key -privkey-file "$SLOW_DIR/server.priv" \
            -pubkey-file "$SLOW_DIR/server.pub" &>/dev/null || true
    fi

    # Systemd service — listen 5300 (forward dari port 53 lewat iptables)
    if [[ -x "$SLOW_BIN" ]]; then
        cat > /etc/systemd/system/slowdns.service <<SLDEOF
[Unit]
Description=SlowDNS Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SLOW_DIR
ExecStart=$SLOW_BIN -udp :5300 -privkey-file $SLOW_DIR/server.priv ns.example.com 127.0.0.1:22
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SLDEOF
        systemctl daemon-reload
        systemctl enable slowdns &>/dev/null

        # Redirect port 53 UDP → 5300
        iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null \
            || iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
        netfilter-persistent save &>/dev/null

        systemctl restart slowdns 2>/dev/null
        ok "SlowDNS aktif (port 53 → 5300)"
    fi
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — WebSocket Python Proxy
# ════════════════════════════════════════════════════════════
install_ws_proxy() {
    inf "Install WebSocket proxy (HTTP injector)..."
    mkdir -p "$WS_DIR"

    # Tulis python ws-proxy minimal
    cat > "$WS_BIN" <<'WSPY'
#!/usr/bin/env python3
# MAX WS Proxy — HTTP CONNECT/Injector style proxy
# Listens on 127.0.0.1:<port>, accepts HTTP upgrade, forwards raw TCP to SSH/Dropbear backend.
# Dipakai sebagai backend untuk Nginx (path /ws-ssh). Tidak listen public.
import socket, threading, select, sys, signal

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8880
DEFAULT_TARGET = ('127.0.0.1', 22)
RESPONSE = b'HTTP/1.1 200 OK\r\nServer: MAX-WS\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'
BUFLEN  = 8192
TIMEOUT = 60

class Server(threading.Thread):
    def __init__(self, host, port):
        super().__init__(daemon=True)
        self.host = host; self.port = port
        self.threads = []
        self.running = True
        self.sock = None

    def run(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((self.host, self.port))
        self.sock.listen(0)
        while self.running:
            try:
                c, _ = self.sock.accept()
                c.setblocking(True)
            except OSError:
                break
            ch = ConnectionHandler(c, DEFAULT_TARGET)
            ch.start()
            self.threads.append(ch)
        self.sock.close()

    def stop(self):
        self.running = False
        try: self.sock.close()
        except: pass

class ConnectionHandler(threading.Thread):
    def __init__(self, client, target):
        super().__init__(daemon=True)
        self.client = client; self.target = target
        self.target_sock = None

    def run(self):
        try:
            self.client.settimeout(TIMEOUT)
            data = self.client.recv(BUFLEN)
            host_port = self.target
            self.client.sendall(RESPONSE)
            self.target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.target_sock.settimeout(TIMEOUT)
            self.target_sock.connect(host_port)
            self.relay(self.client, self.target_sock)
        except Exception:
            pass
        finally:
            try: self.client.close()
            except: pass
            try:
                if self.target_sock: self.target_sock.close()
            except: pass

    def relay(self, a, b):
        sockets = [a, b]
        timeout_count = 0
        while True:
            r, _, x = select.select(sockets, [], sockets, 3)
            if x:
                break
            if r:
                for s in r:
                    try:
                        data = s.recv(BUFLEN)
                    except Exception:
                        return
                    if not data:
                        return
                    other = b if s is a else a
                    try:
                        other.sendall(data)
                    except Exception:
                        return
                    timeout_count = 0
            else:
                timeout_count += 1
                if timeout_count > 5:
                    return

def main():
    s = Server(LISTEN_HOST, LISTEN_PORT)
    s.start()
    def sigterm(*_):
        s.stop()
    signal.signal(signal.SIGTERM, sigterm)
    signal.signal(signal.SIGINT,  sigterm)
    s.join()

if __name__ == '__main__':
    main()
WSPY
    chmod +x "$WS_BIN"

    # Systemd: HANYA satu WS proxy di 127.0.0.1:8880 (akan di-reverse-proxy oleh Nginx via /ws-ssh)
    # FIX: hapus listener pada port 80 dan 2095 (clash dengan Nginx + public exposure tanpa Nginx).
    # Sekaligus hapus service lama (ws-max-80, ws-max-2095) bila ada sisa install sebelumnya.
    for stale in /etc/systemd/system/ws-max-80.service /etc/systemd/system/ws-max-2095.service; do
        if [[ -f "$stale" ]]; then
            local svc; svc=$(basename "$stale" .service)
            systemctl stop    "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
            rm -f "$stale"
        fi
    done
    cat > /etc/systemd/system/ws-max-8880.service <<WSSVC
[Unit]
Description=MAX WS Proxy (internal 127.0.0.1:8880, reverse-proxied by Nginx)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $WS_BIN 8880
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
WSSVC
    systemctl daemon-reload
    systemctl enable  ws-max-8880 &>/dev/null
    systemctl restart ws-max-8880 2>/dev/null

    # FIX: TIDAK lagi append stunnel WS-TLS sections. Nginx terminasi TLS di port 443.
    # Hapus block stunnel WS-TLS lama (idempotent) bila tertinggal dari versi sebelumnya.
    if [[ -f /etc/stunnel/stunnel.conf ]]; then
        # Hapus pakai marker (versi baru) dan section lama (versi lama tanpa marker)
        sed -i '/^# >>> MAXPANEL-WS-STUNNEL >>>$/,/^# <<< MAXPANEL-WS-STUNNEL <<<$/d' /etc/stunnel/stunnel.conf 2>/dev/null
        # Legacy cleanup (sebelum marker dipakai)
        sed -i '/^\[ws-tls-443\]/,/^$/d' /etc/stunnel/stunnel.conf 2>/dev/null
        sed -i '/^\[ws-tls-2096\]/,/^$/d' /etc/stunnel/stunnel.conf 2>/dev/null
        systemctl restart stunnel4 2>/dev/null
    fi

    ok "WS proxy aktif di 127.0.0.1:8880 (path /ws-ssh → Nginx 80/443)"
}

# ════════════════════════════════════════════════════════════
#  INSTALLER — Nginx reverse-proxy (path-routing untuk Xray)
# ════════════════════════════════════════════════════════════
install_nginx() {
    inf "Install Nginx + reverse-proxy path-routing (HTTP 80/8080/2086/8880 + TLS 443/2083/2087/8443)..."
    if ! command -v nginx &>/dev/null; then
        apt-get install -y -qq nginx 2>/dev/null
    fi
    mkdir -p /etc/nginx/conf.d

    local dom; dom=$(get_domain)

    # Remove default site (akan dipegang config kita)
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null

    # FIX: Nginx listen multi-port supaya cocok dengan UI panel.
    #   HTTP non-TLS : 80, 8080, 2086, 8880
    #   HTTPS TLS    : 443, 2083, 2087, 8443
    # Semua path Xray + WS-SSH dirutekan dari sini.
    # SSH/Dropbear/Stunnel TIDAK pakai port-port di atas.
    #
    # Xray inbound mapping (semua 127.0.0.1):
    #   /vmess       -> 10001  (VMess WS)
    #   /vless       -> 10002  (VLess WS)
    #   /trojan-ws   -> 10003  (Trojan WS)
    #   /vless-grpc  -> 10004  (VLess gRPC)  -- hanya di server TLS
    #   /trojan-grpc -> 10005  (Trojan gRPC) -- hanya di server TLS
    #   /ws-ssh      -> 8880   (SSH-over-WS via python proxy) -- internal only
    cat > /etc/nginx/conf.d/xray.conf <<NGX
# MAX PANEL -- Xray reverse-proxy (multi-port HTTP + TLS)
# === SHARED PROXY HEADERS ===========================================
map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }

# === HTTP non-TLS: 80, 8080, 2086, 8880 ==============================
server {
    listen 80 default_server;
    listen 8080;
    listen 2086;
    listen 8880;
    listen [::]:80 default_server;
    listen [::]:8080;
    listen [::]:2086;
    listen [::]:8880;
    server_name ${dom} _;
    root /var/www/html;
    index index.html;

    location = /vmess {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }

    location = /vless {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }

    location = /trojan-ws {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }

    # SSH-over-WebSocket (Nginx -> python WS proxy -> SSH:22 / Dropbear:109)
    location = /ws-ssh {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 7200s;
        proxy_buffering off;
    }

    location / { return 200 'MAX PANEL OK'; add_header Content-Type text/plain; }
}

# === HTTPS TLS: 443, 2083, 2087, 8443 ================================
server {
    listen 443 ssl http2;
    listen 2083 ssl http2;
    listen 2087 ssl http2;
    listen 8443 ssl http2;
    listen [::]:443 ssl http2;
    listen [::]:2083 ssl http2;
    listen [::]:2087 ssl http2;
    listen [::]:8443 ssl http2;
    server_name ${dom} _;

    ssl_certificate     /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;

    # gRPC VLess
    location ^~ /vless-grpc {
        grpc_pass grpc://127.0.0.1:10004;
        grpc_set_header Host \$host;
        client_max_body_size 0;
    }

    # gRPC Trojan
    location ^~ /trojan-grpc {
        grpc_pass grpc://127.0.0.1:10005;
        grpc_set_header Host \$host;
        client_max_body_size 0;
    }

    # WS over TLS (Nginx terminates TLS, forward plaintext WS ke Xray internal)
    location = /vmess {
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }
    location = /vless {
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }
    location = /trojan-ws {
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }
    location = /ws-ssh {
        proxy_pass http://127.0.0.1:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 7200s;
        proxy_buffering off;
    }

    location / { return 200 'MAX PANEL OK'; add_header Content-Type text/plain; }
}
NGX

    # Test config dulu, baru restart (jangan break Nginx existing)
    if nginx -t &>/dev/null; then
        systemctl enable nginx &>/dev/null
        systemctl restart nginx 2>/dev/null
        is_up nginx && ok "Nginx aktif (HTTP 80/8080/2086/8880 + TLS 443/2083/2087/8443)" \
                    || warn "Nginx belum aktif"
    else
        err "Konfigurasi Nginx INVALID -- cek: nginx -t"
        nginx -t 2>&1 | tail -10 | while read -r ln; do warn "  $ln"; done
    fi
}


# ════════════════════════════════════════════════════════════
#  INSTALLER — OHP (OpenSSH Over HTTP) — opsional
# ════════════════════════════════════════════════════════════
install_ohp() {
    inf "Install OHP (OpenSSH Over HTTP)..."
    if [[ ! -x "$OHP_BIN" ]]; then
        if dl "$OHP_URL" "$OHP_BIN"; then
            chmod +x "$OHP_BIN"
            if ! verify_binary "$OHP_BIN" 100000; then
                rm -f "$OHP_BIN"
                warn "Binary OHP gagal — dilewati"
                return
            fi
        else
            warn "Gagal download OHP — fitur opsional dilewati"
            return
        fi
    fi
    # Service OHP port 8081 (8080 dipakai Nginx HTTP)
    cat > /etc/systemd/system/ohp.service <<OHPEOF
[Unit]
Description=OHP OpenSSH Over HTTP
After=network.target

[Service]
Type=simple
User=root
ExecStart=$OHP_BIN -port=8081 -bind=0.0.0.0 -proxy=127.0.0.1:22
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
OHPEOF
    systemctl daemon-reload
    systemctl enable ohp &>/dev/null
    systemctl restart ohp 2>/dev/null
    ok "OHP aktif di port 8081"
}

# ════════════════════════════════════════════════════════════
#  MASTER INSTALLER — Jalankan semua step 1..15
# ════════════════════════════════════════════════════════════
do_install_all() {
    show_header
    _top; _btn "  ${IT}${AL}🚀  INSTALL MAX PANEL — Premium Tunneling${NC}"; _bot; echo ""

    # Trap untuk fail-safe
    trap 'err "Instalasi gagal di langkah: ${CURRENT_STEP:-unknown}"; trap - ERR; return 1' ERR

    local sip; sip=$(get_ip)
    echo -ne "  ${A3}Domain / IP${NC}             : "; read -r inp_domain
    [[ -z "$inp_domain" ]] && inp_domain="$sip"
    echo -ne "  ${A3}Nama Brand / Toko${NC}       : "; read -r inp_brand
    [[ -z "$inp_brand" ]] && inp_brand="MAX PANEL"
    echo -ne "  ${A3}Username Telegram Admin${NC}  : "; read -r inp_tg
    [[ -z "$inp_tg" ]] && inp_tg="-"

    mkdir -p "$DIR" "$LOGDIR"
    echo "$inp_domain" > "$DOMF"
    printf "BRAND=%q\nADMIN_TG=%q\n" "$inp_brand" "$inp_tg" > "$STRF"
    [[ ! -f "$THEMEF" ]] && echo "1" > "$THEMEF"
    echo "$SCRIPT_VERSION" > "$VERSIONF"

    # Buat file DB kosong supaya selalu ada
    for f in "$MLDB" "$SSH_DB" "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" \
             "$TROJANGO_DB" "$OVPN_DB" "$WG_DB" "$HY_DB" "$SS_DB" "$SLOW_DB"; do
        touch "$f"
    done

    echo ""
    echo -e "  ${A1}${_DASH}${NC}"
    inf "Mulai instalasi ${AL}MAX PANEL Premium${NC} → 15 langkah..."
    echo -e "  ${A1}${_DASH}${NC}"; echo ""

    _step() {
        local n="$1" desc="$2"
        CURRENT_STEP="$desc"
        echo ""
        echo -e "  ${A4}[${n}/15]${NC} ${BLD}${AL}${desc}${NC}"
        echo -e "  ${A1}${_DASH}${NC}"
    }

    _step  1 "Cek root & OS";                        check_root; check_os; ok "OS: $OS_NAME"
    _step  2 "Update apt + install dependencies";    install_deps
    _step  3 "Setup direktori /etc/maxpanel";        mkdir -p "$DIR" "$LOGDIR" "$BACKUPDIR"; ok "Direktori siap"
    _step  4 "Generate SSL self-signed (fallback)";  gen_selfsigned_ssl
    _step  5 "OpenSSH + Dropbear + Stunnel";         install_ssh
    _step  6 "Xray-core (VMess/VLess/Trojan/SS)";    install_xray
    _step  7 "Trojan-Go (port 2096)";                install_trojan_go
    _step  8 "Hysteria 2 (UDP 36712 + range)";       install_hysteria
    _step  9 "BadVPN UDPGW (7100/7200/7300)";        install_udpgw
    _step 10 "OpenVPN (TCP 1194 + UDP 2200)";        install_openvpn
    _step 11 "WireGuard (UDP 51820)";                install_wireguard
    _step 12 "SlowDNS (port 53 + 5300)";             install_slowdns
    _step 13 "WebSocket Python proxy";               install_ws_proxy
    _step 14 "Nginx reverse-proxy (path-routing)";   install_nginx
    _step 15 "Cron: expired cleanup + maxlogin + backup"; install_cron_jobs

    trap - ERR

    # Kernel tuning + BBR + IPv6
    enable_bbr_silent
    sysctl -w net.core.rmem_max=16777216 &>/dev/null
    sysctl -w net.core.wmem_max=16777216 &>/dev/null

    # Setup menu command
    setup_menu_cmd
    install_ssh_splash

    # Tulis version
    echo "$SCRIPT_VERSION" > "$VERSIONF"

    echo ""
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${LG}${BLD}  ✦  MAX PANEL PREMIUM BERHASIL DIINSTALL!${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    printf  "  ${DIM} Domain     :${NC}  ${W}%s${NC}\n" "$inp_domain"
    printf  "  ${DIM} Brand      :${NC}  ${AL}%s${NC}\n" "$inp_brand"
    printf  "  ${DIM} Versi      :${NC}  ${Y}%s${NC}\n" "$SCRIPT_VERSION"
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${BLD}${A4}  Daftar Protokol & Port${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    printf  "  ${A3}•${NC} OpenSSH         : ${Y}22${NC}\n"
    printf  "  ${A3}•${NC} Dropbear        : ${Y}109, 143${NC}\n"
    printf  "  ${A3}•${NC} Stunnel SSL     : ${Y}990, 446, 110, 444${NC}\n"
    printf  "  ${A3}•${NC} Nginx (HTTP)    : ${Y}80, 8080, 2086, 8880${NC}\n"
    printf  "  ${A3}•${NC} Nginx (TLS)     : ${Y}443, 2083, 2087, 8443${NC}\n"
    printf  "  ${A3}•${NC} SSH WebSocket   : ${Y}/ws-ssh${NC} (→ internal 127.0.0.1:8880)\n"
    printf  "  ${A3}•${NC} OpenVPN         : ${Y}TCP 1194, UDP 2200${NC}\n"
    printf  "  ${A3}•${NC} Xray VMess WS   : ${Y}/vmess${NC}  (HTTP + TLS multi-port)\n"
    printf  "  ${A3}•${NC} Xray VLess WS   : ${Y}/vless${NC}  + gRPC ${Y}/vless-grpc${NC}\n"
    printf  "  ${A3}•${NC} Xray Trojan     : ${Y}/trojan-ws${NC} + gRPC ${Y}/trojan-grpc${NC}\n"
    printf  "  ${A3}•${NC} Shadowsocks-22  : ${Y}8388${NC}\n"
    printf  "  ${A3}•${NC} Trojan-Go       : ${Y}2096${NC}\n"
    printf  "  ${A3}•${NC} BadVPN UDPGW    : ${Y}7100, 7200, 7300${NC}\n"
    printf  "  ${A3}•${NC} Hysteria 2      : ${Y}UDP 36712 (+ 5300, 7300)${NC}\n"
    printf  "  ${A3}•${NC} SlowDNS         : ${Y}53 → 5300${NC}\n"
    printf  "  ${A3}•${NC} WireGuard       : ${Y}UDP 51820${NC}\n"
    echo -e "  ${A1}${_DASH}${NC}"
    echo ""
    echo -e "  ${DIM}Ketik ${A1}menu-max${NC}${DIM} kapan saja untuk membuka panel.${NC}"
    echo -e "  ${DIM}Reboot disarankan untuk memastikan semua service aktif.${NC}"
    echo ""

    _tg_send "🎉 <b>MAX PANEL terpasang</b>
🌐 Domain : <code>$inp_domain</code>
🖥 IP     : <code>$sip</code>
📦 Versi  : <code>$SCRIPT_VERSION</code>"

    pause
}

# ── Generate self-signed SSL untuk seluruh service (single shared) ──
gen_selfsigned_ssl() {
    local dom; dom=$(get_domain)
    mkdir -p /etc/xray /etc/hysteria /etc/trojan-go
    if [[ ! -s /etc/xray/xray.crt ]]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -subj "/CN=${dom}" \
            -keyout /etc/xray/xray.key -out /etc/xray/xray.crt &>/dev/null
        # FIX: private key WAJIB 600
        chmod 644 /etc/xray/xray.crt
        chmod 600 /etc/xray/xray.key
    fi
    # Copy ke service lain (preserve perm 600 untuk key)
    cp -f /etc/xray/xray.crt /etc/hysteria/server.crt 2>/dev/null
    cp -f /etc/xray/xray.key /etc/hysteria/server.key 2>/dev/null
    cp -f /etc/xray/xray.crt /etc/trojan-go/server.crt 2>/dev/null
    cp -f /etc/xray/xray.key /etc/trojan-go/server.key 2>/dev/null
    chmod 644 /etc/hysteria/server.crt /etc/trojan-go/server.crt 2>/dev/null
    chmod 600 /etc/hysteria/server.key /etc/trojan-go/server.key 2>/dev/null
    ok "SSL self-signed siap (CN=${dom})"
}

# ── BBR silent (panggil dari installer) ─────────────────────────────────────────────────────────
enable_bbr_silent() {
    modprobe tcp_bbr 2>/dev/null
    # FIX: pakai marker idempotent (re-run aman, tidak duplikat baris)
    _apply_block "BBR-MODULE" /etc/modules-load.d/maxpanel.conf <<'BBRMOD'
tcp_bbr
BBRMOD
    sysctl -w net.core.default_qdisc=fq           &>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr &>/dev/null
    _apply_block "BBR-SYSCTL" /etc/sysctl.conf <<'BBRSYS'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
BBRSYS
    sysctl -p &>/dev/null
}

# ════════════════════════════════════════════════════════════
#  USER MANAGEMENT — SSH / OpenSSH + Dropbear (shared user db)
# ════════════════════════════════════════════════════════════
ssh_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN SSH${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}              : "; read -r u
    [[ -z "$u" ]] && { err "Username kosong!"; pause; return; }
    if id "$u" &>/dev/null; then err "User sistem '$u' sudah ada!"; pause; return; fi
    grep -q "^${u}|" "$SSH_DB" 2>/dev/null && { err "Username sudah terdaftar!"; pause; return; }

    echo -ne "  ${A3}Password${NC} [auto]      : "; read -r p
    [[ -z "$p" ]] && p=$(rand_pass)

    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && d=30

    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ -z "$ml" || ! "$ml" =~ ^[0-9]+$ ]] && ml=2

    local exp; exp=$(mk_exp "$d")

    # Buat user sistem dengan shell /bin/false (hanya bisa tunnel)
    useradd -e "$exp" -s /bin/false -M "$u" 2>/dev/null
    echo -e "${p}\n${p}" | passwd "$u" &>/dev/null

    echo "${u}|${p}|${exp}|${ml}" >> "$SSH_DB"
    set_maxlogin "$u" "$ml"

    show_box_ssh "$u" "$p" "$exp" "$ml"

    local ip dom brand
    ip=$(get_ip); dom=$(get_domain); brand=$(_tg_brand)
    tg_send_text "<b>✅ Akun SSH/OpenSSH — ${brand}</b>
━━━━━━━━━━━━━━━━━━━━━━━
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
━━━━━━━━━━━━━━━━━━━━━━━
🖥 <b>IP Publik</b> : <code>${ip}</code>
🌐 <b>Host</b>      : <code>${dom}</code>
🔌 <b>Port SSH</b>  : <code>22</code>
🔌 <b>Dropbear</b>  : <code>109, 143</code>
🔒 <b>SSH SSL</b>   : <code>990, 446, 110, 444</code>
🔌 <b>WS HTTP</b>   : <code>80, 8080, 2086, 8880 (/ws-ssh)</code>
🔒 <b>WS HTTPS</b>  : <code>443, 2083, 2087, 8443 (/ws-ssh)</code>
📡 <b>OpenVPN</b>   : <code>TCP 1194 / UDP 2200</code>
📡 <b>UDPGW</b>     : <code>7100, 7200, 7300</code>
━━━━━━━━━━━━━━━━━━━━━━━
🔒 <b>MaxLogin</b>  : <code>${ml} device</code>
📅 <b>Expired</b>   : <code>${exp}</code>"

    pause
}

ssh_trial() {
    show_header
    _top; _btn "  ${IT}${AL}🎁  AKUN SSH TRIAL (1 jam)${NC}"; _bot; echo ""
    local u="trial$(date +%s | tail -c 6)"
    local p; p=$(rand_pass)
    # Exp 1 jam dari sekarang — pakai useradd -e (tetap 1 hari minimum di /etc/shadow)
    local exp; exp=$(TZ="Asia/Jakarta" date +"%Y-%m-%d")
    useradd -s /bin/false -M "$u" 2>/dev/null
    echo -e "${p}\n${p}" | passwd "$u" &>/dev/null
    chage -E "$(date -d '+1 day' +%Y-%m-%d)" "$u" 2>/dev/null

    echo "${u}|${p}|TRIAL-$(date +%s)|1" >> "$SSH_DB"
    set_maxlogin "$u" "1"

    # Schedule auto-delete 1 jam (atrun atau cron)
    if command -v at &>/dev/null; then
        echo "/usr/sbin/userdel -r ${u}; sed -i '/^${u}|/d' ${SSH_DB}; sed -i '/^${u}|/d' ${MLDB}" | \
            at now + 1 hour 2>/dev/null
    else
        # Fallback: tulis ke /etc/cron.d
        local cron_id="trial-$(date +%s)-${u}"
        local t; t=$(TZ="Asia/Jakarta" date -d "+1 hour" "+%M %H %d %m")
        echo "$t * root /usr/sbin/userdel -r ${u}; sed -i '/^${u}|/d' ${SSH_DB}; rm -f /etc/cron.d/${cron_id}" \
            > "/etc/cron.d/${cron_id}"
    fi

    show_box_ssh "$u" "$p" "Trial 1 jam" "1"

    local ip dom brand
    ip=$(get_ip); dom=$(get_domain); brand=$(_tg_brand)
    tg_send_text "<b>🎁 SSH Trial — ${brand}</b>
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>Host</b>      : <code>${dom}</code>
🖥 <b>IP</b>        : <code>${ip}</code>
🔌 <b>SSH</b>       : <code>22</code>
🔒 <b>SSH SSL</b>   : <code>990, 446, 110, 444</code>
📅 <b>Expired</b>   : <code>Trial 1 jam</code>"
    pause
}

ssh_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS AKUN SSH${NC}"; _bot; echo ""
    ssh_list_compact
    echo ""
    echo -ne "  ${A3}Username yang dihapus${NC}: "; read -r u
    [[ -z "$u" ]] && { err "Username kosong!"; pause; return; }
    if ! grep -q "^${u}|" "$SSH_DB" 2>/dev/null; then
        err "User '$u' tidak ada di DB!"; pause; return
    fi
    userdel -r "$u" 2>/dev/null
    sed -i "/^${u}|/d" "$SSH_DB"
    del_maxlogin "$u"
    ok "User ${W}${u}${NC} dihapus dari sistem & DB"
    _tg_send "🗑 <b>SSH User Deleted</b>
👤 <code>${u}</code>"
    pause
}

ssh_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG AKUN SSH${NC}"; _bot; echo ""
    ssh_list_compact
    echo ""
    echo -ne "  ${A3}Username${NC}             : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    if ! grep -q "^${u}|" "$SSH_DB" 2>/dev/null; then
        err "User tidak ada!"; pause; return
    fi
    echo -ne "  ${A3}Tambah masa aktif (hari)${NC} [30]: "; read -r d
    [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && d=30

    local cur_exp new_exp
    cur_exp=$(grep "^${u}|" "$SSH_DB" | cut -d'|' -f3 | head -1)
    new_exp=$(TZ="Asia/Jakarta" date -d "${cur_exp} +${d} days" +"%Y-%m-%d" 2>/dev/null)
    [[ -z "$new_exp" ]] && new_exp=$(mk_exp "$d")

    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new_exp}|" "$SSH_DB"
    chage -E "$new_exp" "$u" 2>/dev/null
    ok "Akun ${W}${u}${NC} diperpanjang sampai ${Y}${new_exp}${NC}"
    pause
}

ssh_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST AKUN SSH${NC}"; _bot; echo ""
    if [[ ! -s "$SSH_DB" ]]; then
        warn "Belum ada akun SSH."
        pause; return
    fi
    printf "  ${BLD}${A3}%-3s %-15s %-12s %-12s %-5s${NC}\n" "No" "Username" "Password" "Expired" "ML"
    _sep
    local i=0
    while IFS='|' read -r u p e ml; do
        i=$((i+1))
        local left col
        left=$(days_left "$e")
        if is_expired "$e"; then col="$LR"; left="EXP"
        elif [[ "$left" -le 3 ]]; then col="$Y"
        else col="$LG"
        fi
        printf "  %-3s ${W}%-15s${NC} ${A3}%-12s${NC} ${col}%-12s${NC} ${Y}%-5s${NC}\n" \
            "$i." "$u" "$p" "$e" "$ml"
    done < "$SSH_DB"
    _sep
    pause
}

ssh_list_compact() {
    if [[ ! -s "$SSH_DB" ]]; then
        warn "Belum ada akun SSH."
        return
    fi
    printf "  ${DIM}%-3s %-15s %-12s %-12s${NC}\n" "No" "Username" "Pass" "Expired"
    local i=0
    while IFS='|' read -r u p e _; do
        i=$((i+1))
        printf "  %-3s ${W}%-15s${NC} ${A3}%-12s${NC} ${Y}%-12s${NC}\n" "$i." "$u" "$p" "$e"
    done < "$SSH_DB"
}

ssh_online() {
    show_header
    _top; _btn "  ${IT}${AL}🔍  CEK USER SSH ONLINE${NC}"; _bot; echo ""
    local list
    list=$(ps -eo user,pid,etime,cmd --no-headers 2>/dev/null | grep 'sshd:' | grep -v 'root' | awk '{print $1}' | sort -u)
    if [[ -z "$list" ]]; then
        warn "Tidak ada user SSH online."
    else
        printf "  ${BLD}${A3}%-3s %-15s %-10s${NC}\n" "No" "Username" "Login"
        _sep
        local i=0
        while read -r u; do
            i=$((i+1))
            local cnt; cnt=$(ps -eo user,cmd --no-headers 2>/dev/null | grep "sshd: ${u}@" | grep -c -v grep)
            printf "  %-3s ${W}%-15s${NC} ${LG}%-10s${NC}\n" "$i." "$u" "$cnt sesi"
        done <<< "$list"
        _sep
    fi
    pause
}

ssh_clean_expired() {
    show_header
    _top; _btn "  ${IT}${AL}🧹  HAPUS USER EXPIRED${NC}"; _bot; echo ""
    if [[ ! -s "$SSH_DB" ]]; then
        warn "DB kosong."
        pause; return
    fi
    local td; td=$(TZ="Asia/Jakarta" date +%Y-%m-%d)
    local count=0
    while IFS='|' read -r u p e ml; do
        if [[ -n "$e" && "$td" > "$e" ]]; then
            userdel -r "$u" 2>/dev/null
            sed -i "/^${u}|/d" "$SSH_DB"
            del_maxlogin "$u"
            ok "Deleted: ${W}${u}${NC} (exp ${e})"
            count=$((count+1))
        fi
    done < "$SSH_DB"
    [[ "$count" == "0" ]] && inf "Tidak ada user expired."
    pause
}

# ════════════════════════════════════════════════════════════
#  USER MANAGEMENT — Xray (VMess / VLess / Trojan) + SS
# ════════════════════════════════════════════════════════════
# Helper: rotate config via python (jq tidak selalu ada di minimal sys)
_xray_reload() {
    systemctl restart xray 2>/dev/null
    sleep 0.5
}

# Update inbound clients berdasarkan DB (panggil setiap CRUD)
_xray_sync_clients() {
    python3 - <<'PYSYNC' 2>/dev/null
import json, os
CFG = "/etc/xray/config.json"
DIR = "/etc/maxpanel"
def load(p):
    try:
        with open(p) as f: return [l.strip() for l in f if l.strip()]
    except: return []
def parse_users(path):
    out=[]
    for line in load(path):
        parts = line.split('|')
        if len(parts)<3: continue
        out.append(parts)
    return out
with open(CFG) as f: cfg = json.load(f)
inbounds = cfg.get('inbounds', [])
def set_inbound(tag, clients):
    for ib in inbounds:
        if ib.get('tag') == tag:
            ib.setdefault('settings', {})['clients'] = clients
def vless_clients():
    return [ {"id": u[1], "email": u[0], "flow": ""} for u in parse_users(os.path.join(DIR,"vless-users.db")) ]
def vmess_clients():
    return [ {"id": u[1], "alterId": 0, "email": u[0]} for u in parse_users(os.path.join(DIR,"vmess-users.db")) ]
def trojan_clients():
    return [ {"password": u[1], "email": u[0]} for u in parse_users(os.path.join(DIR,"trojan-users.db")) ]
def ss_clients():
    out=[]
    for u in parse_users(os.path.join(DIR,"ss-users.db")):
        out.append({"password": u[1], "method":"aes-128-gcm", "email": u[0]})
    return out
# VLess (single WS inbound + single gRPC inbound \u2014 TLS dipisah ke Nginx)
for tag in ("vless-ws","vless-grpc"):
    set_inbound(tag, vless_clients())
# VMess (single WS inbound)
for tag in ("vmess-ws",):
    set_inbound(tag, vmess_clients())
# Trojan (WS + gRPC)
for tag in ("trojan-ws","trojan-grpc"):
    set_inbound(tag, trojan_clients())
# SS
ss = ss_clients()
for ib in inbounds:
    if ib.get('tag') == 'ss-2022':
        ib.setdefault('settings', {})
        if ss:
            ib['settings']['clients'] = ss
            # ss-2022 single password fallback
            ib['settings'].setdefault('method','aes-128-gcm')
        else:
            ib['settings']['clients'] = []
            ib['settings'].setdefault('method','aes-128-gcm')
with open(CFG,'w') as f: json.dump(cfg, f, indent=2)
PYSYNC
    _xray_reload
}

# ── VMess ─────────────────────────────────────────────────────────
vmess_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN VMESS${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username/Remark${NC}      : "; read -r u
    [[ -z "$u" ]] && { err "Kosong!"; pause; return; }
    grep -q "^${u}|" "$VMESS_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ -z "$ml" || ! "$ml" =~ ^[0-9]+$ ]] && ml=2

    local uuid exp
    uuid=$(rand_uuid)
    exp=$(mk_exp "$d")

    echo "${u}|${uuid}|${exp}|${ml}" >> "$VMESS_DB"
    set_maxlogin "$u" "$ml"
    _xray_sync_clients

    show_box_xray "VMess" "$u" "$uuid" "$exp" "$ml"

    # Cetak link VMess (base64)
    local dom ip
    dom=$(get_domain); ip=$(get_ip)
    local vmess_tls vmess_ntls
    vmess_tls=$(printf '%s' "{\"v\":\"2\",\"ps\":\"${u}-TLS\",\"add\":\"${dom}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${dom}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${dom}\"}" | base64 -w0)
    vmess_ntls=$(printf '%s' "{\"v\":\"2\",\"ps\":\"${u}-HTTP\",\"add\":\"${dom}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${dom}\",\"path\":\"/vmess\",\"tls\":\"none\"}" | base64 -w0)
    echo -e "  ${DIM}🔗 Link VMess TLS :${NC}"
    echo -e "  ${LG}vmess://${vmess_tls}${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link VMess HTTP:${NC}"
    echo -e "  ${LG}vmess://${vmess_ntls}${NC}"
    echo ""

    # Full TG notif + config file
    local brand ip; brand=$(_tg_brand); ip=$(get_ip)
    tg_send_text "<b>✅ Akun VMess — ${brand}</b>
━━━━━━━━━━━━━━━━━━━━━━━
👤 <b>Remark</b>    : <code>${u}</code>
🔑 <b>UUID</b>      : <code>${uuid}</code>
━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Host</b>      : <code>${dom}</code>
🖥 <b>IP</b>        : <code>${ip}</code>
🔒 <b>Port TLS</b>  : <code>443, 2083, 2087, 8443</code>
🔌 <b>Port HTTP</b> : <code>80, 8080, 2086, 8880</code>
🛣  <b>WS Path</b>   : <code>/vmess</code>
🛣  <b>Network</b>   : <code>ws, h2, tls</code>
━━━━━━━━━━━━━━━━━━━━━━━
🔒 <b>MaxLogin</b>  : <code>${ml} device</code>
📅 <b>Expired</b>   : <code>${exp}</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "vmess-${u}.txt" \
        "MAX PANEL -- VMess account ${u}" \
        "Host       : ${dom}" \
        "IP         : ${ip}" \
        "Port TLS   : 443, 2083, 2087, 8443" \
        "Port HTTP  : 80, 8080, 2086, 8880" \
        "UUID       : ${uuid}" \
        "AlterID    : 0" \
        "Path       : /vmess" \
        "Network    : ws / h2 / tls" \
        "Expired    : ${exp}" \
        "" \
        "# Link VMess TLS:" \
        "vmess://${vmess_tls}" \
        "" \
        "# Link VMess HTTP:" \
        "vmess://${vmess_ntls}")
    tg_send_file "$cfg_path" "<b>VMess config</b> — <code>${u}</code>"

    pause
}

vmess_trial() {
    show_header
    _top; _btn "  ${IT}${AL}🎁  VMESS TRIAL (1 jam)${NC}"; _bot; echo ""
    local u="trial-vmess-$(date +%s | tail -c 5)"
    local uuid; uuid=$(rand_uuid)
    local exp; exp=$(mk_exp 1)
    echo "${u}|${uuid}|TRIAL|${exp}|1" >> "$VMESS_DB"
    set_maxlogin "$u" "1"
    _xray_sync_clients

    show_box_xray "VMess" "$u" "$uuid" "Trial 1 jam" "1"

    # Auto-delete 1 jam
    local cron_id="trial-vmess-$(date +%s)"
    local t; t=$(TZ="Asia/Jakarta" date -d "+1 hour" "+%M %H %d %m")
    echo "$t * root sed -i '/^${u}|/d' ${VMESS_DB}; sed -i '/^${u}|/d' ${MLDB}; /usr/local/bin/max-menu --sync-xray; rm -f /etc/cron.d/${cron_id}" \
        > "/etc/cron.d/${cron_id}"

    local dom ip brand vmess_tls vmess_ntls
    dom=$(get_domain); ip=$(get_ip); brand=$(_tg_brand)
    vmess_tls=$(printf '%s' "{\"v\":\"2\",\"ps\":\"${u}-TLS\",\"add\":\"${dom}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${dom}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${dom}\"}" | base64 -w0)
    vmess_ntls=$(printf '%s' "{\"v\":\"2\",\"ps\":\"${u}-HTTP\",\"add\":\"${dom}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${dom}\",\"path\":\"/vmess\",\"tls\":\"none\"}" | base64 -w0)
    tg_send_text "<b>🎁 VMess Trial — ${brand}</b>
👤 <b>Remark</b>   : <code>${u}</code>
🔑 <b>UUID</b>     : <code>${uuid}</code>
🌐 <b>Host</b>     : <code>${dom}</code>
🔒 <b>Port TLS</b> : <code>443, 2083, 2087, 8443</code>
🔌 <b>Port HTTP</b>: <code>80, 8080, 2086, 8880</code>
🛣  <b>Path</b>     : <code>/vmess</code>
📅 <b>Expired</b>  : <code>Trial 1 jam</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "vmess-trial-${u}.txt" \
        "vmess://${vmess_tls}" \
        "vmess://${vmess_ntls}")
    tg_send_file "$cfg_path" "<b>VMess Trial config</b> — <code>${u}</code>"
    pause
}

vmess_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS AKUN VMESS${NC}"; _bot; echo ""
    xray_list_compact "$VMESS_DB" "VMess"
    echo ""
    echo -ne "  ${A3}Username VMess${NC}: "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    if ! grep -q "^${u}|" "$VMESS_DB"; then err "User tidak ada!"; pause; return; fi
    sed -i "/^${u}|/d" "$VMESS_DB"
    del_maxlogin "$u"
    _xray_sync_clients
    ok "VMess ${W}${u}${NC} dihapus"
    _tg_send "🗑 VMess deleted: <code>${u}</code>"
    pause
}

vmess_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG VMESS${NC}"; _bot; echo ""
    xray_list_compact "$VMESS_DB" "VMess"
    echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    if ! grep -q "^${u}|" "$VMESS_DB"; then err "User tidak ada!"; pause; return; fi
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$VMESS_DB" | cut -d'|' -f3)
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new}|" "$VMESS_DB"
    ok "VMess ${W}${u}${NC} diperpanjang → ${Y}${new}${NC}"
    pause
}

vmess_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST AKUN VMESS${NC}"; _bot; echo ""
    xray_list_pretty "$VMESS_DB" "VMess" "UUID"
    pause
}

# ── VLess ─────────────────────────────────────────────────────────
vless_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN VLESS${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username/Remark${NC}      : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$VLESS_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ -z "$ml" || ! "$ml" =~ ^[0-9]+$ ]] && ml=2

    local uuid exp
    uuid=$(rand_uuid); exp=$(mk_exp "$d")
    echo "${u}|${uuid}|${exp}|${ml}" >> "$VLESS_DB"
    set_maxlogin "$u" "$ml"
    _xray_sync_clients

    show_box_xray "VLess" "$u" "$uuid" "$exp" "$ml"

    local dom; dom=$(get_domain)
    echo -e "  ${DIM}🔗 Link VLess WS TLS :${NC}"
    echo -e "  ${LG}vless://${uuid}@${dom}:443?path=/vless&security=tls&encryption=none&host=${dom}&type=ws&sni=${dom}#${u}-TLS${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link VLess WS HTTP:${NC}"
    echo -e "  ${LG}vless://${uuid}@${dom}:80?path=/vless&encryption=none&host=${dom}&type=ws#${u}-HTTP${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link VLess gRPC TLS:${NC}"
    echo -e "  ${LG}vless://${uuid}@${dom}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${dom}#${u}-gRPC${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link VLess gRPC alt-TLS (port 8443):${NC}"
    echo -e "  ${DIM}vless://${uuid}@${dom}:8443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${dom}#${u}-gRPC-ALT${NC}"
    echo ""
    local brand ip
    brand=$(_tg_brand); ip=$(get_ip)
    tg_send_text "<b>✅ Akun VLess — ${brand}</b>
━━━━━━━━━━━━━━━━━━━━━━━
👤 <b>Remark</b>    : <code>${u}</code>
🔑 <b>UUID</b>      : <code>${uuid}</code>
━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Host</b>      : <code>${dom}</code>
🖥 <b>IP</b>        : <code>${ip}</code>
🔒 <b>Port TLS</b>  : <code>443, 2083, 2087, 8443</code>
🔌 <b>Port HTTP</b> : <code>80, 8080, 2086, 8880</code>
🛣  <b>WS Path</b>   : <code>/vless</code>
🛣  <b>gRPC SVC</b>  : <code>vless-grpc</code>
━━━━━━━━━━━━━━━━━━━━━━━
🔒 <b>MaxLogin</b>  : <code>${ml} device</code>
📅 <b>Expired</b>   : <code>${exp}</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "vless-${u}.txt" \
        "MAX PANEL -- VLess account ${u}" \
        "Host       : ${dom}" \
        "IP         : ${ip}" \
        "Port TLS   : 443, 2083, 2087, 8443" \
        "Port HTTP  : 80, 8080, 2086, 8880" \
        "UUID       : ${uuid}" \
        "Path       : /vless" \
        "gRPC SVC   : vless-grpc" \
        "Expired    : ${exp}" \
        "" \
        "# VLess WS TLS:" \
        "vless://${uuid}@${dom}:443?path=/vless&security=tls&encryption=none&host=${dom}&type=ws&sni=${dom}#${u}-TLS" \
        "" \
        "# VLess WS HTTP:" \
        "vless://${uuid}@${dom}:80?path=/vless&encryption=none&host=${dom}&type=ws#${u}-HTTP" \
        "" \
        "# VLess gRPC TLS:" \
        "vless://${uuid}@${dom}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${dom}#${u}-gRPC")
    tg_send_file "$cfg_path" "<b>VLess config</b> — <code>${u}</code>"
    pause
}

vless_trial() {
    show_header
    _top; _btn "  ${IT}${AL}🎁  VLESS TRIAL (1 jam)${NC}"; _bot; echo ""
    local u="trial-vless-$(date +%s | tail -c 5)"
    local uuid; uuid=$(rand_uuid)
    echo "${u}|${uuid}|$(mk_exp 1)|1" >> "$VLESS_DB"
    set_maxlogin "$u" "1"
    _xray_sync_clients
    show_box_xray "VLess" "$u" "$uuid" "Trial 1 jam" "1"
    local cron_id="trial-vless-$(date +%s)"
    local t; t=$(TZ="Asia/Jakarta" date -d "+1 hour" "+%M %H %d %m")
    echo "$t * root sed -i '/^${u}|/d' ${VLESS_DB}; /usr/local/bin/max-menu --sync-xray; rm -f /etc/cron.d/${cron_id}" \
        > "/etc/cron.d/${cron_id}"
    local dom brand; dom=$(get_domain); brand=$(_tg_brand)
    tg_send_text "<b>🎁 VLess Trial — ${brand}</b>
👤 <b>Remark</b>   : <code>${u}</code>
🔑 <b>UUID</b>     : <code>${uuid}</code>
🌐 <b>Host</b>     : <code>${dom}</code>
🔒 <b>Port TLS</b> : <code>443, 2083, 2087, 8443</code>
🔌 <b>Port HTTP</b>: <code>80, 8080, 2086, 8880</code>
📅 <b>Expired</b>  : <code>Trial 1 jam</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "vless-trial-${u}.txt" \
        "vless://${uuid}@${dom}:443?path=/vless&security=tls&encryption=none&host=${dom}&type=ws&sni=${dom}#${u}-TLS" \
        "vless://${uuid}@${dom}:80?path=/vless&encryption=none&host=${dom}&type=ws#${u}-HTTP")
    tg_send_file "$cfg_path" "<b>VLess Trial config</b> — <code>${u}</code>"
    pause
}

vless_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS AKUN VLESS${NC}"; _bot; echo ""
    xray_list_compact "$VLESS_DB" "VLess"
    echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$VLESS_DB" || { err "User tidak ada!"; pause; return; }
    sed -i "/^${u}|/d" "$VLESS_DB"; del_maxlogin "$u"; _xray_sync_clients
    ok "VLess ${W}${u}${NC} dihapus"
    pause
}

vless_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG VLESS${NC}"; _bot; echo ""
    xray_list_compact "$VLESS_DB" "VLess"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$VLESS_DB" || { err "User tidak ada!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$VLESS_DB" | cut -d'|' -f3)
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new}|" "$VLESS_DB"
    ok "Diperpanjang → ${Y}${new}${NC}"
    pause
}

vless_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST AKUN VLESS${NC}"; _bot; echo ""
    xray_list_pretty "$VLESS_DB" "VLess" "UUID"
    pause
}

# ── Trojan (Xray) ─────────────────────────────────────────────────────────
trojan_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN TROJAN${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username/Remark${NC}      : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$TROJAN_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    echo -ne "  ${A3}Password${NC} [auto]      : "; read -r p
    [[ -z "$p" ]] && p=$(rand_pass)
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ ! "$ml" =~ ^[0-9]+$ ]] && ml=2
    local exp; exp=$(mk_exp "$d")
    echo "${u}|${p}|${exp}|${ml}" >> "$TROJAN_DB"
    set_maxlogin "$u" "$ml"
    _xray_sync_clients
    show_box_xray "Trojan" "$u" "$p" "$exp" "$ml"
    local dom; dom=$(get_domain)
    echo -e "  ${DIM}🔗 Link Trojan WS TLS  :${NC}"
    echo -e "  ${LG}trojan://${p}@${dom}:443?path=/trojan-ws&security=tls&host=${dom}&type=ws&sni=${dom}#${u}-WS${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link Trojan gRPC TLS:${NC}"
    echo -e "  ${LG}trojan://${p}@${dom}:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni=${dom}#${u}-gRPC${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link Trojan gRPC alt-TLS (port 8443):${NC}"
    echo -e "  ${DIM}trojan://${p}@${dom}:8443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni=${dom}#${u}-gRPC-ALT${NC}"
    echo ""
    local brand ip; brand=$(_tg_brand); ip=$(get_ip)
    tg_send_text "<b>✅ Akun Trojan — ${brand}</b>
━━━━━━━━━━━━━━━━━━━━━━━
👤 <b>Remark</b>    : <code>${u}</code>
🔑 <b>Password</b>  : <code>${p}</code>
━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Host</b>      : <code>${dom}</code>
🖥 <b>IP</b>        : <code>${ip}</code>
🔒 <b>Port TLS</b>  : <code>443, 2083, 2087, 8443</code>
🛣  <b>WS Path</b>   : <code>/trojan-ws</code>
🛣  <b>gRPC SVC</b>  : <code>trojan-grpc</code>
━━━━━━━━━━━━━━━━━━━━━━━
🔒 <b>MaxLogin</b>  : <code>${ml} device</code>
📅 <b>Expired</b>   : <code>${exp}</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "trojan-${u}.txt" \
        "MAX PANEL -- Trojan account ${u}" \
        "Host       : ${dom}" \
        "IP         : ${ip}" \
        "Port TLS   : 443, 2083, 2087, 8443" \
        "Password   : ${p}" \
        "WS Path    : /trojan-ws" \
        "gRPC SVC   : trojan-grpc" \
        "Expired    : ${exp}" \
        "" \
        "# Trojan WS TLS:" \
        "trojan://${p}@${dom}:443?path=/trojan-ws&security=tls&host=${dom}&type=ws&sni=${dom}#${u}-WS" \
        "" \
        "# Trojan gRPC TLS:" \
        "trojan://${p}@${dom}:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni=${dom}#${u}-gRPC")
    tg_send_file "$cfg_path" "<b>Trojan config</b> — <code>${u}</code>"
    pause
}

trojan_trial() {
    show_header
    _top; _btn "  ${IT}${AL}🎁  TROJAN TRIAL (1 jam)${NC}"; _bot; echo ""
    local u="trial-trojan-$(date +%s | tail -c 5)"
    local p; p=$(rand_pass)
    echo "${u}|${p}|$(mk_exp 1)|1" >> "$TROJAN_DB"
    set_maxlogin "$u" "1"; _xray_sync_clients
    show_box_xray "Trojan" "$u" "$p" "Trial 1 jam" "1"
    local cron_id="trial-trojan-$(date +%s)"
    local t; t=$(TZ="Asia/Jakarta" date -d "+1 hour" "+%M %H %d %m")
    echo "$t * root sed -i '/^${u}|/d' ${TROJAN_DB}; /usr/local/bin/max-menu --sync-xray; rm -f /etc/cron.d/${cron_id}" \
        > "/etc/cron.d/${cron_id}"
    local dom brand; dom=$(get_domain); brand=$(_tg_brand)
    tg_send_text "<b>🎁 Trojan Trial — ${brand}</b>
👤 <b>Remark</b>   : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>Host</b>     : <code>${dom}</code>
🔒 <b>Port TLS</b> : <code>443, 2083, 2087, 8443</code>
📅 <b>Expired</b>  : <code>Trial 1 jam</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "trojan-trial-${u}.txt" \
        "trojan://${p}@${dom}:443?path=/trojan-ws&security=tls&host=${dom}&type=ws&sni=${dom}#${u}-WS")
    tg_send_file "$cfg_path" "<b>Trojan Trial config</b> — <code>${u}</code>"
    pause
}

trojan_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS AKUN TROJAN${NC}"; _bot; echo ""
    xray_list_compact "$TROJAN_DB" "Trojan"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$TROJAN_DB" || { err "User tidak ada!"; pause; return; }
    sed -i "/^${u}|/d" "$TROJAN_DB"; del_maxlogin "$u"; _xray_sync_clients
    ok "Trojan ${W}${u}${NC} dihapus"
    pause
}

trojan_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG TROJAN${NC}"; _bot; echo ""
    xray_list_compact "$TROJAN_DB" "Trojan"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$TROJAN_DB" || { err "User tidak ada!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$TROJAN_DB" | cut -d'|' -f3)
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new}|" "$TROJAN_DB"
    ok "Diperpanjang → ${Y}${new}${NC}"
    pause
}

trojan_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST AKUN TROJAN${NC}"; _bot; echo ""
    xray_list_pretty "$TROJAN_DB" "Trojan" "Password"
    pause
}

# ── Helper list pretty / compact untuk Xray protokol ──
xray_list_pretty() {
    local db="$1" label="$2" col2="$3"
    if [[ ! -s "$db" ]]; then warn "Belum ada akun ${label}."; return; fi
    printf "  ${BLD}${A3}%-3s %-15s %-36s %-12s %-3s${NC}\n" "No" "User" "$col2" "Expired" "ML"
    _sep
    local i=0
    while IFS='|' read -r u key e ml; do
        i=$((i+1))
        local left col
        left=$(days_left "$e")
        if is_expired "$e"; then col="$LR"
        elif [[ "$left" -le 3 ]]; then col="$Y"
        else col="$LG"
        fi
        printf "  %-3s ${W}%-15s${NC} ${A3}%-36s${NC} ${col}%-12s${NC} ${Y}%-3s${NC}\n" \
            "$i." "$u" "$key" "$e" "$ml"
    done < "$db"
    _sep
}

xray_list_compact() {
    local db="$1" label="$2"
    if [[ ! -s "$db" ]]; then warn "Belum ada akun ${label}."; return; fi
    printf "  ${DIM}%-3s %-15s %-12s${NC}\n" "No" "Username" "Expired"
    local i=0
    while IFS='|' read -r u _ e _; do
        i=$((i+1))
        printf "  %-3s ${W}%-15s${NC} ${Y}%-12s${NC}\n" "$i." "$u" "$e"
    done < "$db"
}

# Online check via Xray access log
xray_online() {
    show_header
    _top; _btn "  ${IT}${AL}🔍  CEK USER XRAY ONLINE${NC}"; _bot; echo ""
    if [[ ! -s "$XRAY_LOG" ]]; then warn "Log Xray kosong."; pause; return; fi
    local since
    since=$(date -d '5 min ago' '+%Y/%m/%d %H:%M:%S' 2>/dev/null)
    inf "5 menit terakhir (sumber: ${XRAY_LOG}):"
    echo ""
    awk -v s="$since" '$0>=s && /email:/ { for(i=1;i<=NF;i++) if($i=="email:") print $(i+1) }' "$XRAY_LOG" \
        | sort | uniq -c | sort -rn | head -50 \
        | awk -v W="$W" -v G="$LG" -v N="$NC" \
            '{printf "  %s%-3d%s  %s%-30s%s\n", G, $1, N, W, $2, N}'
    [[ "$(wc -l <"$XRAY_LOG")" -eq 0 ]] && warn "Tidak ada aktivitas."
    pause
}

xray_clean_expired() {
    show_header
    _top; _btn "  ${IT}${AL}🧹  HAPUS USER XRAY EXPIRED${NC}"; _bot; echo ""
    local td; td=$(TZ="Asia/Jakarta" date +%Y-%m-%d)
    local count=0 f
    for f in "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$SS_DB"; do
        [[ -s "$f" ]] || continue
        while IFS='|' read -r u key e ml; do
            if [[ -n "$e" && "$td" > "$e" ]]; then
                sed -i "/^${u}|/d" "$f"; del_maxlogin "$u"
                ok "Hapus: ${W}${u}${NC} dari $(basename "$f") (exp ${e})"
                count=$((count+1))
            fi
        done < "$f"
    done
    _xray_sync_clients
    [[ "$count" == "0" ]] && inf "Tidak ada user expired."
    pause
}

# ── Shadowsocks ─────────────────────────────────────────────────────────
ss_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN SHADOWSOCKS${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}             : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$SS_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    echo -ne "  ${A3}Password${NC} [auto]     : "; read -r p
    [[ -z "$p" ]] && p=$(rand_pass)
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ ! "$ml" =~ ^[0-9]+$ ]] && ml=2
    local exp; exp=$(mk_exp "$d")
    echo "${u}|${p}|${exp}|${ml}" >> "$SS_DB"
    set_maxlogin "$u" "$ml"
    _xray_sync_clients
    local dom; dom=$(get_domain)
    show_box_xray "Shadowsocks" "$u" "$p" "$exp" "$ml"
    local link
    link=$(printf '%s' "aes-128-gcm:${p}@${dom}:8388" | base64 -w0)
    echo -e "  ${DIM}🔗 Link SS :${NC}"
    echo -e "  ${LG}ss://${link}#${u}${NC}"
    echo ""
    local ip brand; ip=$(get_ip); brand=$(_tg_brand)
    tg_send_text "<b>✅ Akun Shadowsocks — ${brand}</b>
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>Host</b>     : <code>${dom}</code>
🖥 <b>IP</b>       : <code>${ip}</code>
🔌 <b>Port</b>     : <code>8388</code>
🔐 <b>Method</b>   : <code>aes-128-gcm</code>
🔒 <b>MaxLogin</b> : <code>${ml} device</code>
📅 <b>Expired</b>  : <code>${exp}</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "ss-${u}.txt" \
        "MAX PANEL -- Shadowsocks account ${u}" \
        "Host     : ${dom}" \
        "Port     : 8388" \
        "Password : ${p}" \
        "Method   : aes-128-gcm" \
        "Expired  : ${exp}" \
        "" \
        "# Link SS:" \
        "ss://${link}#${u}")
    tg_send_file "$cfg_path" "<b>Shadowsocks config</b> — <code>${u}</code>"
    pause
}

ss_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS SHADOWSOCKS${NC}"; _bot; echo ""
    xray_list_compact "$SS_DB" "SS"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$SS_DB" || { err "Tidak ada!"; pause; return; }
    sed -i "/^${u}|/d" "$SS_DB"; del_maxlogin "$u"; _xray_sync_clients
    ok "SS ${W}${u}${NC} dihapus"
    pause
}

ss_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST SHADOWSOCKS${NC}"; _bot; echo ""
    xray_list_pretty "$SS_DB" "Shadowsocks" "Password"
    pause
}

# ════════════════════════════════════════════════════════════
#  USER MANAGEMENT — Trojan-Go (standalone, port 2096)
# ════════════════════════════════════════════════════════════
_trojango_sync() {
    [[ ! -f "$TROJANGO_CFG" ]] && return
    python3 - <<'PYTG' 2>/dev/null
import json, os
CFG = "/etc/trojan-go/config.json"
DB  = "/etc/maxpanel/trojango-users.db"
try:
    with open(CFG) as f: c = json.load(f)
except: c = {}
pws = []
try:
    with open(DB) as f:
        for line in f:
            p = line.strip().split("|")
            if len(p) >= 2: pws.append(p[1])
except: pass
c['password'] = pws
with open(CFG, 'w') as f: json.dump(c, f, indent=2)
PYTG
    systemctl restart trojan-go 2>/dev/null
}

tgo_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN TROJAN-GO${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}             : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$TROJANGO_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    echo -ne "  ${A3}Password${NC} [auto]     : "; read -r p
    [[ -z "$p" ]] && p=$(rand_pass)
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ ! "$ml" =~ ^[0-9]+$ ]] && ml=2
    local exp; exp=$(mk_exp "$d")
    echo "${u}|${p}|${exp}|${ml}" >> "$TROJANGO_DB"
    set_maxlogin "$u" "$ml"
    _trojango_sync

    local dom; dom=$(get_domain)
    echo ""
    echo -e "  ${LG}✅ Akun Trojan-Go${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Username${NC} : ${W}%s${NC}\n" "$u"
    printf  "  ${A1}│${NC} 🔑 ${DIM}Password${NC} : ${A3}%s${NC}\n" "$p"
    printf  "  ${A1}│${NC} 🌐 ${DIM}Host    ${NC} : ${W}%s${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🔌 ${DIM}Port    ${NC} : ${Y}2096${NC}\n"
    printf  "  ${A1}│${NC} 🛣  ${DIM}Path    ${NC} : ${Y}/trojan-go${NC}\n"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    printf  "  ${A1}│${NC} 🔒 ${DIM}MaxLogin${NC} : ${Y}%s${NC}\n" "$ml"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link Trojan-Go:${NC}"
    echo -e "  ${LG}trojan-go://${p}@${dom}:2096?sni=${dom}&type=ws&path=%2Ftrojan-go#${u}${NC}"
    echo ""
    local brand ip; brand=$(_tg_brand); ip=$(get_ip)
    tg_send_text "<b>✅ Akun Trojan-Go — ${brand}</b>
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>Host</b>     : <code>${dom}</code>
🖥 <b>IP</b>       : <code>${ip}</code>
🔌 <b>Port</b>     : <code>2096</code>
🛣  <b>Path</b>     : <code>/trojan-go</code>
🔒 <b>MaxLogin</b> : <code>${ml} device</code>
📅 <b>Expired</b>  : <code>${exp}</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "tgo-${u}.txt" \
        "MAX PANEL -- Trojan-Go account ${u}" \
        "Host     : ${dom}" \
        "Port     : 2096" \
        "Password : ${p}" \
        "Path     : /trojan-go" \
        "Expired  : ${exp}" \
        "" \
        "# Link Trojan-Go:" \
        "trojan-go://${p}@${dom}:2096?sni=${dom}&type=ws&path=%2Ftrojan-go#${u}")
    tg_send_file "$cfg_path" "<b>Trojan-Go config</b> — <code>${u}</code>"
    pause
}

tgo_trial() {
    show_header
    _top; _btn "  ${IT}${AL}🎁  TROJAN-GO TRIAL (1 jam)${NC}"; _bot; echo ""
    local u="trial-tgo-$(date +%s | tail -c 5)" p; p=$(rand_pass)
    echo "${u}|${p}|$(mk_exp 1)|1" >> "$TROJANGO_DB"
    set_maxlogin "$u" "1"; _trojango_sync
    ok "Trial Trojan-Go: ${W}${u}${NC} / ${A3}${p}${NC}"
    local cron_id="trial-tgo-$(date +%s)"
    local t; t=$(TZ="Asia/Jakarta" date -d "+1 hour" "+%M %H %d %m")
    echo "$t * root sed -i '/^${u}|/d' ${TROJANGO_DB}; systemctl restart trojan-go; rm -f /etc/cron.d/${cron_id}" \
        > "/etc/cron.d/${cron_id}"
    pause
}

tgo_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS TROJAN-GO${NC}"; _bot; echo ""
    xray_list_compact "$TROJANGO_DB" "Trojan-Go"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$TROJANGO_DB" || { err "Tidak ada!"; pause; return; }
    sed -i "/^${u}|/d" "$TROJANGO_DB"; del_maxlogin "$u"; _trojango_sync
    ok "Trojan-Go ${W}${u}${NC} dihapus"
    pause
}

tgo_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG TROJAN-GO${NC}"; _bot; echo ""
    xray_list_compact "$TROJANGO_DB" "Trojan-Go"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$TROJANGO_DB" || { err "Tidak ada!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$TROJANGO_DB" | cut -d'|' -f3)
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new}|" "$TROJANGO_DB"
    ok "Diperpanjang → ${Y}${new}${NC}"
    pause
}

tgo_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST TROJAN-GO${NC}"; _bot; echo ""
    xray_list_pretty "$TROJANGO_DB" "Trojan-Go" "Password"
    pause
}

# ════════════════════════════════════════════════════════════
#  USER MANAGEMENT — Hysteria 2 (userpass)
# ════════════════════════════════════════════════════════════
_hy_sync() {
    [[ ! -f "$HY_CFG" ]] && return
    python3 - <<'PYHY' 2>/dev/null
import yaml, os
CFG = "/etc/hysteria/config.yaml"
DB  = "/etc/maxpanel/hysteria-users.db"
try:
    with open(CFG) as f: c = yaml.safe_load(f) or {}
except Exception:
    c = {}
up = {}
try:
    with open(DB) as f:
        for line in f:
            p = line.strip().split("|")
            if len(p) >= 2: up[p[0]] = p[1]
except: pass
c.setdefault('auth', {})['type'] = 'userpass'
c['auth']['userpass'] = up
with open(CFG, 'w') as f: yaml.safe_dump(c, f, default_flow_style=False)
PYHY
    # Fallback bila yaml module tidak ada
    if [[ $? -ne 0 ]]; then
        python3 - <<'PYHY2' 2>/dev/null
import os, re
CFG = "/etc/hysteria/config.yaml"
DB  = "/etc/maxpanel/hysteria-users.db"
up_lines = []
try:
    with open(DB) as f:
        for line in f:
            p = line.strip().split("|")
            if len(p) >= 2: up_lines.append(f"    {p[0]}: {p[1]}")
except: pass
with open(CFG) as f: content = f.read()
new = re.sub(r"(?ms)^auth:.*?(?=^\S)", "", content, flags=re.M)
new += "\nauth:\n  type: userpass\n  userpass:\n" + "\n".join(up_lines) + "\n"
with open(CFG, 'w') as f: f.write(new)
PYHY2
    fi
    systemctl restart hysteria-server 2>/dev/null
}

hy_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN HYSTERIA 2${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}             : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$HY_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    echo -ne "  ${A3}Password${NC} [auto]     : "; read -r p
    [[ -z "$p" ]] && p=$(rand_pass)
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ ! "$ml" =~ ^[0-9]+$ ]] && ml=2
    local exp; exp=$(mk_exp "$d")
    echo "${u}|${p}|${exp}|${ml}" >> "$HY_DB"
    set_maxlogin "$u" "$ml"
    _hy_sync
    local dom; dom=$(get_domain)
    echo ""
    echo -e "  ${LG}✅ Akun Hysteria 2${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Username${NC} : ${W}%s${NC}\n" "$u"
    printf  "  ${A1}│${NC} 🔑 ${DIM}Password${NC} : ${A3}%s${NC}\n" "$p"
    printf  "  ${A1}│${NC} 🌐 ${DIM}Host    ${NC} : ${W}%s${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🔌 ${DIM}Port    ${NC} : ${Y}36712 (UDP)${NC}\n"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    printf  "  ${A1}│${NC} 🔒 ${DIM}MaxLogin${NC} : ${Y}%s${NC}\n" "$ml"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${DIM}🔗 Link Hysteria 2:${NC}"
    echo -e "  ${LG}hy2://${u}:${p}@${dom}:36712?insecure=1&sni=${dom}#${u}${NC}"
    echo ""
    local brand ip; brand=$(_tg_brand); ip=$(get_ip)
    tg_send_text "<b>✅ Akun Hysteria 2 — ${brand}</b>
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>Host</b>     : <code>${dom}</code>
🖥 <b>IP</b>       : <code>${ip}</code>
🔌 <b>Port</b>     : <code>36712 (UDP)</code>
🔒 <b>MaxLogin</b> : <code>${ml} device</code>
📅 <b>Expired</b>  : <code>${exp}</code>"
    local cfg_path
    cfg_path=$(_tg_tmpfile "hy-${u}.txt" \
        "MAX PANEL -- Hysteria 2 account ${u}" \
        "Host     : ${dom}" \
        "Port     : 36712 (UDP)" \
        "Username : ${u}" \
        "Password : ${p}" \
        "Expired  : ${exp}" \
        "" \
        "# Link Hysteria 2:" \
        "hy2://${u}:${p}@${dom}:36712?insecure=1&sni=${dom}#${u}")
    tg_send_file "$cfg_path" "<b>Hysteria 2 config</b> — <code>${u}</code>"
    pause
}

hy_trial() {
    show_header
    _top; _btn "  ${IT}${AL}🎁  HYSTERIA TRIAL (1 jam)${NC}"; _bot; echo ""
    local u="trial-hy-$(date +%s | tail -c 5)" p; p=$(rand_pass)
    echo "${u}|${p}|$(mk_exp 1)|1" >> "$HY_DB"
    set_maxlogin "$u" "1"; _hy_sync
    ok "Trial: ${W}${u}${NC} / ${A3}${p}${NC}"
    local cron_id="trial-hy-$(date +%s)"
    local t; t=$(TZ="Asia/Jakarta" date -d "+1 hour" "+%M %H %d %m")
    echo "$t * root sed -i '/^${u}|/d' ${HY_DB}; systemctl restart hysteria-server; rm -f /etc/cron.d/${cron_id}" \
        > "/etc/cron.d/${cron_id}"
    pause
}

hy_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS HYSTERIA${NC}"; _bot; echo ""
    xray_list_compact "$HY_DB" "Hysteria"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$HY_DB" || { err "Tidak ada!"; pause; return; }
    sed -i "/^${u}|/d" "$HY_DB"; del_maxlogin "$u"; _hy_sync
    ok "Hysteria ${W}${u}${NC} dihapus"
    pause
}

hy_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG HYSTERIA${NC}"; _bot; echo ""
    xray_list_compact "$HY_DB" "Hysteria"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$HY_DB" || { err "Tidak ada!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$HY_DB" | cut -d'|' -f3)
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new}|" "$HY_DB"
    ok "Diperpanjang → ${Y}${new}${NC}"
    pause
}

hy_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST HYSTERIA${NC}"; _bot; echo ""
    xray_list_pretty "$HY_DB" "Hysteria" "Password"
    pause
}

# ════════════════════════════════════════════════════════════
#  USER MANAGEMENT — OpenVPN (PAM auth → user sistem)
# ════════════════════════════════════════════════════════════
ovpn_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN OPENVPN${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}             : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$OVPN_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    if id "$u" &>/dev/null; then err "User sistem '$u' sudah ada!"; pause; return; fi
    echo -ne "  ${A3}Password${NC} [auto]     : "; read -r p
    [[ -z "$p" ]] && p=$(rand_pass)
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ ! "$ml" =~ ^[0-9]+$ ]] && ml=2
    local exp; exp=$(mk_exp "$d")

    useradd -e "$exp" -s /bin/false -M "$u" 2>/dev/null
    echo -e "${p}\n${p}" | passwd "$u" &>/dev/null
    echo "${u}|${p}|${exp}|${ml}" >> "$OVPN_DB"
    set_maxlogin "$u" "$ml"

    # Generate .ovpn client config (TCP + UDP)
    mkdir -p "/etc/openvpn/client/${u}"
    local ip; ip=$(get_ip)
    _make_ovpn_client "$u" "$ip" "1194" "tcp" > "/etc/openvpn/client/${u}/${u}-tcp.ovpn"
    _make_ovpn_client "$u" "$ip" "2200" "udp" > "/etc/openvpn/client/${u}/${u}-udp.ovpn"

    echo ""
    echo -e "  ${LG}✅ Akun OpenVPN${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Username${NC} : ${W}%s${NC}\n" "$u"
    printf  "  ${A1}│${NC} 🔑 ${DIM}Password${NC} : ${A3}%s${NC}\n" "$p"
    printf  "  ${A1}│${NC} 🔌 ${DIM}TCP     ${NC} : ${Y}1194${NC}\n"
    printf  "  ${A1}│${NC} 🔌 ${DIM}UDP     ${NC} : ${Y}2200${NC}\n"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    printf  "  ${A1}│${NC} 🔒 ${DIM}MaxLogin${NC} : ${Y}%s${NC}\n" "$ml"
    echo -e "  ${A1}├─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 📄 ${DIM}Config TCP${NC}: ${W}/etc/openvpn/client/%s/%s-tcp.ovpn${NC}\n" "$u" "$u"
    printf  "  ${A1}│${NC} 📄 ${DIM}Config UDP${NC}: ${W}/etc/openvpn/client/%s/%s-udp.ovpn${NC}\n" "$u" "$u"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""
    local brand; brand=$(_tg_brand)
    tg_send_text "<b>✅ Akun OpenVPN — ${brand}</b>
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>Host</b>     : <code>${ip}</code>
🔌 <b>Port TCP</b> : <code>1194</code>
🔌 <b>Port UDP</b> : <code>2200</code>
🔒 <b>MaxLogin</b> : <code>${ml} device</code>
📅 <b>Expired</b>  : <code>${exp}</code>

Config TCP &amp; UDP terlampir di bawah \u2014 download lalu import ke OpenVPN client."
    tg_send_file "/etc/openvpn/client/${u}/${u}-tcp.ovpn" "<b>OpenVPN TCP</b> \u2014 <code>${u}</code>"
    tg_send_file "/etc/openvpn/client/${u}/${u}-udp.ovpn" "<b>OpenVPN UDP</b> \u2014 <code>${u}</code>"
    pause
}

_make_ovpn_client() {
    local user="$1" srv="$2" port="$3" proto="$4"
    local ca; ca=$(cat /etc/openvpn/server/ca.crt 2>/dev/null)
    local ta; ta=$(cat /etc/openvpn/server/ta.key 2>/dev/null)
    cat <<OVPNCLI
client
dev tun
proto ${proto}
remote ${srv} ${port}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-128-CBC
auth SHA256
auth-user-pass
auth-nocache
verb 3
<ca>
${ca}
</ca>
<tls-auth>
${ta}
</tls-auth>
key-direction 1
OVPNCLI
}

ovpn_trial() {
    show_header
    _top; _btn "  ${IT}${AL}🎁  OPENVPN TRIAL (1 jam)${NC}"; _bot; echo ""
    local u="trial-ovpn-$(date +%s | tail -c 5)" p; p=$(rand_pass)
    useradd -s /bin/false -M "$u" 2>/dev/null
    echo -e "${p}\n${p}" | passwd "$u" &>/dev/null
    chage -E "$(date -d '+1 day' +%Y-%m-%d)" "$u" 2>/dev/null
    echo "${u}|${p}|TRIAL|1" >> "$OVPN_DB"
    set_maxlogin "$u" "1"
    ok "Trial OpenVPN: ${W}${u}${NC} / ${A3}${p}${NC}"
    local cron_id="trial-ovpn-$(date +%s)"
    local t; t=$(TZ="Asia/Jakarta" date -d "+1 hour" "+%M %H %d %m")
    echo "$t * root userdel -r ${u}; sed -i '/^${u}|/d' ${OVPN_DB}; rm -f /etc/cron.d/${cron_id}" \
        > "/etc/cron.d/${cron_id}"
    # Generate config trial juga supaya bisa dikirim ke Telegram
    mkdir -p "/etc/openvpn/client/${u}"
    local ip; ip=$(get_ip)
    _make_ovpn_client "$u" "$ip" "1194" "tcp" > "/etc/openvpn/client/${u}/${u}-tcp.ovpn"
    _make_ovpn_client "$u" "$ip" "2200" "udp" > "/etc/openvpn/client/${u}/${u}-udp.ovpn"
    local brand; brand=$(_tg_brand)
    tg_send_text "<b>🎁 OpenVPN Trial — ${brand}</b>
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>Host</b>     : <code>${ip}</code>
🔌 <b>TCP</b>      : <code>1194</code>
🔌 <b>UDP</b>      : <code>2200</code>
📅 <b>Expired</b>  : <code>Trial 1 jam</code>"
    tg_send_file "/etc/openvpn/client/${u}/${u}-tcp.ovpn" "<b>OpenVPN Trial TCP</b> — <code>${u}</code>"
    tg_send_file "/etc/openvpn/client/${u}/${u}-udp.ovpn" "<b>OpenVPN Trial UDP</b> — <code>${u}</code>"
    pause
}

ovpn_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS OPENVPN${NC}"; _bot; echo ""
    xray_list_compact "$OVPN_DB" "OpenVPN"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$OVPN_DB" || { err "Tidak ada!"; pause; return; }
    userdel -r "$u" 2>/dev/null
    sed -i "/^${u}|/d" "$OVPN_DB"; del_maxlogin "$u"
    rm -rf "/etc/openvpn/client/${u}" 2>/dev/null
    ok "OpenVPN ${W}${u}${NC} dihapus"
    pause
}

ovpn_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG OPENVPN${NC}"; _bot; echo ""
    xray_list_compact "$OVPN_DB" "OpenVPN"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$OVPN_DB" || { err "Tidak ada!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$OVPN_DB" | cut -d'|' -f3)
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new}|" "$OVPN_DB"
    chage -E "$new" "$u" 2>/dev/null
    ok "Diperpanjang → ${Y}${new}${NC}"
    pause
}

ovpn_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST OPENVPN${NC}"; _bot; echo ""
    xray_list_pretty "$OVPN_DB" "OpenVPN" "Password"
    pause
}

ovpn_online() {
    show_header
    _top; _btn "  ${IT}${AL}🔍  CEK USER OPENVPN ONLINE${NC}"; _bot; echo ""
    for st in /var/log/openvpn-tcp-status.log /var/log/openvpn-udp-status.log; do
        [[ -f "$st" ]] || continue
        echo -e "  ${DIM}── $(basename "$st") ──${NC}"
        awk -F',' '/^CLIENT_LIST/ {print $2,$3,$4}' "$st" 2>/dev/null | while read -r u v r; do
            printf "  ${W}%-15s${NC} ${A3}%-15s${NC} ${LG}%s${NC}\n" "$u" "$v" "$r"
        done
        echo ""
    done
    pause
}

# ════════════════════════════════════════════════════════════
#  USER MANAGEMENT — WireGuard
# ════════════════════════════════════════════════════════════
wg_next_ip() {
    local last_ip used last
    used=$(awk -F'|' '{print $4}' "$WG_DB" 2>/dev/null | sort -t. -k4 -n | tail -1)
    if [[ -n "$used" ]]; then
        last=$(echo "$used" | awk -F'.' '{print $4}')
        echo "10.66.66.$((last + 1))"
    else
        echo "10.66.66.2"
    fi
}

wg_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH PEER WIREGUARD${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username/Remark${NC}      : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$WG_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ ! "$ml" =~ ^[0-9]+$ ]] && ml=2

    local privk pubk psk ip exp spub
    privk=$(wg genkey)
    pubk=$(echo "$privk" | wg pubkey)
    psk=$(wg genpsk)
    ip=$(wg_next_ip)
    exp=$(mk_exp "$d")
    spub=$(cat "$WG_DIR/server_public.key")

    # Tambah peer ke wg0
    cat >> "$WG_CFG" <<WGP

# BEGIN ${u}
[Peer]
PublicKey = ${pubk}
PresharedKey = ${psk}
AllowedIPs = ${ip}/32
# END ${u}
WGP

    # Reload wireguard
    wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || systemctl restart wg-quick@wg0

    echo "${u}|${pubk}|${privk}|${ip}|${exp}|${ml}" >> "$WG_DB"
    set_maxlogin "$u" "$ml"

    # Tulis client config (mengandung PrivateKey → chmod 600)
    mkdir -p "$WG_CLIENT_DIR"
    chmod 700 "$WG_CLIENT_DIR"
    local cfile="$WG_CLIENT_DIR/${u}.conf"
    local srv; srv=$(get_domain)
    ( umask 077; cat > "$cfile" <<WGCLI
[Interface]
PrivateKey = ${privk}
Address = ${ip}/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${spub}
PresharedKey = ${psk}
Endpoint = ${srv}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
WGCLI
)
    chmod 600 "$cfile"

    echo ""
    echo -e "  ${LG}✅ Peer WireGuard${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Name    ${NC} : ${W}%s${NC}\n" "$u"
    printf  "  ${A1}│${NC} 🌐 ${DIM}IP Peer ${NC} : ${A3}%s${NC}\n" "$ip"
    printf  "  ${A1}│${NC} 🔑 ${DIM}PubKey  ${NC} : ${DIM}%s${NC}\n" "$pubk"
    printf  "  ${A1}│${NC} 🔌 ${DIM}Endpoint${NC} : ${Y}%s:51820${NC}\n" "$srv"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    printf  "  ${A1}│${NC} 📄 ${DIM}File    ${NC} : ${W}%s${NC}\n" "$cfile"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""

    if command -v qrencode &>/dev/null; then
        echo -e "  ${DIM}QR Code (scan via WireGuard app):${NC}"
        qrencode -t ANSIUTF8 < "$cfile"
        echo ""
    fi
    local brand; brand=$(_tg_brand)
    tg_send_text "<b>✅ Peer WireGuard — ${brand}</b>
👤 <b>Name</b>     : <code>${u}</code>
🌐 <b>IP Peer</b>  : <code>${ip}</code>
🔌 <b>Endpoint</b> : <code>${srv}:51820</code>
📅 <b>Expired</b>  : <code>${exp}</code>
🔒 <b>MaxLogin</b> : <code>${ml}</code>"
    tg_send_file "$cfile" "<b>WireGuard config</b> — <code>${u}</code>"
    pause
}

wg_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS PEER WG${NC}"; _bot; echo ""
    if [[ ! -s "$WG_DB" ]]; then warn "Belum ada peer."; pause; return; fi
    awk -F'|' '{printf "  %-15s  %-15s  %s\n", $1, $4, $5}' "$WG_DB"
    echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$WG_DB" || { err "Tidak ada!"; pause; return; }
    # Hapus blok dari config
    sed -i "/^# BEGIN ${u}$/,/^# END ${u}$/d" "$WG_CFG"
    wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || systemctl restart wg-quick@wg0
    sed -i "/^${u}|/d" "$WG_DB"; del_maxlogin "$u"
    rm -f "$WG_CLIENT_DIR/${u}.conf" 2>/dev/null
    ok "Peer WG ${W}${u}${NC} dihapus"
    pause
}

wg_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG WG${NC}"; _bot; echo ""
    if [[ ! -s "$WG_DB" ]]; then warn "Belum ada peer."; pause; return; fi
    awk -F'|' '{printf "  %-15s  %-15s  %s\n", $1, $4, $5}' "$WG_DB"
    echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$WG_DB" || { err "Tidak ada!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$WG_DB" | awk -F'|' '{print $5}')
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|[^|]*|[^|]*|\)[^|]*|\1${new}|" "$WG_DB"
    ok "Diperpanjang → ${Y}${new}${NC}"
    pause
}

wg_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST PEER WG${NC}"; _bot; echo ""
    if [[ ! -s "$WG_DB" ]]; then warn "Belum ada peer."; pause; return; fi
    printf "  ${BLD}${A3}%-3s %-15s %-15s %-12s${NC}\n" "No" "User" "IP" "Expired"
    _sep
    local i=0
    while IFS='|' read -r u _ _ ip e _; do
        i=$((i+1))
        local col
        if is_expired "$e"; then col="$LR"
        elif [[ "$(days_left "$e")" -le 3 ]]; then col="$Y"
        else col="$LG"
        fi
        printf "  %-3s ${W}%-15s${NC} ${A3}%-15s${NC} ${col}%-12s${NC}\n" "$i." "$u" "$ip" "$e"
    done < "$WG_DB"
    _sep
    pause
}

wg_online() {
    show_header
    _top; _btn "  ${IT}${AL}🔍  WG PEERS ONLINE${NC}"; _bot; echo ""
    if ! command -v wg &>/dev/null; then warn "WG tidak terinstall."; pause; return; fi
    wg show wg0 2>/dev/null | awk '
        /peer:/ {peer=$2}
        /endpoint:/ {ep=$2}
        /latest handshake:/ {hs=substr($0, index($0,$3))}
        /transfer:/ {tx=$2 " " $3 " ↓ " $4 " " $5 " ↑"; printf "  %s  %s\n  endpoint: %s\n  handshake: %s\n  transfer: %s\n\n", peer, "", ep, hs, tx; peer="";ep="";hs="";tx=""}
    '
    pause
}

# ════════════════════════════════════════════════════════════
#  USER MANAGEMENT — SlowDNS
# ════════════════════════════════════════════════════════════
slow_add() {
    show_header
    _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN SLOWDNS${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}             : "; read -r u
    [[ -z "$u" ]] && { pause; return; }
    grep -q "^${u}|" "$SLOW_DB" 2>/dev/null && { err "User sudah ada!"; pause; return; }
    if id "$u" &>/dev/null; then err "User sistem '$u' sudah ada!"; pause; return; fi
    echo -ne "  ${A3}Password${NC} [auto]     : "; read -r p
    [[ -z "$p" ]] && p=$(rand_pass)
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    echo -ne "  ${A3}Max Login Device${NC} [2]  : "; read -r ml
    [[ ! "$ml" =~ ^[0-9]+$ ]] && ml=2
    local exp; exp=$(mk_exp "$d")

    useradd -e "$exp" -s /bin/false -M "$u" 2>/dev/null
    echo -e "${p}\n${p}" | passwd "$u" &>/dev/null
    echo "${u}|${p}|${exp}|${ml}" >> "$SLOW_DB"
    set_maxlogin "$u" "$ml"

    local dom pub; dom=$(get_domain)
    pub=$(cat "$SLOW_DIR/server.pub" 2>/dev/null || echo "-")

    echo ""
    echo -e "  ${LG}✅ Akun SlowDNS${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Username${NC} : ${W}%s${NC}\n" "$u"
    printf  "  ${A1}│${NC} 🔑 ${DIM}Password${NC} : ${A3}%s${NC}\n" "$p"
    printf  "  ${A1}│${NC} 🌐 ${DIM}NS Domain${NC}: ${W}%s${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🔌 ${DIM}Port    ${NC} : ${Y}53 (UDP), 5300${NC}\n"
    printf  "  ${A1}│${NC} 🔑 ${DIM}PubKey  ${NC} : ${DIM}%s${NC}\n" "$pub"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""

    local brand; brand=$(_tg_brand)
    tg_send_text "<b>✅ Akun SlowDNS — ${brand}</b>
👤 <b>Username</b> : <code>${u}</code>
🔑 <b>Password</b> : <code>${p}</code>
🌐 <b>NS Domain</b>: <code>${dom}</code>
🔌 <b>Port</b>     : <code>53 (UDP), 5300</code>
🔑 <b>PubKey</b>   : <code>${pub}</code>
🔒 <b>MaxLogin</b> : <code>${ml} device</code>
📅 <b>Expired</b>  : <code>${exp}</code>"
    pause
}

slow_del() {
    show_header
    _top; _btn "  ${IT}${AL}🗑   HAPUS SLOWDNS${NC}"; _bot; echo ""
    xray_list_compact "$SLOW_DB" "SlowDNS"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$SLOW_DB" || { err "Tidak ada!"; pause; return; }
    userdel -r "$u" 2>/dev/null
    sed -i "/^${u}|/d" "$SLOW_DB"; del_maxlogin "$u"
    ok "SlowDNS ${W}${u}${NC} dihapus"
    pause
}

slow_renew() {
    show_header
    _top; _btn "  ${IT}${AL}🔁  PERPANJANG SLOWDNS${NC}"; _bot; echo ""
    xray_list_compact "$SLOW_DB" "SlowDNS"; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r u
    grep -q "^${u}|" "$SLOW_DB" || { err "Tidak ada!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} [30]: "; read -r d
    [[ ! "$d" =~ ^[0-9]+$ ]] && d=30
    local cur new
    cur=$(grep "^${u}|" "$SLOW_DB" | cut -d'|' -f3)
    new=$(TZ="Asia/Jakarta" date -d "${cur} +${d} days" +"%Y-%m-%d" 2>/dev/null || mk_exp "$d")
    sed -i "s|^\(${u}|[^|]*|\)[^|]*|\1${new}|" "$SLOW_DB"
    chage -E "$new" "$u" 2>/dev/null
    ok "Diperpanjang → ${Y}${new}${NC}"
    pause
}

slow_list() {
    show_header
    _top; _btn "  ${IT}${AL}📋  LIST SLOWDNS${NC}"; _bot; echo ""
    xray_list_pretty "$SLOW_DB" "SlowDNS" "Password"
    pause
}

# ════════════════════════════════════════════════════════════
#  MAXLOGIN ENFORCER — Kick user yang melebihi maxdevice
# ════════════════════════════════════════════════════════════
check_maxlogin_all() {
    [[ ! -f "$MLDB" ]] && return
    local uname maxdev

    # ── SSH connections (PAM-based) ────────────────────────────
    while IFS='|' read -r uname maxdev; do
        [[ -z "$uname" || -z "$maxdev" ]] && continue
        # Hitung sesi sshd user ini (cocokkan kolom cmd = "sshd:" diikuti "<user>@..." pada kolom berikutnya)
        local active
        active=$(ps -eo user,cmd --no-headers 2>/dev/null \
                 | awk -v u="$uname" '$2 == "sshd:" && $3 ~ ("^" u "@") {c++} END{print c+0}')
        if [[ "$active" -gt "$maxdev" ]]; then
            # FIX: ambil PID dari ps -eo pid,cmd \u2014 cmd-token pertama adalah $2 ("sshd:"),
            # username pada token $3 dengan format <user>@<tty>.
            local pids
            mapfile -t pids < <(ps -eo pid,cmd --no-headers 2>/dev/null \
                | awk -v u="$uname" '$2 == "sshd:" && $3 ~ ("^" u "@") {print $1}')
            local extra=$(( active - maxdev ))
            local i=0 pid
            for pid in "${pids[@]}"; do
                [[ "$i" -ge "$extra" ]] && break
                [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && continue
                kill -9 "$pid" 2>/dev/null && i=$((i+1))
            done
            # Dropbear juga: pattern "dropbear" + user (best-effort, kalau pakai PAM)
            local dpids
            mapfile -t dpids < <(ps -eo pid,user,cmd --no-headers 2>/dev/null \
                | awk -v u="$uname" '$3 ~ /dropbear/ && $2 == u {print $1}')
            local j=0 dpid
            for dpid in "${dpids[@]}"; do
                [[ "$j" -ge "$extra" ]] && break
                [[ -z "$dpid" || ! "$dpid" =~ ^[0-9]+$ ]] && continue
                kill -9 "$dpid" 2>/dev/null && j=$((j+1))
            done
            _tg_send "🚫 <b>MaxLogin SSH</b>
👤 <code>${uname}</code> melebihi ${maxdev} device — kick ${extra} sesi"
        fi
    done < "$MLDB"

    # ── Xray-based protokol (via access.log parsing) ──────────
    if [[ -s "$XRAY_LOG" ]]; then
        local since
        since=$(date -d '2 min ago' '+%Y/%m/%d %H:%M:%S' 2>/dev/null)
        # Mapping email → unique source IP count
        declare -A xc
        while IFS= read -r line; do
            local email ip
            email=$(echo "$line" | grep -oE 'email: [^ ]+' | awk '{print $2}')
            ip=$(echo "$line"    | grep -oE 'from [^ ]+'  | awk '{print $2}' | cut -d: -f1)
            [[ -z "$email" || -z "$ip" ]] && continue
            xc["${email}|${ip}"]=1
        done < <(awk -v s="$since" '$0>=s' "$XRAY_LOG" 2>/dev/null)

        declare -A user_ips
        for key in "${!xc[@]}"; do
            local u="${key%%|*}"
            user_ips[$u]=$(( ${user_ips[$u]:-0} + 1 ))
        done

        for u in "${!user_ips[@]}"; do
            local cnt=${user_ips[$u]}
            local ml; ml=$(get_maxlogin "$u")
            [[ -z "$ml" ]] && continue
            if [[ "$cnt" -gt "$ml" ]]; then
                # Hapus dari DB Xray protokol
                for db in "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$SS_DB"; do
                    sed -i "/^${u}|/d" "$db" 2>/dev/null
                done
                _xray_sync_clients
                _tg_send "🚫 <b>MaxLogin Xray</b>
👤 <code>${u}</code> melebihi ${ml} device (aktual ${cnt}) — auto-deleted"
            fi
        done
    fi
}

# ════════════════════════════════════════════════════════════
#  CRON JOBS — Auto-delete expired + MaxLogin + Backup
# ════════════════════════════════════════════════════════════
install_cron_jobs() {
    inf "Setup cron auto-clean + maxlogin enforcer..."
    mkdir -p /etc/cron.d /var/log/maxpanel

    # Daily 00:05: hapus user expired semua protokol
    cat > /etc/cron.d/maxpanel-expired <<CRON1
# MAX PANEL — auto-delete expired users (daily 00:05)
5 0 * * * root /usr/local/bin/max-menu --clean-expired >> /var/log/maxpanel/expired.log 2>&1
CRON1

    # Every minute: maxlogin enforcer
    cat > /etc/cron.d/maxpanel-maxlogin <<CRON2
# MAX PANEL — maxlogin enforcer (every 1 min)
* * * * * root /usr/local/bin/max-menu --check-maxlogin >> /var/log/maxpanel/maxlogin.log 2>&1
CRON2

    # Weekly auto-backup (Sunday 03:30)
    cat > /etc/cron.d/maxpanel-backup <<CRON3
# MAX PANEL — weekly auto-backup
30 3 * * 0 root /usr/local/bin/max-menu --auto-backup >> /var/log/maxpanel/backup.log 2>&1
CRON3

    # Daily script update check
    cat > /etc/cron.d/maxpanel-update <<CRON4
# MAX PANEL — daily update check
17 4 * * * root /usr/local/bin/max-menu --check-update >> /var/log/maxpanel/update.log 2>&1
CRON4

    chmod 0644 /etc/cron.d/maxpanel-*
    systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null
    ok "Cron jobs aktif"
}

# Eksekutor untuk cron jobs
do_clean_expired_all() {
    local td count=0
    td=$(TZ="Asia/Jakarta" date +%Y-%m-%d)

    # SSH / OpenVPN / SlowDNS (system user)
    for db in "$SSH_DB" "$OVPN_DB" "$SLOW_DB"; do
        [[ -s "$db" ]] || continue
        while IFS='|' read -r u p e ml; do
            if [[ -n "$e" && "$td" > "$e" ]]; then
                userdel -r "$u" 2>/dev/null
                sed -i "/^${u}|/d" "$db"
                del_maxlogin "$u"
                count=$((count+1))
                echo "[$(date)] expired: $u from $(basename "$db")"
            fi
        done < "$db"
    done

    # Xray-based
    for db in "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$SS_DB" "$TROJANGO_DB" "$HY_DB"; do
        [[ -s "$db" ]] || continue
        while IFS='|' read -r u key e ml; do
            if [[ -n "$e" && "$td" > "$e" ]]; then
                sed -i "/^${u}|/d" "$db"
                del_maxlogin "$u"
                count=$((count+1))
                echo "[$(date)] expired: $u from $(basename "$db")"
            fi
        done < "$db"
    done

    # WireGuard
    if [[ -s "$WG_DB" ]]; then
        while IFS='|' read -r u pub priv ip e ml; do
            if [[ -n "$e" && "$td" > "$e" ]]; then
                sed -i "/^# BEGIN ${u}$/,/^# END ${u}$/d" "$WG_CFG"
                sed -i "/^${u}|/d" "$WG_DB"
                del_maxlogin "$u"
                rm -f "$WG_CLIENT_DIR/${u}.conf"
                count=$((count+1))
                echo "[$(date)] expired: $u (wireguard)"
            fi
        done < "$WG_DB"
        wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || true
    fi

    # Reload Xray + Trojan-Go + Hysteria
    _xray_sync_clients 2>/dev/null
    _trojango_sync     2>/dev/null
    _hy_sync           2>/dev/null

    echo "[$(date)] Total expired removed: $count"
}

# ════════════════════════════════════════════════════════════
#  SYSTEM TOOLS — BBR, IPv6, Speedtest, dll
# ════════════════════════════════════════════════════════════
tool_bbr() {
    show_header
    _top; _btn "  ${IT}${AL}🚀  BBR + FQ CONGESTION CONTROL${NC}"; _bot; echo ""
    local cur; cur=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
    local qd;  qd=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
    echo -e "  ${DIM}Congestion Ctrl :${NC} ${W}${cur}${NC}"
    echo -e "  ${DIM}Queue Discipline:${NC} ${W}${qd}${NC}"
    echo ""
    echo -e "  ${A2}[1]${NC}  Aktifkan BBR + FQ"
    echo -e "  ${A2}[2]${NC}  Kembali ke default (cubic + pfifo_fast)"
    echo -e "  ${LR}[0]${NC}  Batal"
    echo ""
    echo -ne "  ${A1}›${NC} "; read -r ch
    case $ch in
        1)
            enable_bbr_silent
            ok "BBR + FQ aktif"
            ;;
        2)
            sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null
            sysctl -w net.core.default_qdisc=pfifo_fast &>/dev/null
            sed -i '/tcp_congestion_control/d;/default_qdisc/d' /etc/sysctl.conf
            ok "Kembali ke default"
            ;;
    esac
    pause
}

tool_ipv6() {
    show_header
    _top; _btn "  ${IT}${AL}🛑  TOGGLE IPv6${NC}"; _bot; echo ""
    local cur; cur=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 0)
    if [[ "$cur" == "1" ]]; then
        echo -e "  ${DIM}IPv6 saat ini :${NC} ${LR}DISABLED${NC}"
    else
        echo -e "  ${DIM}IPv6 saat ini :${NC} ${LG}ENABLED${NC}"
    fi
    echo ""
    echo -e "  ${A2}[1]${NC}  Disable IPv6"
    echo -e "  ${A2}[2]${NC}  Enable IPv6"
    echo -e "  ${LR}[0]${NC}  Batal"
    echo ""
    echo -ne "  ${A1}›${NC} "; read -r ch
    case $ch in
        1)
            # FIX: idempotent block dengan marker (re-run tidak duplikat)
            _apply_block "IPV6-DISABLE" /etc/sysctl.conf <<'V6'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
V6
            sysctl -p &>/dev/null
            ok "IPv6 dinonaktifkan"
            ;;
        2)
            # Hapus block disable (marker baru) + legacy line-by-line cleanup
            sed -i '/^# >>> MAXPANEL-IPV6-DISABLE >>>$/,/^# <<< MAXPANEL-IPV6-DISABLE <<<$/d' /etc/sysctl.conf 2>/dev/null
            sed -i '/disable_ipv6/d' /etc/sysctl.conf
            sysctl -w net.ipv6.conf.all.disable_ipv6=0 &>/dev/null
            sysctl -w net.ipv6.conf.default.disable_ipv6=0 &>/dev/null
            sysctl -w net.ipv6.conf.lo.disable_ipv6=0 &>/dev/null
            ok "IPv6 diaktifkan"
            ;;
    esac
    pause
}

tool_speedtest() {
    show_header
    _top; _btn "  ${IT}${AL}🚀  SPEEDTEST${NC}"; _bot; echo ""
    if ! command -v speedtest-cli &>/dev/null; then
        inf "Install speedtest-cli..."
        apt-get install -y -qq speedtest-cli &>/dev/null || pip3 install speedtest-cli &>/dev/null
    fi
    if command -v speedtest-cli &>/dev/null; then
        speedtest-cli --simple
    else
        err "speedtest-cli tidak tersedia"
    fi
    pause
}

tool_sysinfo() {
    show_header
    _top; _btn "  ${IT}${AL}ℹ️   SYSTEM INFO LENGKAP${NC}"; _bot; echo ""
    local hn ip os krn up ram_t ram_u cpu cpus disk_t disk_u tx_mo
    hn=$(hostname); ip=$(get_ip)
    # shellcheck disable=SC1091
    os=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
    krn=$(uname -r)
    up=$(uptime -p 2>/dev/null || awk '{printf "%dd %dh", $1/86400, ($1%86400)/3600}' /proc/uptime)
    ram_t=$(free -h | awk '/^Mem/{print $2}')
    ram_u=$(free -h | awk '/^Mem/{print $3}')
    cpus=$(nproc 2>/dev/null)
    cpu=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ //')
    disk_t=$(df -h / | awk 'NR==2{print $2}')
    disk_u=$(df -h / | awk 'NR==2{print $3}')
    tx_mo=$(vnstat --oneline 2>/dev/null | awk -F\; '{print $11}')
    [[ -z "$tx_mo" ]] && tx_mo="N/A"

    local isp; isp=$(curl -s --max-time 5 https://ipinfo.io/org 2>/dev/null || echo "N/A")

    echo -e "  ${DIM}Hostname  :${NC} ${W}${hn}${NC}"
    echo -e "  ${DIM}OS        :${NC} ${W}${os}${NC}"
    echo -e "  ${DIM}Kernel    :${NC} ${W}${krn}${NC}"
    echo -e "  ${DIM}Uptime    :${NC} ${W}${up}${NC}"
    echo -e "  ${DIM}CPU       :${NC} ${W}${cpu} (${cpus} cores)${NC}"
    echo -e "  ${DIM}RAM       :${NC} ${A3}${ram_u}/${ram_t}${NC}"
    echo -e "  ${DIM}Disk /    :${NC} ${A3}${disk_u}/${disk_t}${NC}"
    echo -e "  ${DIM}IP Publik :${NC} ${LG}${ip}${NC}"
    echo -e "  ${DIM}ISP/Org   :${NC} ${Y}${isp}${NC}"
    echo -e "  ${DIM}Trafik bln:${NC} ${A4}${tx_mo}${NC}"
    pause
}

tool_reboot_sched() {
    show_header
    _top; _btn "  ${IT}${AL}♻️   AUTO-REBOOT SCHEDULER${NC}"; _bot; echo ""
    local cur; cur=$(grep -l 'maxpanel-reboot' /etc/cron.d/maxpanel-reboot 2>/dev/null | head -1)
    if [[ -f /etc/cron.d/maxpanel-reboot ]]; then
        local cur_t; cur_t=$(awk '!/^#/ {print $1, $2; exit}' /etc/cron.d/maxpanel-reboot)
        echo -e "  ${DIM}Schedule saat ini :${NC} ${A3}${cur_t} (menit jam)${NC}"
    else
        echo -e "  ${DIM}Schedule saat ini :${NC} ${LR}belum di-set${NC}"
    fi
    echo ""
    echo -e "  ${A2}[1]${NC}  Set auto-reboot harian"
    echo -e "  ${A2}[2]${NC}  Hapus jadwal"
    echo -e "  ${LR}[0]${NC}  Batal"
    echo ""
    echo -ne "  ${A1}›${NC} "; read -r ch
    case $ch in
        1)
            echo -ne "  ${A3}Jam reboot${NC} [0-23] (default 4): "; read -r h
            [[ -z "$h" || ! "$h" =~ ^[0-9]+$ ]] && h=4
            echo "0 ${h} * * * root /sbin/reboot" > /etc/cron.d/maxpanel-reboot
            chmod 0644 /etc/cron.d/maxpanel-reboot
            ok "Auto-reboot diatur tiap hari jam ${Y}${h}:00${NC}"
            ;;
        2)
            rm -f /etc/cron.d/maxpanel-reboot
            ok "Jadwal auto-reboot dihapus"
            ;;
    esac
    pause
}

tool_bandwidth() {
    show_header
    _top; _btn "  ${IT}${AL}📊  BANDWIDTH USAGE${NC}"; _bot; echo ""
    if ! command -v vnstat &>/dev/null; then
        inf "Install vnstat..."
        apt-get install -y -qq vnstat &>/dev/null
        systemctl enable vnstat &>/dev/null; systemctl start vnstat &>/dev/null
    fi
    vnstat
    pause
}

tool_restart_all() {
    show_header
    _top; _btn "  ${IT}${AL}🔄  RESTART SEMUA SERVICE${NC}"; _bot; echo ""
    local svcs=(ssh sshd dropbear stunnel4 xray trojan-go hysteria-server \
                openvpn-server@tcp openvpn-server@udp wg-quick@wg0 nginx \
                badvpn-udpgw-7100 badvpn-udpgw-7200 badvpn-udpgw-7300 \
                ws-max-8880 slowdns ohp)
    for s in "${svcs[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${s}\\.service"; then
            if systemctl restart "$s" 2>/dev/null; then
                ok "${s}"
            else
                warn "${s} gagal restart"
            fi
        fi
    done
    pause
}

tool_check_service() {
    show_header
    _top; _btn "  ${IT}${AL}🔍  STATUS SEMUA SERVICE${NC}"; _bot; echo ""
    local svcs=(ssh dropbear stunnel4 xray trojan-go hysteria-server \
                openvpn-server@tcp openvpn-server@udp wg-quick@wg0 nginx \
                badvpn-udpgw-7100 badvpn-udpgw-7200 badvpn-udpgw-7300 \
                ws-max-8880 slowdns ohp cron)
    printf "  ${BLD}${A3}%-28s %s${NC}\n" "SERVICE" "STATUS"
    _sep
    for s in "${svcs[@]}"; do
        local stat
        if is_up "$s"; then
            stat="${LG}● running${NC}"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^${s}\\.service"; then
            stat="${LR}● stopped${NC}"
        else
            stat="${DIM}— not installed${NC}"
        fi
        printf "  %-28s %b\n" "$s" "$stat"
    done
    _sep
    pause
}

tool_cleaner() {
    show_header
    _top; _btn "  ${IT}${AL}🧽  CLEANER — Log, Cache, Journal${NC}"; _bot; echo ""
    inf "Membersihkan log lama..."
    journalctl --vacuum-time=3d &>/dev/null
    find /var/log -type f -name '*.log' -mtime +7 -delete 2>/dev/null
    find /var/log -type f -name '*.gz'  -delete 2>/dev/null
    find /tmp -mindepth 1 -mtime +3 -delete 2>/dev/null
    rm -rf /var/cache/apt/archives/*.deb 2>/dev/null
    apt-get clean -qq &>/dev/null
    ok "Cleaner selesai."
    pause
}

tool_set_banner() {
    show_header
    _top; _btn "  ${IT}${AL}🎨  GANTI BANNER MOTD${NC}"; _bot; echo ""
    echo -e "  ${DIM}Banner saat ini:${NC}"
    head -10 /etc/issue.net 2>/dev/null || echo "  (kosong)"
    echo ""
    echo -e "  ${A2}[1]${NC}  Edit /etc/issue.net (vi/nano)"
    echo -e "  ${A2}[2]${NC}  Generate ulang dengan figlet"
    echo -e "  ${A2}[3]${NC}  Restore default"
    echo -e "  ${LR}[0]${NC}  Batal"
    echo ""
    echo -ne "  ${A1}›${NC} "; read -r ch
    case $ch in
        1) ${EDITOR:-nano} /etc/issue.net ;;
        2)
            echo -ne "  ${A3}Teks banner${NC} [MAX PANEL]: "; read -r t
            [[ -z "$t" ]] && t="MAX PANEL"
            if command -v figlet &>/dev/null; then
                figlet -f standard "$t" > /etc/issue.net
                ok "Banner di-generate"
            else
                echo "$t" > /etc/issue.net
                warn "figlet tidak ada — pakai teks polos"
            fi
            ;;
        3)
            echo "Welcome to MAX PANEL VPS" > /etc/issue.net
            ok "Banner direset"
            ;;
    esac
    pause
}

tool_set_limit() {
    show_header
    _top; _btn "  ${IT}${AL}🚦  LIMIT TOTAL USER${NC}"; _bot; echo ""
    local cur; cur=$(cat "$LIMITF" 2>/dev/null || echo "unlimited")
    echo -e "  ${DIM}Limit saat ini :${NC} ${W}${cur}${NC}"
    echo -e "  ${DIM}User saat ini  :${NC} ${A3}$(total_users_all)${NC}"
    echo ""
    echo -ne "  ${A3}Limit baru (0=unlimited)${NC}: "; read -r v
    [[ ! "$v" =~ ^[0-9]+$ ]] && { err "Bukan angka"; pause; return; }
    if [[ "$v" == "0" ]]; then
        rm -f "$LIMITF"
        ok "Limit diset ke unlimited"
    else
        echo "$v" > "$LIMITF"
        ok "Limit diset ke ${W}${v}${NC}"
    fi
    pause
}

# ════════════════════════════════════════════════════════════
#  BACKUP & RESTORE
# ════════════════════════════════════════════════════════════
do_backup() {
    show_header
    _top; _btn "  ${IT}${AL}💾  BACKUP DATA MAX PANEL${NC}"; _bot; echo ""
    mkdir -p "$BACKUPDIR"
    local out="$BACKUPDIR/max-backup-$(date +%Y-%m-%d_%H%M%S).tar.gz"
    inf "Membuat arsip backup..."

    local files=()
    [[ -d "$DIR" ]] && files+=("$DIR")
    [[ -d /etc/xray ]] && files+=("/etc/xray")
    [[ -d /etc/trojan-go ]] && files+=("/etc/trojan-go")
    [[ -d /etc/hysteria ]] && files+=("/etc/hysteria")
    [[ -d /etc/wireguard ]] && files+=("/etc/wireguard")
    [[ -d /etc/openvpn ]] && files+=("/etc/openvpn")
    [[ -d /etc/stunnel ]] && files+=("/etc/stunnel")
    [[ -d /etc/slowdns ]] && files+=("/etc/slowdns")
    [[ -f /etc/ssh/sshd_config ]] && files+=("/etc/ssh/sshd_config")
    [[ -f /etc/default/dropbear ]] && files+=("/etc/default/dropbear")
    [[ -d /etc/nginx/conf.d ]] && files+=("/etc/nginx/conf.d")

    if tar -czPf "$out" "${files[@]}" 2>/dev/null; then
        local sz; sz=$(du -sh "$out" | cut -f1)
        ok "Backup: ${W}$(basename "$out")${NC} (${Y}${sz}${NC})"
        ok "Path : ${A3}${out}${NC}"
        if _tg_load; then
            inf "Mengirim backup ke Telegram..."
            if tg_send_file "$out" "<b>💾 Backup MAX PANEL</b>
📁 <code>$(basename "$out")</code>
📦 Size: ${sz}
🕒 $(date '+%d/%m/%Y %H:%M:%S')"; then
                ok "Backup terkirim ke Telegram"
            else
                warn "Gagal kirim ke Telegram (cek BOT_TOKEN/CHAT_ID)"
            fi
        else
            warn "Bot Telegram belum di-setup — backup hanya lokal"
        fi
    else
        err "Backup gagal!"
    fi
    pause
}

do_restore() {
    show_header
    _top; _btn "  ${IT}${AL}♻️   RESTORE BACKUP${NC}"; _bot; echo ""
    if [[ ! -d "$BACKUPDIR" ]] || [[ -z "$(ls -A "$BACKUPDIR" 2>/dev/null)" ]]; then
        warn "Belum ada file backup di $BACKUPDIR"
        pause; return
    fi
    local files=() i=1
    while IFS= read -r f; do
        files+=("$f")
        local sz; sz=$(du -sh "$f" 2>/dev/null | cut -f1)
        printf "  ${A2}[%d]${NC} %s ${DIM}(%s)${NC}\n" "$i" "$(basename "$f")" "$sz"
        i=$((i+1))
    done < <(ls -1t "$BACKUPDIR"/*.tar.gz 2>/dev/null)
    echo ""
    echo -ne "  ${A3}Nomor backup${NC}: "; read -r n
    [[ ! "$n" =~ ^[0-9]+$ || $n -lt 1 || $n -gt ${#files[@]} ]] && { err "Nomor invalid"; pause; return; }
    local f="${files[$((n-1))]}"

    warn "Restore akan menimpa file konfigurasi saat ini!"
    echo -ne "  ${A3}Ketik ${LR}YES${A3} untuk konfirmasi${NC}: "; read -r cf
    [[ "$cf" != "YES" ]] && { inf "Dibatalkan."; pause; return; }

    inf "Restoring dari ${W}$(basename "$f")${NC}..."
    tar -xzPf "$f" -C / && ok "Restore selesai" || err "Restore gagal!"
    systemctl daemon-reload
    tool_restart_all >/dev/null 2>&1
    pause
}

# Restore dari Telegram: pilih file backup yang dikirim user ke bot.
# Alur:
#   1) User upload file .tar.gz ke chat bot (sebagai document).
#   2) Pilih menu Restore-from-Telegram.
#   3) Script polling getUpdates untuk document terbaru dari chat tsb,
#      download via getFile/file_path, lalu extract.
do_restore_tg() {
    show_header
    _top; _btn "  ${IT}${AL}♻️   RESTORE DARI TELEGRAM${NC}"; _bot; echo ""
    if ! _tg_load; then
        err "Bot Telegram belum di-setup."
        inf "Buka Pengaturan → Setup Telegram Bot dulu."
        pause; return
    fi
    inf "Kirim file backup (.tar.gz) ke bot @${BOT_NAME:-bot}, lalu tekan Enter..."
    inf "  Chat ID tujuan: ${W}${CHAT_ID}${NC}"
    echo -ne "  ${A3}[Enter] saya sudah kirim, lanjut ambil${NC}"; read -r _

    inf "Polling Telegram untuk document terbaru..."
    local meta fid name
    meta=$(tg_get_latest_document)
    if [[ -z "$meta" || "$meta" != *"|"* ]]; then
        err "Tidak ada document baru di chat. Pastikan file sudah dikirim ke bot."
        warn "Catatan: bot tidak bisa baca file yang dikirim SEBELUM bot di-setup."
        pause; return
    fi
    fid="${meta%%|*}"
    name="${meta#*|}"
    [[ -z "$fid" ]] && { err "file_id kosong"; pause; return; }

    mkdir -p "$TG_TMP" "$BACKUPDIR"
    local out="$BACKUPDIR/tg-restore-$(date +%Y-%m-%d_%H%M%S)-${name}"
    inf "Download '${name}' dari Telegram..."
    if ! tg_download_file "$fid" "$out"; then
        err "Gagal download dari Telegram."; pause; return
    fi
    local sz; sz=$(du -sh "$out" | cut -f1)
    ok "Tersimpan: ${W}$(basename "$out")${NC} (${Y}${sz}${NC})"

    warn "Restore akan menimpa file konfigurasi saat ini!"
    echo -ne "  ${A3}Ketik ${LR}YES${A3} untuk konfirmasi${NC}: "; read -r cf
    [[ "$cf" != "YES" ]] && { inf "Dibatalkan."; pause; return; }

    inf "Restoring..."
    if tar -xzPf "$out" -C / 2>/dev/null; then
        ok "Restore selesai dari Telegram"
        systemctl daemon-reload
        tool_restart_all >/dev/null 2>&1
        tg_send_text "♻️ <b>Restore Selesai</b>
📁 <code>$(basename "$out")</code>
🕒 $(date '+%d/%m/%Y %H:%M:%S')"
    else
        err "Restore gagal! File mungkin korup atau bukan backup MAX PANEL."
    fi
    pause
}

# ════════════════════════════════════════════════════════════
#  UPDATE SCRIPT
# ════════════════════════════════════════════════════════════
cek_update() {
    show_header
    _top; _btn "  ${IT}${AL}🔄  CEK UPDATE MAX PANEL${NC}"; _bot; echo ""
    local cur="$SCRIPT_VERSION" remote
    printf "  ${DIM}Versi sekarang :${NC} ${W}%s${NC}\n" "$cur"
    inf "Mengecek versi terbaru..."
    remote=$(curl -s --max-time 15 "$VERSION_URL" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$remote" ]] && remote=$(wget -qO- --timeout=15 "$VERSION_URL" 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$remote" ]]; then
        err "Gagal cek versi remote."; pause; return
    fi
    printf "  ${DIM}Versi remote  :${NC} ${LG}%s${NC}\n" "$remote"; echo ""

    if [[ "$remote" == "$cur" ]]; then
        ok "Sudah versi terbaru."
        pause; return
    fi
    echo -e "  ${A4}⚡ Update tersedia: ${Y}${cur}${NC} → ${LG}${remote}${NC}"
    echo -ne "  ${A3}Update sekarang? [y/N]${NC}: "; read -r y
    [[ "${y,,}" != "y" ]] && { inf "Dibatalkan"; pause; return; }
    do_update_script
}

do_update_script() {
    local tmp; tmp=$(mktemp /tmp/max-update-XXXXXX.sh)
    if dl "$SCRIPT_URL" "$tmp"; then
        if bash -n "$tmp"; then
            install -m755 "$tmp" /usr/local/bin/max-menu
            ln -sf /usr/local/bin/max-menu /usr/local/bin/menu-max
            ok "Update sukses → restart panel..."
            rm -f "$tmp"
            pause
            exec bash /usr/local/bin/max-menu
        else
            err "File update korup"; rm -f "$tmp"; pause
        fi
    else
        err "Download gagal"; rm -f "$tmp"; pause
    fi
}

check_update_silent() {
    local remote; remote=$(curl -s --max-time 10 "$VERSION_URL" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$remote" ]] && return
    if [[ "$remote" != "$SCRIPT_VERSION" ]]; then
        _tg_send "🔔 <b>MAX PANEL Update Tersedia</b>
Versi: <code>${SCRIPT_VERSION}</code> → <code>${remote}</code>"
        echo "[$(date)] update tersedia: $remote"
    fi
}

# ════════════════════════════════════════════════════════════
#  DOMAIN + SSL Management (acme.sh / certbot)
# ════════════════════════════════════════════════════════════
domain_set() {
    show_header
    _top; _btn "  ${IT}${AL}🌐  SET DOMAIN${NC}"; _bot; echo ""
    local cur ip; cur=$(get_domain); ip=$(get_ip)
    echo -e "  ${DIM}Domain saat ini :${NC} ${W}${cur}${NC}"
    echo -e "  ${DIM}IP Publik       :${NC} ${A3}${ip}${NC}"
    echo ""
    inf "Pastikan A-record domain → ${Y}${ip}${NC}"
    echo -ne "  ${A3}Domain baru${NC} (kosong = pakai IP): "; read -r d
    if [[ -z "$d" ]]; then
        echo "$ip" > "$DOMF"
        ok "Domain di-set ke IP publik"
    else
        echo "$d" > "$DOMF"
        ok "Domain disimpan: ${W}${d}${NC}"
        echo -ne "  ${A3}Issue SSL Let's Encrypt sekarang?${NC} [y/N]: "; read -r y
        [[ "${y,,}" == "y" ]] && domain_issue_ssl
    fi
    pause
}

domain_issue_ssl() {
    show_header
    _top; _btn "  ${IT}${AL}🔐  ISSUE SSL LET'S ENCRYPT (acme.sh)${NC}"; _bot; echo ""
    local dom; dom=$(get_domain)
    [[ "$dom" =~ ^[0-9.]+$ ]] && { err "Domain belum di-set (masih IP)"; pause; return; }
    if [[ ! -x "$HOME/.acme.sh/acme.sh" ]]; then
        inf "Install acme.sh..."
        curl -s https://get.acme.sh | sh -s email=admin@"${dom}" &>/dev/null
    fi
    local ACME="$HOME/.acme.sh/acme.sh"
    [[ -x "$ACME" ]] || { err "acme.sh gagal terinstall"; pause; return; }

    # Stop service yang pakai port 80 sementara
    systemctl stop nginx 2>/dev/null
    systemctl stop xray  2>/dev/null

    "$ACME" --issue --standalone -d "$dom" --keylength 2048 &>/dev/null
    if [[ $? -eq 0 ]]; then
        mkdir -p /etc/xray /etc/hysteria /etc/trojan-go
        "$ACME" --install-cert -d "$dom" \
            --fullchain-file /etc/xray/xray.crt \
            --key-file       /etc/xray/xray.key &>/dev/null
        # FIX: lock down private key ke 600 (acme default 644 untuk fullchain)
        chmod 644 /etc/xray/xray.crt
        chmod 600 /etc/xray/xray.key
        cp -f /etc/xray/xray.crt /etc/hysteria/server.crt
        cp -f /etc/xray/xray.key /etc/hysteria/server.key
        cp -f /etc/xray/xray.crt /etc/trojan-go/server.crt
        cp -f /etc/xray/xray.key /etc/trojan-go/server.key
        chmod 644 /etc/hysteria/server.crt /etc/trojan-go/server.crt
        chmod 600 /etc/hysteria/server.key /etc/trojan-go/server.key
        ok "SSL Let's Encrypt terpasang untuk ${W}${dom}${NC}"
    else
        err "Gagal issue SSL — pastikan domain valid & port 80 bebas"
    fi
    systemctl start nginx 2>/dev/null
    systemctl start xray  2>/dev/null
    systemctl restart hysteria-server 2>/dev/null
    systemctl restart trojan-go 2>/dev/null
    pause
}

# ════════════════════════════════════════════════════════════
#  TELEGRAM BOT setup
# ════════════════════════════════════════════════════════════
tg_setup() {
    show_header
    _top; _btn "  ${IT}${AL}🤖  SETUP TELEGRAM BOT${NC}"; _bot; echo ""
    if [[ -f "$BOTF" ]]; then
        # shellcheck disable=SC1090
        source "$BOTF" 2>/dev/null
        echo -e "  ${DIM}Bot saat ini :${NC} ${LG}@${BOT_NAME:-?}${NC}"
        echo -e "  ${DIM}Chat ID      :${NC} ${W}${CHAT_ID:-?}${NC}"
        echo ""
    fi
    echo -ne "  ${A3}Bot Token${NC}: "; read -r tok
    [[ -z "$tok" ]] && { warn "Dibatalkan"; pause; return; }
    echo -ne "  ${A3}Chat ID${NC}  : "; read -r cid
    [[ -z "$cid" ]] && { warn "Dibatalkan"; pause; return; }
    # Test
    inf "Tes koneksi bot..."
    local resp
    resp=$(curl -s --max-time 10 "https://api.telegram.org/bot${tok}/getMe")
    local name
    name=$(echo "$resp" | grep -oE '"username":"[^"]*"' | head -1 | cut -d\" -f4)
    if [[ -z "$name" ]]; then
        err "Bot token tidak valid!"; pause; return
    fi
    printf "BOT_TOKEN=%q\nCHAT_ID=%q\nBOT_NAME=%q\n" "$tok" "$cid" "$name" > "$BOTF"
    chmod 600 "$BOTF"
    ok "Bot @${name} tersimpan"

    curl -s --max-time 10 -X POST "https://api.telegram.org/bot${tok}/sendMessage" \
        -d "chat_id=${cid}" \
        -d "text=✅ Bot terhubung ke MAX PANEL!" \
        -d "parse_mode=HTML" &>/dev/null
    pause
}

tg_test() {
    show_header
    _top; _btn "  ${IT}${AL}📡  TES TELEGRAM BOT${NC}"; _bot; echo ""
    if [[ ! -f "$BOTF" ]]; then warn "Bot belum di-setup"; pause; return; fi
    _tg_send "🟢 Tes koneksi MAX PANEL — $(date '+%d/%m/%Y %H:%M:%S')"
    ok "Pesan tes terkirim."
    pause
}

# ════════════════════════════════════════════════════════════
#  STORE setup
# ════════════════════════════════════════════════════════════
store_setup() {
    show_header
    _top; _btn "  ${IT}${AL}🛒  SET TOKO / BRAND${NC}"; _bot; echo ""
    if [[ -f "$STRF" ]]; then
        # shellcheck disable=SC1090
        source "$STRF" 2>/dev/null
        echo -e "  ${DIM}Brand     :${NC} ${AL}${BRAND:-MAX PANEL}${NC}"
        echo -e "  ${DIM}Admin TG  :${NC} ${W}${ADMIN_TG:--}${NC}"
        echo -e "  ${DIM}Admin WA  :${NC} ${W}${ADMIN_WA:--}${NC}"
        echo ""
    fi
    echo -ne "  ${A3}Nama Brand${NC} [MAX PANEL]: "; read -r b
    [[ -z "$b" ]] && b="MAX PANEL"
    echo -ne "  ${A3}Admin Telegram${NC}        : "; read -r tg
    [[ -z "$tg" ]] && tg="-"
    echo -ne "  ${A3}Admin WhatsApp${NC}        : "; read -r wa
    [[ -z "$wa" ]] && wa="-"
    printf "BRAND=%q\nADMIN_TG=%q\nADMIN_WA=%q\n" "$b" "$tg" "$wa" > "$STRF"
    ok "Brand/Store tersimpan"
    pause
}

# ════════════════════════════════════════════════════════════
#  MENU TEMA  — 15 Tema (struktur identik dengan ogh-ziv)
# ════════════════════════════════════════════════════════════
menu_tema() {
    while true; do
        clear; load_theme
        local cur_theme; cur_theme=$(cat "$THEMEF" 2>/dev/null || echo 1)
        echo ""
        echo -e "  \033[38;5;135m─────────────────────────────────────────────────────────\033[0m"
        echo -e "  \033[3m\033[38;5;141m  🎨  PILIH TEMA WARNA — 15 Tema Premium\033[0m"
        echo -e "  \033[38;5;135m─────────────────────────────────────────────────────────\033[0m"
        echo ""

        _tema_row() {
            local num="$1" icon="$2" name="$3" desc="$4"
            local c1="$5" c2="$6" c3="$7"
            local mark="  "
            [[ "$cur_theme" == "$num" ]] && mark="\033[1;32m▶\033[0m "
            printf "  %b%s  \033[2m[%2s]\033[0m  %b%-14s\033[0m  %b██\033[0m%b██\033[0m%b██\033[0m  \033[2m%s\033[0m\n" \
                "$mark" "$icon" "$num" "$c1" "$name" "$c1" "$c2" "$c3" "$desc"
        }

        _tema_row  1 "💜" "VIOLET"       "Ungu premium klasik"    '\033[38;5;135m' '\033[38;5;141m' '\033[1;35m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  2 "🩵" "ARCTIC CYAN"  "Neon biru dingin elegan" '\033[38;5;51m'  '\033[38;5;87m'  '\033[1;36m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  3 "💚" "MATRIX GREEN" "Hijau hacker klasik"     '\033[38;5;46m'  '\033[38;5;82m'  '\033[38;5;40m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  4 "💛" "ROYAL GOLD"   "Emas mewah kerajaan"     '\033[38;5;220m' '\033[38;5;226m' '\033[38;5;214m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  5 "❤️ " "CRIMSON RED"  "Merah gagah berani"      '\033[38;5;196m' '\033[38;5;203m' '\033[38;5;204m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  6 "🩷" "SAKURA PINK"  "Pink cantik lembut"      '\033[38;5;213m' '\033[38;5;219m' '\033[38;5;218m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  7 "🌈" "RAINBOW"      "Pelangi warna-warni"     '\033[38;5;196m' '\033[38;5;82m'  '\033[38;5;51m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  8 "🌊" "OCEAN BLUE"   "Biru samudra dalam"      '\033[38;5;27m'  '\033[38;5;33m'  '\033[38;5;45m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row  9 "🌅" "SUNSET ORANGE" "Oranye hangat senja"    '\033[38;5;202m' '\033[38;5;208m' '\033[38;5;214m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row 10 "🌑" "MIDNIGHT"     "Gelap misterius premium"  '\033[38;5;239m' '\033[38;5;245m' '\033[38;5;153m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row 11 "💎" "EMERALD"      "Hijau zamrud mewah"       '\033[38;5;35m'  '\033[38;5;41m'  '\033[38;5;85m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row 12 "🫧" "LAVENDER"     "Ungu lavender anggun"     '\033[38;5;99m'  '\033[38;5;105m' '\033[38;5;183m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row 13 "🌸" "ROSE GOLD"    "Pink keemasan eksklusif"  '\033[38;5;210m' '\033[38;5;216m' '\033[38;5;222m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row 14 "🧊" "ICE WHITE"    "Putih bersih minimalis"   '\033[38;5;195m' '\033[38;5;231m' '\033[38;5;159m'
        echo -e "  \033[38;5;239m─────────────────────────────────────────────────────────\033[0m"
        _tema_row 15 "⚡" "NEON PURPLE"  "Ungu neon cyberpunk"      '\033[38;5;129m' '\033[38;5;135m' '\033[38;5;201m'

        echo ""
        echo -e "  \033[38;5;135m─────────────────────────────────────────────────────────\033[0m"
        echo -e "  \033[2mTema aktif : \033[0m${AL}${THEME_NAME}${NC}"
        echo -e "  \033[38;5;135m─────────────────────────────────────────────────────────\033[0m"
        echo -e "  ${LR}[0]${NC}  ◀  Kembali ke menu utama"
        echo -e "  \033[38;5;135m─────────────────────────────────────────────────────────\033[0m"
        echo ""
        echo -ne "  ${A1}›${NC} Pilih tema [0-15]: "; read -r ch
        case $ch in
            [1-9]|1[0-5])
                echo "$ch" > "$THEMEF"; load_theme
                ok "Tema ${AT}${THEME_NAME}${NC} aktif! ✨"; sleep 0.8 ;;
            0) break ;;
            *) warn "Pilihan tidak valid! Masukkan 0-15"; sleep 0.5 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU SSH/OpenSSH
# ════════════════════════════════════════════════════════════
menu_ssh() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🛡   SSH / OPENSSH / DROPBEAR / STUNNEL${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun SSH"
        _sep; _btn "  ${A2}[2]${NC}  🎁  Akun SSH Trial (1 jam)"
        _sep; _btn "  ${A2}[3]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[4]${NC}  🔁  Perpanjang Akun"
        _sep; _btn "  ${A2}[5]${NC}  📋  List Semua Akun"
        _sep; _btn "  ${A2}[6]${NC}  🔍  Cek User Online"
        _sep; _btn "  ${A2}[7]${NC}  🧹  Hapus Akun Expired"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) ssh_add ;; 2) ssh_trial ;; 3) ssh_del ;;
            4) ssh_renew ;; 5) ssh_list ;; 6) ssh_online ;;
            7) ssh_clean_expired ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU OpenVPN
# ════════════════════════════════════════════════════════════
menu_openvpn() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🛡   OPENVPN — TCP 1194 + UDP 2200${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun OpenVPN"
        _sep; _btn "  ${A2}[2]${NC}  🎁  Akun Trial (1 jam)"
        _sep; _btn "  ${A2}[3]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[4]${NC}  🔁  Perpanjang Akun"
        _sep; _btn "  ${A2}[5]${NC}  📋  List Semua Akun"
        _sep; _btn "  ${A2}[6]${NC}  🔍  Cek Online"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) ovpn_add ;; 2) ovpn_trial ;; 3) ovpn_del ;;
            4) ovpn_renew ;; 5) ovpn_list ;; 6) ovpn_online ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU Xray (VMess / VLess / Trojan / Shadowsocks)
# ════════════════════════════════════════════════════════════
menu_xray() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🛡   XRAY-CORE — VMess / VLess / Trojan / SS${NC}"
        _sep; _btn "  ${A2}[1]${NC}  🟣  Menu VMess"
        _sep; _btn "  ${A2}[2]${NC}  🔵  Menu VLess"
        _sep; _btn "  ${A2}[3]${NC}  🔴  Menu Trojan (Xray)"
        _sep; _btn "  ${A2}[4]${NC}  🟢  Menu Shadowsocks"
        _sep; _btn "  ${A2}[5]${NC}  🔍  Cek User Xray Online"
        _sep; _btn "  ${A2}[6]${NC}  🧹  Hapus User Expired"
        _sep; _btn "  ${A2}[7]${NC}  🔄  Sync Konfigurasi"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) menu_vmess ;; 2) menu_vless ;; 3) menu_trojan ;;
            4) menu_ss ;;    5) xray_online ;; 6) xray_clean_expired ;;
            7) _xray_sync_clients; ok "Xray config disinkron"; sleep 1 ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

menu_vmess() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🟣  VMESS — path /vmess via Nginx 80/443${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun"
        _sep; _btn "  ${A2}[2]${NC}  🎁  Trial 1 jam"
        _sep; _btn "  ${A2}[3]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[4]${NC}  🔁  Perpanjang"
        _sep; _btn "  ${A2}[5]${NC}  📋  List Akun"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) vmess_add ;; 2) vmess_trial ;; 3) vmess_del ;;
            4) vmess_renew ;; 5) vmess_list ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

menu_vless() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🔵  VLESS — path /vless via Nginx 80/443 + gRPC${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun"
        _sep; _btn "  ${A2}[2]${NC}  🎁  Trial 1 jam"
        _sep; _btn "  ${A2}[3]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[4]${NC}  🔁  Perpanjang"
        _sep; _btn "  ${A2}[5]${NC}  📋  List Akun"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) vless_add ;; 2) vless_trial ;; 3) vless_del ;;
            4) vless_renew ;; 5) vless_list ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

menu_trojan() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🔴  TROJAN (Xray) — path /trojan-ws via Nginx 443 + gRPC${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun"
        _sep; _btn "  ${A2}[2]${NC}  🎁  Trial 1 jam"
        _sep; _btn "  ${A2}[3]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[4]${NC}  🔁  Perpanjang"
        _sep; _btn "  ${A2}[5]${NC}  📋  List Akun"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) trojan_add ;; 2) trojan_trial ;; 3) trojan_del ;;
            4) trojan_renew ;; 5) trojan_list ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

menu_ss() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🟢  SHADOWSOCKS — port 8388${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun"
        _sep; _btn "  ${A2}[2]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[3]${NC}  📋  List Akun"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) ss_add ;; 2) ss_del ;; 3) ss_list ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU Trojan-Go
# ════════════════════════════════════════════════════════════
menu_trojan_go() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}⚡  TROJAN-GO — port 2096${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun"
        _sep; _btn "  ${A2}[2]${NC}  🎁  Trial 1 jam"
        _sep; _btn "  ${A2}[3]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[4]${NC}  🔁  Perpanjang"
        _sep; _btn "  ${A2}[5]${NC}  📋  List Akun"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) tgo_add ;; 2) tgo_trial ;; 3) tgo_del ;;
            4) tgo_renew ;; 5) tgo_list ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU WireGuard
# ════════════════════════════════════════════════════════════
menu_wireguard() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🌐  WIREGUARD — UDP 51820${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Tambah Peer"
        _sep; _btn "  ${A2}[2]${NC}  🗑   Hapus Peer"
        _sep; _btn "  ${A2}[3]${NC}  🔁  Perpanjang Peer"
        _sep; _btn "  ${A2}[4]${NC}  📋  List Peer"
        _sep; _btn "  ${A2}[5]${NC}  🔍  Peer Online"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) wg_add ;; 2) wg_del ;; 3) wg_renew ;;
            4) wg_list ;; 5) wg_online ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU Hysteria
# ════════════════════════════════════════════════════════════
menu_hysteria() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}⚡  HYSTERIA 2 — UDP 36712${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun"
        _sep; _btn "  ${A2}[2]${NC}  🎁  Trial 1 jam"
        _sep; _btn "  ${A2}[3]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[4]${NC}  🔁  Perpanjang"
        _sep; _btn "  ${A2}[5]${NC}  📋  List Akun"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) hy_add ;; 2) hy_trial ;; 3) hy_del ;;
            4) hy_renew ;; 5) hy_list ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU SlowDNS
# ════════════════════════════════════════════════════════════
menu_slowdns() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}🌐  SLOWDNS — port 53 → 5300${NC}"
        _sep; _btn "  ${A2}[1]${NC}  ➕  Buat Akun"
        _sep; _btn "  ${A2}[2]${NC}  🗑   Hapus Akun"
        _sep; _btn "  ${A2}[3]${NC}  🔁  Perpanjang"
        _sep; _btn "  ${A2}[4]${NC}  📋  List Akun"
        _sep; _btn "  ${A2}[5]${NC}  🔑  Tampilkan PublicKey Server"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) slow_add ;; 2) slow_del ;; 3) slow_renew ;; 4) slow_list ;;
            5) cat "$SLOW_DIR/server.pub" 2>/dev/null || warn "PubKey tidak ada"; pause ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU System Tools
# ════════════════════════════════════════════════════════════
menu_system() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}⚙️   SYSTEM TOOLS${NC}"
        _sep; _btn "  ${A2}[1]${NC}  🚀  BBR Toggle"
        _sep; _btn "  ${A2}[2]${NC}  🛑  IPv6 Toggle"
        _sep; _btn "  ${A2}[3]${NC}  📡  Speedtest"
        _sep; _btn "  ${A2}[4]${NC}  ℹ️   System Info"
        _sep; _btn "  ${A2}[5]${NC}  ♻️   Auto-Reboot Scheduler"
        _sep; _btn "  ${A2}[6]${NC}  📊  Bandwidth (vnstat)"
        _sep; _btn "  ${A2}[7]${NC}  🔄  Restart Semua Service"
        _sep; _btn "  ${A2}[8]${NC}  🔍  Check Status Service"
        _sep; _btn "  ${A2}[9]${NC}  🧽  Cleaner (log/cache)"
        _sep; _btn "  ${A2}[A]${NC}  🎨  Ganti Banner MOTD"
        _sep; _btn "  ${A2}[B]${NC}  🚦  Limit Total User"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case ${ch,,} in
            1) tool_bbr ;;       2) tool_ipv6 ;;     3) tool_speedtest ;;
            4) tool_sysinfo ;;   5) tool_reboot_sched ;;
            6) tool_bandwidth ;; 7) tool_restart_all ;; 8) tool_check_service ;;
            9) tool_cleaner ;;   a) tool_set_banner ;; b) tool_set_limit ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU Backup
# ════════════════════════════════════════════════════════════
menu_backup() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}💾  BACKUP & RESTORE${NC}"
        _sep; _btn "  ${A2}[1]${NC}  💾  Backup Sekarang (lokal + Telegram)"
        _sep; _btn "  ${A2}[2]${NC}  ♻️   Restore dari File Lokal"
        _sep; _btn "  ${A2}[3]${NC}  ☁️   Restore dari Telegram"
        _sep; _btn "  ${A2}[4]${NC}  📋  List File Backup"
        _sep; _btn "  ${A2}[5]${NC}  🗑   Hapus Backup Lama"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) do_backup ;; 2) do_restore ;; 3) do_restore_tg ;;
            4)
                show_header; _top; _btn "  ${IT}${AL}📋  LIST BACKUP${NC}"; _bot
                if [[ -d "$BACKUPDIR" ]]; then
                    ls -lh "$BACKUPDIR" 2>/dev/null | awk 'NR>1{printf "  %s  %s\n", $9, $5}'
                else
                    warn "Belum ada backup"
                fi
                pause ;;
            5)
                show_header; _top; _btn "  ${IT}${AL}🗑  HAPUS BACKUP > 30 HARI${NC}"; _bot
                find "$BACKUPDIR" -name 'max-backup-*.tar.gz' -mtime +30 -delete -print 2>/dev/null
                ok "Backup > 30 hari dihapus"; pause ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MENU Settings (domain, bot, store, banner)
# ════════════════════════════════════════════════════════════
menu_settings() {
    while true; do
        show_header
        _top; _btn "  ${IT}${AL}⚙️   PENGATURAN PANEL${NC}"
        _sep; _btn "  ${A2}[1]${NC}  🌐  Set Domain"
        _sep; _btn "  ${A2}[2]${NC}  🔐  Issue SSL (acme.sh)"
        _sep; _btn "  ${A2}[3]${NC}  🤖  Setup Telegram Bot"
        _sep; _btn "  ${A2}[4]${NC}  📡  Tes Telegram Bot"
        _sep; _btn "  ${A2}[5]${NC}  🛒  Set Toko/Brand"
        _sep; _btn "  ${A2}[6]${NC}  🎨  Ganti Banner MOTD"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""
        echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) domain_set ;; 2) domain_issue_ssl ;;
            3) tg_setup ;;   4) tg_test ;;
            5) store_setup ;; 6) tool_set_banner ;;
            0) break ;; *) warn "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  ABOUT
# ════════════════════════════════════════════════════════════
menu_about() {
    show_header
    _top; _btn "  ${IT}${AL}ℹ️   TENTANG MAX PANEL${NC}"; _bot; echo ""
    cat <<ABOUT
  ${BLD}MAX PANEL — Premium VPS Tunneling${NC}
  Versi    : ${LG}${SCRIPT_VERSION}${NC}
  Repo     : ${W}https://github.com/chanelog/max${NC}
  Lisensi  : ${A3}Open / Free${NC}

  ${DIM}Protokol terinstall:${NC}
   • OpenSSH (22)                  • Dropbear (109, 143)
   • Stunnel SSL (445, 777)        • Nginx (80 / 443 / 8443)
   • SSH WebSocket via Nginx        • OpenVPN (TCP 1194 / UDP 2200)
   • Xray VMess/VLess/Trojan/SS    • Trojan-Go (2096)
   • Hysteria 2 (UDP 36712 + range) • BadVPN UDPGW (7100/7200/7300)
   • WireGuard (UDP 51820)         • SlowDNS (53 → 5300)
   • OHP (8081) opsional

  ${DIM}Path config:${NC}
   • /etc/maxpanel/        : panel data + user DB
   • /etc/xray/            : Xray config + SSL
   • /etc/trojan-go/       : Trojan-Go
   • /etc/hysteria/        : Hysteria 2
   • /etc/wireguard/wg0.conf : WireGuard
   • /etc/openvpn/         : OpenVPN (TCP+UDP)
   • /etc/slowdns/         : SlowDNS

  ${DIM}Command:${NC}
   • ${W}menu-max${NC}  : buka panel
   • ${W}max-menu${NC}  : alias
ABOUT
    echo ""
    pause
}

# ════════════════════════════════════════════════════════════
#  CEK SEMUA AKUN — Ringkasan SSH + V2Ray + Status Proxy
# ════════════════════════════════════════════════════════════
_count_db() {
    local db="$1"
    [[ -s "$db" ]] || { echo 0; return; }
    grep -cvE '^[[:space:]]*$' "$db"
}

_count_db_expired() {
    local db="$1" exp_field="${2:-3}" cnt=0
    [[ -s "$db" ]] || { echo 0; return; }
    local exp
    while IFS='|' read -r -a parts; do
        exp="${parts[$((exp_field-1))]:-}"
        [[ -z "$exp" ]] && continue
        # Skip trial markers (TRIAL, TRIAL-<ts>) — bukan tanggal YYYY-MM-DD
        [[ "$exp" == TRIAL* ]] && continue
        [[ ! "$exp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && continue
        if is_expired "$exp"; then cnt=$((cnt+1)); fi
    done < "$db"
    echo "$cnt"
}

_port_badge() {
    local port="$1" proto="${2:-tcp}"
    if ss -lnt "( sport = :$port )" 2>/dev/null | grep -q ":$port"; then
        printf '%b' "${LG}●${NC}"
    elif [[ "$proto" == "udp" ]] && ss -lnu "( sport = :$port )" 2>/dev/null | grep -q ":$port"; then
        printf '%b' "${LG}●${NC}"
    else
        printf '%b' "${LR}●${NC}"
    fi
}

cek_all_accounts() {
    show_header
    _top; _btn "  ${IT}${AL}📊  CEK SEMUA AKUN & STATUS PROXY${NC}"; _bot; echo ""

    # ── Akun per protokol ──
    local ssh_t ssh_e vm_t vm_e vl_t vl_e tr_t tr_e tgo_t tgo_e
    local ss_t ss_e hy_t hy_e wg_t ovpn_t ovpn_e slow_t slow_e
    ssh_t=$(_count_db   "$SSH_DB");      ssh_e=$(_count_db_expired "$SSH_DB"   3)
    vm_t=$(_count_db    "$VMESS_DB");    vm_e=$(_count_db_expired "$VMESS_DB"  3)
    vl_t=$(_count_db    "$VLESS_DB");    vl_e=$(_count_db_expired "$VLESS_DB"  3)
    tr_t=$(_count_db    "$TROJAN_DB");   tr_e=$(_count_db_expired "$TROJAN_DB" 3)
    tgo_t=$(_count_db   "$TROJANGO_DB"); tgo_e=$(_count_db_expired "$TROJANGO_DB" 3)
    ss_t=$(_count_db    "$SS_DB");       ss_e=$(_count_db_expired "$SS_DB"     3)
    hy_t=$(_count_db    "$HY_DB");       hy_e=$(_count_db_expired "$HY_DB"     3)
    wg_t=$(_count_db    "$WG_DB")
    ovpn_t=$(_count_db  "$OVPN_DB");     ovpn_e=$(_count_db_expired "$OVPN_DB" 3)
    slow_t=$(_count_db  "$SLOW_DB");     slow_e=$(_count_db_expired "$SLOW_DB" 3)

    # Total + expired global
    local total_all=$(( ssh_t + vm_t + vl_t + tr_t + tgo_t + ss_t + hy_t + wg_t + ovpn_t + slow_t ))
    local exp_all=$(( ssh_e + vm_e + vl_e + tr_e + tgo_e + ss_e + hy_e + ovpn_e + slow_e ))

    echo -e "  ${A1}┌──────────────── ${BLD}${AL}AKUN${NC} ${A1}──────────────────${NC}"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "🛡 SSH"        "$ssh_t"  "$ssh_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "🟣 VMess"      "$vm_t"   "$vm_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "🟣 VLess"      "$vl_t"   "$vl_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "🟣 Trojan"     "$tr_t"   "$tr_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "⚡ Trojan-Go"  "$tgo_t"  "$tgo_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "🧦 Shadowsocks" "$ss_t"  "$ss_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "💨 Hysteria 2" "$hy_t"   "$hy_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}\n"                          "🌐 WireGuard"  "$wg_t"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "🔐 OpenVPN"    "$ovpn_t" "$ovpn_e"
    printf  "  ${A1}│${NC} %-12s  Total ${W}%4d${NC}   Expired ${LR}%3d${NC}\n" "🌍 SlowDNS"    "$slow_t" "$slow_e"
    echo -e "  ${A1}├─────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} %-12s  Total ${LG}%4d${NC}   Expired ${LR}%3d${NC}\n" "📊 SEMUA"      "$total_all" "$exp_all"
    echo -e "  ${A1}└─────────────────────────────────────────────${NC}"
    echo ""

    # ── Status service + port ──
    echo -e "  ${A1}┌──────────── ${BLD}${AL}STATUS LAYANAN & PORT${NC} ${A1}──────────${NC}"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge ssh)"      "OpenSSH"      "22"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge dropbear)" "Dropbear"     "109, 143"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge stunnel4)" "Stunnel SSL"  "990, 446, 110, 444"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge nginx)"    "Nginx (HTTP)" "80, 8080, 2086, 8880"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge nginx)"    "Nginx (TLS)"  "443, 2083, 2087, 8443"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge xray)"     "Xray-core"    "10001-10005 (loop), 8388 (SS)"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge trojan-go)" "Trojan-Go"   "2096"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge hysteria-server)" "Hysteria 2" "36712 (UDP)"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge wg-quick@wg0)" "WireGuard" "51820 (UDP)"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge openvpn-server@tcp)" "OpenVPN TCP" "1194"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge openvpn-server@udp)" "OpenVPN UDP" "2200"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge slowdns)"  "SlowDNS"      "53, 5300"
    printf  "  ${A1}│${NC} %s  %-10s  ${DIM}port${NC} ${Y}%s${NC}\n" "$(svc_badge ws-max-8880)" "WS Proxy"  "8880 (internal)"
    echo -e "  ${A1}└─────────────────────────────────────────────${NC}"
    echo ""

    # Online sesi (cepat, tidak fatal kalau log Xray belum ada)
    local ssh_online_n
    ssh_online_n=$(ps -eo cmd --no-headers 2>/dev/null | grep -c '^sshd: ')
    printf "  ${DIM}🔴 SSH session aktif :${NC} ${LG}%s${NC}\n" "$ssh_online_n"
    echo ""

    pause
}

# ════════════════════════════════════════════════════════════
#  MAIN MENU
# ════════════════════════════════════════════════════════════
main_menu() {
    # Cetak baris menu 2 kolom — kolom kiri 32 char, separator, kolom kanan
    _r2() {
        local CL="$1" TL="$2" CR="$3" TR="$4"
        echo -e "  ${CL}${TL}${NC}  ${A1}│${NC}  ${CR}${TR}${NC}"
    }

    while true; do
        show_header

        echo -e "  ${A1}${_DASH}${NC}"
        echo -e "  ${A1}     +-------------- ${BLD}${AL}MAX PANEL MAIN MENU${NC} ${A1}--------------+${NC}"
        echo -e "  ${A1}${_DASH}${NC}"
        echo ""

        _r2 "${A2}" "[1]  🛡  SSH / OpenSSH      " "${A2}" "[2]  🔐  OpenVPN"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${A2}" "[3]  🟣  Xray (VMess/VL/TR) " "${A2}" "[4]  ⚡  Trojan-Go"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${A2}" "[5]  🌐  WireGuard          " "${A2}" "[6]  💨  Hysteria 2"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${A2}" "[7]  🌍  SlowDNS            " "${A2}" "[8]  ⚙   System Tools"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${A2}" "[9]  💾  Backup & Restore   " "${A2}" "[10] 🎨  Tema"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${A2}" "[11] ⚙️  Pengaturan         " "${A2}" "[12] 🔄  Update Script"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${A2}" "[13] ℹ️  About              " "${A2}" "[14] 📊  Cek Semua Akun"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${A4}" "[15] 🚀  Install Ulang      " "${LR}" "[E]  🗑  Uninstall"
        echo -e "  ${A1}${_DASH}${NC}"
        _r2 "${LR}" "[X]  ✗   Keluar             " "${DIM}" "                                "
        echo -e "  ${A1}${_DASH}${NC}"
        echo -e "  ${DIM}                   ✦  MAX PANEL v${SCRIPT_VERSION}  ✦                ${NC}"
        echo ""
        echo -ne "  ${A1}›${NC} Pilih menu: "; read -r ch
        case ${ch,,} in
            1)  menu_ssh ;;
            2)  menu_openvpn ;;
            3)  menu_xray ;;
            4)  menu_trojan_go ;;
            5)  menu_wireguard ;;
            6)  menu_hysteria ;;
            7)  menu_slowdns ;;
            8)  menu_system ;;
            9)  menu_backup ;;
            10) menu_tema ;;
            11) menu_settings ;;
            12) cek_update ;;
            13) menu_about ;;
            14) cek_all_accounts ;;
            15) do_install_all ;;
            e)  do_uninstall ;;
            x|0)
                echo -e "\n  ${IT}${AL}Sampai jumpa! — MAX PANEL${NC}\n"
                exit 0 ;;
            *)  warn "Pilihan tidak valid!"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  UNINSTALL
# ════════════════════════════════════════════════════════════
do_uninstall() {
    show_header
    _top; _btn "  ${IT}${LR}🗑   UNINSTALL MAX PANEL${NC}"; _bot; echo ""
    warn "Aksi ini akan menghapus seluruh data MAX PANEL!"
    warn "Termasuk: semua user, config Xray/Trojan-Go/Hysteria/WG/OpenVPN, dll"
    echo ""
    echo -ne "  ${A3}Ketik ${LR}UNINSTALL${A3} untuk lanjut${NC}: "; read -r cf
    [[ "$cf" != "UNINSTALL" ]] && { inf "Dibatalkan"; pause; return; }

    inf "Menghentikan service..."
    for s in xray trojan-go hysteria-server wg-quick@wg0 stunnel4 dropbear \
             openvpn-server@tcp openvpn-server@udp slowdns ohp \
             ws-max-8880 \
             badvpn-udpgw-7100 badvpn-udpgw-7200 badvpn-udpgw-7300 nginx; do
        systemctl stop "$s" 2>/dev/null
        systemctl disable "$s" 2>/dev/null
    done

    inf "Menghapus file binary & config..."
    rm -rf /etc/xray /etc/trojan-go /etc/hysteria /etc/slowdns
    rm -f  "$XRAY_BIN" "$TROJANGO_BIN" "$HY_BIN" "$UDPGW_BIN" "$WS_BIN" "$OHP_BIN" "$SLOW_BIN"
    rm -f  /etc/systemd/system/xray.service /etc/systemd/system/trojan-go.service
    rm -f  /etc/systemd/system/hysteria-server.service /etc/systemd/system/slowdns.service
    rm -f  /etc/systemd/system/badvpn-udpgw-*.service
    rm -f  /etc/systemd/system/ws-max-*.service /etc/systemd/system/ohp.service
    rm -f  /etc/cron.d/maxpanel-*
    rm -f  /usr/local/bin/menu-max /usr/local/bin/max-menu

    # WireGuard hanya disable
    systemctl disable wg-quick@wg0 2>/dev/null

    # Hapus splash dari bashrc
    sed -i '/MAX-PANEL-SPLASH/,+1d' /root/.bashrc 2>/dev/null
    sed -i "/alias menu-max=/d;/alias max-menu=/d" /root/.bashrc 2>/dev/null

    # Hapus user yang dibuat panel (SSH/OpenVPN/SlowDNS DB)
    for db in "$SSH_DB" "$OVPN_DB" "$SLOW_DB"; do
        [[ -s "$db" ]] || continue
        while IFS='|' read -r u _ _ _; do userdel -r "$u" 2>/dev/null; done < "$db"
    done

    rm -rf "$DIR" "$LOGDIR"
    systemctl daemon-reload

    ok "MAX PANEL berhasil di-uninstall."
    pause
    exit 0
}

# ════════════════════════════════════════════════════════════
#  SETUP COMMAND  — install ke /usr/local/bin/max-menu
# ════════════════════════════════════════════════════════════
setup_menu_cmd() {
    cp "$0" /usr/local/bin/max-menu 2>/dev/null
    chmod +x /usr/local/bin/max-menu 2>/dev/null
    ln -sf /usr/local/bin/max-menu /usr/local/bin/menu-max 2>/dev/null
    chmod +x /usr/local/bin/menu-max 2>/dev/null

    sed -i '/alias menu-max=/d' ~/.bashrc 2>/dev/null
    sed -i '/alias max-menu=/d' ~/.bashrc 2>/dev/null
    echo "alias menu-max='bash /usr/local/bin/max-menu'" >> ~/.bashrc
    echo "alias max-menu='bash /usr/local/bin/max-menu'" >> ~/.bashrc

    sed -i '/alias menu-max=/d' /root/.profile 2>/dev/null
    echo "alias menu-max='bash /usr/local/bin/max-menu'" >> /root/.profile

    cat > /etc/profile.d/max-panel.sh <<'PROFEOF'
#!/bin/bash
alias menu-max='bash /usr/local/bin/max-menu'
alias max-menu='bash /usr/local/bin/max-menu'
PROFEOF
    chmod +x /etc/profile.d/max-panel.sh 2>/dev/null
}

# ════════════════════════════════════════════════════════════
#  SSH SPLASH (auto-tampil saat SSH login)
# ════════════════════════════════════════════════════════════
install_ssh_splash() {
    cat > /etc/max-panel-splash.sh <<'SPLASH'
#!/bin/bash
# MAX-PANEL splash — auto-generated, jangan diedit manual

THEMEF="/etc/maxpanel/theme.conf"
NC='\033[0m'; BLD='\033[1m'; DIM='\033[2m'
cur_theme=$(cat "$THEMEF" 2>/dev/null || echo 1)
case "$cur_theme" in
    7)  L1='\033[38;5;196m'; L2='\033[38;5;214m'; L3='\033[38;5;226m'
        L4='\033[38;5;82m';  L5='\033[38;5;51m'
        A1='\033[38;5;82m';  A2='\033[38;5;82m';  A3='\033[38;5;226m'; A4='\033[38;5;51m' ;;
    2)  L1='\033[38;5;51m';  L2='\033[38;5;51m';  L3='\033[0;36m'
        L4='\033[38;5;51m';  L5='\033[0;36m'
        A1='\033[38;5;51m';  A2='\033[1;36m';     A3='\033[0;36m';     A4='\033[38;5;123m' ;;
    *)  L1='\033[1;37m';     L2='\033[1;37m';     L3='\033[1;33m'
        L4='\033[1;37m';     L5='\033[1;33m'
        A1='\033[1;34m';     A2='\033[1;32m';     A3='\033[1;33m';     A4='\033[1;36m' ;;
esac
DASH="───────────────────────────────────────────────────────────────"
clear
echo ""
echo -e "  ${A1}${DASH}${NC}"
echo -e "  ${L1}${BLD}  ███╗   ███╗ █████╗ ██╗  ██╗    ██████╗  █████╗ ███╗   ██╗ ${NC}"
echo -e "  ${L2}${BLD}  ████╗ ████║██╔══██╗╚██╗██╔╝    ██╔══██╗██╔══██╗████╗  ██║ ${NC}"
echo -e "  ${L3}${BLD}  ██╔████╔██║███████║ ╚███╔╝     ██████╔╝███████║██╔██╗ ██║ ${NC}"
echo -e "  ${L4}${BLD}  ██║╚██╔╝██║██╔══██║ ██╔██╗     ██╔═══╝ ██╔══██║██║╚██╗██║ ${NC}"
echo -e "  ${L5}${BLD}  ██║ ╚═╝ ██║██║  ██║██╔╝ ██╗    ██║     ██║  ██║██║ ╚████║ ${NC}"
echo -e "  ${DIM}  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝ ${NC}"
echo -e "  ${A1}${DASH}${NC}"
echo ""
echo -e "  ${A4}      ✦  * MAX PREMIUM TUNNELING PANEL *  ✦      ${NC}"
echo -e "  ${DIM}     +------------ ${A2}[ ALL-IN-ONE ]${DIM} ------------+    ${NC}"
echo ""
echo -e "  ${A1}${DASH}${NC}"
echo -e "  ${DIM}            ✦  MAX PANEL — chanelog/max  ✦            ${NC}"
echo -e "  ${A1}${DASH}${NC}"
echo ""
echo -e "       ${A3}type ${BLD}menu-max${NC}${A3} to continue${NC}"
echo ""
SPLASH

    chmod +x /etc/max-panel-splash.sh

    sed -i '/# MAX-PANEL-SPLASH/d' /root/.bashrc 2>/dev/null
    sed -i '/max-panel-splash/d'   /root/.bashrc 2>/dev/null
    echo '# MAX-PANEL-SPLASH' >> /root/.bashrc
    echo 'bash /etc/max-panel-splash.sh' >> /root/.bashrc
}

# ════════════════════════════════════════════════════════════
#  CLI FLAG HANDLER (untuk cron / first-run)
# ════════════════════════════════════════════════════════════
handle_cli_flags() {
    case "${1:-}" in
        --check-maxlogin)
            check_root
            mkdir -p "$DIR"
            check_maxlogin_all
            exit 0
            ;;
        --clean-expired)
            check_root
            do_clean_expired_all
            exit 0
            ;;
        --sync-xray)
            check_root
            _xray_sync_clients
            exit 0
            ;;
        --auto-backup)
            check_root
            mkdir -p "$BACKUPDIR"
            local out="$BACKUPDIR/max-backup-$(date +%Y-%m-%d_%H%M%S).tar.gz"
            tar -czPf "$out" \
                "$DIR" /etc/xray /etc/trojan-go /etc/hysteria /etc/wireguard \
                /etc/openvpn /etc/stunnel /etc/slowdns 2>/dev/null
            # Rotate: simpan max 10 backup
            ls -1t "$BACKUPDIR"/max-backup-*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
            # Kirim ke Telegram bila bot di-setup
            if _tg_load && [[ -s "$out" ]]; then
                local sz; sz=$(du -sh "$out" | cut -f1)
                tg_send_file "$out" "<b>💾 Auto-Backup MAX PANEL</b>
📁 <code>$(basename "$out")</code>
📦 Size: ${sz}
🕒 $(date '+%d/%m/%Y %H:%M:%S')" || true
            fi
            echo "[$(date)] auto-backup: $out"
            exit 0
            ;;
        --check-update)
            check_update_silent
            exit 0
            ;;
        --version|-v)
            echo "MAX PANEL v${SCRIPT_VERSION}"
            exit 0
            ;;
        --help|-h)
            cat <<HELP
MAX PANEL v${SCRIPT_VERSION}

Usage:
  setup-max.sh                 → Install + buka menu
  setup-max.sh --version       → Versi
  setup-max.sh --check-maxlogin → Enforce maxlogin (cron)
  setup-max.sh --clean-expired  → Hapus user expired (cron)
  setup-max.sh --auto-backup    → Backup data (cron)
  setup-max.sh --check-update   → Cek versi terbaru
  setup-max.sh --sync-xray      → Sync Xray config dari DB

Command setelah install:
  menu-max          → buka panel
HELP
            exit 0
            ;;
    esac
}

# ════════════════════════════════════════════════════════════
#  MAIN ENTRYPOINT
# ════════════════════════════════════════════════════════════

# Cek CLI flags dulu (untuk cron)
handle_cli_flags "$@"

# Cek prasyarat
check_root
check_os

# Setup direktori dasar
mkdir -p "$DIR" "$LOGDIR" "$BACKUPDIR"

# Theme & touch DB files
load_theme
for f in "$MLDB" "$SSH_DB" "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" \
         "$TROJANGO_DB" "$OVPN_DB" "$WG_DB" "$HY_DB" "$SS_DB" "$SLOW_DB"; do
    [[ ! -f "$f" ]] && touch "$f"
done

# Deteksi: jika belum diinstall (binary inti tidak ada), jalankan installer.
NEED_INSTALL=0
[[ ! -x "$XRAY_BIN" ]] && NEED_INSTALL=1
[[ ! -f "$VERSIONF" ]] && NEED_INSTALL=1

if [[ "$NEED_INSTALL" == "1" && ! -L /usr/local/bin/menu-max && ! -x /usr/local/bin/max-menu ]]; then
    # First-run flow: install + langsung set command
    do_install_all
    # Setelah install, masuk menu utama
    main_menu
    exit 0
fi

# Setup symlink command kalau belum
if [[ ! -x /usr/local/bin/max-menu ]]; then
    setup_menu_cmd 2>/dev/null
fi

# Splash install (sekali)
if [[ ! -f /etc/max-panel-splash.sh ]]; then
    install_ssh_splash 2>/dev/null
fi

# Langsung buka menu utama
main_menu
exit 0
