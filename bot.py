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
import hashlib
from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup,
    ReplyKeyboardMarkup, KeyboardButton
)
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes, ConversationHandler
)

# ─── CONFIG ────────────────────────────────────────────
DB_PATH     = "/etc/zivpn-panel/users.db"
CONF_PATH   = "/etc/zivpn-panel/panel.conf"
BACKUP_DIR  = "/etc/zivpn-panel/backups"
ZIVPN_CONF  = "/etc/zivpn/config.json"

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# ─── LOAD CONFIG ───────────────────────────────────────
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

# ─── DB HELPER ─────────────────────────────────────────
def db():
    return sqlite3.connect(DB_PATH)

def get_setting(key):
    with db() as con:
        row = con.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        return row[0] if row else ""

def set_setting(key, value):
    with db() as con:
        con.execute("INSERT OR REPLACE INTO settings VALUES (?,?)", (key, value))

def get_admin_ids():
    val = get_setting("admin_id")
    return [x.strip() for x in val.split(",") if x.strip()]

def is_admin(uid):
    return str(uid) in get_admin_ids()

def is_reseller(uid):
    with db() as con:
        row = con.execute(
            "SELECT id FROM resellers WHERE telegram_id=? AND active=1", (str(uid),)
        ).fetchone()
        return row is not None

# ─── GENERATE RANDOM PASSWORD ──────────────────────────
def gen_password(length=8):
    import random, string
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

# ─── GET VPS IP ────────────────────────────────────────
def get_vps_ip():
    conf = load_conf()
    return conf.get("VPS_IP", "N/A")

# ─── REGISTER AKUN KE ZIVPN ───────────────────────────
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
        logger.error(f"register_zivpn error: {e}")
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
        logger.error(f"unregister_zivpn error: {e}")
        return False

# ─── KEYBOARD HELPERS ──────────────────────────────────
def main_kb(uid):
    """Main menu keyboard - simetris kiri kanan"""
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
             InlineKeyboardButton("🌐 Multi-VPS",   callback_data="menu_multivps")],
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
             InlineKeyboardButton("🖥️ Cek Status",  callback_data="menu_vps")],
        ])

def back_kb(target="menu_main"):
    return InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Kembali", callback_data=target)]])

# ─── COMMAND START ─────────────────────────────────────
async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid  = update.effective_user.id
    name = update.effective_user.first_name

    role = "👑 Admin" if is_admin(uid) else ("🏪 Reseller" if is_reseller(uid) else "👤 User")

    text = (
        f"✨ *Selamat datang, {name}!*\n\n"
        f"🆔 ID Anda: `{uid}`\n"
        f"🎭 Role: {role}\n\n"
        f"*ZiVPN UDP Panel*\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"Pilih menu di bawah ini:"
    )
    await update.message.reply_text(text, parse_mode="Markdown", reply_markup=main_kb(uid))

# ─── CALLBACK QUERY ROUTER ─────────────────────────────
async def callback_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q   = update.callback_query
    uid = q.from_user.id
    data = q.data
    await q.answer()

    # ── MAIN MENU ──
    if data == "menu_main":
        name = q.from_user.first_name
        role = "👑 Admin" if is_admin(uid) else ("🏪 Reseller" if is_reseller(uid) else "👤 User")
        text = (
            f"✨ *Halo, {name}!*\n\n"
            f"🎭 Role: {role}\n\n"
            f"Pilih menu di bawah:"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=main_kb(uid))

    # ── BUAT AKUN (Admin/Reseller) ──
    elif data == "menu_create":
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak.", reply_markup=back_kb())
            return
        ctx.user_data['state'] = 'create_username'
        await q.edit_message_text(
            "➕ *BUAT AKUN BARU*\n\n"
            "Kirim username akun:\n_(ketik /batal untuk membatalkan)_",
            parse_mode="Markdown",
            reply_markup=back_kb()
        )

    # ── HAPUS AKUN (Admin/Reseller) ──
    elif data == "menu_delete":
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak.", reply_markup=back_kb())
            return
        with db() as con:
            rows = con.execute(
                "SELECT username, expired_date, status FROM accounts ORDER BY created_at DESC LIMIT 20"
            ).fetchall()

        if not rows:
            await q.edit_message_text("📭 Belum ada akun.", reply_markup=back_kb())
            return

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
            "🗑️ *HAPUS AKUN*\n\nPilih akun yang ingin dihapus:",
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
            await q.edit_message_text("❌ Akun tidak ditemukan.", reply_markup=back_kb("menu_delete"))
            return

        u, p, m, e, s, c = row
        text = (
            f"⚠️ *KONFIRMASI HAPUS AKUN*\n\n"
            f"👤 Username   : `{u}`\n"
            f"🔑 Password   : `{p}`\n"
            f"🔢 Max Login  : `{m}`\n"
            f"📅 Expired    : `{e}`\n"
            f"📌 Status     : `{s}`\n"
            f"📆 Dibuat     : `{c}`\n\n"
            f"❓ Yakin hapus akun ini?"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("✅ Ya, Hapus",   callback_data=f"del_exec_{username}"),
             InlineKeyboardButton("❌ Batal",       callback_data="menu_delete")]
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
                parse_mode="Markdown",
                reply_markup=back_kb()
            )
        else:
            await q.edit_message_text("❌ Akun tidak ditemukan.", reply_markup=back_kb("menu_delete"))

    # ── LIST AKUN ──
    elif data == "menu_list":
        if not (is_admin(uid) or is_reseller(uid)):
            await q.edit_message_text("❌ Akses ditolak.", reply_markup=back_kb()); return

        with db() as con:
            rows = con.execute(
                "SELECT username, password, max_login, expired_date, status FROM accounts ORDER BY created_at DESC"
            ).fetchall()
            total  = con.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            active = con.execute("SELECT COUNT(*) FROM accounts WHERE status='active'").fetchone()[0]

        if not rows:
            await q.edit_message_text("📭 Belum ada akun.", reply_markup=back_kb()); return

        text = f"📋 *DAFTAR AKUN* | Total: {total} | Aktif: {active}\n"
        text += "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        for r in rows[:20]:
            icon = "✅" if r[4] == "active" else "❌"
            text += f"{icon} `{r[0]}` | Pass: `{r[1]}` | MaxL: {r[2]} | Exp: {r[3][:10]}\n"
        if len(rows) > 20:
            text += f"\n_... dan {len(rows)-20} akun lainnya_"

        await q.edit_message_text(text, parse_mode="Markdown",
                                  reply_markup=back_kb())

    # ── TOKO UDP ──
    elif data == "menu_shop":
        p1 = get_setting("price_1day")
        p7 = get_setting("price_7day")
        p30 = get_setting("price_30day")
        text = (
            f"🛒 *TOKO UDP ZIVPN*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"📦 *Paket Tersedia:*\n\n"
            f"⚡ 1 Hari      : Rp {int(p1):,}\n"
            f"📅 7 Hari      : Rp {int(p7):,}\n"
            f"📆 30 Hari     : Rp {int(p30):,}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"💡 Hubungi admin setelah transfer"
        )
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("⚡ Beli 1 Hari",   callback_data="buy_1day"),
             InlineKeyboardButton("📅 Beli 7 Hari",   callback_data="buy_7day")],
            [InlineKeyboardButton("📆 Beli 30 Hari",  callback_data="buy_30day")],
            [InlineKeyboardButton("💳 Lihat QRIS",    callback_data="show_qris")],
            [InlineKeyboardButton("⬅️ Kembali",       callback_data="menu_main")],
        ])
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

    # ── SHOW QRIS ──
    elif data == "show_qris":
        qris = get_setting("qris_image")
        if qris:
            try:
                await q.message.reply_photo(photo=qris, caption="💳 *Scan QRIS untuk pembayaran*", parse_mode="Markdown")
            except:
                await q.message.reply_text("❌ Gagal menampilkan QRIS.")
        else:
            await q.edit_message_text("⚠️ QRIS belum diatur oleh admin.", reply_markup=back_kb("menu_shop"))

    # ── BUY HANDLER ──
    elif data.startswith("buy_"):
        plan = data.replace("buy_", "")
        prices = {"1day": get_setting("price_1day"), "7day": get_setting("price_7day"), "30day": get_setting("price_30day")}
        labels = {"1day": "1 Hari", "7day": "7 Hari", "30day": "30 Hari"}
        text = (
            f"🛒 *ORDER PAKET {labels.get(plan,'?')}*\n\n"
            f"💰 Harga: Rp {int(prices.get(plan,0)):,}\n\n"
            f"📌 Langkah:\n"
            f"1. Transfer sesuai nominal\n"
            f"2. Kirim bukti ke admin\n"
            f"3. Admin akan aktifkan akun\n\n"
            f"_Ketik /start untuk kembali ke menu_"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb("menu_shop"))

    # ── INFO VPS ──
    elif data == "menu_vps":
        conf = load_conf()
        vps_ip = conf.get("VPS_IP", "N/A")
        vps_id = conf.get("VPS_ID", "N/A")
        hostname = conf.get("VPS_HOSTNAME", "N/A")

        with db() as con:
            servers = con.execute("SELECT id, name, ip, port, status FROM servers").fetchall()

        svc = subprocess.getoutput("systemctl is-active zivpn.service")
        icon = "🟢" if svc == "active" else "🔴"

        text = (
            f"🖥️ *INFO VPS*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 VPS ID   : `{vps_id}`\n"
            f"🌐 IP       : `{vps_ip}`\n"
            f"🖥️ Hostname : `{hostname}`\n"
            f"{icon} ZiVPN UDP : `{svc}`\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"*Server Terdaftar:*\n"
        )
        for s in servers:
            stat_icon = "🟢" if s[4] == "active" else "🔴"
            text += f"{stat_icon} `{s[1]}` | `{s[2]}:{s[3]}`\n"

        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

    # ── BACKUP ──
    elif data == "menu_backup":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return

        await q.edit_message_text("⏳ Membuat backup...", parse_mode="Markdown")
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_file = f"{BACKUP_DIR}/backup_{ts}.tar.gz"
        os.makedirs(BACKUP_DIR, exist_ok=True)

        with tarfile.open(backup_file, "w:gz") as tar:
            if os.path.exists(DB_PATH): tar.add(DB_PATH)
            if os.path.exists(ZIVPN_CONF): tar.add(ZIVPN_CONF)

        size = os.path.getsize(backup_file)
        await q.message.reply_document(
            document=open(backup_file, 'rb'),
            filename=f"zivpn_backup_{ts}.tar.gz",
            caption=f"✅ *Backup berhasil!*\n📦 Ukuran: {size//1024} KB\n📅 {ts}",
            parse_mode="Markdown"
        )
        await q.edit_message_text("✅ Backup dikirim ke chat.", reply_markup=back_kb())

    # ── RESTORE ──
    elif data == "menu_restore":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        ctx.user_data['state'] = 'restore_file'
        await q.edit_message_text(
            "📥 *RESTORE DATA*\n\nKirim file backup (.tar.gz) ke sini:",
            parse_mode="Markdown",
            reply_markup=back_kb()
        )

    # ── PENGATURAN (Admin only) ──
    elif data == "menu_settings":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return
        await show_settings(q)

    # ── PENGATURAN SUBMENU ──
    elif data == "set_price":
        ctx.user_data['state'] = 'set_price'
        await q.edit_message_text(
            "💰 *SET HARGA PAKET*\n\nFormat: `1day,7day,30day`\nContoh: `3000,15000,50000`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_qris":
        ctx.user_data['state'] = 'set_qris'
        await q.edit_message_text(
            "💳 *UPLOAD FOTO QRIS*\n\nKirim foto QRIS kamu sekarang:",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_admin":
        ctx.user_data['state'] = 'set_admin'
        current = get_setting("admin_id")
        await q.edit_message_text(
            f"👑 *TAMBAH/SET ADMIN*\n\nAdmin saat ini: `{current}`\n\n"
            f"Kirim Telegram ID admin baru (pisah koma jika lebih dari 1):\nContoh: `123456789,987654321`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    elif data == "set_vps_info":
        ctx.user_data['state'] = 'set_vps_info'
        await q.edit_message_text(
            "🖥️ *TAMBAH SERVER VPS*\n\nFormat: `id,nama,ip,port`\nContoh: `vps2,Server Bandung,1.2.3.4,5667`",
            parse_mode="Markdown", reply_markup=back_kb("menu_settings")
        )

    # ── RESELLER MENU ──
    elif data == "menu_reseller":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return

        with db() as con:
            rows = con.execute("SELECT telegram_id, username, balance, active FROM resellers").fetchall()

        text = f"👥 *MANAJEMEN RESELLER*\n\nTotal: {len(rows)} reseller\n━━━━━━━━━━━━━━━━━━━━\n"
        for r in rows:
            icon = "✅" if r[3] else "❌"
            text += f"{icon} ID: `{r[0]}` | @{r[1]} | Saldo: Rp {r[2]:,.0f}\n"

        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Tambah Reseller",  callback_data="add_reseller"),
             InlineKeyboardButton("🗑️ Hapus Reseller",  callback_data="del_reseller")],
            [InlineKeyboardButton("💰 Tambah Saldo",    callback_data="topup_reseller"),
             InlineKeyboardButton("📋 Detail",          callback_data="detail_reseller")],
            [InlineKeyboardButton("⬅️ Kembali",         callback_data="menu_main")],
        ])
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

    elif data == "add_reseller":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'add_reseller'
        await q.edit_message_text(
            "➕ *TAMBAH RESELLER*\n\nKirim Telegram ID reseller:\nContoh: `123456789`",
            parse_mode="Markdown", reply_markup=back_kb("menu_reseller")
        )

    elif data == "del_reseller":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'del_reseller'
        await q.edit_message_text(
            "🗑️ *HAPUS RESELLER*\n\nKirim Telegram ID reseller yang ingin dihapus:",
            parse_mode="Markdown", reply_markup=back_kb("menu_reseller")
        )

    elif data == "topup_reseller":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'topup_reseller'
        await q.edit_message_text(
            "💰 *TOPUP SALDO RESELLER*\n\nFormat: `telegram_id,jumlah`\nContoh: `123456789,50000`",
            parse_mode="Markdown", reply_markup=back_kb("menu_reseller")
        )

    # ── MULTI VPS ──
    elif data == "menu_multivps":
        if not is_admin(uid):
            await q.edit_message_text("❌ Hanya admin.", reply_markup=back_kb()); return

        with db() as con:
            servers = con.execute("SELECT id, name, ip, port, location, status FROM servers").fetchall()

        text = "🌐 *MULTI VPS MANAGER*\n\n"
        for s in servers:
            icon = "🟢" if s[5] == "active" else "🔴"
            text += f"{icon} `{s[0]}` | {s[1]}\n   📍 {s[2]}:{s[3]} | {s[4]}\n\n"

        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Tambah VPS",    callback_data="set_vps_info"),
             InlineKeyboardButton("🗑️ Hapus VPS",   callback_data="del_vps")],
            [InlineKeyboardButton("⬅️ Kembali",      callback_data="menu_main")],
        ])
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

    elif data == "del_vps":
        if not is_admin(uid): return
        ctx.user_data['state'] = 'del_vps'
        await q.edit_message_text(
            "🗑️ *HAPUS VPS*\n\nKirim VPS ID yang ingin dihapus:",
            parse_mode="Markdown", reply_markup=back_kb("menu_multivps")
        )

    # ── SALDO RESELLER ──
    elif data == "menu_balance":
        with db() as con:
            row = con.execute(
                "SELECT balance FROM resellers WHERE telegram_id=?", (str(uid),)
            ).fetchone()
        bal = row[0] if row else 0
        await q.edit_message_text(
            f"💰 *SALDO SAYA*\n\nSaldo Anda: `Rp {bal:,.0f}`\n\n"
            f"Hubungi admin untuk topup saldo.",
            parse_mode="Markdown", reply_markup=back_kb()
        )

    elif data == "menu_contact":
        admins = get_admin_ids()
        text = "📞 *HUBUNGI ADMIN*\n\n"
        for a in admins:
            text += f"• Admin ID: `{a}`\n"
        text += "\nKetik pesan Anda dan kirim ke admin."
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

    elif data == "menu_howto":
        vps_ip = get_vps_ip()
        text = (
            f"ℹ️ *CARA MENGGUNAKAN*\n\n"
            f"1️⃣ Beli paket di menu *Toko UDP*\n"
            f"2️⃣ Konfirmasi ke admin\n"
            f"3️⃣ Dapatkan username & password\n"
            f"4️⃣ Buka app ZiVPN di HP Anda\n"
            f"5️⃣ Masukkan:\n"
            f"   • Server: `{vps_ip}`\n"
            f"   • Port: `5667`\n"
            f"   • Username & Password dari admin\n\n"
            f"✅ Selesai! Nikmati internet bebas!"
        )
        await q.edit_message_text(text, parse_mode="Markdown", reply_markup=back_kb())

# ─── SHOW SETTINGS ─────────────────────────────────────
async def show_settings(q):
    p1  = get_setting("price_1day")
    p7  = get_setting("price_7day")
    p30 = get_setting("price_30day")
    text = (
        f"⚙️ *PENGATURAN BOT*\n\n"
        f"💰 Harga 1 Hari  : Rp {int(p1):,}\n"
        f"💰 Harga 7 Hari  : Rp {int(p7):,}\n"
        f"💰 Harga 30 Hari : Rp {int(p30):,}\n\n"
        f"Pilih yang ingin diubah:"
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("💰 Set Harga Paket",  callback_data="set_price"),
         InlineKeyboardButton("💳 Upload QRIS",      callback_data="set_qris")],
        [InlineKeyboardButton("👑 Set Admin",        callback_data="set_admin"),
         InlineKeyboardButton("🖥️ Tambah VPS",     callback_data="set_vps_info")],
        [InlineKeyboardButton("⬅️ Kembali",         callback_data="menu_main")],
    ])
    await q.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)

# ─── MESSAGE HANDLER (state machine) ───────────────────
async def message_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid   = update.effective_user.id
    text  = update.message.text or ""
    state = ctx.user_data.get('state', '')

    # ── CREATE AKUN - step username ──
    if state == 'create_username':
        if not (is_admin(uid) or is_reseller(uid)): return
        ctx.user_data['new_username'] = text.strip()
        ctx.user_data['state'] = 'create_password'
        await update.message.reply_text(
            f"✅ Username: `{text.strip()}`\n\nKirim password (atau ketik `auto` untuk generate otomatis):",
            parse_mode="Markdown"
        )

    elif state == 'create_password':
        if not (is_admin(uid) or is_reseller(uid)): return
        password = gen_password() if text.strip().lower() == "auto" else text.strip()
        ctx.user_data['new_password'] = password
        ctx.user_data['state'] = 'create_maxlogin'
        await update.message.reply_text(
            f"✅ Password: `{password}`\n\nKirim max login (default: 2):",
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
            f"✅ Max Login: `{ml}`\n\nKirim lama aktif (hari, contoh: `30`):",
            parse_mode="Markdown"
        )

    elif state == 'create_expdays':
        if not (is_admin(uid) or is_reseller(uid)): return
        try:
            days = int(text.strip())
        except:
            days = 30

        username   = ctx.user_data.get('new_username', '')
        password   = ctx.user_data.get('new_password', '')
        max_login  = ctx.user_data.get('new_maxlogin', 2)
        exp_date   = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime('%Y-%m-%d %H:%M:%S')
        conf       = load_conf()
        server_id  = conf.get("VPS_ID", "vps1")
        vps_ip     = conf.get("VPS_IP", "N/A")

        # Cek duplikat
        with db() as con:
            exist = con.execute("SELECT COUNT(*) FROM accounts WHERE username=?", (username,)).fetchone()[0]
        if exist:
            await update.message.reply_text(f"❌ Username `{username}` sudah ada!", parse_mode="Markdown")
            ctx.user_data.clear(); return

        with db() as con:
            con.execute(
                "INSERT INTO accounts (username, password, max_login, expired_date, server_id, created_by, status) "
                "VALUES (?,?,?,?,?,?,?)",
                (username, password, max_login, exp_date, server_id, str(uid), 'active')
            )

        register_zivpn(password)
        ctx.user_data.clear()

        result_text = (
            f"✅ *AKUN BERHASIL DIBUAT!*\n\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username   : `{username}`\n"
            f"🔑 Password   : `{password}`\n"
            f"🔢 Max Login  : `{max_login}`\n"
            f"📅 Expired    : `{exp_date}`\n"
            f"🌐 Server     : `{vps_ip}`\n"
            f"📡 Port       : `5667`\n"
            f"🆔 Server ID  : `{server_id}`\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🔗 *Format Koneksi:*\n"
            f"`{vps_ip}:5667`"
        )
        await update.message.reply_text(result_text, parse_mode="Markdown", reply_markup=back_kb())

    # ── PENGATURAN - Set Harga ──
    elif state == 'set_price':
        if not is_admin(uid): return
        parts = text.strip().split(',')
        if len(parts) == 3:
            set_setting("price_1day",  parts[0].strip())
            set_setting("price_7day",  parts[1].strip())
            set_setting("price_30day", parts[2].strip())
            await update.message.reply_text(
                f"✅ Harga diperbarui!\n1 Hari: Rp {int(parts[0]):,}\n7 Hari: Rp {int(parts[1]):,}\n30 Hari: Rp {int(parts[2]):,}",
                reply_markup=back_kb("menu_settings")
            )
        else:
            await update.message.reply_text("❌ Format salah! Gunakan: `1day,7day,30day`", parse_mode="Markdown")
        ctx.user_data.clear()

    # ── PENGATURAN - Set Admin ──
    elif state == 'set_admin':
        if not is_admin(uid): return
        set_setting("admin_id", text.strip())
        await update.message.reply_text(f"✅ Admin ID diperbarui: `{text.strip()}`", parse_mode="Markdown")
        ctx.user_data.clear()

    # ── PENGATURAN - Tambah VPS ──
    elif state == 'set_vps_info':
        if not is_admin(uid): return
        parts = text.strip().split(',')
        if len(parts) >= 4:
            vid, vname, vip, vport = parts[0].strip(), parts[1].strip(), parts[2].strip(), parts[3].strip()
            with db() as con:
                con.execute("INSERT OR REPLACE INTO servers (id, name, ip, port, status) VALUES (?,?,?,?,?)",
                            (vid, vname, vip, int(vport), 'active'))
            await update.message.reply_text(f"✅ VPS `{vid}` ({vname}) berhasil ditambahkan!", parse_mode="Markdown")
        else:
            await update.message.reply_text("❌ Format salah! Gunakan: `id,nama,ip,port`", parse_mode="Markdown")
        ctx.user_data.clear()

    # ── Hapus VPS ──
    elif state == 'del_vps':
        if not is_admin(uid): return
        with db() as con:
            con.execute("DELETE FROM servers WHERE id=?", (text.strip(),))
        await update.message.reply_text(f"✅ VPS `{text.strip()}` dihapus.", parse_mode="Markdown")
        ctx.user_data.clear()

    # ── Tambah Reseller ──
    elif state == 'add_reseller':
        if not is_admin(uid): return
        res_id = text.strip()
        with db() as con:
            con.execute("INSERT OR IGNORE INTO resellers (telegram_id, username) VALUES (?,?)",
                        (res_id, f"user_{res_id}"))
        await update.message.reply_text(f"✅ Reseller `{res_id}` berhasil ditambahkan!", parse_mode="Markdown")
        ctx.user_data.clear()

    # ── Hapus Reseller ──
    elif state == 'del_reseller':
        if not is_admin(uid): return
        res_id = text.strip()
        with db() as con:
            con.execute("DELETE FROM resellers WHERE telegram_id=?", (res_id,))
        await update.message.reply_text(f"✅ Reseller `{res_id}` dihapus.", parse_mode="Markdown")
        ctx.user_data.clear()

    # ── Topup Reseller ──
    elif state == 'topup_reseller':
        if not is_admin(uid): return
        parts = text.strip().split(',')
        if len(parts) == 2:
            res_id, amount = parts[0].strip(), int(parts[1].strip())
            with db() as con:
                con.execute("UPDATE resellers SET balance = balance + ? WHERE telegram_id=?", (amount, res_id))
            await update.message.reply_text(
                f"✅ Saldo reseller `{res_id}` ditambah Rp {amount:,}", parse_mode="Markdown"
            )
        ctx.user_data.clear()

# ─── PHOTO HANDLER (QRIS upload) ───────────────────────
async def photo_handler(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid   = update.effective_user.id
    state = ctx.user_data.get('state', '')

    if state == 'set_qris' and is_admin(uid):
        photo = update.message.photo[-1]
        file_id = photo.file_id
        set_setting("qris_image", file_id)
        await update.message.reply_text("✅ Foto QRIS berhasil disimpan!", reply_markup=back_kb("menu_settings"))
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

# ─── SESSION MONITOR (background task) ─────────────────
async def session_monitor(app):
    while True:
        try:
            with db() as con:
                rows = con.execute(
                    "SELECT username, max_login FROM accounts WHERE status='active'"
                ).fetchall()
            for username, max_login in rows:
                sessions = int(subprocess.getoutput(
                    f"ss -u -a 2>/dev/null | grep -c '{username}' || echo 0"
                ))
                if sessions > max_login:
                    subprocess.run(["pkill", "-f", username], capture_output=True)
            # Update expired
            with db() as con:
                con.execute(
                    "UPDATE accounts SET status='expired' "
                    "WHERE expired_date < datetime('now') AND expired_date != '' AND status='active'"
                )
        except Exception as e:
            logger.error(f"monitor error: {e}")
        await asyncio.sleep(60)

# ─── MAIN ──────────────────────────────────────────────
def main():
    token = get_setting("bot_token")
    if not token:
        print("ERROR: Bot token belum diset!")
        print("Jalankan: sqlite3 /etc/zivpn-panel/users.db \"UPDATE settings SET value='TOKEN_ANDA' WHERE key='bot_token';\"")
        return

    app = Application.builder().token(token).build()

    # Handlers
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CallbackQueryHandler(callback_handler))
    app.add_handler(MessageHandler(filters.PHOTO | filters.Document.ALL, photo_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, message_handler))

    # Background monitor
    async def post_init(app):
        asyncio.create_task(session_monitor(app))
    app.post_init = post_init

    print("🤖 ZiVPN Bot started!")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
