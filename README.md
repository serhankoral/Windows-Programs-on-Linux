<div align="center">

<img src="https://raw.githubusercontent.com/winapps-org/winapps/main/docs/winapps.svg" alt="WinApps Logo" width="120"/>

# ubuntu-winapps-setup

**Türkçe** | [English](#english)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Shell-Bash-green.svg)](ubuntu-full-setup.sh)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%2B-E95420.svg)](https://ubuntu.com)
[![WinApps](https://img.shields.io/badge/WinApps-Docker-blue.svg)](https://github.com/winapps-org/winapps)

Sıfır Ubuntu kurulumundan WinApps'e kadar **tek komutla** tam otomatik kurulum scripti.  
GNOME araçları, touchpad ayarı ve Windows VM kurulumunu otomatikleştirir.

</div>

---

## 🇹🇷 Türkçe

### 📋 Genel Bakış

Bu script, Ubuntu üzerine aşağıdakileri **otomatik olarak** kurar ve yapılandırır:

| Bölüm | İçerik |
|-------|--------|
| **GNOME Araçları** | GNOME Tweaks, dconf-editor, Extension Manager, Dash to Panel, Dash to Dock |
| **Touchpad** | USB fare takılınca touchpad otomatik kapanır (tüm kullanıcılar) |
| **WinApps** | Docker + KVM + Windows VM + WinApps sistem geneli kurulum |
| **Yenileme** | `winapps-refresh` komutu + programlar menüsü kısayolu + systemd timer |

### ✨ Özellikler

- 🌐 **Türkçe/İngilizce** dil desteği
- 👥 **Tüm kullanıcılar** için kurulum (`/usr/share/applications`, system-wide)
- 🔄 **Akıllı kontrol** — kurulu paketleri atlar, eksikleri kurar
- 🪟 **Türkçe Windows** — Microsoft'tan Türkçe ISO otomatik indirilir
- 🔒 **Güvenli** — Windows şifresi sistem geneli config'de güvenle saklanır
- ♻️ **Yeniden çalıştırılabilir** — mevcut kurulumu temizleyip yeniden kurar
- 🗑️ **Tam kaldırma** — Docker, WinApps, GNOME araçları dahil her şeyi temizler

### 🖥️ Sistem Gereksinimleri

| Gereksinim | Detay |
|-----------|-------|
| **İşletim Sistemi** | Ubuntu 24.04+ (Debian ailesi desteklenir) |
| **CPU** | VT-x veya AMD-V sanallaştırma desteği (BIOS'tan etkin) |
| **RAM** | Minimum 8 GB (4 GB Windows VM + 4 GB Linux) |
| **Disk** | Minimum 80 GB boş alan |
| **İnternet** | Geniş bant (Windows ISO ~5-6 GB indirilir) |
| **GPU** | — |

> ⚠️ **Önemli:** Windows 10/11 **Home** sürümü RDP desteklemez. Sadece **Pro**, **Enterprise** veya **Server** kullanın. Windows 11 varsayılan olarak Pro sürümüdür.

### 🚀 Kurulum

#### 1. Scripti indirin

```bash
curl -fsSL https://raw.githubusercontent.com/KULLANICI_ADINIZ/ubuntu-winapps-setup/main/ubuntu-full-setup.sh \
  -o ubuntu-full-setup.sh
```

#### 2. Çalıştırın

```bash
chmod +x ubuntu-full-setup.sh
./ubuntu-full-setup.sh
```

#### 3. Dil ve mod seçin

```
Language / Dil:
[1] Türkçe
[2] English

Ne yapmak istersiniz?
[1] Kurulum   — GNOME + Touchpad + WinApps + Yenileme Sistemi
[2] Kaldırma  — Her şeyi temizle (Windows VM dahil)
[3] Çıkış
```

### 📂 Kurulum Sonrası Dosya Konumları

```
/etc/winapps/
├── winapps.conf          # WinApps bağlantı ayarları
├── compose.yaml          # Docker VM yapılandırması
└── oem/                  # Windows RDP otomatik yapılandırma

/etc/dconf/db/local.d/
├── 00-gnome-shell        # Aktif GNOME extension'lar
├── 01-touchpad           # Touchpad ayarı
└── 02-gnome-misc         # Genel GNOME ayarları

/usr/local/bin/
├── winapps               # Ana WinApps komutu
├── winapps-setup         # Uygulama kurulum/kaldırma
├── winapps-refresh       # Uygulama listesi yenileme
└── winapps-refresh-gui   # GUI launcher

/usr/share/applications/  # Tüm kullanıcıların programlar menüsü
├── winapps-refresh.desktop
├── word.desktop          # (Windows'a kurulu ise)
└── ...
```

### 💻 WinApps Kullanımı

```bash
# Tam Windows masaüstü (RDP)
winapps windows

# Manuel uygulama başlat
winapps manual "notepad.exe"

# Windows uygulaması ekle (Windows'a kurduktan sonra)
winapps-refresh
# veya programlar menüsünden: "WinApps — Uygulamaları Yenile"
```

### 🖥️ Windows VM Yönetimi

```bash
# VNC arayüzü (tarayıcıdan)
# http://127.0.0.1:8006

# VM başlat/durdur/yeniden başlat
docker compose --file /etc/winapps/compose.yaml start
docker compose --file /etc/winapps/compose.yaml stop
docker compose --file /etc/winapps/compose.yaml restart
```

### 🔄 Yenileme Sistemi

Windows'a yeni bir program kurduktan sonra Linux programlar menüsüne eklemek için:

```bash
# Terminal ile
winapps-refresh

# Veya uygulamalar menüsünden
# "WinApps — Uygulamaları Yenile" → tıkla
```

### 🗑️ Kaldırma

Scripti çalıştırıp `[2] Kaldırma` seçeneğini seçin:

```bash
./ubuntu-full-setup.sh
# → [2] Kaldırma
```

Veya sadece Windows VM'i sıfırlamak için:

```bash
docker compose --file /etc/winapps/compose.yaml down --rmi=all --volumes
```

### ❓ Sık Sorulan Sorular

<details>
<summary><b>Windows dosyalarıma Linux'tan nasıl erişirim?</b></summary>

`winapps windows` ile RDP masaüstü açın, Dosya Gezgini'nde `\\tsclient\home` adresine gidin. Linux home dizininiz doğrudan görünür.

</details>

<details>
<summary><b>"Another user is signed in" hatası alıyorum</b></summary>

Windows'ta kullanıcı oturumu açık. `http://127.0.0.1:8006` adresine gidin → Başlat → Sign out yapın → WinApps kurulumunu tekrar çalıştırın.

</details>

<details>
<summary><b>Dash to Panel ve Dash to Dock aynı anda çalışabilir mi?</b></summary>

Hayır, ikisi çakışır. Extension Manager'dan birini seçip diğerini devre dışı bırakın.

</details>

<details>
<summary><b>Windows Home sürümü çalışır mı?</b></summary>

Hayır. RDP yalnızca Windows Pro, Enterprise ve Server sürümlerinde çalışır. Varsayılan Windows 11 kurulumu Pro sürümüdür.

</details>

---

## 🇬🇧 English

### 📋 Overview

This script **automatically** installs and configures the following on Ubuntu:

| Section | Content |
|---------|---------|
| **GNOME Tools** | GNOME Tweaks, dconf-editor, Extension Manager, Dash to Panel, Dash to Dock |
| **Touchpad** | Auto-disable touchpad when USB mouse is connected (all users) |
| **WinApps** | Docker + KVM + Windows VM + system-wide WinApps installation |
| **Refresh** | `winapps-refresh` command + app menu shortcut + systemd timer |

### ✨ Features

- 🌐 **Turkish/English** bilingual support
- 👥 **All users** installation (`/usr/share/applications`, system-wide)
- 🔄 **Smart detection** — skips already installed packages
- 🪟 **Turkish Windows** — Turkish ISO downloaded directly from Microsoft
- 🔒 **Secure** — Windows credentials stored safely in system config
- ♻️ **Re-runnable** — cleans existing installation and reinstalls
- 🗑️ **Full uninstall** — removes everything including Docker, WinApps, and GNOME tools

### 🖥️ System Requirements

| Requirement | Detail |
|------------|--------|
| **OS** | Ubuntu 24.04+ (Debian family supported) |
| **CPU** | VT-x or AMD-V virtualization (enabled in BIOS) |
| **RAM** | Minimum 8 GB (4 GB Windows VM + 4 GB Linux) |
| **Disk** | Minimum 80 GB free space |
| **Internet** | Broadband (Windows ISO ~5-6 GB download) |

> ⚠️ **Important:** Windows 10/11 **Home** does not support RDP. Use only **Pro**, **Enterprise**, or **Server**. Windows 11 defaults to Pro.

### 🚀 Installation

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/KULLANICI_ADINIZ/ubuntu-winapps-setup/main/ubuntu-full-setup.sh \
  -o ubuntu-full-setup.sh

# Run
chmod +x ubuntu-full-setup.sh
./ubuntu-full-setup.sh
```

### 💻 WinApps Usage

```bash
# Full Windows desktop (RDP)
winapps windows

# Launch app manually
winapps manual "notepad.exe"

# Add new Windows apps to Linux menu
winapps-refresh
```

### 🗑️ Uninstall

```bash
./ubuntu-full-setup.sh
# → [2] Uninstall
```

---

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md)

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## 📄 License

[MIT](LICENSE) © 2026

## 🙏 Credits

- [WinApps](https://github.com/winapps-org/winapps) — Windows apps on Linux
- [dockur/windows](https://github.com/dockur/windows) — Windows in Docker
