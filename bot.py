#!/usr/bin/env python3
# bot.py - Telegram Bot ZiVPN UDP - FIXED EDITION
# Requires: python-telegram-bot==20.7

import logging, sqlite3, json, os, asyncio
import subprocess, tarfile, datetime, random, string
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
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

# ─── ZIVPN CONFIG HELPERS ──────────────────────────────
def read_zivpn_conf():
    """Baca config, pastikan struktur benar"""
    try:
        with open(ZIVPN_CONF) as f:
            d = json.load(f)
    except:
        d = {}
    # Struktur default yang benar
    if "listen" not in d:   d["listen"] = ":5667"
    if "cert" not in d:     d["cert"]   = "/etc/zivpn/zivpn.crt"
    if "key" not in d:      d["key"]    = "/etc/zivpn/zivpn.key"
    if "obfs" not in d:     d["obfs"]   = "zivpn"
    if "auth" not in d:     d["auth"]   = {"mode": "passwords", "config": ["zi"]}
    if "config" not in d["auth"]: d["auth"]["config"] = ["zi"]
    # Hapus root 'config' jika ada (fix duplikat lama)
    if "config" in d:
        del d["config"]
    return d

def write_zivpn_conf(d):
    """Tulis config, pastikan tidak ada duplikat"""
    if "config" in d:
        del d["config"]
    with open(ZIVPN_CONF, "w") as f:
        json.dump(d, f, indent=2)

def register_zivpn(password):
    """Tambah password ke auth.config SAJA"""
    try:
        d = read_zivpn_conf()
        if password not in d["auth"]["config"]:
            d["auth"]["config"].append(password)
        write_zivpn_conf(d)
        os.system("systemctl restart zivpn.service")
        return True
    except Exception as e:
        logger.error(f"register_zivpn: {e}")
        return False

def unregister_zivpn(password):
    """Hapus password dari auth.config"""
    try:
        d = read_zivpn_conf()
        if password in d["auth"]["config"]:
            d["auth"]["config"].remove(password)
        write_zivpn_conf(d)
        os.system("systemctl restart zivpn.service")
        return True
    except Exception as e:
        logger.error(f"unregister_zivpn: {e}")
        return False

def fix_zivpn_conf():
    """Perbaiki config - gabungkan semua password, hapus duplikat"""
    try:
        with open(ZIVPN_CONF) as f:
            d = json.load(f)
        passwords = []
        # Kumpulkan dari root config (lama)
        if "config" in d:
            for p in d["config"]:
                if p not in passwords:
                    passwords.append(p)
            del d["config"]
        # Kumpulkan dari auth.config (baru)
        if "auth" in d and "config" in d["auth"]:
            for p in d["auth"]["config"]:
                if p not in passwords:
                    passwords.append(p)
        d["auth"] = {"mode": "passwords", "config": passwords or ["zi"]}
        write_zivpn_conf(d)
        return True, len(passwords)
    except Exception as e:
        return False, str(e)

# ─── DB & SETTINGS ─────────────────────────────────────
def load_conf():
    conf = {}
    if os.path.exists(CONF_PATH):
        with open(CONF_PATH) as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=', 1)
                    conf[k] = v
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
    return [x.strip() for x in get_setting("admin_id").split(",") if x.strip()]

def is_admin(uid):
    return str(uid) in get_admin_ids()

def is_reseller(uid):
    try:
        with db() as con:
            return con.execute(
                "SELECT id FROM resellers WHERE telegram_id=? AND active=1", (str(uid),)
            ).fetchone() is not None
    except:
        return False

def gen_password(length=8):
    return ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(length))

def get_vps_ip():
    return load_conf().get("VPS_IP", "N/A")

def get_vps_spek():
    try:
        return {
            "cpu":    subprocess.getoutput("grep -m1 'model name' /proc/cpuinfo | cut -d: -f2").strip(),
            "core":   subprocess.getoutput("nproc").strip(),
            "ram":    subprocess.getoutput("free -m | awk 'NR==2{print $3\"/\"$2\" MB\"}'").strip(),
            "disk":   subprocess.getoutput("df -h / | awk 'NR==2{print $3\"/\"$2\" (\"$5\")'").strip(),
            "os":     subprocess.getoutput("grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2").strip(),
            "uptime": subprocess.getoutput("uptime -p").strip(),
            "load":   subprocess.getoutput("uptime | awk -F'load average:' '{print $2}'").strip(),
        }
    except:
        return {}

# ─── KEYBOARDS ─────────────────────────────────────────
def main_kb(uid):
    if is_admin(uid):
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Buat Akun",    callback_data="menu_create"),
             InlineKeyboardButton("🗑️ Hapus Akun",  callback_data="menu_delete")],
            [InlineKeyboardButton("📋 Info Akun",    callback_data="menu_list"),
             InlineKeyboardButton("🛒 Toko UDP",     callback_data="menu_shop")],
            [InlineKeyboardButton("💾 Backup",       callback_data="menu_backup"),
             InlineKeyboardButton("📥 Restore",      callback_data="menu_restore")],
            [InlineKeyboardButton("🖥️ Info VPS",    callback_data="menu_vps"),
             InlineKeyboardButton("⚙️ Pengaturan",  callback_data="menu_settings")],
            [InlineKeyboardButton("👥 Reseller",     callback_data="menu_reseller"),
             InlineKeyboardButton("🔧 Fix Config",   callback_data="menu_fixconf")],
        ])
    elif is_reseller(uid):
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Buat Akun",    callback_data="menu_create"),
             InlineKeyboardButton("🗑️ Hapus Akun",  callback_data="menu_delete")],
            [InlineKeyboardButton("📋 Info Akun",    callback_data="menu_list"),
             InlineKeyboardButton("🛒 Toko UDP",     callback_data="menu_shop")],
            [InlineKeyboardButton("🖥️ Info VPS",    callback_data="menu_vps"),
             InlineKeyboardButton("💰 Saldo Saya",  callback_data="menu_balance")],
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
    await update.message.reply_text(
        f"✨ *Selamat datang, {name}!*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"🆔 ID   : `{uid}`\n"
        f"🎭 Role : {role}\n"
        f"━━━━━━━━━━━━━━━━━━━━\n\n"
        f"*ZiVPN UDP Panel* — Pilih menu:",
        parse_mode="Markdown", reply_markup=main_kb(uid)
    )

# ─── CALLBACK HANDLER ──────────────────────────────────
async def callback_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q    = update.callback_query
    uid  = q.from_user.id
    data = q.data
    await q.answer()

    if data == "menu_main":
        role = "👑 Admin" if is_admin(uid) else ("🏪 Reseller" if is_reseller(uid) else "👤 User")
        await q.edit_message_text(
            f"✨ *Menu Utama*\n\n🎭 Role: {role}\n━━━━━━━━━━━━━━━━━━━━\nPilih menu:",
            parse_mode="Markdown", reply_markup=main_kb(uid)
        )

    # ── BUAT AKUN ──
    elif data == "menu_create":
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak.", reply_markup=back_kb()); return
        ctx.user_data['state'] = 'create_username'
        await q.edit_message_text(
            "➕ *BUAT AKUN BARU*\n\n━━━━━━━━━━━━━━━━━━━━\nKirim *username* akun:",
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
                row_btns.append(InlineKeyboardButton(f"{icon} {r[0]}", callback_data=f"del_confirm_{r[0]}"))
            buttons.append(row_btns)
        buttons.append([InlineKeyboardButton("⬅️ Kembali", callback_data="menu_main")])
        await q.edit_message_text(
            "🗑️ *HAPUS AKUN*\n\n━━━━━━━━━━━━━━━━━━━━\nPilih akun:",
            parse_mode="Markdown", reply_markup=InlineKeyboardMarkup(buttons)
        )

    elif data.startswith("del_confirm_"):
        username = data.replace("del_confirm_", "")
        if not (is_admin(uid) or is_reseller(uid)): return
        with db() as con:
            row = con.execute(
                "SELECT username,password,max_login,expired_date,status,created_at FROM accounts WHERE username=?",
                (username,)
            ).fetchone()
        if not row:
            await q.edit_message_text("❌ Akun tidak ditemukan.", reply_markup=back_kb("menu_delete")); return
        u, p, m, e, s, c = row
        icon = "✅" if s == "active" else "❌"
        await q.edit_message_text(
            f"⚠️ *KONFIRMASI HAPUS*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username  : `{u}`\n"
            f"🔑 Password  : `{p}`\n"
            f"🔢 Max Login : `{m}`\n"
            f"📅 Expired   : `{e}`\n"
            f"📌 Status    : {icon} `{s}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"❓ Yakin hapus?",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("✅ Ya, Hapus", callback_data=f"del_exec_{username}"),
                 InlineKeyboardButton("❌ Batal",     callback_data="menu_delete")]
            ])
        )

    elif data.startswith("del_exec_"):
        username = data.replace("del_exec_", "")
        if not (is_admin(uid) or is_reseller(uid)): return
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
            rows   = con.execute("SELECT username,password,max_login,expired_date,status FROM accounts ORDER BY created_at DESC").fetchall()
            total  = con.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            active = con.execute("SELECT COUNT(*) FROM accounts WHERE status='active'").fetchone()[0]
        if not rows:
            await q.edit_message_text("📭 Belum ada akun.", reply_markup=back_kb()); return
        text = f"📋 *DAFTAR AKUN*\n\n━━━━━━━━━━━━━━━━━━━━\n📊 Total: `{total}` | Aktif: `{active}`\n━━━━━━━━━━━━━━━━━━━━\n"
        for r in rows[:20]:
            icon = "✅" if r[4] == "active" else "❌"
            text += f"{icon} `{r[0]}` | `{r[1]}` | MaxL:{r[2]} | {str(r[3])[:10]}\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
        if len(rows) > 20:
            text += f"_... dan {len(rows)-20} lainnya_"
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

    # ── TOKO ──
    elif data == "menu_shop":
        p15 = get_setting("price_15day", "5000")
        p30 = get_setting("price_30day", "10000")
        await q.edit_message_text(
            f"🛒 *TOKO UDP ZIVPN*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"📅 *15 Hari*  →  Rp {int(p15):,}\n"
            f"┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"📆 *30 Hari*  →  Rp {int(p30):,}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"💡 Transfer → kirim bukti ke admin",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("📅 Beli 15 Hari", callback_data="buy_15day"),
                 InlineKeyboardButton("📆 Beli 30 Hari", callback_data="buy_30day")],
                [InlineKeyboardButton("💳 Lihat QRIS",   callback_data="show_qris")],
                [InlineKeyboardButton("⬅️ Kembali",      callback_data="menu_main")],
            ])
        )

    elif data == "show_qris":
        qris = get_setting("qris_image")
        if qris:
            try:
                await q.message.reply_photo(photo=qris, caption="💳 *Scan QRIS untuk bayar*", parse_mode="Markdown")
            except:
                await q.edit_message_text("❌ Gagal load QRIS.", reply_markup=back_kb("menu_shop"))
        else:
            await q.edit_message_text("⚠️ QRIS belum diatur admin.", reply_markup=back_kb("menu_shop"))

    elif data.startswith("buy_"):
        plan   = data.replace("buy_", "")
        prices = {"15day": get_setting("price_15day","5000"), "30day": get_setting("price_30day","10000")}
        labels = {"15day": "15 Hari", "30day": "30 Hari"}
        await q.edit_message_text(
            f"🛒 *ORDER {labels.get(plan,'?')}*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"💰 Harga : Rp {int(prices.get(plan,0)):,}\n"
            f"⏳ Masa  : {labels.get(plan,'?')}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"1️⃣ Transfer\n2️⃣ Kirim bukti ke admin\n3️⃣ Akun diaktifkan",
            parse_mode="Markdown", reply_markup=back_kb("menu_shop")
        )

    # ── INFO VPS ──
    elif data == "menu_vps":
        conf     = load_conf()
        vps_ip   = conf.get("VPS_IP", "N/A")
        vps_id   = conf.get("VPS_ID", "N/A")
        hostname = conf.get("VPS_HOSTNAME", "N/A")
        spek     = get_vps_spek()
        svc      = subprocess.getoutput("systemctl is-active zivpn.service")
        bot_svc  = subprocess.getoutput("systemctl is-active zivpn-bot.service")

        # Baca passwords dari config
        try:
            d = read_zivpn_conf()
            pw_count = len(d["auth"]["config"])
        except:
            pw_count = 0

        with db() as con:
            total  = con.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            active = con.execute("SELECT COUNT(*) FROM accounts WHERE status='active'").fetchone()[0]

        await q.edit_message_text(
            f"🖥️ *INFO VPS & SPESIFIKASI*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 VPS ID    : `{vps_id}`\n"
            f"🌐 IP        : `{vps_ip}`\n"
            f"🖥️ Hostname  : `{hostname}`\n"
            f"💿 OS        : `{spek.get('os','N/A')}`\n"
            f"{'🟢' if svc=='active' else '🔴'} ZiVPN     : `{svc}`\n"
            f"{'🟢' if bot_svc=='active' else '🔴'} Bot TG    : `{bot_svc}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"⚙️ *Hardware:*\n\n"
            f"🔲 CPU   : `{spek.get('cpu','N/A')}`\n"
            f"🔢 Core  : `{spek.get('core','N/A')}`\n"
            f"💾 RAM   : `{spek.get('ram','N/A')}`\n"
            f"💿 Disk  : `{spek.get('disk','N/A')}`\n"
            f"⏱️ Uptime: `{spek.get('uptime','N/A')}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"👥 Total Akun : `{total}` | Aktif: `{active}`\n"
            f"🔑 Password   : `{pw_count}` terdaftar\n"
            f"━━━━━━━━━━━━━━━━━━━━",
            parse_mode="Markdown", reply_markup=back_kb()
        )

    # ── FIX CONFIG ──
    elif data == "menu_fixconf":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        await q.edit_message_text("⏳ *Memperbaiki config.json...*", parse_mode="Markdown")
        ok, result = fix_zivpn_conf()
        os.system("systemctl restart zivpn.service")
        if ok:
            await q.edit_message_text(
                f"✅ *Config berhasil diperbaiki!*\n\n"
                f"🔑 Total password: `{result}`\n"
                f"🔄 ZiVPN direstart",
                parse_mode="Markdown", reply_markup=back_kb()
            )
        else:
            await q.edit_message_text(f"❌ Gagal: `{result}`", parse_mode="Markdown", reply_markup=back_kb())

    # ── BACKUP ──
    elif data == "menu_backup":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        await q.edit_message_text("⏳ *Membuat backup...*", parse_mode="Markdown")
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_file = f"{BACKUP_DIR}/backup_{ts}.tar.gz"
        os.makedirs(BACKUP_DIR, exist_ok=True)
        with tarfile.open(backup_file, "w:gz") as tar:
            if os.path.exists(DB_PATH):    tar.add(DB_PATH)
            if os.path.exists(ZIVPN_CONF): tar.add(ZIVPN_CONF)
        size = os.path.getsize(backup_file) // 1024
        await q.message.reply_document(
            document=open(backup_file, 'rb'),
            filename=f"zivpn_backup_{ts}.tar.gz",
            caption=f"✅ *Backup Berhasil!*\n📦 `{ts}`\n📐 `{size} KB`",
            parse_mode="Markdown"
        )
        await q.edit_message_text("✅ Backup dikirim!", reply_markup=back_kb())

    # ── RESTORE ──
    elif data == "menu_restore":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        ctx.user_data['state'] = 'restore_file'
        await q.edit_message_text(
            "📥 *RESTORE DATA*\n\n━━━━━━━━━━━━━━━━━━━━\nKirim file backup `.tar.gz`:",
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
            f"Saat ini: 15hr=Rp{int(p15):,} | 30hr=Rp{int(p30):,}\n\n"
            f"Format: `15day,30day`\nContoh: `5000,10000`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_qris":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'set_qris'
        await q.edit_message_text(
            "💳 *UPLOAD FOTO QRIS*\n\n━━━━━━━━━━━━━━━━━━━━\nKirim foto QRIS sekarang:",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_admin":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'set_admin'
        await q.edit_message_text(
            f"👑 *SET ADMIN*\n\nSaat ini: `{get_setting('admin_id')}`\n\n"
            f"Kirim ID baru (pisah koma):",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_vps_info":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'set_vps_info'
        await q.edit_message_text(
            "🖥️ *TAMBAH VPS*\n\n━━━━━━━━━━━━━━━━━━━━\nFormat: `id,nama,ip,port`\nContoh: `vps2,SGP,1.2.3.4,5667`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    # ── RESELLER ──
    elif data == "menu_reseller":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        with db() as con:
            rows = con.execute("SELECT telegram_id,username,balance,active FROM resellers").fetchall()
        text = f"👥 *RESELLER* | Total: {len(rows)}\n\n━━━━━━━━━━━━━━━━━━━━\n"
        for r in rows:
            icon = "✅" if r[3] else "❌"
            text += f"{icon} `{r[0]}` | Saldo: Rp {r[2]:,.0f}\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Tambah",      callback_data="add_reseller"),
             InlineKeyboardButton("🗑️ Hapus",      callback_data="del_reseller")],
            [InlineKeyboardButton("💰 Topup",       callback_data="topup_reseller"),
             InlineKeyboardButton("⬅️ Kembali",    callback_data="menu_main")],
        ]))

    elif data in ["add_reseller","del_reseller","topup_reseller"]:
        if not is_admin(uid): return
        ctx.user_data['state'] = data
        msgs = {
            "add_reseller":   "➕ *TAMBAH RESELLER*\n\nKirim Telegram ID:",
            "del_reseller":   "🗑️ *HAPUS RESELLER*\n\nKirim Telegram ID:",
            "topup_reseller": "💰 *TOPUP SALDO*\n\nFormat: `id,jumlah`\nContoh: `123456,50000`",
        }
        await q.edit_message_text(msgs[data], parse_mode="Markdown", reply_markup=back_kb("menu_reseller"))

    elif data == "menu_balance":
        with db() as con:
            row = con.execute("SELECT balance FROM resellers WHERE telegram_id=?", (str(uid),)).fetchone()
        bal = row[0] if row else 0
        await q.edit_message_text(
            f"💰 *SALDO SAYA*\n\n━━━━━━━━━━━━━━━━━━━━\nSaldo: `Rp {bal:,.0f}`",
            parse_mode="Markdown", reply_markup=back_kb()
        )

    elif data == "menu_contact":
        admins = get_admin_ids()
        text = "📞 *HUBUNGI ADMIN*\n\n━━━━━━━━━━━━━━━━━━━━\n"
        for a in admins:
            text += f"• ID: `{a}`\n"
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

    elif data == "menu_howto":
        vps_ip = get_vps_ip()
        await q.edit_message_text(
            f"ℹ️ *CARA PAKAI*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"1️⃣ Beli paket → *Toko UDP*\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"2️⃣ Transfer & kirim bukti\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"3️⃣ Dapat akun dari admin\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"4️⃣ Setting app ZiVPN:\n"
            f"   🌐 Server : `{vps_ip}`\n"
            f"   📡 Port   : `5667`\n"
            f"   🔒 Obfs   : `zivpn`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"✅ Konek & nikmati! 🚀",
            parse_mode="Markdown", reply_markup=back_kb()
        )

async def show_settings_menu(q):
    p15 = get_setting("price_15day","5000")
    p30 = get_setting("price_30day","10000")
    await q.edit_message_text(
        f"⚙️ *PENGATURAN*\n\n━━━━━━━━━━━━━━━━━━━━\n"
        f"💰 15 Hari : Rp {int(p15):,}\n"
        f"💰 30 Hari : Rp {int(p30):,}\n"
        f"━━━━━━━━━━━━━━━━━━━━",
        parse_mode="Markdown",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("💰 Set Harga",    callback_data="set_price"),
             InlineKeyboardButton("💳 Upload QRIS",  callback_data="set_qris")],
            [InlineKeyboardButton("👑 Set Admin",    callback_data="set_admin"),
             InlineKeyboardButton("🖥️ Tambah VPS",  callback_data="set_vps_info")],
            [InlineKeyboardButton("⬅️ Kembali",     callback_data="menu_main")],
        ])
    )

# ─── MESSAGE HANDLER ───────────────────────────────────
async def message_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid   = update.effective_user.id
    text  = update.message.text or ""
    state = ctx.user_data.get('state', '')

    if text.strip() == "/batal":
        ctx.user_data.clear()
        await update.message.reply_text("❌ Dibatalkan.", reply_markup=back_kb()); return

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
        try: ml = int(text.strip())
        except: ml = 2
        ctx.user_data['new_maxlogin'] = ml
        ctx.user_data['state'] = 'create_expdays'
        await update.message.reply_text(
            f"✅ Max Login: `{ml}`\n\n━━━━━━━━━━━━━━━━━━━━\n`15` = 15 hari (Rp 5.000)\n`30` = 30 hari (Rp 10.000)\n\nKirim lama aktif:",
            parse_mode="Markdown"
        )

    elif state == 'create_expdays':
        if not (is_admin(uid) or is_reseller(uid)): return
        try: days = int(text.strip())
        except: days = 30

        username  = ctx.user_data.get('new_username','')
        password  = ctx.user_data.get('new_password','')
        max_login = ctx.user_data.get('new_maxlogin', 2)
        exp_date  = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime('%Y-%m-%d %H:%M:%S')
        conf      = load_conf()
        server_id = conf.get("VPS_ID","vps1")
        vps_ip    = conf.get("VPS_IP","N/A")

        with db() as con:
            exist = con.execute("SELECT COUNT(*) FROM accounts WHERE username=?", (username,)).fetchone()[0]
        if exist:
            await update.message.reply_text(f"❌ Username `{username}` sudah ada!", parse_mode="Markdown")
            ctx.user_data.clear(); return

        with db() as con:
            con.execute(
                "INSERT INTO accounts (username,password,max_login,expired_date,server_id,created_by,status) VALUES (?,?,?,?,?,?,?)",
                (username, password, max_login, exp_date, server_id, str(uid), 'active')
            )

        register_zivpn(password)
        ctx.user_data.clear()
        harga = "Rp 5.000" if days <= 15 else "Rp 10.000"

        await update.message.reply_text(
            f"✅ *AKUN BERHASIL DIBUAT!*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username  : `{username}`\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"🔑 Password  : `{password}`\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"🔢 Max Login : `{max_login}`\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"📅 Expired   : `{exp_date}`\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"🌐 Server    : `{vps_ip}`\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"📡 Port      : `5667`\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
            f"🔒 Obfs      : `zivpn`\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n"
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
                f"✅ Harga: 15hr=Rp{int(parts[0]):,} | 30hr=Rp{int(parts[1]):,}",
                reply_markup=back_kb("menu_settings")
            )
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
                            (parts[0].strip(),parts[1].strip(),parts[2].strip(),int(parts[3].strip()),'active'))
            await update.message.reply_text(f"✅ VPS `{parts[0].strip()}` ditambahkan!", parse_mode="Markdown")
        ctx.user_data.clear()

    elif state == 'add_reseller':
        if not is_admin(uid): return
        with db() as con:
            con.execute("INSERT OR IGNORE INTO resellers (telegram_id,username) VALUES (?,?)",
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
                con.execute("UPDATE resellers SET balance=balance+? WHERE telegram_id=?",
                            (int(parts[1].strip()), parts[0].strip()))
            await update.message.reply_text(f"✅ Topup Rp{int(parts[1]):,} ke `{parts[0].strip()}`", parse_mode="Markdown")
        ctx.user_data.clear()

# ─── PHOTO/DOC HANDLER ─────────────────────────────────
async def photo_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid   = update.effective_user.id
    state = ctx.user_data.get('state','')
    if state == 'set_qris' and is_admin(uid):
        file_id = update.message.photo[-1].file_id
        set_setting("qris_image", file_id)
        await update.message.reply_text("✅ QRIS disimpan!", reply_markup=back_kb("menu_settings"))
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
                con.execute(
                    "UPDATE accounts SET status='expired' "
                    "WHERE expired_date < datetime('now') AND expired_date!='' AND status='active'"
                )
                rows = con.execute("SELECT username,max_login FROM accounts WHERE status='active'").fetchall()
            for username, max_login in rows:
                sessions = int(subprocess.getoutput(
                    f"ss -u -a 2>/dev/null | grep -c '{username}' || echo 0"
                ).strip() or 0)
                if sessions > max_login:
                    subprocess.run(["pkill","-f",username], capture_output=True)
        except Exception as e:
            logger.error(f"monitor: {e}")
        await asyncio.sleep(60)

# ─── MAIN ──────────────────────────────────────────────
def main():
    token = get_setting("bot_token")
    if not token:
        print("ERROR: Bot token belum diset! Jalankan setup-bot.sh"); return

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
