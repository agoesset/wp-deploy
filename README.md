# VPS Setup Script for WordPress Hosting

Script otomatis untuk setup VPS Ubuntu tanpa control panel untuk WordPress hosting.

## ✨ Fitur

- 🔐 **Security Setup** - Timezone, UFW Firewall, Fail2ban
- 🌐 **LEMP Stack** - NGINX, PHP 8.3, MariaDB
- 📝 **WordPress** - WP-CLI, auto install & config
- 🚀 **Caching** - Redis Object Cache, WP Super Cache + NGINX
- ⏰ **Cron** - Server-side WP-Cron

## 📋 Requirements

- Ubuntu 22.04+ / Debian 11+
- Root access
- Domain sudah diarahkan ke IP VPS (untuk SSL)

---

## 🚀 Instalasi

### Option 1: Dengan Git

```bash
# Clone repository
git clone https://github.com/agoesset/wp-deploy.git
cd wp-deploy/scripts

# Jalankan
chmod +x vps-setup.sh
sudo ./vps-setup.sh
```

### Option 2: Tanpa Git (curl)

```bash
# Download semua file
mkdir -p ~/vps-setup/lib ~/vps-setup/templates && cd ~/vps-setup

# Main script
curl -sSLO https://raw.githubusercontent.com/agoesset/wp-deploy/main/scripts/vps-setup.sh

# Libraries
for f in colors helpers vps-security webserver wordpress caching; do
  curl -sSL "https://raw.githubusercontent.com/agoesset/wp-deploy/main/scripts/lib/${f}.sh" -o "lib/${f}.sh"
done

# Templates
for f in nginx.conf nginx-site.conf phpfpm-pool.conf wsc.conf; do
  curl -sSL "https://raw.githubusercontent.com/agoesset/wp-deploy/main/scripts/templates/${f}" -o "templates/${f}"
done

# Jalankan
chmod +x vps-setup.sh
sudo ./vps-setup.sh
```

### Option 3: One-liner

```bash
bash <(curl -sSL https://raw.githubusercontent.com/agoesset/wp-deploy/main/scripts/install.sh)
```

---

## 📖 Penggunaan

Setelah menjalankan script, Anda akan melihat menu:

```
╔═══════════════════════════════════════════════════╗
║              VPS SETUP                            ║
║      Dynamic VPS Setup for WordPress Hosting      ║
╚═══════════════════════════════════════════════════╝

  1. 🔐 Initial VPS Setup (Security)
  2. 🌐 Install Webserver Stack
  3. 📝 Add WordPress Site
  4. 🚀 Setup Caching (Redis & WP Super Cache)
  5. ⏰ Setup Cron
  6. 📦 Full Installation (All of the above)

  i. ℹ️  System Information
  0. 🚪 Exit
```

### Urutan Instalasi yang Direkomendasikan

| Step | Menu | Deskripsi |
|------|------|-----------|
| 1 | `1` | Setup timezone, update packages, firewall, fail2ban |
| 2 | `2` | Install NGINX, PHP, MariaDB, Certbot, WP-CLI |
| 3 | `3` | Tambah WordPress site (bisa diulang untuk multi-site) |
| 4 | `4` | Install Redis + konfigurasi WP Super Cache |
| 5 | `5` | Setup cron untuk WordPress site |

> **Tip**: Pilih `6` untuk menjalankan step 1-2 sekaligus, lalu lanjut manual ke step 3-5.

---

## 🔧 Komponen yang Diinstall

### Security (Menu 1)
- Timezone configuration
- System packages update
- UFW Firewall (allow SSH, HTTP, HTTPS)
- Fail2ban (brute-force protection)

### Webserver Stack (Menu 2)
- NGINX (dari PPA ondrej/nginx)
- PHP 8.3-FPM + extensions
- MariaDB
- Certbot (Let's Encrypt SSL)
- WP-CLI

### Per-Site Setup (Menu 3)
- Linux user per-site
- PHP-FPM pool per-site
- NGINX virtual host dengan SSL
- Database + user
- WordPress installation

### Caching (Menu 4)
- Redis Server
- NGINX rules untuk WP Super Cache

---

## 📁 Struktur File

```
/home/{username}/{domain}/
├── public/          # WordPress files
└── logs/
    ├── access.log
    └── error.log
```

---

## 🧪 Unit Tests

Jalankan unit tests untuk memvalidasi script:

```bash
cd scripts/tests
./run_tests.sh
```

Membutuhkan [BATS](https://bats-core.readthedocs.io/) testing framework.

---

## 📚 Dokumentasi Lengkap

Lihat folder dokumentasi untuk panduan manual step-by-step:

- `01-intro/` - Pengenalan
- `02-setup-and-secure-vps/` - Setup keamanan VPS
- `03-install-webserver/` - Install LEMP stack
- `04-add-wordpress-site/` - Menambah site WordPress
- `05-caching/` - Setup caching
- `06-cron-and-backup/` - Setup cron

---

## 🤝 Credits

Berdasarkan materi **WPBogor Meetup-08** Workshop.

## 📄 License

MIT License