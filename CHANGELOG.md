# Changelog

All notable changes to this project will be documented in this file.  
Bu projedeki tüm önemli değişiklikler bu dosyada belgelenir.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

---

## [v6.0.0] - 2026-05-04

### Added / Eklendi
- 🌐 Türkçe/İngilizce (TR/EN) bilingual support / dil desteği
- 🗑️ Complete uninstall mode / Tam kaldırma modu (`[2] Kaldırma`)
- 🪟 Windows language selection / Windows dil seçimi (Türkçe/İngilizce ISO)
- 🔄 Main menu (Install / Uninstall / Exit) / Ana menü (Kur / Kaldır / Çıkış)
- 🔒 `detect_language()` — auto-detect system language / sistem dilini otomatik tespit

### Fixed / Düzeltildi
- Docker socket symlink for WinApps compatibility / WinApps uyumluluğu için Docker socket symlink
- `DOCKER_HOST` environment variable passed via `sudo -E` / `sudo -E` ile DOCKER_HOST aktarımı
- `winapps.conf` file permissions (644) for all users / Tüm kullanıcılar için dosya izinleri
- FreeRDP certificate cleanup on reinstall / Yeniden kurulumda FreeRDP sertifika temizleme

---

## [v5.0.0] - 2026-05-03

### Added / Eklendi
- 🔄 `winapps-refresh` command and desktop shortcut / komut ve masaüstü kısayolu
- ⏱️ Optional systemd timer for automatic app refresh / İsteğe bağlı otomatik yenileme timer
- 🧹 `cleanup_existing()` — clears old config on re-run / Yeniden çalıştırmada eski config temizleme
- 🖥️ Windows VM detection on startup / Başlangıçta Windows VM tespiti
- OEM AutoSignOut — auto sign-out via Task Scheduler / Görev Zamanlayıcı ile otomatik oturum kapatma

### Fixed / Düzeltildi
- `sg docker` not found on some Ubuntu installs / Bazı Ubuntu kurulumlarında `sg` bulunamıyor
- Docker compose file path quoting issue / Docker compose dosya yolu tırnak sorunu
- `set -e` + `[[ ]] &&` pattern causing silent exit / Sessiz çıkışa neden olan pattern
- `DISTRO_ID_LIKE` syntax error with `set -u` / `set -u` ile syntax hatası

---

## [v4.0.0] - 2026-05-02

### Added / Eklendi
- Windows VM existence check before install / Kurulum öncesi Windows VM varlık kontrolü
- OEM `RDPApps.reg` + `install.bat` for automatic RDP config / Otomatik RDP yapılandırması
- HOME volume mount in compose.yaml / compose.yaml'da HOME volume mount
- Post-install OEM disable and container restart / Kurulum sonrası OEM devre dışı

### Fixed / Düzeltildi
- `setup.sh` must run without `sudo` (HOME=/root issue) / `sudo` olmadan çalıştırma (HOME sorunu)
- All users + `/etc/skel` + root symlinks / Tüm kullanıcılar + /etc/skel + root symlink'leri
- `qemu-kvm` virtual package on Ubuntu 25.04+ / Ubuntu 25.04+'ta sanal paket sorunu

---

## [v3.0.0] - 2026-05-01

### Added / Eklendi
- Touchpad auto-disable via dconf system override / dconf override ile touchpad otomatik kapatma
- GNOME Tweaks, dconf-editor, Extension Manager (Flatpak)
- Dash to Panel (GitHub releases) + Dash to Dock (apt/GitHub)
- System-wide WinApps install (`--system`) → `/usr/share/applications`
- All users added to docker group / Tüm kullanıcılar docker grubuna eklendi

---

## [v2.0.0] - 2026-04-30

### Added / Eklendi
- Docker Engine official installation / Resmi Docker Engine kurulumu
- KVM + qemu-kvm + iptables setup / KVM kurulumu
- Multi-distro support: Debian/Ubuntu, Fedora, Arch, openSUSE

---

## [v1.0.0] - 2026-04-29

### Added / Eklendi
- Initial release / İlk sürüm
- Basic WinApps Docker setup script / Temel WinApps Docker kurulum scripti
