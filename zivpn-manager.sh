#!/bin/bash
# zivpn-manager.sh - Panel Manajemen Akun ZiVPN UDP
# Multi-VPS | Debian & Ubuntu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

DB="/etc/zivpn-panel/users.db"
CONF="/etc/zivpn-panel/panel.conf"
BACKUP_DIR="/etc/zivpn-panel/backups"

[[ -f "$CONF" ]] && source "$CONF"

# ─── CEK ROOT ──────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Harus dijalankan sebagai root!${NC}"; exit 1
fi

# ─── FUNGSI UMUM ───────────────────────────────────────
header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════╗"
    printf "║  %-43s║\n" "$1"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

pause() {
    echo -e "\n${YELLOW}Tekan Enter untuk kembali...${NC}"
    read -r
}

get_ip() {
    curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

count_sessions() {
    local user=$1
    ss -u -a 2>/dev/null | grep -c "$user" || echo 0
}

# ─── CEK EXPIRED & KILL SESSION BERLEBIH ──────────────
monitor_sessions() {
    while IFS='|' read -r username max_login; do
        sessions=$(count_sessions "$username")
        if [[ "$sessions" -gt "$max_login" ]]; then
            pkill -f "$username" 2>/dev/null
            sqlite3 "$DB" "UPDATE accounts SET active_sessions=0 WHERE username='$username';"
        fi
    done < <(sqlite3 "$DB" "SELECT username, max_login FROM accounts WHERE status='active';")

    # Cek expired
    sqlite3 "$DB" "UPDATE accounts SET status='expired' 
                   WHERE expired_date < datetime('now') AND expired_date != '' AND status='active';"
}

# ─── CREATE AKUN ───────────────────────────────────────
create_account() {
    header "CREATE AKUN BARU"
    read -p " Username     : " username
    if [[ -z "$username" ]]; then echo -e "${RED}Username kosong!${NC}"; pause; return; fi

    # Cek duplikat
    exist=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE username='$username';")
    if [[ "$exist" -gt 0 ]]; then
        echo -e "${RED}Username sudah ada!${NC}"; pause; return
    fi

    read -p " Password     : " password
    [[ -z "$password" ]] && password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)

    read -p " Max Login    : " max_login
    [[ -z "$max_login" ]] && max_login=2

    read -p " Expired (hari, contoh: 30): " exp_days
    [[ -z "$exp_days" ]] && exp_days=30

    expired_date=$(date -d "+${exp_days} days" '+%Y-%m-%d %H:%M:%S')
    VPS_IP=$(get_ip)

    sqlite3 "$DB" "INSERT INTO accounts (username, password, max_login, expired_date, server_id, status)
                   VALUES ('$username','$password','$max_login','$expired_date','${VPS_ID:-vps1}','active');"

    # Daftarkan ke zivpn config
    current_configs=$(python3 -c "
import json
with open('/etc/zivpn/config.json') as f:
    d = json.load(f)
configs = d.get('config', [])
if '$password' not in configs:
    configs.append('$password')
d['config'] = configs
with open('/etc/zivpn/config.json','w') as f:
    json.dump(d, f, indent=2)
print('OK')
" 2>/dev/null)

    systemctl restart zivpn.service 2>/dev/null

    echo -e "\n${GREEN}${BOLD}═══════ INFO AKUN BERHASIL DIBUAT ═══════${NC}"
    echo -e "${CYAN}"
    echo " ┌─────────────────────────────────────┐"
    printf " │  %-35s│\n" "USERNAME  : $username"
    printf " │  %-35s│\n" "PASSWORD  : $password"
    printf " │  %-35s│\n" "MAX LOGIN : $max_login"
    printf " │  %-35s│\n" "EXPIRED   : $expired_date"
    printf " │  %-35s│\n" "SERVER IP : $VPS_IP"
    printf " │  %-35s│\n" "PORT      : 5667"
    echo " └─────────────────────────────────────┘"
    echo -e "${NC}"
    pause
}

# ─── HAPUS AKUN ────────────────────────────────────────
delete_account() {
    header "HAPUS AKUN"
    echo -e "${YELLOW}Daftar akun aktif:${NC}\n"

    sqlite3 "$DB" "SELECT username, password, max_login, expired_date, status 
                   FROM accounts ORDER BY created_at DESC;" | \
    while IFS='|' read -r u p m e s; do
        printf "  ${CYAN}%-15s${NC} | Pass: %-10s | MaxL: %-2s | Exp: %-20s | ${GREEN}%s${NC}\n" \
               "$u" "$p" "$m" "$e" "$s"
    done

    echo ""
    read -p " Masukkan username yang ingin dihapus: " del_user
    if [[ -z "$del_user" ]]; then pause; return; fi

    # Tampilkan detail sebelum hapus
    result=$(sqlite3 "$DB" "SELECT username, password, max_login, expired_date, status 
                             FROM accounts WHERE username='$del_user';")
    if [[ -z "$result" ]]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"; pause; return
    fi

    IFS='|' read -r u p m e s <<< "$result"
    echo -e "\n${YELLOW}${BOLD}═══ DETAIL AKUN YANG AKAN DIHAPUS ═══${NC}"
    echo -e "${RED}"
    echo " ┌──────────────────────────────────────┐"
    printf " │  %-36s│\n" "USERNAME  : $u"
    printf " │  %-36s│\n" "PASSWORD  : $p"
    printf " │  %-36s│\n" "MAX LOGIN : $m"
    printf " │  %-36s│\n" "EXPIRED   : $e"
    printf " │  %-36s│\n" "STATUS    : $s"
    echo " └──────────────────────────────────────┘"
    echo -e "${NC}"

    read -p " Konfirmasi hapus akun '$del_user'? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${YELLOW}Dibatalkan.${NC}"; pause; return
    fi

    # Hapus dari database
    sqlite3 "$DB" "DELETE FROM accounts WHERE username='$del_user';"

    # Hapus dari zivpn config
    python3 -c "
import json
with open('/etc/zivpn/config.json') as f:
    d = json.load(f)
configs = d.get('config', [])
if '$p' in configs:
    configs.remove('$p')
d['config'] = configs
with open('/etc/zivpn/config.json','w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null

    # Kill session
    pkill -f "$del_user" 2>/dev/null
    systemctl restart zivpn.service 2>/dev/null

    echo -e "\n${GREEN}Akun '$del_user' berhasil dihapus!${NC}"
    pause
}

# ─── INFO SEMUA AKUN ───────────────────────────────────
list_accounts() {
    header "DAFTAR SEMUA AKUN"
    monitor_sessions

    total=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts;")
    active=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE status='active';")
    expired=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE status='expired';")

    echo -e "${CYAN} Total: ${BOLD}$total${NC}${CYAN}  |  Aktif: ${GREEN}${BOLD}$active${NC}${CYAN}  |  Expired: ${RED}${BOLD}$expired${NC}\n"
    echo -e "${BOLD}  No  Username         Password     MaxL  Expired              Status${NC}"
    echo "  ──────────────────────────────────────────────────────────────────────"

    i=1
    sqlite3 "$DB" "SELECT username, password, max_login, expired_date, status 
                   FROM accounts ORDER BY created_at DESC;" | \
    while IFS='|' read -r u p m e s; do
        if [[ "$s" == "active" ]]; then color=$GREEN; else color=$RED; fi
        printf "  ${CYAN}%-4s${NC}%-17s%-13s%-6s%-21s${color}%s${NC}\n" \
               "$i." "$u" "$p" "$m" "$e" "$s"
        ((i++))
    done
    echo ""
    pause
}

# ─── BACKUP ────────────────────────────────────────────
backup_data() {
    header "BACKUP DATA"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="$BACKUP_DIR/backup_${timestamp}.tar.gz"

    echo -e "${YELLOW}Membuat backup...${NC}"
    tar -czf "$backup_file" /etc/zivpn-panel/users.db /etc/zivpn/config.json 2>/dev/null

    size=$(du -sh "$backup_file" | cut -f1)
    echo -e "${GREEN}Backup berhasil: ${BOLD}$backup_file${NC}"
    echo -e "${CYAN}Ukuran: $size${NC}"
    echo -e "\n${YELLOW}Daftar backup tersedia:${NC}"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "Tidak ada backup"
    pause
}

# ─── RESTORE ───────────────────────────────────────────
restore_data() {
    header "RESTORE DATA"
    echo -e "${YELLOW}Daftar backup tersedia:${NC}\n"

    mapfile -t backups < <(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${RED}Tidak ada file backup!${NC}"; pause; return
    fi

    for i in "${!backups[@]}"; do
        size=$(du -sh "${backups[$i]}" | cut -f1)
        echo -e "  ${CYAN}$((i+1)).${NC} $(basename "${backups[$i]}") (${size})"
    done

    echo ""
    read -p " Pilih nomor backup: " pick
    pick=$((pick - 1))

    if [[ -z "${backups[$pick]}" ]]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"; pause; return
    fi

    read -p " Konfirmasi restore dari '$(basename "${backups[$pick]}")'? (y/n): " confirm
    [[ "$confirm" != "y" ]] && { echo -e "${YELLOW}Dibatalkan.${NC}"; pause; return; }

    tar -xzf "${backups[$pick]}" -C / 2>/dev/null
    systemctl restart zivpn.service 2>/dev/null

    echo -e "${GREEN}Restore berhasil!${NC}"
    pause
}

# ─── STATUS SERVICE ────────────────────────────────────
check_status() {
    header "STATUS SISTEM"
    VPS_IP=$(get_ip)

    echo -e "${CYAN} IP VPS     : ${BOLD}$VPS_IP${NC}"
    echo -e "${CYAN} VPS ID    : ${BOLD}${VPS_ID:-N/A}${NC}"
    echo -e "${CYAN} Hostname  : ${BOLD}$(hostname)${NC}"
    echo ""

    # Status ZiVPN
    if systemctl is-active --quiet zivpn.service; then
        echo -e " ZiVPN UDP  : ${GREEN}${BOLD}● RUNNING${NC}"
    else
        echo -e " ZiVPN UDP  : ${RED}${BOLD}● STOPPED${NC}"
    fi

    # Uptime
    echo -e " Uptime     : ${CYAN}$(uptime -p)${NC}"
    echo -e " RAM Used   : ${CYAN}$(free -m | awk 'NR==2{printf "%s/%s MB (%.1f%%)", $3,$2,$3*100/$2}')${NC}"
    echo -e " CPU        : ${CYAN}$(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')%${NC}"
    echo ""

    total=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts;")
    active=$(sqlite3 "$DB" "SELECT COUNT(*) FROM accounts WHERE status='active';")
    echo -e " Total Akun : ${CYAN}${BOLD}$total${NC}"
    echo -e " Akun Aktif : ${GREEN}${BOLD}$active${NC}"
    pause
}

# ─── UPGRADE BINARY ────────────────────────────────────
upgrade_binary() {
    header "UPGRADE ZIVPN BINARY"
    echo -e "${YELLOW}Mendownload versi terbaru...${NC}"
    systemctl stop zivpn.service
    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
        -O /usr/local/bin/zivpn
    chmod +x /usr/local/bin/zivpn
    systemctl start zivpn.service
    echo -e "${GREEN}Binary berhasil diupgrade!${NC}"
    pause
}

# ─── MAIN MENU ─────────────────────────────────────────
main_menu() {
    while true; do
        monitor_sessions
        header "ZIVPN UDP MANAGER - ${VPS_ID:-VPS}"
        VPS_IP=$(get_ip)

        echo -e "  ${CYAN}IP: ${BOLD}$VPS_IP${NC}${CYAN}  |  ${NC}$(systemctl is-active zivpn.service | \
            sed 's/active/\x1b[32m● AKTIF\x1b[0m/;s/inactive/\x1b[31m● MATI\x1b[0m/')\n"

        echo -e "  ${GREEN}[1]${NC} Create Akun          ${GREEN}[2]${NC} Hapus Akun"
        echo -e "  ${GREEN}[3]${NC} Info Semua Akun      ${GREEN}[4]${NC} Status Sistem"
        echo -e "  ${GREEN}[5]${NC} Backup Data          ${GREEN}[6]${NC} Restore Data"
        echo -e "  ${GREEN}[7]${NC} Upgrade Binary       ${GREEN}[8]${NC} Restart ZiVPN"
        echo -e "  ${RED}[0]${NC} Keluar"
        echo ""
        read -p "  Pilih menu: " choice

        case $choice in
            1) create_account ;;
            2) delete_account ;;
            3) list_accounts ;;
            4) check_status ;;
            5) backup_data ;;
            6) restore_data ;;
            7) upgrade_binary ;;
            8)
                systemctl restart zivpn.service
                echo -e "${GREEN}ZiVPN direstart!${NC}"
                sleep 1
                ;;
            0) echo -e "${YELLOW}Sampai jumpa!${NC}"; exit 0 ;;
            *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
