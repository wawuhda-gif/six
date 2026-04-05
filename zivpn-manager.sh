#!/bin/bash
# zivpn-manager.sh - Panel Manajemen Akun ZiVPN UDP
# Multi-VPS | Debian & Ubuntu | Fixed Edition

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Garis tebal unicode
LINE='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
LINE2='══════════════════════════════════════════════'

DB="/etc/zivpn-panel/users.db"
CONF="/etc/zivpn-panel/panel.conf"
BACKUP_DIR="/etc/zivpn-panel/backups"

[[ -f "$CONF" ]] && source "$CONF"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Harus dijalankan sebagai root!${NC}"; exit 1
fi

# ─── FUNGSI UMUM ───────────────────────────────────────
header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔${LINE2}╗"
    printf "  ║  %-44s║\n" "$1"
    echo "  ╚${LINE2}╝"
    echo -e "  ${LINE}"
    echo -e "${NC}"
}

section() {
    echo -e "${CYAN}${BOLD}  ${LINE}${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}  ${LINE}${NC}"
}

pause() {
    echo ""
    echo -e "${CYAN}${BOLD}  ${LINE}${NC}"
    echo -e "${YELLOW}  Tekan Enter untuk kembali...${NC}"
    echo -e "${CYAN}${BOLD}  ${LINE}${NC}"
    read -r
}

get_ip() {
    curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

# ─── MONITOR SESSION & EXPIRED ─────────────────────────
monitor_sessions() {
    sqlite3 "$DB" "UPDATE accounts SET status='expired'
                   WHERE expired_date < datetime('now') AND expired_date != '' AND status='active';" 2>/dev/null
}

# ─── INFO SPEK VPS ─────────────────────────────────────
get_spek() {
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
    DISK_USED=$(df -h / | awk 'NR==2{print $3}')
    DISK_PERSEN=$(df -h / | awk 'NR==2{print $5}')
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    UPTIME_STR=$(uptime -p)
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
}

# ─── CREATE AKUN ───────────────────────────────────────
create_account() {
    header "➕  CREATE AKUN BARU"

    section "Input Data Akun"
    read -p "  Username     : " username
    echo -e "  ${CYAN}${LINE}${NC}"

    if [[ -z "$username" ]]; then
        echo -e "  ${RED}Username tidak boleh kosong!${NC}"; pause; return
    fi

    exist=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE username='$username';")
    if [[ "$exist" -gt 0 ]]; then
        echo -e "  ${RED}Username '$username' sudah ada!${NC}"; pause; return
    fi

    read -p "  Password (enter=auto): " password
    echo -e "  ${CYAN}${LINE}${NC}"
    [[ -z "$password" ]] && password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)

    read -p "  Max Login    : " max_login
    echo -e "  ${CYAN}${LINE}${NC}"
    [[ -z "$max_login" ]] && max_login=2

    read -p "  Lama aktif (hari) [15/30]: " exp_days
    echo -e "  ${CYAN}${LINE}${NC}"
    [[ -z "$exp_days" ]] && exp_days=30

    expired_date=$(date -d "+${exp_days} days" '+%Y-%m-%d %H:%M:%S')
    VPS_IP=$(get_ip)

    sqlite3 "$DB" "INSERT INTO accounts (username, password, max_login, expired_date, server_id, status)
                   VALUES ('$username','$password','$max_login','$expired_date','${VPS_ID:-vps1}','active');"

    # Daftarkan password ke zivpn config
    python3 -c "
import json
try:
    with open('/etc/zivpn/config.json') as f:
        d = json.load(f)
except:
    d = {}
configs = d.get('config', [])
if '$password' not in configs:
    configs.append('$password')
d['config'] = configs
with open('/etc/zivpn/config.json','w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null
    systemctl restart zivpn.service 2>/dev/null

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔${LINE2}╗"
    echo "  ║       ✓  AKUN BERHASIL DIBUAT              ║"
    echo "  ╠${LINE2}╣"
    printf "  ║  %-44s║\n" "USERNAME  : $username"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "PASSWORD  : $password"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "MAX LOGIN : $max_login"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "EXPIRED   : $expired_date"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "SERVER IP : $VPS_IP"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "PORT      : 5667"
    echo "  ╚${LINE2}╝"
    echo -e "${NC}"
    pause
}

# ─── HAPUS AKUN ────────────────────────────────────────
delete_account() {
    header "🗑️  HAPUS AKUN"
    monitor_sessions

    section "Daftar Akun"
    i=1
    sqlite3 "$DB" "SELECT username, password, expired_date, status FROM accounts ORDER BY created_at DESC;" | \
    while IFS='|' read -r u p e s; do
        if [[ "$s" == "active" ]]; then icon="${GREEN}✓${NC}"; else icon="${RED}✗${NC}"; fi
        printf "  ${CYAN}%-4s${NC} %-15s %-12s %-20s %b\n" "$i." "$u" "$p" "$e" "$icon $s"
        echo -e "  ${CYAN}${LINE}${NC}"
        ((i++))
    done

    echo ""
    read -p "  Masukkan username yang akan dihapus: " del_user
    echo -e "  ${CYAN}${LINE}${NC}"

    if [[ -z "$del_user" ]]; then pause; return; fi

    result=$(sqlite3 "$DB" "SELECT username,password,max_login,expired_date,status,created_at FROM accounts WHERE username='$del_user';")
    if [[ -z "$result" ]]; then
        echo -e "  ${RED}Akun '$del_user' tidak ditemukan!${NC}"; pause; return
    fi

    IFS='|' read -r u p m e s c <<< "$result"

    echo ""
    echo -e "${YELLOW}${BOLD}"
    echo "  ╔${LINE2}╗"
    echo "  ║     ⚠  AKUN YANG AKAN DIHAPUS              ║"
    echo "  ╠${LINE2}╣"
    printf "  ║  %-44s║\n" "USERNAME  : $u"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "PASSWORD  : $p"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "MAX LOGIN : $m"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "EXPIRED   : $e"
    echo "  ║$(printf '%.0s─' {1..46})║"
    printf "  ║  %-44s║\n" "STATUS    : $s"
    echo "  ╚${LINE2}╝"
    echo -e "${NC}"

    read -p "  Konfirmasi hapus akun '$del_user'? (y/n): " confirm
    echo -e "  ${CYAN}${LINE}${NC}"

    if [[ "$confirm" != "y" ]]; then
        echo -e "  ${YELLOW}Dibatalkan.${NC}"; pause; return
    fi

    sqlite3 "$DB" "DELETE FROM accounts WHERE username='$del_user';"
    python3 -c "
import json
try:
    with open('/etc/zivpn/config.json') as f:
        d = json.load(f)
    configs = d.get('config', [])
    if '$p' in configs:
        configs.remove('$p')
    d['config'] = configs
    with open('/etc/zivpn/config.json','w') as f:
        json.dump(d, f, indent=2)
except: pass
" 2>/dev/null
    pkill -f "$del_user" 2>/dev/null
    systemctl restart zivpn.service 2>/dev/null

    echo -e "  ${GREEN}${BOLD}✓ Akun '$del_user' berhasil dihapus!${NC}"
    pause
}

# ─── INFO SEMUA AKUN ───────────────────────────────────
list_accounts() {
    header "📋  INFO SEMUA AKUN"
    monitor_sessions

    total=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts;")
    active=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE status='active';")
    expired=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE status='expired';")

    section "Statistik"
    printf "  ${CYAN}Total: ${BOLD}%-5s${NC}${CYAN}  Aktif: ${GREEN}${BOLD}%-5s${NC}${CYAN}  Expired: ${RED}${BOLD}%s${NC}\n" \
           "$total" "$active" "$expired"
    echo -e "  ${CYAN}${LINE}${NC}"
    echo ""

    printf "  ${BOLD}%-4s %-15s %-13s %-5s %-12s %s${NC}\n" "No" "Username" "Password" "MaxL" "Expired" "Status"
    echo -e "  ${CYAN}${LINE}${NC}"

    i=1
    sqlite3 "$DB" "SELECT username, password, max_login, expired_date, status FROM accounts ORDER BY created_at DESC;" | \
    while IFS='|' read -r u p m e s; do
        if [[ "$s" == "active" ]]; then color=$GREEN; icon="✓"; else color=$RED; icon="✗"; fi
        exp_short=$(echo "$e" | cut -c1-10)
        printf "  ${CYAN}%-4s${NC} %-15s %-13s %-5s %-12s ${color}%s %s${NC}\n" \
               "$i." "$u" "$p" "$m" "$exp_short" "$icon" "$s"
        echo -e "  ${CYAN}${LINE}${NC}"
        ((i++))
    done
    echo ""
    pause
}

# ─── INFO VPS & SPEK ───────────────────────────────────
info_vps() {
    header "🖥️  INFO VPS & SPESIFIKASI"
    get_spek
    VPS_IP=$(get_ip)

    # Status ZiVPN
    if systemctl is-active --quiet zivpn.service; then
        SVC="${GREEN}${BOLD}● RUNNING${NC}"
    else
        SVC="${RED}${BOLD}● STOPPED${NC}"
    fi

    # Status Bot
    if systemctl is-active --quiet zivpn-bot.service; then
        BOT="${GREEN}${BOLD}● RUNNING${NC}"
    else
        BOT="${RED}${BOLD}● STOPPED${NC}"
    fi

    section "Informasi VPS"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "VPS ID"    "${VPS_ID:-N/A}"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "IP Publik" "$VPS_IP"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "Hostname"  "${VPS_HOSTNAME:-$(hostname)}"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "OS"        "$OS_NAME"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: " "ZiVPN UDP"
    echo -e "$SVC"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: " "Telegram Bot"
    echo -e "$BOT"
    echo -e "  ${CYAN}${LINE}${NC}"

    echo ""
    section "Spesifikasi Hardware"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "CPU Model" "$CPU_MODEL"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s core(s)${NC}\n" "CPU Core" "$CPU_CORES"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s MB / %s MB${NC}\n" "RAM" "$RAM_USED" "$RAM_TOTAL"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s / %s (%s)${NC}\n" "Disk" "$DISK_USED" "$DISK_TOTAL" "$DISK_PERSEN"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "Uptime" "$UPTIME_STR"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "Load Avg" "$LOAD"
    echo -e "  ${CYAN}${LINE}${NC}"

    echo ""
    section "Statistik Akun"
    total=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts;" 2>/dev/null || echo 0)
    active=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE status='active';" 2>/dev/null || echo 0)
    expired=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE status='expired';" 2>/dev/null || echo 0)
    printf "  ${CYAN}%-15s${NC}: ${BOLD}%s${NC}\n" "Total Akun" "$total"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${GREEN}${BOLD}%s${NC}\n" "Akun Aktif" "$active"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-15s${NC}: ${RED}${BOLD}%s${NC}\n" "Akun Expired" "$expired"
    echo -e "  ${CYAN}${LINE}${NC}"
    pause
}

# ─── BACKUP ────────────────────────────────────────────
backup_data() {
    header "💾  BACKUP DATA"
    section "Membuat Backup"

    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="$BACKUP_DIR/backup_${timestamp}.tar.gz"
    mkdir -p "$BACKUP_DIR"

    echo -e "  ${YELLOW}Memproses backup...${NC}"
    echo -e "  ${CYAN}${LINE}${NC}"
    tar -czf "$backup_file" /etc/zivpn-panel/users.db /etc/zivpn/config.json 2>/dev/null

    size=$(du -sh "$backup_file" | cut -f1)
    echo -e "  ${GREEN}✓ Backup berhasil dibuat!${NC}"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-12s${NC}: ${BOLD}%s${NC}\n" "File" "$backup_file"
    echo -e "  ${CYAN}${LINE}${NC}"
    printf "  ${CYAN}%-12s${NC}: ${BOLD}%s${NC}\n" "Ukuran" "$size"
    echo -e "  ${CYAN}${LINE}${NC}"

    echo ""
    section "Daftar Backup"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{printf "  %-30s %s\n", $9, $5}'
    echo -e "  ${CYAN}${LINE}${NC}"
    pause
}

# ─── RESTORE ───────────────────────────────────────────
restore_data() {
    header "📥  RESTORE DATA"
    section "Daftar Backup Tersedia"

    mapfile -t backups < <(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "  ${RED}Tidak ada file backup!${NC}"
        echo -e "  ${CYAN}${LINE}${NC}"
        pause; return
    fi

    for i in "${!backups[@]}"; do
        size=$(du -sh "${backups[$i]}" | cut -f1)
        printf "  ${CYAN}%-4s${NC} %-40s %s\n" "$((i+1))." "$(basename "${backups[$i]}")" "$size"
        echo -e "  ${CYAN}${LINE}${NC}"
    done

    echo ""
    read -p "  Pilih nomor backup: " pick
    echo -e "  ${CYAN}${LINE}${NC}"
    pick=$((pick - 1))

    if [[ -z "${backups[$pick]}" ]]; then
        echo -e "  ${RED}Pilihan tidak valid!${NC}"; pause; return
    fi

    read -p "  Konfirmasi restore '$(basename "${backups[$pick]}")'? (y/n): " confirm
    echo -e "  ${CYAN}${LINE}${NC}"
    [[ "$confirm" != "y" ]] && { echo -e "  ${YELLOW}Dibatalkan.${NC}"; pause; return; }

    tar -xzf "${backups[$pick]}" -C / 2>/dev/null
    systemctl restart zivpn.service 2>/dev/null
    echo -e "  ${GREEN}${BOLD}✓ Restore berhasil!${NC}"
    echo -e "  ${CYAN}${LINE}${NC}"
    pause
}

# ─── UPGRADE BINARY ────────────────────────────────────
upgrade_binary() {
    header "⬆️  UPGRADE ZIVPN BINARY"
    section "Download Binary Terbaru"
    systemctl stop zivpn.service
    echo -e "  ${YELLOW}Mendownload...${NC}"
    echo -e "  ${CYAN}${LINE}${NC}"
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
        -O /usr/local/bin/zivpn
    chmod +x /usr/local/bin/zivpn
    systemctl start zivpn.service
    echo -e "  ${GREEN}${BOLD}✓ Binary berhasil diupgrade!${NC}"
    echo -e "  ${CYAN}${LINE}${NC}"
    pause
}

# ─── MAIN MENU ─────────────────────────────────────────
main_menu() {
    while true; do
        monitor_sessions
        clear
        VPS_IP=$(get_ip)

        if systemctl is-active --quiet zivpn.service; then
            SVC_STATUS="${GREEN}${BOLD}● AKTIF${NC}"
        else
            SVC_STATUS="${RED}${BOLD}● MATI${NC}"
        fi

        echo -e "${CYAN}${BOLD}"
        echo "  ╔${LINE2}╗"
        printf "  ║  %-44s║\n" "  ZIVPN UDP MANAGER - ${VPS_ID:-VPS}"
        echo "  ╠${LINE2}╣"
        printf "  ║  %-44s║\n" "  IP: $VPS_IP"
        echo "  ╚${LINE2}╝"
        echo -e "${NC}"
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"
        printf "  ZiVPN UDP : %b\n" "$SVC_STATUS"
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"
        echo ""
        echo -e "  ${GREEN}${BOLD}[1]${NC} ➕ Create Akun        ${GREEN}${BOLD}[2]${NC} 🗑️  Hapus Akun"
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"
        echo -e "  ${GREEN}${BOLD}[3]${NC} 📋 Info Semua Akun    ${GREEN}${BOLD}[4]${NC} 🖥️  Info VPS & Spek"
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"
        echo -e "  ${GREEN}${BOLD}[5]${NC} 💾 Backup Data        ${GREEN}${BOLD}[6]${NC} 📥 Restore Data"
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"
        echo -e "  ${GREEN}${BOLD}[7]${NC} ⬆️  Upgrade Binary     ${GREEN}${BOLD}[8]${NC} 🔄 Restart ZiVPN"
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"
        echo -e "  ${RED}${BOLD}[0]${NC} 🚪 Keluar"
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"
        echo ""
        read -p "  Pilih menu: " choice
        echo -e "  ${CYAN}${BOLD}${LINE}${NC}"

        case $choice in
            1) create_account ;;
            2) delete_account ;;
            3) list_accounts ;;
            4) info_vps ;;
            5) backup_data ;;
            6) restore_data ;;
            7) upgrade_binary ;;
            8)
                systemctl restart zivpn.service
                echo -e "  ${GREEN}✓ ZiVPN direstart!${NC}"
                echo -e "  ${CYAN}${LINE}${NC}"
                sleep 1
                ;;
            0)
                echo -e "  ${YELLOW}Sampai jumpa!${NC}"
                echo -e "  ${CYAN}${LINE}${NC}"
                exit 0
                ;;
            *)
                echo -e "  ${RED}Pilihan tidak valid!${NC}"
                echo -e "  ${CYAN}${LINE}${NC}"
                sleep 1
                ;;
        esac
    done
}

main_menu
