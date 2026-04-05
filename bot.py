#!/usr/bin/env python3
# bot.py - Telegram Bot ZiVPN UDP
# Full fitur: Toko, Reseller, Multi-VPS, Admin Panel
# Requires: python-telegram-bot==20.7

import logging
import sqlite3
import json
import os
import asyncio
import subprocess
import tarfile
import datetime
import random
import string
from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup
)
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes
)

DB_PATH    = "/etc/zivpn-panel/users.db"
CONF_PATH  = "/etc/zivpn-panel/panel.conf"
BACKUP_DIR = "/etc/zivpn-panel/backups"
ZIVPN_CONF = "/etc/zivpn/config.json"

logging.basicConfig(format='%(asctime)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# ─── HELPERS ───────────────────────────────────────────
def load_conf():
    conf = {}
    if os.path.exists(CONF_PATH):
        with open(CONF_PATH) as f:
            for line in f:
                line = line.strip()
                if '=' in line:
                    k, v = line.split('=', 1)
                    conf[k.strip()] = v.strip()
    return conf

def db():
    return sqlite3.connect(DB_PATH)

def get_setting(key, default=""):
    try:
        with db() as con:
            row = con.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
            return row[0] if row else default
    except:
        return default

def set_setting(key, value):
    with db() as con:
        con.execute("INSERT OR REPLACE INTO settings VALUES (?,?)", (key, value))

def get_admin_ids():
    val = get_setting("admin_id")
    return [x.strip() for x in val.split(",") if x.strip()]

def is_admin(uid):
    return str(uid) in get_admin_ids()

def is_reseller(uid):
    try:
        with db() as con:
            row = con.execute(
                "SELECT id FROM resellers WHERE telegram_id=? AND active=1", (str(uid),)
            ).fetchone()
            return row is not None
    except:
        return False

def gen_password(length=8):
    return ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(length))

def get_vps_ip():
    conf = load_conf()
    return conf.get("VPS_IP", "N/A")

def get_vps_spek():
    try:
        cpu_model = subprocess.getoutput("grep -m1 'model name' /proc/cpuinfo | cut -d: -f2").strip()
        cpu_core  = subprocess.getoutput("nproc").strip()
        ram_info  = subprocess.getoutput("free -m | awk 'NR==2{print $3\"/\"$2\" MB\"}'").strip()
        disk_info = subprocess.getoutput("df -h / | awk 'NR==2{print $3\"/\"$2\" (\"$5\")'").strip()
        os_name   = subprocess.getoutput("grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2").strip()
        uptime_s  = subprocess.getoutput("uptime -p").strip()
        load_s    = subprocess.getoutput("uptime | awk -F'load average:' '{print $2}'").strip()
        return {
            "cpu_model": cpu_model or "N/A",
            "cpu_core": cpu_core or "N/A",
            "ram": ram_info or "N/A",
            "disk": disk_info or "N/A",
            "os": os_name or "N/A",
            "uptime": uptime_s or "N/A",
            "load": load_s or "N/A"
        }
    except:
        return {}

def register_zivpn(password):
    try:
        with open(ZIVPN_CONF) as f:
            data = json.load(f)
        configs = data.get("config", [])
        if password not in configs:
            configs.append(password)
        data["config"] = configs
        with open(ZIVPN_CONF, "w") as f:
            json.dump(data, f, indent=2)
        os.system("systemctl restart zivpn.service")
        return True
    except Exception as e:
        logger.error(f"register_zivpn: {e}")
        return False

def unregister_zivpn(password):
    try:
        with open(ZIVPN_CONF) as f:
            data = json.load(f)
        configs = data.get("config", [])
        if password in configs:
            configs.remove(password)
        data["config"] = configs
        with open(ZIVPN_CONF, "w") as f:
            json.dump(data, f, indent=2)
        os.system("systemctl restart zivpn.service")
        return True
    except Exception as e:
        logger.error(f"unregister_zivpn: {e}")
        return False

# ─── KEYBOARDS ─────────────────────────────────────────
def main_kb(uid):
    if is_admin(uid):
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Buat Akun",     callback_data="menu_create"),
             InlineKeyboardButton("🗑️ Hapus Akun",   callback_data="menu_delete")],
            [InlineKeyboardButton("📋 Info Akun",     callback_data="menu_list"),
             InlineKeyboardButton("🛒 Toko UDP",      callback_data="menu_shop")],
            [InlineKeyboardButton("💾 Backup",        callback_data="menu_backup"),
             InlineKeyboardButton("📥 Restore",       callback_data="menu_restore")],
            [InlineKeyboardButton("🖥️ Info VPS",     callback_data="menu_vps"),
             InlineKeyboardButton("⚙️ Pengaturan",   callback_data="menu_settings")],
            [InlineKeyboardButton("👥 Reseller",      callback_data="menu_reseller"),
             InlineKeyboardButton("🌐 Multi-VPS",    callback_data="menu_multivps")],
        ])
    elif is_reseller(uid):
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Buat Akun",     callback_data="menu_create"),
             InlineKeyboardButton("🗑️ Hapus Akun",   callback_data="menu_delete")],
            [InlineKeyboardButton("📋 Info Akun",     callback_data="menu_list"),
             InlineKeyboardButton("🛒 Toko UDP",      callback_data="menu_shop")],
            [InlineKeyboardButton("🖥️ Info VPS",     callback_data="menu_vps"),
             InlineKeyboardButton("💰 Saldo Saya",   callback_data="menu_balance")],
        ])
    else:
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("🛒 Beli Akun UDP", callback_data="menu_shop"),
             InlineKeyboardButton("📞 Hubungi Admin", callback_data="menu_contact")],
            [InlineKeyboardButton("ℹ️ Cara Pakai",   callback_data="menu_howto"),
             InlineKeyboardButton("🖥️ Status VPS",  callback_data="menu_vps")],
        ])

def back_kb(target="menu_main"):
    return InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Kembali", callback_data=target)]])

# ─── START ─────────────────────────────────────────────
async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid  = update.effective_user.id
    name = update.effective_user.first_name
    role = "👑 Admin" if is_admin(uid) else ("🏪 Reseller" if is_reseller(uid) else "👤 User")

    text = (
        f"✨ *Selamat datang, {name}!*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"🆔 ID      : `{uid}`\n"
        f"🎭 Role    : {role}\n"
        f"━━━━━━━━━━━━━━━━━━━━\n\n"
        f"*ZiVPN UDP Panel*\n"
        f"Pilih menu di bawah ini:"
    )
    await update.message.reply_text(text, parse_mode="Markdown", reply_markup=main_kb(uid))

# ─── CALLBACK HANDLER ──────────────────────────────────
async def callback_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q    = update.callback_query
    uid  = q.from_user.id
    data = q.data
    await q.answer()

    # ── MAIN MENU ──
    if data == "menu_main":
        name = q.from_user.first_name
        role = "👑 Admin" if is_admin(uid) else ("🏪 Reseller" if is_reseller(uid) else "👤 User")
        text = (
            f"✨ *Halo, {name}!*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"🎭 Role : {role}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n\n"
            f"Pilih menu:"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=main_kb(uid))

    # ── BUAT AKUN ──
    elif data == "menu_create":
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak.", reply_markup=back_kb()); return
        ctx.user_data['state'] = 'create_username'
        await q.edit_message_text(
            "➕ *BUAT AKUN BARU*\n\n"
            "━━━━━━━━━━━━━━━━━━━━\n"
            "Kirim *username* akun:\n"
            "_(ketik /batal untuk membatalkan)_",
            parse_mode="Markdown", reply_markup=back_kb()
        )

    # ── HAPUS AKUN ──
    elif data == "menu_delete":
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak.", reply_markup=back_kb()); return

        with db() as con:
            rows = con.execute(
                "SELECT username, expired_date, status FROM accounts ORDER BY created_at DESC LIMIT 20"
            ).fetchall()

        if not rows:
            await q.edit_message_text("📭 Belum ada akun.", reply_markup=back_kb()); return

        buttons = []
        for i in range(0, len(rows), 2):
            row_btns = []
            for r in rows[i:i+2]:
                icon = "✅" if r[2] == "active" else "❌"
                row_btns.append(InlineKeyboardButton(
                    f"{icon} {r[0]}", callback_data=f"del_confirm_{r[0]}"
                ))
            buttons.append(row_btns)
        buttons.append([InlineKeyboardButton("⬅️ Kembali", callback_data="menu_main")])

        await q.edit_message_text(
            "🗑️ *HAPUS AKUN*\n\n━━━━━━━━━━━━━━━━━━━━\nPilih akun yang ingin dihapus:",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup(buttons)
        )

    # ── KONFIRMASI DELETE ──
    elif data.startswith("del_confirm_"):
        username = data.replace("del_confirm_", "")
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak."); return

        with db() as con:
            row = con.execute(
                "SELECT username, password, max_login, expired_date, status, created_at FROM accounts WHERE username=?",
                (username,)
            ).fetchone()

        if not row:
            await q.edit_message_text("❌ Akun tidak ditemukan.", reply_markup=back_kb("menu_delete")); return

        u, p, m, e, s, c = row
        icon = "✅" if s == "active" else "❌"
        text = (
            f"⚠️ *KONFIRMASI HAPUS AKUN*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username   : `{u}`\n"
            f"🔑 Password   : `{p}`\n"
            f"🔢 Max Login  : `{m}`\n"
            f"📅 Expired    : `{e}`\n"
            f"📌 Status     : {icon} `{s}`\n"
            f"📆 Dibuat     : `{c}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"❓ Yakin hapus akun ini?"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("✅ Ya, Hapus",  callback_data=f"del_exec_{username}"),
             InlineKeyboardButton("❌ Batal",      callback_data="menu_delete")]
        ]))

    # ── EKSEKUSI DELETE ──
    elif data.startswith("del_exec_"):
        username = data.replace("del_exec_", "")
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak."); return

        with db() as con:
            row = con.execute("SELECT password FROM accounts WHERE username=?", (username,)).fetchone()
            if row:
                con.execute("DELETE FROM accounts WHERE username=?", (username,))

        if row:
            unregister_zivpn(row[0])
            await q.edit_message_text(
                f"✅ *Akun `{username}` berhasil dihapus!*",
                parse_mode="Markdown", reply_markup=back_kb()
            )
        else:
            await q.edit_message_text("❌ Akun tidak ditemukan.", reply_markup=back_kb("menu_delete"))

    # ── LIST AKUN ──
    elif data == "menu_list":
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak.", reply_markup=back_kb()); return

        with db() as con:
            rows   = con.execute("SELECT username, password, max_login, expired_date, status FROM accounts ORDER BY created_at DESC").fetchall()
            total  = con.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            active = con.execute("SELECT COUNT(*) FROM accounts WHERE status='active'").fetchone()[0]

        if not rows:
            await q.edit_message_text("📭 Belum ada akun.", reply_markup=back_kb()); return

        text = (
            f"📋 *DAFTAR AKUN*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"📊 Total: `{total}` | Aktif: `{active}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
        )
        for r in rows[:20]:
            icon = "✅" if r[4] == "active" else "❌"
            exp_short = r[3][:10] if r[3] else "-"
            text += f"{icon} `{r[0]}` | `{r[1]}` | MaxL:{r[2]} | {exp_short}\n"
            text += "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
        if len(rows) > 20:
            text += f"\n_... dan {len(rows)-20} akun lainnya_"

        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

    # ── TOKO UDP ──
    elif data == "menu_shop":
        p15 = get_setting("price_15day", "5000")
        p30 = get_setting("price_30day", "10000")
        text = (
            f"🛒 *TOKO UDP ZIVPN*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"📦 *Paket Tersedia:*\n\n"
            f"📅 *15 Hari*  →  Rp {int(p15):,}\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"📆 *30 Hari*  →  Rp {int(p30):,}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"💡 Transfer → kirim bukti ke admin"
        )
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("📅 Beli 15 Hari",  callback_data="buy_15day"),
             InlineKeyboardButton("📆 Beli 30 Hari",  callback_data="buy_30day")],
            [InlineKeyboardButton("💳 Lihat QRIS",    callback_data="show_qris")],
            [InlineKeyboardButton("⬅️ Kembali",       callback_data="menu_main")],
        ])
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

    # ── SHOW QRIS ──
    elif data == "show_qris":
        qris = get_setting("qris_image")
        if qris:
            try:
                await q.message.reply_photo(
                    photo=qris,
                    caption="💳 *Scan QRIS untuk pembayaran*\n\nSetelah transfer, kirim bukti ke admin.",
                    parse_mode="Markdown"
                )
                await q.answer("QRIS dikirim!")
            except:
                await q.edit_message_text("❌ Gagal menampilkan QRIS.", reply_markup=back_kb("menu_shop"))
        else:
            await q.edit_message_text("⚠️ QRIS belum diatur admin.", reply_markup=back_kb("menu_shop"))

    # ── BUY ──
    elif data.startswith("buy_"):
        plan   = data.replace("buy_", "")
        prices = {"15day": get_setting("price_15day","5000"), "30day": get_setting("price_30day","10000")}
        labels = {"15day": "15 Hari", "30day": "30 Hari"}
        text = (
            f"🛒 *ORDER PAKET {labels.get(plan,'?')}*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"💰 Harga : Rp {int(prices.get(plan,0)):,}\n"
            f"⏳ Masa  : {labels.get(plan,'?')}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"📌 *Langkah Order:*\n"
            f"1️⃣ Transfer sesuai nominal\n"
            f"2️⃣ Kirim bukti ke admin\n"
            f"3️⃣ Admin aktifkan akun Anda\n"
            f"━━━━━━━━━━━━━━━━━━━━"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb("menu_shop"))

    # ── INFO VPS & SPEK ──
    elif data == "menu_vps":
        conf      = load_conf()
        vps_ip    = conf.get("VPS_IP", "N/A")
        vps_id    = conf.get("VPS_ID", "N/A")
        hostname  = conf.get("VPS_HOSTNAME", "N/A")
        spek      = get_vps_spek()

        svc  = subprocess.getoutput("systemctl is-active zivpn.service")
        svc_icon = "🟢" if svc == "active" else "🔴"
        bot_svc  = subprocess.getoutput("systemctl is-active zivpn-bot.service")
        bot_icon = "🟢" if bot_svc == "active" else "🔴"

        with db() as con:
            servers = con.execute("SELECT id, name, ip, port, status FROM servers").fetchall()
            total   = con.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            active  = con.execute("SELECT COUNT(*) FROM accounts WHERE status='active'").fetchone()[0]

        text = (
            f"🖥️ *INFO VPS & SPESIFIKASI*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 VPS ID    : `{vps_id}`\n"
            f"🌐 IP Publik : `{vps_ip}`\n"
            f"🖥️ Hostname  : `{hostname}`\n"
            f"💿 OS        : `{spek.get('os','N/A')}`\n"
            f"{svc_icon} ZiVPN UDP  : `{svc}`\n"
            f"{bot_icon} Bot TG     : `{bot_svc}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"⚙️ *Spesifikasi Hardware:*\n\n"
            f"🔲 CPU  : `{spek.get('cpu_model','N/A')}`\n"
            f"🔢 Core : `{spek.get('cpu_core','N/A')} core`\n"
            f"💾 RAM  : `{spek.get('ram','N/A')}`\n"
            f"💿 Disk : `{spek.get('disk','N/A')}`\n"
            f"⏱️ Uptime: `{spek.get('uptime','N/A')}`\n"
            f"📊 Load : `{spek.get('load','N/A')}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"👥 *Statistik Akun:*\n\n"
            f"📦 Total   : `{total}`\n"
            f"✅ Aktif   : `{active}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"🌐 *Server Terdaftar:*\n\n"
        )
        for s in servers:
            si = "🟢" if s[4] == "active" else "🔴"
            text += f"{si} `{s[1]}` | `{s[2]}:{s[3]}`\n"

        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

    # ── BACKUP ──
    elif data == "menu_backup":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        await q.edit_message_text("⏳ *Membuat backup...*", parse_mode="Markdown")
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_file = f"{BACKUP_DIR}/backup_{ts}.tar.gz"
        os.makedirs(BACKUP_DIR, exist_ok=True)
        with tarfile.open(backup_file, "w:gz") as tar:
            if os.path.exists(DB_PATH): tar.add(DB_PATH)
            if os.path.exists(ZIVPN_CONF): tar.add(ZIVPN_CONF)
        size = os.path.getsize(backup_file) // 1024
        await q.message.reply_document(
            document=open(backup_file, 'rb'),
            filename=f"zivpn_backup_{ts}.tar.gz",
            caption=(
                f"✅ *Backup Berhasil!*\n\n"
                f"━━━━━━━━━━━━━━━━━━━━\n"
                f"📦 File  : `zivpn_backup_{ts}.tar.gz`\n"
                f"📐 Size  : `{size} KB`\n"
                f"📅 Waktu : `{ts}`\n"
                f"━━━━━━━━━━━━━━━━━━━━"
            ),
            parse_mode="Markdown"
        )
        await q.edit_message_text("✅ Backup dikirim ke chat.", reply_markup=back_kb())

    # ── RESTORE ──
    elif data == "menu_restore":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        ctx.user_data['state'] = 'restore_file'
        await q.edit_message_text(
            "📥 *RESTORE DATA*\n\n"
            "━━━━━━━━━━━━━━━━━━━━\n"
            "Kirim file backup (`.tar.gz`) ke sini:",
            parse_mode="Markdown", reply_markup=back_kb()
        )

    # ── PENGATURAN ──
    elif data == "menu_settings":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        await show_settings_menu(q)

    elif data == "set_price":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'set_price'
        p15 = get_setting("price_15day","5000")
        p30 = get_setting("price_30day","10000")
        await q.edit_message_text(
            f"💰 *SET HARGA PAKET*\n\n"
            f"Harga saat ini:\n"
            f"• 15 Hari: Rp {int(p15):,}\n"
            f"• 30 Hari: Rp {int(p30):,}\n\n"
            f"Format baru: `15day,30day`\n"
            f"Contoh: `5000,10000`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_qris":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'set_qris'
        await q.edit_message_text(
            "💳 *UPLOAD FOTO QRIS*\n\n"
            "━━━━━━━━━━━━━━━━━━━━\n"
            "Kirim foto QRIS sekarang:",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_admin":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'set_admin'
        current = get_setting("admin_id")
        await q.edit_message_text(
            f"👑 *SET ADMIN*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"Admin saat ini: `{current}`\n\n"
            f"Kirim Telegram ID admin baru:\n"
            f"_(pisah koma jika lebih dari 1)_\n"
            f"Contoh: `123456789,987654321`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_vps_info":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'set_vps_info'
        await q.edit_message_text(
            "🖥️ *TAMBAH SERVER VPS*\n\n"
            "━━━━━━━━━━━━━━━━━━━━\n"
            "Format: `id,nama,ip,port`\n"
            "Contoh: `vps2,Server SG,1.2.3.4,5667`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    # ── RESELLER ──
    elif data == "menu_reseller":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return

        with db() as con:
            rows = con.execute("SELECT telegram_id, username, balance, active FROM resellers").fetchall()

        text = f"👥 *MANAJEMEN RESELLER*\n\n━━━━━━━━━━━━━━━━━━━━\nTotal: {len(rows)} reseller\n━━━━━━━━━━━━━━━━━━━━\n"
        for r in rows:
            icon = "✅" if r[3] else "❌"
            text += f"{icon} ID: `{r[0]}` | Saldo: Rp {r[2]:,.0f}\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"

        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Tambah",       callback_data="add_reseller"),
             InlineKeyboardButton("🗑️ Hapus",       callback_data="del_reseller")],
            [InlineKeyboardButton("💰 Topup Saldo",  callback_data="topup_reseller"),
             InlineKeyboardButton("📋 Detail",       callback_data="detail_reseller")],
            [InlineKeyboardButton("⬅️ Kembali",      callback_data="menu_main")],
        ])
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

    elif data == "add_reseller":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'add_reseller'
        await q.edit_message_text(
            "➕ *TAMBAH RESELLER*\n\n━━━━━━━━━━━━━━━━━━━━\nKirim Telegram ID reseller:",
            parse_mode="Markdown", reply_markup=back_kb("menu_reseller")
        )

    elif data == "del_reseller":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'del_reseller'
        await q.edit_message_text(
            "🗑️ *HAPUS RESELLER*\n\n━━━━━━━━━━━━━━━━━━━━\nKirim Telegram ID reseller:",
            parse_mode="Markdown", reply_markup=back_kb("menu_reseller")
        )

    elif data == "topup_reseller":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'topup_reseller'
        await q.edit_message_text(
            "💰 *TOPUP SALDO RESELLER*\n\n━━━━━━━━━━━━━━━━━━━━\nFormat: `telegram_id,jumlah`\nContoh: `123456789,50000`",
            parse_mode="Markdown", reply_markup=back_kb("menu_reseller")
        )

    # ── MULTI VPS ──
    elif data == "menu_multivps":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return

        with db() as con:
            servers = con.execute("SELECT id, name, ip, port, location, status FROM servers").fetchall()

        text = "🌐 *MULTI VPS MANAGER*\n\n━━━━━━━━━━━━━━━━━━━━\n"
        for s in servers:
            icon = "🟢" if s[5] == "active" else "🔴"
            text += f"{icon} *{s[1]}*\n📍 `{s[2]}:{s[3]}` | {s[4]}\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"

        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Tambah VPS",   callback_data="set_vps_info"),
             InlineKeyboardButton("🗑️ Hapus VPS",   callback_data="del_vps")],
            [InlineKeyboardButton("⬅️ Kembali",      callback_data="menu_main")],
        ])
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

    elif data == "del_vps":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'del_vps'
        await q.edit_message_text(
            "🗑️ *HAPUS VPS*\n\n━━━━━━━━━━━━━━━━━━━━\nKirim VPS ID:",
            parse_mode="Markdown", reply_markup=back_kb("menu_multivps")
        )

    # ── SALDO RESELLER ──
    elif data == "menu_balance":
        with db() as con:
            row = con.execute("SELECT balance FROM resellers WHERE telegram_id=?", (str(uid),)).fetchone()
        bal = row[0] if row else 0
        await q.edit_message_text(
            f"💰 *SALDO SAYA*\n\n━━━━━━━━━━━━━━━━━━━━\nSaldo: `Rp {bal:,.0f}`\n━━━━━━━━━━━━━━━━━━━━\nHubungi admin untuk topup.",
            parse_mode="Markdown", reply_markup=back_kb()
        )

    elif data == "menu_contact":
        admins = get_admin_ids()
        text = "📞 *HUBUNGI ADMIN*\n\n━━━━━━━━━━━━━━━━━━━━\n"
        for a in admins:
            text += f"• Admin ID: `{a}`\n"
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

    elif data == "menu_howto":
        vps_ip = get_vps_ip()
        text = (
            f"ℹ️ *CARA MENGGUNAKAN*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"1️⃣ Beli paket di menu *Toko UDP*\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"2️⃣ Transfer & konfirmasi ke admin\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"3️⃣ Dapat username & password\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"4️⃣ Buka app *ZiVPN* di HP\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"5️⃣ Masukkan:\n"
            f"   🌐 Server : `{vps_ip}`\n"
            f"   📡 Port   : `5667`\n"
            f"   👤 User   : dari admin\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"✅ Selesai! Enjoy! 🚀"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

# ─── SHOW SETTINGS MENU ────────────────────────────────
async def show_settings_menu(q):
    p15 = get_setting("price_15day", "5000")
    p30 = get_setting("price_30day", "10000")
    text = (
        f"⚙️ *PENGATURAN BOT*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"💰 Harga 15 Hari : Rp {int(p15):,}\n"
        f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
        f"💰 Harga 30 Hari : Rp {int(p30):,}\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"Pilih yang ingin diubah:"
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("💰 Set Harga",     callback_data="set_price"),
         InlineKeyboardButton("💳 Upload QRIS",   callback_data="set_qris")],
        [InlineKeyboardButton("👑 Set Admin",     callback_data="set_admin"),
         InlineKeyboardButton("🖥️ Tambah VPS",  callback_data="set_vps_info")],
        [InlineKeyboardButton("⬅️ Kembali",      callback_data="menu_main")],
    ])
    await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

# ─── MESSAGE HANDLER ───────────────────────────────────
async def message_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid   = update.effective_user.id
    text  = update.message.text or ""
    state = ctx.user_data.get('state', '')

    if text.strip() == "/batal":
        ctx.user_data.clear()
        await update.message.reply_text("❌ Dibatalkan.", reply_markup=back_kb())
        return

    if state == 'create_username':
        if not (is_admin(uid) or is_reseller(uid)): return
        ctx.user_data['new_username'] = text.strip()
        ctx.user_data['state'] = 'create_password'
        await update.message.reply_text(
            f"✅ Username: `{text.strip()}`\n\n━━━━━━━━━━━━━━━━━━━━\nKirim *password* (atau `auto`):",
            parse_mode="Markdown"
        )

    elif state == 'create_password':
        if not (is_admin(uid) or is_reseller(uid)): return
        password = gen_password() if text.strip().lower() == "auto" else text.strip()
        ctx.user_data['new_password'] = password
        ctx.user_data['state'] = 'create_maxlogin'
        await update.message.reply_text(
            f"✅ Password: `{password}`\n\n━━━━━━━━━━━━━━━━━━━━\nKirim *max login* (default: 2):",
            parse_mode="Markdown"
        )

    elif state == 'create_maxlogin':
        if not (is_admin(uid) or is_reseller(uid)): return
        try:
            ml = int(text.strip())
        except:
            ml = 2
        ctx.user_data['new_maxlogin'] = ml
        ctx.user_data['state'] = 'create_expdays'
        await update.message.reply_text(
            f"✅ Max Login: `{ml}`\n\n━━━━━━━━━━━━━━━━━━━━\nKirim lama aktif:\n`15` = 15 hari (Rp 5.000)\n`30` = 30 hari (Rp 10.000)",
            parse_mode="Markdown"
        )

    elif state == 'create_expdays':
        if not (is_admin(uid) or is_reseller(uid)): return
        try:
            days = int(text.strip())
        except:
            days = 30

        username  = ctx.user_data.get('new_username', '')
        password  = ctx.user_data.get('new_password', '')
        max_login = ctx.user_data.get('new_maxlogin', 2)
        exp_date  = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime('%Y-%m-%d %H:%M:%S')
        conf      = load_conf()
        server_id = conf.get("VPS_ID", "vps1")
        vps_ip    = conf.get("VPS_IP", "N/A")

        with db() as con:
            exist = con.execute("SELECT COUNT(*) FROM accounts WHERE username=?", (username,)).fetchone()[0]
        if exist:
            await update.message.reply_text(f"❌ Username `{username}` sudah ada!", parse_mode="Markdown")
            ctx.user_data.clear(); return

        with db() as con:
            con.execute(
                "INSERT INTO accounts (username, password, max_login, expired_date, server_id, created_by, status) VALUES (?,?,?,?,?,?,?)",
                (username, password, max_login, exp_date, server_id, str(uid), 'active')
            )

        register_zivpn(password)
        ctx.user_data.clear()

        # Harga otomatis
        harga = "Rp 5.000" if days <= 15 else "Rp 10.000"

        await update.message.reply_text(
            f"✅ *AKUN BERHASIL DIBUAT!*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username  : `{username}`\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"🔑 Password  : `{password}`\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"🔢 Max Login : `{max_login}`\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"⏳ Expired   : `{exp_date}`\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"🌐 Server    : `{vps_ip}`\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"📡 Port      : `5667`\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"💰 Harga     : `{harga}`\n"
            f"━━━━━━━━━━━━━━━━━━━━",
            parse_mode="Markdown", reply_markup=back_kb()
        )

    elif state == 'set_price':
        if not is_admin(uid): return
        parts = text.strip().split(',')
        if len(parts) == 2:
            set_setting("price_15day", parts[0].strip())
            set_setting("price_30day", parts[1].strip())
            await update.message.reply_text(
                f"✅ *Harga diperbarui!*\n\n15 Hari: Rp {int(parts[0]):,}\n30 Hari: Rp {int(parts[1]):,}",
                parse_mode="Markdown", reply_markup=back_kb("menu_settings")
            )
        else:
            await update.message.reply_text("❌ Format salah! Gunakan: `15day,30day`", parse_mode="Markdown")
        ctx.user_data.clear()

    elif state == 'set_admin':
        if not is_admin(uid): return
        set_setting("admin_id", text.strip())
        await update.message.reply_text(f"✅ Admin ID: `{text.strip()}`", parse_mode="Markdown")
        ctx.user_data.clear()

    elif state == 'set_vps_info':
        if not is_admin(uid): return
        parts = text.strip().split(',')
        if len(parts) >= 4:
            with db() as con:
                con.execute("INSERT OR REPLACE INTO servers (id,name,ip,port,status) VALUES (?,?,?,?,?)",
                            (parts[0].strip(), parts[1].strip(), parts[2].strip(), int(parts[3].strip()), 'active'))
            await update.message.reply_text(f"✅ VPS `{parts[0].strip()}` ditambahkan!", parse_mode="Markdown")
        else:
            await update.message.reply_text("❌ Format salah!", parse_mode="Markdown")
        ctx.user_data.clear()

    elif state == 'del_vps':
        if not is_admin(uid): return
        with db() as con:
            con.execute("DELETE FROM servers WHERE id=?", (text.strip(),))
        await update.message.reply_text(f"✅ VPS `{text.strip()}` dihapus.", parse_mode="Markdown")
        ctx.user_data.clear()

    elif state == 'add_reseller':
        if not is_admin(uid): return
        with db() as con:
            con.execute("INSERT OR IGNORE INTO resellers (telegram_id, username) VALUES (?,?)",
                        (text.strip(), f"user_{text.strip()}"))
        await update.message.reply_text(f"✅ Reseller `{text.strip()}` ditambahkan!", parse_mode="Markdown")
        ctx.user_data.clear()

    elif state == 'del_reseller':
        if not is_admin(uid): return
        with db() as con:
            con.execute("DELETE FROM resellers WHERE telegram_id=?", (text.strip(),))
        await update.message.reply_text(f"✅ Reseller `{text.strip()}` dihapus.", parse_mode="Markdown")
        ctx.user_data.clear()

    elif state == 'topup_reseller':
        if not is_admin(uid): return
        parts = text.strip().split(',')
        if len(parts) == 2:
            with db() as con:
                con.execute("UPDATE resellers SET balance = balance + ? WHERE telegram_id=?",
                            (int(parts[1].strip()), parts[0].strip()))
            await update.message.reply_text(
                f"✅ Saldo `{parts[0].strip()}` + Rp {int(parts[1]):,}", parse_mode="Markdown"
            )
        ctx.user_data.clear()

# ─── PHOTO/DOC HANDLER ─────────────────────────────────
async def photo_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid   = update.effective_user.id
    state = ctx.user_data.get('state', '')

    if state == 'set_qris' and is_admin(uid):
        photo   = update.message.photo[-1]
        file_id = photo.file_id
        set_setting("qris_image", file_id)
        await update.message.reply_text("✅ Foto QRIS disimpan!", reply_markup=back_kb("menu_settings"))
        ctx.user_data.clear()

    elif state == 'restore_file' and is_admin(uid):
        doc = update.message.document
        if doc and doc.file_name.endswith('.tar.gz'):
            file = await ctx.bot.get_file(doc.file_id)
            restore_path = f"{BACKUP_DIR}/restore_tmp.tar.gz"
            await file.download_to_drive(restore_path)
            with tarfile.open(restore_path, "r:gz") as tar:
                tar.extractall("/")
            os.system("systemctl restart zivpn.service")
            await update.message.reply_text("✅ *Restore berhasil!*", parse_mode="Markdown")
        else:
            await update.message.reply_text("❌ Kirim file .tar.gz!")
        ctx.user_data.clear()

# ─── SESSION MONITOR ───────────────────────────────────
async def session_monitor(app):
    while True:
        try:
            with db() as con:
                rows = con.execute("SELECT username, max_login FROM accounts WHERE status='active'").fetchall()
                con.execute(
                    "UPDATE accounts SET status='expired' "
                    "WHERE expired_date < datetime('now') AND expired_date != '' AND status='active'"
                )
            for username, max_login in rows:
                sessions = int(subprocess.getoutput(
                    f"ss -u -a 2>/dev/null | grep -c '{username}' || echo 0"
                ).strip() or 0)
                if sessions > max_login:
                    subprocess.run(["pkill", "-f", username], capture_output=True)
        except Exception as e:
            logger.error(f"monitor: {e}")
        await asyncio.sleep(60)

# ─── MAIN ──────────────────────────────────────────────
def main():
    token = get_setting("bot_token")
    if not token:
        print("ERROR: Bot token belum diset!")
        print("Jalankan setup-bot.sh terlebih dahulu.")
        return

    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CallbackQueryHandler(callback_handler))
    app.add_handler(MessageHandler(filters.PHOTO | filters.Document.ALL, photo_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, message_handler))

    async def post_init(application):
        asyncio.create_task(session_monitor(application))
    app.post_init = post_init

    print("🤖 ZiVPN Bot started!")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
