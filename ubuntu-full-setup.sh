#!/usr/bin/env bash
# ==============================================================================
#  Ubuntu Full System Setup Script v6
#  Türkçe/English — TR/EN bilingual support
#  ─────────────────────────────────────────────────────────────────────────────
#  SECTIONS / BÖLÜMLER:
#   1 — GNOME Tools (Tweaks, dconf-editor, Extension Manager, Dash to Panel/Dock)
#   2 — Touchpad (auto-disable on external mouse / USB fare takılınca kapat)
#   3 — WinApps  (KVM + Docker + Windows VM)
#   4 — App Refresh System / Uygulama Yenileme Sistemi
#
#  MODES / MODLAR:
#   install   — Full installation / Tam kurulum
#   uninstall — Complete removal   / Tam kaldırma
#
#  Usage / Kullanım:
#    chmod +x ubuntu-full-setup.sh
#    ./ubuntu-full-setup.sh
# ==============================================================================

set -euo pipefail

# ─────────────────────────────────────────────
# Sabitler
# ─────────────────────────────────────────────
readonly WINAPPS_ETC_DIR="/etc/winapps"
readonly WINAPPS_CONF="${WINAPPS_ETC_DIR}/winapps.conf"
readonly WINAPPS_COMPOSE="${WINAPPS_ETC_DIR}/compose.yaml"
readonly WINAPPS_OEM_DIR="${WINAPPS_ETC_DIR}/oem"
readonly WINAPPS_SKEL_DIR="/etc/skel/.config/winapps"
readonly REFRESH_BIN="/usr/local/bin/winapps-refresh"
readonly REFRESH_DESKTOP="/usr/share/applications/winapps-refresh.desktop"
readonly REFRESH_LAUNCHER="/usr/local/bin/winapps-refresh-gui"
readonly EXT_DASH_TO_PANEL="dash-to-panel@jderose9.github.com"
readonly EXT_DASH_TO_DOCK="dash-to-dock@micxgx.gmail.com"
readonly DCONF_DIR="/etc/dconf/db/local.d"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ─────────────────────────────────────────────
# Renkler ve yardımcı fonksiyonlar
# ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ─────────────────────────────────────────────
# Dil / Language (tr | en)
# Sistem dilinden otomatik tespit, override edilebilir
# ─────────────────────────────────────────────
SCRIPT_LANG="tr"  # Varsayılan / Default

detect_language() {
  local sys_lang="${LANG:-}"
  if [[ "$sys_lang" =~ ^tr ]]; then
    SCRIPT_LANG="tr"
  else
    SCRIPT_LANG="en"
  fi
}

# msg <türkçe> <english> — aktif dile göre mesaj döndürür
msg() { [[ "$SCRIPT_LANG" == "tr" ]] && echo -e "$1" || echo -e "$2"; }

# Bilingual yardımcı fonksiyonlar
info()    {
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo -e "  ${CYAN}[BİLGİ]${NC}  $*"
  else
    echo -e "  ${CYAN}[INFO]${NC}   $*"
  fi
}
success() { echo -e "  ${GREEN}[OK]${NC}     $*"; }
warn()    {
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo -e "  ${YELLOW}[UYARI]${NC} $*"
  else
    echo -e "  ${YELLOW}[WARN]${NC}  $*"
  fi
}
error()   {
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo -e "  ${RED}[HATA]${NC}   $*" >&2
  else
    echo -e "  ${RED}[ERROR]${NC}  $*" >&2
  fi
  exit 1
}
step()    {
  echo -e "\n${BOLD}${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}${CYAN}│  $*${NC}"
  echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────────┘${NC}"
}

banner() {
  echo -e "${BOLD}${CYAN}"
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║       Ubuntu Tam Sistem Kurulum Scripti v6                        ║"
    echo "║   GNOME + Touchpad + WinApps + Uygulama Yenileme  [TR/EN]        ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  else
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║       Ubuntu Full System Setup Script v6                          ║"
    echo "║   GNOME + Touchpad + WinApps + App Refresh System  [TR/EN]        ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  fi
  echo -e "${NC}"
}

confirm() {
  local msg="$1" default="${2:-y}" prompt
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    [[ "$default" == "y" ]] && prompt="[E/h]" || prompt="[e/H]"
  else
    [[ "$default" == "y" ]] && prompt="[Y/n]" || prompt="[y/N]"
  fi
  read -rp "$(echo -e "  ${YELLOW}${msg} ${prompt}: ${NC}")" ans
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[EeYyHh]$ ]] && [[ ! "$ans" =~ ^[Hh]$ ]] ||   { [[ "$ans" =~ ^[EeYy]$ ]]; }
}

ask() {
  local var="$1" msg="$2" default="${3:-}" val
  read -rp "$(echo -e "  ${CYAN}${msg}${default:+ [varsayılan: $default]}: ${NC}")" val
  printf -v "$var" '%s' "${val:-$default}"
}

ask_password() {
  local var="$1" msg="$2"
  while true; do
    read -rsp "$(echo -e "  ${CYAN}${msg}: ${NC}")" p1; echo
    read -rsp "$(echo -e "  ${CYAN}Tekrar girin: ${NC}")" p2; echo
    [[ "$p1" == "$p2" ]] && { printf -v "$var" '%s' "$p1"; break; }
    warn "Parolalar eşleşmedi, tekrar deneyin."
  done
}

# ── docker compose çalıştırıcı ───────────────────────────────────
# "$@" ile argümanlar doğru aktarılır, tırnak sorunları olmaz.
# sg varsa docker grubunu re-login olmadan aktif eder.
# sg yoksa sudo ile çalışır.
docker_compose_run() {
  if command -v sg &>/dev/null; then
    # sg için argümanları güvenli string'e çevir
    local args
    args=$(printf '%q ' "$@")
    sg docker -c "docker compose $args"
  else
    sudo docker compose "$@"
  fi
}

# ── sg veya sudo ile bash komutu çalıştır ────────────────────────
docker_sg_run() {
  # $1 = script dosyası, $2.. = argümanlar
  local script="$1"; shift
  local args="$*"
  if command -v sg &>/dev/null; then
    sg docker -c "bash '$script' $args"
  else
    sudo bash "$script" $args
  fi
}

# ══════════════════════════════════════════════════════════════════
#  ÖN KOŞULLAR
# ══════════════════════════════════════════════════════════════════
detect_distro() {
  [[ -f /etc/os-release ]] || error "/etc/os-release bulunamadı."
  # shellcheck source=/dev/null
  source /etc/os-release

  DISTRO_ID="${ID,,}"

  # ── BUG2 DÜZELTİLDİ ──────────────────────────────────────────
  # Eski (hatalı): DISTRO_ID_LIKE="${ID_LIKE,,:-}"
  # Yeni: iki adımda, set -u ile güvenli
  DISTRO_ID_LIKE="${ID_LIKE:-}"   # tanımsızsa boş string
  DISTRO_ID_LIKE="${DISTRO_ID_LIKE,,}"  # küçük harfe çevir

  case "$DISTRO_ID" in
    ubuntu|debian|linuxmint|pop|elementary) DISTRO_FAMILY="debian"   ;;
    fedora|rhel|centos|rocky|alma)          DISTRO_FAMILY="fedora"   ;;
    arch|manjaro|endeavouros|garuda)        DISTRO_FAMILY="arch"     ;;
    opensuse*|sles)                         DISTRO_FAMILY="opensuse" ;;
    *)
      if   [[ "$DISTRO_ID_LIKE" == *debian*  ]]; then DISTRO_FAMILY="debian"
      elif [[ "$DISTRO_ID_LIKE" == *fedora*  || "$DISTRO_ID_LIKE" == *rhel* ]]; then
        DISTRO_FAMILY="fedora"
      elif [[ "$DISTRO_ID_LIKE" == *arch*    ]]; then DISTRO_FAMILY="arch"
      else
        warn "Dağıtım tanımlanamadı: '$DISTRO_ID' — Debian varsayılıyor."
        DISTRO_FAMILY="debian"
      fi ;;
  esac

  success "Dağıtım: ${DISTRO_ID} (${DISTRO_FAMILY} ailesi)"
}

check_prerequisites() {
  step "Ön Koşul Kontrolü"
  if [[ "$EUID" -eq 0 ]]; then
    error "Root olarak çalıştırmayın. Sudo yetkili normal kullanıcı ile çalıştırın."
  fi
  command -v sudo &>/dev/null || error "'sudo' bulunamadı."
  sudo -v || error "sudo yetkisi alınamadı."
  info "Kullanıcı : ${REAL_USER}"
  info "Home      : ${REAL_HOME}"
  detect_distro
  success "Ön koşullar geçti."
}


# ══════════════════════════════════════════════════════════════════
#  MEVCUT KURULUM DOSYALARINI TEMİZLE
#  Script her çalıştığında eski config dosyaları silinir,
#  ardından yeniden oluşturulur. Böylece çakışma olmaz.
# ══════════════════════════════════════════════════════════════════
cleanup_existing() {
  step "Mevcut Kurulum Dosyaları Temizleniyor"

  # ── Windows VM varlık kontrolü ────────────────────────────────
  # Docker kurulu ve WinApps container/volume mevcut mu?
  local vm_exists=0
  local vm_running=0
  local has_volume=0

  if command -v docker &>/dev/null; then
    # Container var mı? (çalışıyor veya durmuş)
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^WinApps$"; then
      vm_exists=1
      # Şu an çalışıyor mu?
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^WinApps$"; then
        vm_running=1
      fi
    elif sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^WinApps$"; then
      vm_exists=1
      if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^WinApps$"; then
        vm_running=1
      fi
    fi

    # Volume var mı? (Windows disk verisi)
    if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^winapps_data$" ||        sudo docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^winapps_data$"; then
      has_volume=1
    fi
  fi

  if [[ $vm_exists -eq 1 ]] || [[ $has_volume -eq 1 ]]; then
    echo ""
    echo -e "  ${BOLD}${YELLOW}⚠️  Mevcut Windows VM Tespit Edildi!${NC}"
    echo "  ──────────────────────────────────────────────────────"

    if [[ $vm_running -eq 1 ]]; then
      echo -e "  Durum  : ${GREEN}ÇALIŞIYOR${NC}"
    else
      echo -e "  Durum  : ${YELLOW}DURDURULMUŞ${NC}"
    fi

    if [[ $has_volume -eq 1 ]]; then
      local vol_size
      vol_size=$(sudo du -sh /var/lib/docker/volumes/winapps_data 2>/dev/null | cut -f1 || echo "?")
      echo -e "  Disk   : ${CYAN}winapps_data${NC} (~${vol_size})"
    fi

    echo ""
    echo "  Ne yapmak istersiniz?"
    echo ""
    echo -e "  ${BOLD}[1]${NC} Mevcut Windows'u SİL, sıfırdan kur"
    echo -e "      ${RED}(Dikkat: Windows diski ve tüm veriler kalıcı silinir!)${NC}"
    echo ""
    echo -e "  ${BOLD}[2]${NC} Mevcut Windows'u KORU, sadece config/ayarları güncelle"
    echo -e "      ${GREEN}(Windows kurulu ve ayarları korunur, sadece WinApps config yenilenir)${NC}"
    echo ""
    echo -e "  ${BOLD}[3]${NC} İptal et, çık"
    echo ""

    local choice=""
    while true; do
      read -rp "$(echo -e "  ${YELLOW}Seçiminiz [1/2/3]: ${NC}")" choice
      case "$choice" in
        1)
          echo ""
          warn "Windows VM ve tüm veriler SİLİNECEK!"
          if confirm "Emin misiniz? Bu işlem GERİ ALINAMAZ" "n"; then
            info "Windows VM durduruluyor ve siliniyor..."
            if command -v docker &>/dev/null; then
              docker compose --file "$WINAPPS_COMPOSE" down --volumes 2>/dev/null || true
              sudo docker compose --file "$WINAPPS_COMPOSE" down --volumes 2>/dev/null || true
              docker rm -f WinApps 2>/dev/null || sudo docker rm -f WinApps 2>/dev/null || true
              docker volume rm winapps_data 2>/dev/null || sudo docker volume rm winapps_data 2>/dev/null || true
            fi
            success "Windows VM ve disk verisi silindi. Sıfırdan kurulum yapılacak."
          else
            info "Silme iptal edildi. Seçim yapın:"
            continue
          fi
          break
          ;;
        2)
          echo ""
          info "Mevcut Windows korunuyor. Sadece config dosyaları güncellenecek."
          if [[ $vm_running -eq 0 ]]; then
            info "Windows VM başlatılıyor..."
            docker compose --file "$WINAPPS_COMPOSE" up -d 2>/dev/null ||               sudo docker compose --file "$WINAPPS_COMPOSE" up -d 2>/dev/null || true
          fi
          break
          ;;
        3)
          echo ""
          info "İptal edildi."
          exit 0
          ;;
        *)
          warn "Geçersiz seçim. 1, 2 veya 3 girin."
          ;;
      esac
    done
    echo ""
  fi

  # ── WinApps config dosyaları ──────────────────────────────────
  if [[ -f "$WINAPPS_CONF" ]] || [[ -f "$WINAPPS_COMPOSE" ]]; then
    info "Eski WinApps config dosyaları siliniyor..."
    sudo rm -f "$WINAPPS_CONF" "$WINAPPS_COMPOSE"
    sudo rm -rf "$WINAPPS_OEM_DIR"
    success "WinApps config temizlendi."
  fi

  # ── dconf override dosyaları ──────────────────────────────────
  if [[ -d "$DCONF_DIR" ]]; then
    info "Eski dconf override dosyaları siliniyor..."
    sudo rm -f       "${DCONF_DIR}/00-gnome-shell"       "${DCONF_DIR}/01-touchpad"       "${DCONF_DIR}/02-gnome-misc"
    sudo dconf update 2>/dev/null || true
    success "dconf override temizlendi."
  fi

  # ── Kullanıcı symlink'leri ────────────────────────────────────
  info "Eski config symlink'leri temizleniyor..."

  # /etc/skel
  sudo rm -f     "${WINAPPS_SKEL_DIR}/winapps.conf"     "${WINAPPS_SKEL_DIR}/compose.yaml" 2>/dev/null || true

  # root
  sudo rm -f     "/root/.config/winapps/winapps.conf"     "/root/.config/winapps/compose.yaml" 2>/dev/null || true

  # Tüm kullanıcılar (UID >= 1000)
  while IFS=: read -r uname _ uid _ _ uhome ushell; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      sudo rm -f         "${uhome}/.config/winapps/winapps.conf"         "${uhome}/.config/winapps/compose.yaml" 2>/dev/null || true
    fi
  done < /etc/passwd

  success "Symlink'ler temizlendi."

  # ── winapps-refresh dosyaları ─────────────────────────────────
  sudo rm -f     "$REFRESH_BIN"     "$REFRESH_DESKTOP"     "$REFRESH_LAUNCHER" 2>/dev/null || true

  # ── Systemd timer/service ─────────────────────────────────────
  if systemctl is-enabled winapps-refresh.timer &>/dev/null 2>&1; then
    sudo systemctl disable --now winapps-refresh.timer 2>/dev/null || true
    sudo rm -f       /etc/systemd/system/winapps-refresh.timer       /etc/systemd/system/winapps-refresh.service
    sudo systemctl daemon-reload
    info "Eski systemd timer temizlendi."
  fi

  success "Temizlik tamamlandı — yeniden kurulum başlıyor."
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 1 — GNOME ARAÇLARI
# ══════════════════════════════════════════════════════════════════
install_gnome_tools() {
  step "BÖLÜM 1A — GNOME Araçları"

  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-get update -y -qq
      sudo apt-get install -y gnome-tweaks dconf-editor dconf-cli
      # gnome-software-plugin-flatpak tüm sürümlerde olmayabilir
      sudo apt-get install -y flatpak gnome-software-plugin-flatpak 2>/dev/null \
        || sudo apt-get install -y flatpak
      ;;
    fedora)   sudo dnf install -y gnome-tweaks dconf-editor flatpak ;;
    arch)     sudo pacman -Syu --needed --noconfirm gnome-tweaks dconf flatpak ;;
    opensuse) sudo zypper install -y gnome-tweaks dconf-editor flatpak ;;
  esac
  success "GNOME Tweaks + dconf-editor + Flatpak kuruldu."

  # Flathub deposu
  sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

  # ── BUG3 DÜZELTİLDİ ─────────────────────────────────────────
  # Eski: flatpak install flathub ... -y
  # Yeni: --noninteractive eklendi (sıfır Ubuntu'da onay istemez)
  flatpak install flathub com.mattjakeman.ExtensionManager \
    --noninteractive -y 2>/dev/null \
    && success "Extension Manager (Flatpak) kuruldu." \
    || warn "Extension Manager kurulamadı. Sonradan: flatpak install flathub com.mattjakeman.ExtensionManager"
}

install_dash_to_dock() {
  step "BÖLÜM 1B — Dash to Dock"

  local EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_DASH_TO_DOCK}"
  if [[ -d "$EXT_DIR" ]]; then info "Dash to Dock zaten kurulu."; return; fi

  # Önce apt dene (eski Ubuntu sürümleri için)
  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    if sudo apt-get install -y gnome-shell-extension-dash-to-dock 2>/dev/null; then
      success "Dash to Dock apt ile kuruldu."
      return
    fi
  fi

  # GitHub releases'den indir (gnome.org yeni GNOME sürümleri için geç güncellenir)
  info "Dash to Dock GitHub'dan indiriliyor..."
  local TMP_ZIP="/tmp/dash-to-dock.zip"
  local LATEST_URL=""
  LATEST_URL=$(curl -fsSL https://api.github.com/repos/micheleg/dash-to-dock/releases/latest \
    2>/dev/null | grep "browser_download_url.*zip" | head -1 | cut -d'"' -f4 || true)

  if [[ -n "$LATEST_URL" ]]; then
    curl -fsSL "$LATEST_URL" -o "$TMP_ZIP"
    sudo mkdir -p "$EXT_DIR"
    sudo unzip -o "$TMP_ZIP" -d "$EXT_DIR" >/dev/null
    rm -f "$TMP_ZIP"
    success "Dash to Dock kuruldu: $EXT_DIR"
  else
    # Son çare: doğrudan zip URL
    info "GitHub releases bulunamadı, main branch'ten indiriliyor..."
    local ZIP_URL="https://github.com/micheleg/dash-to-dock/archive/refs/heads/master.zip"
    curl -fsSL "$ZIP_URL" -o "$TMP_ZIP" 2>/dev/null || {
      warn "Dash to Dock indirilemedi. Extension Manager'dan manuel kurabilirsiniz."
      return
    }
    local TMP_DIR; TMP_DIR=$(mktemp -d)
    sudo unzip -o "$TMP_ZIP" -d "$TMP_DIR" >/dev/null
    sudo mkdir -p "$EXT_DIR"
    sudo cp -r "${TMP_DIR}/dash-to-dock-master/." "$EXT_DIR/"
    rm -rf "$TMP_DIR" "$TMP_ZIP"
    success "Dash to Dock kuruldu (main branch): $EXT_DIR"
  fi
}

install_dash_to_panel() {
  step "BÖLÜM 1C — Dash to Panel"
  local EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_DASH_TO_PANEL}"
  if [[ -d "$EXT_DIR" ]]; then info "Zaten kurulu."; return; fi

  local TMP_ZIP="/tmp/dash-to-panel.zip"
  local LATEST_URL=""

  # GitHub Releases - en güncel sürüm
  info "Dash to Panel GitHub'dan indiriliyor..."
  LATEST_URL=$(curl -fsSL https://api.github.com/repos/home-sweet-gnome/dash-to-panel/releases/latest \
    2>/dev/null | grep "browser_download_url.*zip" | head -1 | cut -d'"' -f4 || true)

  if [[ -n "$LATEST_URL" ]]; then
    curl -fsSL "$LATEST_URL" -o "$TMP_ZIP"
    sudo mkdir -p "$EXT_DIR"
    sudo unzip -o "$TMP_ZIP" -d "$EXT_DIR" >/dev/null
    rm -f "$TMP_ZIP"
    success "Dash to Panel kuruldu: $EXT_DIR"
  else
    # Son çare: main branch zip
    info "GitHub releases bulunamadı, main branch'ten indiriliyor..."
    local ZIP_URL="https://github.com/home-sweet-gnome/dash-to-panel/archive/refs/heads/master.zip"
    curl -fsSL "$ZIP_URL" -o "$TMP_ZIP" 2>/dev/null || {
      warn "Dash to Panel indirilemedi. Extension Manager'dan manuel kurabilirsiniz."
      return
    }
    local TMP_DIR; TMP_DIR=$(mktemp -d)
    sudo unzip -o "$TMP_ZIP" -d "$TMP_DIR" >/dev/null
    sudo mkdir -p "$EXT_DIR"
    sudo cp -r "${TMP_DIR}/dash-to-panel-master/." "$EXT_DIR/"
    rm -rf "$TMP_DIR" "$TMP_ZIP"
    success "Dash to Panel kuruldu (main branch): $EXT_DIR"
  fi
}

_install_ext_from_gnome_org() {
  local UUID="$1"
  local EXT_DIR="/usr/share/gnome-shell/extensions/${UUID}"
  local TMP_ZIP="/tmp/${UUID}.zip"
  local GNOME_VER
  GNOME_VER=$(gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "45")
  local URL="https://extensions.gnome.org/download-extension/${UUID}.shell-extension.zip?shell_version=${GNOME_VER}"
  curl -fsSL "$URL" -o "$TMP_ZIP" 2>/dev/null || { warn "İndirilemedi: $UUID"; return; }
  sudo mkdir -p "$EXT_DIR"
  sudo unzip -o "$TMP_ZIP" -d "$EXT_DIR" >/dev/null
  rm -f "$TMP_ZIP"
  success "Extension kuruldu: $UUID"
}

apply_dconf_system_overrides() {
  step "BÖLÜM 1D — dconf Sistem Override (Tüm Kullanıcılar)"
  sudo mkdir -p "$DCONF_DIR" "${DCONF_DIR}/locks"

  # Extension'lar (Dash to Panel varsayılan aktif)
  # Dash to Panel ve Dash to Dock aynı anda tam çalışmaz — Extension Manager'dan birini seçin
  sudo tee "${DCONF_DIR}/00-gnome-shell" >/dev/null <<'EOF'
[org/gnome/shell]
enabled-extensions=['dash-to-panel@jderose9.github.com', 'dash-to-dock@micxgx.gmail.com']
disable-user-extensions=false
EOF

  # Genel GNOME kolaylıkları
  sudo tee "${DCONF_DIR}/02-gnome-misc" >/dev/null <<'EOF'
[org/gnome/desktop/interface]
clock-show-seconds=true
clock-show-weekday=true
show-battery-percentage=true

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'

[org/gnome/mutter]
edge-tiling=true
EOF

  sudo dconf update
  success "dconf sistem override uygulandı."
  info "Konum: /etc/dconf/db/local.d/ — Tüm kullanıcılara otomatik uygulanır."
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 2 — TOUCHPAD
# ══════════════════════════════════════════════════════════════════
configure_touchpad() {
  step "BÖLÜM 2 — Touchpad (USB Fare → Touchpad Kapat)"

  sudo mkdir -p "$DCONF_DIR"
  sudo tee "${DCONF_DIR}/01-touchpad" >/dev/null <<'EOF'
[org/gnome/desktop/peripherals/touchpad]
send-events='disabled-on-external-mouse'
EOF

  sudo dconf update
  success "Touchpad ayarı uygulandı (tüm kullanıcılar)."

  # Mevcut oturumda da anlık uygula
  local SCHEMA="org.gnome.desktop.peripherals.touchpad"
  if command -v gsettings &>/dev/null && \
     gsettings list-schemas 2>/dev/null | grep -q "$SCHEMA"; then
    gsettings set "$SCHEMA" send-events 'disabled-on-external-mouse' 2>/dev/null \
      && info "Mevcut oturuma anlık uygulandı." || true
  fi
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 3 — WinApps
# ══════════════════════════════════════════════════════════════════
install_kvm() {
  step "BÖLÜM 3A — KVM Kontrolü ve Kurulumu"

  grep -qE '(vmx|svm)' /proc/cpuinfo \
    || error "CPU sanallaştırma (VT-x/AMD-V) bulunamadı. BIOS/UEFI'dan etkinleştirin."
  success "CPU sanallaştırma mevcut."

  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-get update -y -qq
      # Ubuntu 24.10+ ve bazı yeni sürümlerde qemu-kvm sanal paket oldu
      # qemu-system-x86 veya qemu-system-x86-hwe kullanılmalı
      local QEMU_PKG="qemu-system-x86"
      if apt-cache show qemu-kvm 2>/dev/null | grep -q "^Package: qemu-kvm$"; then
        QEMU_PKG="qemu-kvm"
      fi
      sudo apt-get install -y "$QEMU_PKG" libvirt-daemon-system \
                               libvirt-clients bridge-utils cpu-checker
      ;;
    fedora)
      sudo dnf install -y qemu-kvm libvirt libvirt-daemon-config-network \
                          virt-install bridge-utils
      ;;
    arch)
      sudo pacman -Syu --needed --noconfirm qemu-base libvirt bridge-utils dnsmasq
      ;;
    opensuse)
      sudo zypper install -y qemu-kvm libvirt libvirt-daemon-qemu bridge-utils
      ;;
  esac

  sudo modprobe kvm 2>/dev/null || true
  grep -q 'vmx' /proc/cpuinfo \
    && sudo modprobe kvm_intel 2>/dev/null || true \
    || sudo modprobe kvm_amd   2>/dev/null || true

  [[ -e /dev/kvm ]] || error "/dev/kvm oluşturulamadı. BIOS sanallaştırma ayarını kontrol edin."
  success "/dev/kvm hazır."
  command -v kvm-ok &>/dev/null \
    && { sudo kvm-ok && success "kvm-ok: KVM kullanılabilir." || warn "kvm-ok uyarı verdi."; }

  # iptables (docker.md: klasör paylaşımı için zorunlu)
  local changed=0
  lsmod | grep -q '^ip_tables'   || { sudo modprobe ip_tables;   changed=1; }
  lsmod | grep -q '^iptable_nat' || { sudo modprobe iptable_nat; changed=1; }
  if [[ $changed -eq 1 ]]; then
    printf 'ip_tables\niptable_nat\n' \
      | sudo tee /etc/modules-load.d/iptables.conf >/dev/null
    success "iptables modülleri yüklendi ve kalıcı hale getirildi."
  else
    success "iptables modülleri zaten aktif."
  fi
}

install_docker() {
  step "BÖLÜM 3B — Docker Engine + Compose Plugin"

  local docker_ok=0 compose_ok=0
  command -v docker &>/dev/null \
    && { success "Docker mevcut: $(docker --version)"; docker_ok=1; }
  docker compose version &>/dev/null 2>&1 \
    && { success "Compose plugin mevcut: $(docker compose version)"; compose_ok=1; }

  if [[ $docker_ok -eq 1 && $compose_ok -eq 1 ]]; then
    success "Docker zaten kurulu — atlanıyor."
    _docker_service_start
    _docker_socket_symlink
    return
  fi

  info "Docker Engine resmi yöntemle kuruluyor..."
  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-get update -y -qq
      sudo apt-get install -y ca-certificates curl gnupg lsb-release

      # Ubuntu türevi dağıtımlar
      local ddistro="$DISTRO_ID"
      [[ "$DISTRO_ID" =~ ^(linuxmint|pop|elementary)$ ]] && ddistro="ubuntu"

      # ── Eski çakışan GPG/repo dosyalarını temizle ─────────────
      # Çakışma: docker.gpg vs docker.asc, eski repo girişleri
      sudo rm -f         /etc/apt/keyrings/docker.gpg         /etc/apt/keyrings/docker.asc         /etc/apt/sources.list.d/docker.list         /etc/apt/sources.list.d/docker-ce.list 2>/dev/null || true
      sudo install -m 0755 -d /etc/apt/keyrings

      # ── Ubuntu sürüm → Docker repo codename tespiti ───────────
      # Docker resmi deposu her Ubuntu sürümünü desteklemez.
      # Desteklenmeyen sürümler (25.10/resolute vb.) için
      # önceki desteklenen sürüme (noble/24.04) fallback yap.
      local codename; codename=$(lsb_release -cs)
      local docker_codename="$codename"

      # Docker'ın desteklediği Ubuntu codename'leri
      local supported_codenames=("focal" "jammy" "mantic" "noble" "oracular" "plucky")
      local codename_supported=0
      for cn in "${supported_codenames[@]}"; do
        if [[ "$codename" == "$cn" ]]; then
          codename_supported=1
          break
        fi
      done

      if [[ $codename_supported -eq 0 ]]; then
        warn "Ubuntu '$codename' Docker resmi deposunda henüz yok."
        warn "Docker deposu için 'noble' (24.04 LTS) kullanılıyor..."
        docker_codename="noble"
      fi

      # ── GPG anahtarını ekle ───────────────────────────────────
      curl -fsSL "https://download.docker.com/linux/${ddistro}/gpg"         | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
      sudo chmod a+r /etc/apt/keyrings/docker.gpg

      # ── Depo ekle ─────────────────────────────────────────────
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ddistro} ${docker_codename} stable"         | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

      sudo apt-get update -y -qq
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io                                docker-buildx-plugin docker-compose-plugin         || {
          # Son çare: convenience script
          warn "Paket kurulumu başarısız, Docker convenience script deneniyor..."
          local TMP_DOCKER_INSTALL; TMP_DOCKER_INSTALL=$(mktemp /tmp/docker-install-XXXXX.sh)
          curl -fsSL https://get.docker.com -o "$TMP_DOCKER_INSTALL"
          sudo sh "$TMP_DOCKER_INSTALL"
          rm -f "$TMP_DOCKER_INSTALL"
        }
      ;;
    fedora)
      sudo dnf config-manager --add-repo \
        https://download.docker.com/linux/fedora/docker-ce.repo
      sudo dnf install -y docker-ce docker-ce-cli containerd.io \
                          docker-buildx-plugin docker-compose-plugin
      ;;
    arch)
      sudo pacman -Syu --needed --noconfirm docker docker-compose
      ;;
    opensuse)
      sudo zypper addrepo -f \
        https://download.docker.com/linux/opensuse/docker-ce.repo || true
      sudo zypper refresh
      sudo zypper install -y docker docker-compose
      ;;
  esac

  _docker_service_start
  success "Docker kuruldu: $(docker --version)"
}

_docker_socket_symlink() {
  # WinApps setup.sh Docker Desktop socket yolunu arar:
  # ~/.docker/desktop/docker.sock
  # Docker Engine kurulumunda bu yol olmaz, symlink oluşturuyoruz.
  info "Docker socket symlink oluşturuluyor (tüm kullanıcılar)..."

  # root için
  sudo mkdir -p /root/.docker/desktop
  sudo ln -sf /var/run/docker.sock /root/.docker/desktop/docker.sock

  # Tüm kullanıcılar için
  while IFS=: read -r uname _ uid _ _ uhome _; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      sudo mkdir -p "${uhome}/.docker/desktop"
      sudo ln -sf /var/run/docker.sock "${uhome}/.docker/desktop/docker.sock"
      sudo chown -R "${uname}:${uname}" "${uhome}/.docker" 2>/dev/null || true
    fi
  done < /etc/passwd

  # DOCKER_HOST sistem geneli — /etc/environment
  if ! grep -q "DOCKER_HOST" /etc/environment 2>/dev/null; then
    echo 'DOCKER_HOST=unix:///var/run/docker.sock' | sudo tee -a /etc/environment >/dev/null
  fi
  # Mevcut oturum için de set et
  export DOCKER_HOST=unix:///var/run/docker.sock

  success "Docker socket symlink oluşturuldu."
}

_docker_service_start() {
  sudo systemctl enable --now docker
  _docker_socket_symlink
  docker compose version &>/dev/null 2>&1 \
    || error "Docker Compose plugin hâlâ bulunamıyor."
}

add_all_users_to_docker() {
  step "BÖLÜM 3C — Tüm Kullanıcılar → Docker Grubu"
  getent group docker &>/dev/null || sudo groupadd docker

  local added=0
  while IFS=: read -r uname _ uid _ _ uhome ushell; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]] && \
       [[ "$ushell" =~ (bash|zsh|sh|fish)$ ]]; then
      if ! id -nG "$uname" | grep -qw docker; then
        sudo usermod -aG docker "$uname"
        success "  '$uname' docker grubuna eklendi."
        added=$((added + 1))
      else
        info "  '$uname' zaten docker grubunda."
      fi
    fi
  done < /etc/passwd

  if [[ $added -gt 0 ]]; then
    info "$added kullanıcı eklendi. Yeni oturumda tam aktif olur."
  fi
}

install_winapps_deps() {
  step "BÖLÜM 3D — WinApps Bağımlılıkları"
  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-get update -y -qq
      if [[ "$DISTRO_ID" == "debian" ]]; then
        local ver; ver=$(cut -d. -f1 /etc/debian_version 2>/dev/null || echo "0")
        if [[ "$ver" -ge 12 ]] && \
           ! grep -rq "bookworm-backports" /etc/apt/sources.list \
             /etc/apt/sources.list.d/ 2>/dev/null; then
          echo "deb http://deb.debian.org/debian bookworm-backports main" \
            | sudo tee /etc/apt/sources.list.d/bookworm-backports.list >/dev/null
          sudo apt-get update -y -qq
        fi
      fi
      sudo apt-get install -y \
        curl dialog freerdp3-x11 git iproute2 libnotify-bin netcat-openbsd
      ;;
    fedora)
      sudo dnf install -y curl dialog freerdp git iproute libnotify nmap-ncat
      ;;
    arch)
      sudo pacman -Syu --needed --noconfirm \
        curl dialog freerdp git iproute2 libnotify openbsd-netcat
      ;;
    opensuse)
      sudo zypper install -y \
        curl dialog freerdp git iproute2 libnotify-tools netcat-openbsd
      ;;
  esac
  success "WinApps bağımlılıkları kuruldu."
}

setup_oem() {
  step "BÖLÜM 3E — OEM (Windows RDP + Otomatik Sign-Out Yapılandırması)"
  sudo mkdir -p "$WINAPPS_OEM_DIR"

  # ── RDPApps.reg ───────────────────────────────────────────────
  # RDP'yi aktif eder, NLA'yı kapatır (şifresiz bağlantıya izin ver)
  # fSingleSessionPerUser=0 → birden fazla RDP oturumuna izin ver
  # AutoAdminLogon + DefaultDomainName → otomatik oturum açma KAPALI
  # LogonType=0 → interaktif oturum (WinApps için gerekli)
  sudo tee "${WINAPPS_OEM_DIR}/RDPApps.reg" >/dev/null <<'REGEOF'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services]
"fDenyTSConnections"=dword:00000000
"fSingleSessionPerUser"=dword:00000000
"TSEnabled"=dword:00000001
"TSUserEnabled"=dword:00000001
"MaxInstanceCount"=dword:00000064

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server]
"fDenyTSConnections"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp]
"UserAuthentication"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]
"AutoAdminLogon"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters]
"AutoShareWks"=dword:00000001
REGEOF

  # ── AutoSignOut.reg ───────────────────────────────────────────
  # Görev Zamanlayıcı ile sistem başlangıcında otomatik sign-out:
  # Konsol oturumu (VNC üzerindeki) varsa 30 saniye içinde kapatılır.
  # Böylece WinApps her zaman boş oturum bulur.
  sudo tee "${WINAPPS_OEM_DIR}/AutoSignOut.reg" >/dev/null <<'AUTORF'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]
"AutoAdminLogon"=dword:00000000
"ForceAutoLogon"=dword:00000000
AUTORF

  # ── AutoSignOut.ps1 ───────────────────────────────────────────
  # PowerShell: Konsol oturumu açıksa logoff yap
  # Bu script Görev Zamanlayıcı tarafından sistem başlangıcında çalıştırılır
  sudo tee "${WINAPPS_OEM_DIR}/AutoSignOut.ps1" >/dev/null <<'PSEOF'
# AutoSignOut.ps1 — Konsol oturumunu otomatik kapat
# WinApps'in RDP ile boş oturum bulmasını sağlar

$sessions = query session 2>&1
foreach ($line in $sessions) {
    # Console oturumu bul (VNC/fiziksel ekran oturumu)
    if ($line -match "console\s+(\d+)\s+(Active|Bağlı)") {
        $sessionId = $Matches[1]
        Write-Host "Konsol oturumu bulundu (ID: $sessionId), kapatılıyor..."
        # 5 saniye bekle (sistem tam açılsın)
        Start-Sleep -Seconds 5
        logoff $sessionId
        Write-Host "Oturum kapatıldı."
    }
}
PSEOF

  # ── install.bat ───────────────────────────────────────────────
  # Windows ilk açılışında dockur/windows tarafından çalıştırılır.
  # 1. Registry ayarlarını uygula (RDP, NLA, çoklu oturum)
  # 2. Güvenlik duvarında RDP portunu aç
  # 3. Görev Zamanlayıcı'ya AutoSignOut görevini ekle
  #    → Sistem her başladığında konsol oturumunu otomatik kapatır
  sudo tee "${WINAPPS_OEM_DIR}/install.bat" >/dev/null <<'BATEOF'
@echo off
echo [WinApps OEM] Kurulum basliyor...

:: 1. RDP registry ayarlari
echo [1/4] RDP registry ayarlari uygulanıyor...
regedit.exe /s "%~dp0RDPApps.reg"
regedit.exe /s "%~dp0AutoSignOut.reg"

:: 2. Güvenlik duvarı - RDP portu aç
echo [2/4] RDP guvenlik duvari kurali ekleniyor...
netsh advfirewall firewall add rule name="WinApps-RDP" protocol=TCP dir=in localport=3389 action=allow

:: 3. AutoSignOut görevini Görev Zamanlayıcı'ya ekle
echo [3/4] AutoSignOut gorevi ekleniyor...
schtasks /create /tn "WinApps-AutoSignOut" ^
  /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\oem\AutoSignOut.ps1" ^
  /sc onstart ^
  /ru SYSTEM ^
  /rl HIGHEST ^
  /f

:: 4. PowerShell execution policy (ps1 çalışabilsin)
echo [4/4] PowerShell execution policy ayarlaniyor...
powershell.exe -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force"

echo [WinApps OEM] Kurulum tamamlandi!
BATEOF

  sudo chmod 644     "${WINAPPS_OEM_DIR}/RDPApps.reg"     "${WINAPPS_OEM_DIR}/AutoSignOut.reg"     "${WINAPPS_OEM_DIR}/AutoSignOut.ps1"     "${WINAPPS_OEM_DIR}/install.bat"

  success "OEM dosyaları hazır: $WINAPPS_OEM_DIR"
  info "AutoSignOut görevi: Windows her başladığında konsol oturumu otomatik kapatılır."
  info "Böylece WinApps her zaman boş oturum bulur — manuel sign-out gerekmez."
}

create_system_config() {
  step "BÖLÜM 3F — WinApps Yapılandırması"
  sudo mkdir -p "$WINAPPS_ETC_DIR"

  echo ""
  echo -e "  ${BOLD}Windows VM Kimlik Bilgileri${NC}"
  echo "  ─────────────────────────────────────"
  ask WIN_USER "  Windows kullanıcı adı" "MyWindowsUser"
  ask_password WIN_PASS "  Windows kullanıcı parolası"

  echo ""
  echo -e "  ${BOLD}Windows Sürümü${NC}"
  echo "  ─────────────────────────────────────"
  echo -e "  ${YELLOW}⚠️  Windows Home RDP DESTEKLEMİYOR!${NC}"
  echo -e "  ${YELLOW}   Sadece Pro, Enterprise veya Server kullanın.${NC}"
  echo -e "  ${YELLOW}   Windows 11 (varsayılan) otomatik Pro sürümüdür.${NC}"
  echo "  Geçerli değerler: 11, 10, tiny11, 2022, 2019, 2016"
  ask WIN_VERSION "  Windows sürümü" "11"
  ask WIN_RAM     "  RAM (örn: 4G, 8G)" "4G"
  ask WIN_CORES   "  CPU çekirdek sayısı" "4"
  ask WIN_DISK    "  Disk boyutu (örn: 64G)" "64G"
  echo ""
  echo -e "  ${BOLD}Windows Dil Ayarı${NC}"
  echo "  ─────────────────────────────────────"
  echo "  1 → Türkçe (tr-TR)  — Microsoft'tan Türkçe ISO indirilir"
  echo "  2 → İngilizce (en-US) — varsayılan"
  echo ""
  local WIN_LANG_CHOICE
  read -rp "$(echo -e "  ${CYAN}Dil seçin [1/2] [varsayılan: 1]: ${NC}")" WIN_LANG_CHOICE
  WIN_LANG_CHOICE="${WIN_LANG_CHOICE:-1}"

  if [[ "$WIN_LANG_CHOICE" == "1" ]]; then
    WIN_LANGUAGE="Turkish"
    WIN_REGION="tr-TR"
    WIN_KEYBOARD="tr-TR"
    success "  Türkçe Windows seçildi."
  else
    WIN_LANGUAGE="English"
    WIN_REGION="en-US"
    WIN_KEYBOARD="en-US"
    success "  İngilizce Windows seçildi."
  fi

  echo "  100 → Normal  |  140 → HD  |  180 → 4K"
  ask RDP_SCALE   "  Ekran ölçeği" "100"

  # winapps.conf
  sudo tee "$WINAPPS_CONF" >/dev/null <<CONF
##################################
#   WINAPPS CONFIGURATION FILE   #
##################################
RDP_USER="${WIN_USER}"
RDP_PASS="${WIN_PASS}"
RDP_ASKPASS=""
RDP_DOMAIN=""
RDP_IP="127.0.0.1"
VM_NAME="RDPWindows"
WAFLAVOR="docker"
RDP_SCALE="${RDP_SCALE}"
REMOVABLE_MEDIA="/run/media"
RDP_FLAGS="/cert:tofu /sound /microphone +home-drive"
RDP_FLAGS_NON_WINDOWS=""
RDP_FLAGS_WINDOWS=""
DEBUG="true"
AUTOPAUSE="off"
AUTOPAUSE_TIME="300"
FREERDP_COMMAND=""
PORT_TIMEOUT="5"
RDP_TIMEOUT="30"
APP_SCAN_TIMEOUT="60"
BOOT_TIMEOUT="120"
HIDEF="on"
CONF

  sudo chown root:root "$WINAPPS_CONF"
  sudo chmod 644 "$WINAPPS_CONF"
  success "winapps.conf → $WINAPPS_CONF (izin: 644)"

  # compose.yaml — ilk kurulumda oem mount AÇIK
  _write_compose_yaml "with_oem"
}

_write_compose_yaml() {
  local mode="${1:-with_oem}"
  local OEM_LINE
  if [[ "$mode" == "with_oem" ]]; then
    OEM_LINE="      - ${WINAPPS_OEM_DIR}:/oem"
  else
    OEM_LINE="#      - ${WINAPPS_OEM_DIR}:/oem  # Windows kurulumdan sonra devre dışı"
  fi

  sudo tee "$WINAPPS_COMPOSE" >/dev/null <<COMPOSE
name: "winapps"

volumes:
  data:

services:
  windows:
    image: ghcr.io/dockur/windows:latest
    container_name: WinApps
    environment:
      VERSION: "${WIN_VERSION}"
      RAM_SIZE: "${WIN_RAM}"
      CPU_CORES: "${WIN_CORES}"
      DISK_SIZE: "${WIN_DISK}"
      USERNAME: "${WIN_USER}"
      PASSWORD: "${WIN_PASS}"
      HOME: "${REAL_HOME}"
      LANGUAGE: "${WIN_LANGUAGE}"
      REGION: "${WIN_REGION}"
      KEYBOARD: "${WIN_KEYBOARD}"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
      - 3389:3389/tcp
      - 3389:3389/udp
    volumes:
      - data:/storage
      - ${REAL_HOME}:${REAL_HOME}
${OEM_LINE}
    restart: on-failure
    stop_grace_period: 2m
COMPOSE

  sudo chown root:root "$WINAPPS_COMPOSE"
  sudo chmod 644 "$WINAPPS_COMPOSE"
}

symlink_for_all_users() {
  step "BÖLÜM 3G — Config Symlink → Tüm Kullanıcılar"

  # /etc/skel → yeni kullanıcılar otomatik alır
  sudo mkdir -p "$WINAPPS_SKEL_DIR"
  sudo ln -sf "$WINAPPS_CONF"    "${WINAPPS_SKEL_DIR}/winapps.conf"
  sudo ln -sf "$WINAPPS_COMPOSE" "${WINAPPS_SKEL_DIR}/compose.yaml"
  success "/etc/skel symlink eklendi."

  # root → setup.sh sudo ile çalışınca HOME=/root
  sudo mkdir -p /root/.config/winapps
  sudo ln -sf "$WINAPPS_CONF"    /root/.config/winapps/winapps.conf
  sudo ln -sf "$WINAPPS_COMPOSE" /root/.config/winapps/compose.yaml
  success "root → /root/.config/winapps/ symlink eklendi."

  # Mevcut kullanıcılar (UID ≥ 1000)
  while IFS=: read -r uname _ uid _ _ uhome ushell; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]] && \
       [[ "$ushell" =~ (bash|zsh|sh|fish)$ ]]; then
      local confdir="${uhome}/.config/winapps"
      sudo mkdir -p "$confdir"
      sudo ln -sf "$WINAPPS_CONF"    "${confdir}/winapps.conf"
      sudo ln -sf "$WINAPPS_COMPOSE" "${confdir}/compose.yaml"
      sudo chown -R "${uname}:${uname}" "${uhome}/.config" 2>/dev/null || true
      info "  $uname → $confdir"
    fi
  done < /etc/passwd
  success "Tüm kullanıcı oturumları yapılandırıldı."
}

start_windows_vm() {
  step "BÖLÜM 3H — Windows VM Başlatma"

  # sg docker → re-login gerekmeden docker grubunu aktif eder
  docker_compose_run --file "$WINAPPS_COMPOSE" up -d
  success "Windows VM başlatıldı (oem aktif → RDP ayarları otomatik uygulanacak)."

  echo ""
  echo -e "  ${BOLD}━━━ Şu anda yapmanız gerekenler ━━━${NC}"
  echo ""
  echo -e "  1. Tarayıcıda açın  → ${CYAN}http://127.0.0.1:8006${NC}"
  echo "  2. Windows kurulumunu tamamlayın (10–20 dakika)"
  echo -e "  3. ${YELLOW}İstediğiniz uygulamaları Windows'a kurun${NC} (Office, Adobe vb.)"
  echo -e "     ${YELLOW}WinApps bunları KURMAZ — sadece kurulu olanları entegre eder${NC}"
  echo -e "  4. ${YELLOW}Windows kullanıcı oturumunu KAPATIP çıkın${NC} (RDP için şart)"
  echo "  5. Bu terminale dönüp Enter'a basın"
  echo ""

  confirm "Windows hazır ve oturum kapatıldı, devam edelim" \
    || { echo "  Hazır olunca tekrar çalıştırın."; exit 0; }

  # docker.md: kurulum sonrası oem mount kapat
  info "oem mount kapatılıyor (Windows kurulumu tamamlandı)..."
  _write_compose_yaml "without_oem"

  # Eski FreeRDP sertifikalarını temizle — tüm kullanıcılar
  # Windows yeniden kurulunca sertifika değişir, eskisi bağlantıyı engeller
  info "FreeRDP sertifikaları temizleniyor..."
  sudo rm -rf /root/.config/freerdp/server/ 2>/dev/null || true
  rm -rf "${REAL_HOME}/.config/freerdp/server/" 2>/dev/null || true
  while IFS=: read -r uname _ uid _ _ uhome _; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      rm -rf "${uhome}/.config/freerdp/server/" 2>/dev/null || true
    fi
  done < /etc/passwd
  success "FreeRDP sertifikaları temizlendi."

  # Container yeniden başlat
  info "Container yeni yapılandırmayla yeniden başlatılıyor..."
  docker_compose_run --file "$WINAPPS_COMPOSE" down
  docker_compose_run --file "$WINAPPS_COMPOSE" up -d
  success "Container yeniden başlatıldı (oem devre dışı)."
}

run_winapps_installer() {
  step "BÖLÜM 3I — WinApps Sistem Geneli Kurulumu"

  echo ""
  echo "  Kurulum hedefleri (--system):"
  echo "  /usr/local/bin/           → winapps, winapps-setup"
  echo "  /usr/share/applications/  → .desktop kısayolları (TÜM kullanıcılar)"
  echo "  /usr/local/share/winapps/ → uygulama verileri"
  echo ""

  if confirm "WinApps kurulumunu başlat"; then

    local TMP_SETUP
    TMP_SETUP=$(mktemp /tmp/winapps-setup-XXXXX.sh)
    info "setup.sh indiriliyor..."
    curl -fsSL https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh \
      -o "$TMP_SETUP"
    chmod +x "$TMP_SETUP"

    # ── DOCKER_HOST ve socket symlink garantisi ───────────────
    # setup.sh içindeki waCheckContainerRunning "docker ps" çağırır.
    # Docker Engine varken ~/.docker/desktop/docker.sock aranırsa hata verir.
    # DOCKER_HOST ile doğru socket'i gösteriyoruz.
    export DOCKER_HOST=unix:///var/run/docker.sock
    mkdir -p "${REAL_HOME}/.docker/desktop"
    sudo mkdir -p /root/.docker/desktop
    ln -sf /var/run/docker.sock "${REAL_HOME}/.docker/desktop/docker.sock" 2>/dev/null || true
    sudo ln -sf /var/run/docker.sock /root/.docker/desktop/docker.sock 2>/dev/null || true

    # setup.sh'ı DOCKER_HOST ile çalıştır
    # sudo ile çalıştırıyoruz: --system flag'i sudo gerektiriyor
    # -E: mevcut ortam değişkenlerini (DOCKER_HOST dahil) sudo'ya geçir
    sudo -E bash "$TMP_SETUP" --system --setupAllOfficiallySupportedApps
    rm -f "$TMP_SETUP"
  else
    echo ""
    info "Daha sonra çalıştırmak için:"
    echo "  export DOCKER_HOST=unix:///var/run/docker.sock"
    echo "  sudo -E bash <(curl https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh) \\"
    echo "    --system --setupAllOfficiallySupportedApps"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 4 — WinApps UYGULAMA YENİLEME SİSTEMİ
# ══════════════════════════════════════════════════════════════════
install_refresh_system() {
  step "BÖLÜM 4 — WinApps Uygulama Yenileme Sistemi"

  # ── 4.1 Ana refresh scripti ─────────────────────────────────
  sudo tee "$REFRESH_BIN" >/dev/null <<'REFRESH_EOF'
#!/usr/bin/env bash
# ==============================================================
#  winapps-refresh — Windows'a Yeni Program Kurulduktan Sonra
#  Tüm Kullanıcıların Programlar Menüsünü Günceller
#
#  Kullanım: winapps-refresh
#
#  ÖNEMLİ: Windows VM açık, kullanıcı oturumu KAPALI olmalı!
# ==============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

COMPOSE_FILE="/etc/winapps/compose.yaml"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║  WinApps — Uygulama Listesi Yenileniyor         ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ── BUG4 DÜZELTİLDİ ──────────────────────────────────────────
# docker ps için grup kontrolü: docker grubundaysa direkt,
# değilse sudo ile çalışır (sıfır kurulum sonrası re-login öncesi)
_docker_check() {
  if docker ps "$@" 2>/dev/null; then
    return 0
  elif sudo docker ps "$@" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# 1. Windows VM çalışıyor mu?
echo -n "  Windows VM kontrol ediliyor... "
if ! _docker_check --filter name=WinApps --filter status=running \
     --format '{{.Names}}' 2>/dev/null | grep -q "WinApps"; then
  echo -e "${RED}[KAPALI]${NC}"
  echo ""
  echo -e "  ${RED}Windows VM çalışmıyor!${NC}"
  echo "  Başlatmak için:"
  echo "    docker compose --file ${COMPOSE_FILE} start"
  echo "  veya:"
  echo "    sudo docker compose --file ${COMPOSE_FILE} start"
  exit 1
fi
echo -e "${GREEN}[ÇALIŞIYOR]${NC}"

# 2. Oturum uyarısı
echo ""
echo -e "  ${YELLOW}⚠️  Windows kullanıcı oturumu KAPALI olmalı!${NC}"
read -rp "  Oturum kapalı, devam edeyim mi? [E/h]: " ans
ans="${ans:-e}"
[[ "$ans" =~ ^[EeYy]$ ]] || { echo "  İptal edildi."; exit 0; }
echo ""

# 3. setup.sh'ı temp dosyaya indir ve çalıştır
echo -e "  ${CYAN}Windows'taki yeni uygulamalar taranıyor...${NC}"
echo "  (1-2 dakika sürebilir)"
echo ""

TMP_SETUP=$(mktemp /tmp/winapps-setup-XXXXX.sh)
curl -fsSL https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh \
  -o "$TMP_SETUP"
chmod +x "$TMP_SETUP"

# DOCKER_HOST doğru socket'e yönlendir
export DOCKER_HOST=unix:///var/run/docker.sock
mkdir -p "${HOME}/.docker/desktop" 2>/dev/null || true
ln -sf /var/run/docker.sock "${HOME}/.docker/desktop/docker.sock" 2>/dev/null || true

if sudo -E bash "$TMP_SETUP" --system --add-apps; then
  rm -f "$TMP_SETUP"
  echo ""
  echo -e "  ${GREEN}${BOLD}✅ Tamamlandı!${NC}"
  echo ""
  echo "  Yeni uygulamalar → /usr/share/applications/"
  echo "  Tüm kullanıcıların programlar menüsünde görünür."
  echo ""
  # Masaüstü bildirimi
  command -v notify-send &>/dev/null && \
    DISPLAY="${DISPLAY:-:0}" notify-send "WinApps" \
      "Uygulama listesi güncellendi. Yeni Windows uygulamaları programlar menüsüne eklendi." \
      --icon=system-run 2>/dev/null || true
else
  rm -f "$TMP_SETUP"
  echo ""
  echo -e "  ${RED}Hata oluştu! Kontrol edin:${NC}"
  echo "  • Windows VM çalışıyor mu?"
  echo "  • Windows oturumu kapalı mı?"
  echo "  • /etc/winapps/winapps.conf kullanıcı adı/şifre doğru mu?"
  exit 1
fi
REFRESH_EOF

  sudo chmod +x "$REFRESH_BIN"
  success "winapps-refresh komutu → $REFRESH_BIN"

  # ── 4.2 GUI launcher (terminal bul ve aç) ───────────────────
  sudo tee "$REFRESH_LAUNCHER" >/dev/null <<'LAUNCHER_EOF'
#!/usr/bin/env bash
CMD="winapps-refresh; echo ''; echo 'Çıkmak için Enter...'; read"

for term in gnome-terminal konsole xfce4-terminal tilix xterm; do
  command -v "$term" &>/dev/null || continue
  case "$term" in
    gnome-terminal) exec gnome-terminal --title="WinApps Yenileme" -- bash -c "$CMD" ;;
    konsole)        exec konsole --title "WinApps Yenileme" -e bash -c "$CMD" ;;
    xfce4-terminal) exec xfce4-terminal --title="WinApps Yenileme" -x bash -c "$CMD" ;;
    tilix)          exec tilix -e bash -c "$CMD" ;;
    xterm)          exec xterm -title "WinApps Yenileme" -e bash -c "$CMD" ;;
  esac
done

notify-send "WinApps" \
  "Terminal bulunamadı. Terminalde 'winapps-refresh' çalıştırın." \
  --icon=dialog-error 2>/dev/null || true
LAUNCHER_EOF

  sudo chmod +x "$REFRESH_LAUNCHER"
  success "GUI launcher → $REFRESH_LAUNCHER"

  # ── 4.3 Programlar menüsü kısayolu (tüm kullanıcılar) ───────
  sudo tee "$REFRESH_DESKTOP" >/dev/null <<'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=WinApps — Uygulamaları Yenile
GenericName=WinApps Uygulama Tarayıcı
Comment=Windows'a yeni program kurduğunuzda tüm kullanıcıların menüsünü günceller
Exec=/usr/local/bin/winapps-refresh-gui
Icon=system-run
Terminal=false
Categories=System;Utility;
Keywords=winapps;windows;refresh;yenile;
StartupNotify=true
DESKTOP_EOF

  sudo chmod 644 "$REFRESH_DESKTOP"
  success ".desktop → $REFRESH_DESKTOP (tüm kullanıcıların programlar menüsünde)"

  # ── 4.4 Systemd timer (isteğe bağlı) ────────────────────────
  echo ""
  echo -e "  ${BOLD}Otomatik Yenileme (Systemd Timer)${NC}"
  echo "  Sistem başladığında + haftada bir otomatik tarama yapar."
  echo "  Windows VM açık değilse sessizce atlar."
  echo ""

  if confirm "  Otomatik timer'ı kur" "n"; then

    sudo tee /etc/systemd/system/winapps-refresh.service >/dev/null <<'SERVICE_EOF'
[Unit]
Description=WinApps Uygulama Listesi Yenileme
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/winapps-refresh
# VM kapalıysa 0 veya 1 ile çıkabilir — her ikisi de başarı say
SuccessExitStatus=0 1
RemainAfterExit=no
StandardOutput=journal
StandardError=journal
SERVICE_EOF

    sudo tee /etc/systemd/system/winapps-refresh.timer >/dev/null <<'TIMER_EOF'
[Unit]
Description=WinApps Uygulama Listesi Haftalık Yenileme
Requires=winapps-refresh.service

[Timer]
OnBootSec=2min
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now winapps-refresh.timer
    success "winapps-refresh.timer etkinleştirildi."
    info "Durum: sudo systemctl status winapps-refresh.timer"
  else
    info "Timer atlandı. Manuel: winapps-refresh"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  ÖZET
# ══════════════════════════════════════════════════════════════════
print_summary() {
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "╔════════════════════════════════════════════════════════════════════╗"
  echo "║                    Kurulum Tamamlandı! ✅                          ║"
  echo "╚════════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  echo -e "${BOLD}GNOME:${NC}"
  echo "  GNOME Tweaks, dconf-editor → Uygulamalar menüsünden"
  echo "  Extension Manager         → flatpak run com.mattjakeman.ExtensionManager"
  echo "  ✅ Dash to Panel (aktif varsayılan)  📦 Dash to Dock (kurulu, pasif)"
  echo "  → ikisi ÇAKIŞIR, birini seçin (Extension Manager'dan)"
  echo ""

  echo -e "${BOLD}Touchpad:${NC}"
  echo "  USB fare takılınca touchpad kapanır — tüm kullanıcılar"
  echo ""

  echo -e "${BOLD}WinApps:${NC}"
  echo "  winapps windows                    → Tam Windows masaüstü"
  echo "  winapps manual \"uygulama.exe\"      → Manuel başlat"
  echo "  winapps-setup --system --uninstall → Kaldır"
  echo ""

  echo -e "${BOLD}🔄 Windows'a Yeni Program Kurdunuzda:${NC}"
  echo -e "  ${CYAN}Terminal:${NC}          winapps-refresh"
  echo -e "  ${CYAN}Programlar menüsü:${NC} 'WinApps — Uygulamaları Yenile'"
  echo "  → Her ikisi de /usr/share/applications/ günceller"
  echo "  → Tüm kullanıcıların menüsüne yeni uygulama eklenir"
  echo ""

  echo -e "${BOLD}Windows VM:${NC}"
  echo "  http://127.0.0.1:8006                              → VNC"
  echo "  docker compose --file ${WINAPPS_COMPOSE} start    → Aç"
  echo "  docker compose --file ${WINAPPS_COMPOSE} stop     → Kapat"
  echo "  docker compose --file ${WINAPPS_COMPOSE} restart  → Yeniden başlat"
  echo ""

  echo -e "${BOLD}Sıfırdan başlamak:${NC}"
  echo "  docker compose --file ${WINAPPS_COMPOSE} down --rmi=all --volumes"
  echo ""
}

# ══════════════════════════════════════════════════════════════════
#  ANA AKIŞ
# ══════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════
#  TAM KALDIRMA / COMPLETE UNINSTALL
# ══════════════════════════════════════════════════════════════════
uninstall_all() {
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    step "Tam Kaldırma Başlıyor..."
    echo ""
    echo -e "  ${RED}${BOLD}⚠️  Aşağıdakiler kalıcı olarak silinecek:${NC}"
    echo "  • Windows VM ve tüm Windows disk verisi"
    echo "  • WinApps kurulumu ve tüm uygulama kısayolları"
    echo "  • /etc/winapps/ dizini (config, compose, oem)"
    echo "  • GNOME extension'lar (Dash to Panel, Dash to Dock)"
    echo "  • dconf sistem override dosyaları"
    echo "  • winapps-refresh komutu ve kısayolları"
    echo "  • Systemd timer/service"
    echo "  • Tüm kullanıcılardaki config symlink'leri"
    echo ""
    warn "Docker ve KVM paketleri KORUNACAK (isteğe bağlı silebilirsiniz)"
    echo ""
    confirm "Devam etmek istiyor musunuz? Bu işlem GERİ ALINAMAZ" "n" || {
      echo "  İptal edildi."
      exit 0
    }
  else
    step "Starting Complete Uninstall..."
    echo ""
    echo -e "  ${RED}${BOLD}⚠️  The following will be permanently deleted:${NC}"
    echo "  • Windows VM and all Windows disk data"
    echo "  • WinApps installation and all application shortcuts"
    echo "  • /etc/winapps/ directory (config, compose, oem)"
    echo "  • GNOME extensions (Dash to Panel, Dash to Dock)"
    echo "  • dconf system override files"
    echo "  • winapps-refresh command and shortcuts"
    echo "  • Systemd timer/service"
    echo "  • Config symlinks for all users"
    echo ""
    warn "Docker and KVM packages will be KEPT (you can remove them optionally)"
    echo ""
    confirm "Do you want to continue? This action CANNOT BE UNDONE" "n" || {
      echo "  Cancelled."
      exit 0
    }
  fi

  # ── 1. Windows VM ve volume sil ───────────────────────────────
  msg "  Windows VM durduruluyor ve siliniyor..."       "  Stopping and removing Windows VM..."
  export DOCKER_HOST=unix:///var/run/docker.sock
  if command -v docker &>/dev/null; then
    docker compose --file "$WINAPPS_COMPOSE" down --volumes 2>/dev/null || true
    sudo docker compose --file "$WINAPPS_COMPOSE" down --volumes 2>/dev/null || true
    docker rm -f WinApps 2>/dev/null || sudo docker rm -f WinApps 2>/dev/null || true
    docker volume rm winapps_data 2>/dev/null || sudo docker volume rm winapps_data 2>/dev/null || true
    success "$(msg "Windows VM ve disk verisi silindi." "Windows VM and disk data removed.")"
  else
    warn "$(msg "Docker bulunamadı, atlanıyor." "Docker not found, skipping.")"
  fi

  # ── 2. WinApps kurulumunu kaldır (setup.sh --uninstall) ───────
  msg "  WinApps kaldırılıyor..." "  Removing WinApps..."
  export DOCKER_HOST=unix:///var/run/docker.sock
  local TMP_UNINSTALL
  TMP_UNINSTALL=$(mktemp /tmp/winapps-uninstall-XXXXX.sh)
  if curl -fsSL https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh     -o "$TMP_UNINSTALL" 2>/dev/null; then
    chmod +x "$TMP_UNINSTALL"
    sudo -E bash "$TMP_UNINSTALL" --system --uninstall 2>/dev/null || true
    rm -f "$TMP_UNINSTALL"
    success "$(msg "WinApps kaldırıldı." "WinApps removed.")"
  else
    warn "$(msg 'WinApps setup.sh indirilemedi, manuel siliniyor...'          'Could not download WinApps setup.sh, removing manually...')"
    sudo rm -f /usr/local/bin/winapps /usr/local/bin/winapps-setup 2>/dev/null || true
    sudo rm -rf /usr/local/share/winapps /usr/local/bin/winapps-src 2>/dev/null || true
    sudo find /usr/share/applications/ -name "*.desktop"       -exec grep -l "winapps" {} \; | xargs sudo rm -f 2>/dev/null || true
    rm -f "$TMP_UNINSTALL" 2>/dev/null || true
  fi

  # ── 3. /etc/winapps/ dizinini sil ─────────────────────────────
  msg "  /etc/winapps/ siliniyor..." "  Removing /etc/winapps/..."
  sudo rm -rf "$WINAPPS_ETC_DIR" 2>/dev/null || true
  success "$(msg "/etc/winapps/ silindi." "/etc/winapps/ removed.")"

  # ── 4. dconf override dosyaları ───────────────────────────────
  msg "  dconf override dosyaları siliniyor..."       "  Removing dconf override files..."
  sudo rm -f     "${DCONF_DIR}/00-gnome-shell"     "${DCONF_DIR}/01-touchpad"     "${DCONF_DIR}/02-gnome-misc" 2>/dev/null || true
  sudo dconf update 2>/dev/null || true
  success "$(msg "dconf override dosyaları silindi." "dconf override files removed.")"

  # ── 5. GNOME extension'ları sil ───────────────────────────────
  msg "  GNOME extensionlar siliniyor..." "  Removing GNOME extensions..."
  sudo rm -rf     "/usr/share/gnome-shell/extensions/${EXT_DASH_TO_PANEL}"     "/usr/share/gnome-shell/extensions/${EXT_DASH_TO_DOCK}" 2>/dev/null || true
  success "$(msg "GNOME extensionlar silindi." "GNOME extensions removed.")"

  # ── 6. winapps-refresh scriptleri ─────────────────────────────
  msg "  winapps-refresh siliniyor..." "  Removing winapps-refresh..."
  sudo rm -f     "$REFRESH_BIN"     "$REFRESH_LAUNCHER"     "$REFRESH_DESKTOP" 2>/dev/null || true
  success "$(msg "winapps-refresh silindi." "winapps-refresh removed.")"

  # ── 7. Systemd timer/service ───────────────────────────────────
  msg "  Systemd timer siliniyor..." "  Removing systemd timer..."
  sudo systemctl disable --now winapps-refresh.timer 2>/dev/null || true
  sudo rm -f     /etc/systemd/system/winapps-refresh.timer     /etc/systemd/system/winapps-refresh.service 2>/dev/null || true
  sudo systemctl daemon-reload 2>/dev/null || true
  success "$(msg "Systemd timer silindi." "Systemd timer removed.")"

  # ── 8. Tüm kullanıcılardaki symlink'ler ───────────────────────
  msg "  Kullanıcı symlink'leri siliniyor..."       "  Removing user symlinks..."
  # /etc/skel
  sudo rm -f     "${WINAPPS_SKEL_DIR}/winapps.conf"     "${WINAPPS_SKEL_DIR}/compose.yaml" 2>/dev/null || true
  # root
  sudo rm -f     /root/.config/winapps/winapps.conf     /root/.config/winapps/compose.yaml 2>/dev/null || true
  # Mevcut kullanıcılar / current users
  while IFS=: read -r uname _ uid _ _ uhome _; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      sudo rm -f         "${uhome}/.config/winapps/winapps.conf"         "${uhome}/.config/winapps/compose.yaml" 2>/dev/null || true
      sudo rm -f         "${uhome}/.docker/desktop/docker.sock" 2>/dev/null || true
    fi
  done < /etc/passwd
  success "$(msg "Symlinkler silindi." "Symlinks removed.")"

  # ── 9. FreeRDP sertifikaları ───────────────────────────────────
  msg "  FreeRDP sertifikaları siliniyor..."       "  Removing FreeRDP certificates..."
  sudo rm -rf /root/.config/freerdp/server/ 2>/dev/null || true
  while IFS=: read -r uname _ uid _ _ uhome _; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      rm -rf "${uhome}/.config/freerdp/server/" 2>/dev/null || true
    fi
  done < /etc/passwd
  success "$(msg "FreeRDP sertifikaları silindi." "FreeRDP certificates removed.")"

  # ── 10. DOCKER_HOST /etc/environment'tan sil ──────────────────
  sudo sed -i '/^DOCKER_HOST=/d' /etc/environment 2>/dev/null || true

  # ── 11. İsteğe bağlı: Docker'ı kaldır ────────────────────────
  echo ""
  if confirm "$(msg 'Docker Engine kaldırılsın mı? (WinApps dışında Docker kullanmıyorsanız)'                    'Remove Docker Engine? (Only if you do not use Docker for anything else)')" "n"; then
    msg "  Docker kaldırılıyor..." "  Removing Docker..."
    case "$DISTRO_FAMILY" in
      debian)
        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io           docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        sudo apt-get autoremove -y 2>/dev/null || true
        sudo rm -rf /var/lib/docker /etc/docker /etc/apt/keyrings/docker.gpg           /etc/apt/sources.list.d/docker.list 2>/dev/null || true
        ;;
      fedora)
        sudo dnf remove -y docker-ce docker-ce-cli containerd.io           docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        ;;
      arch)
        sudo pacman -Rns --noconfirm docker docker-compose 2>/dev/null || true
        ;;
    esac
    # Docker grubundan kullanıcıları çıkar
    while IFS=: read -r uname _ uid _ _ uhome _; do
      if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
        sudo gpasswd -d "$uname" docker 2>/dev/null || true
      fi
    done < /etc/passwd
    success "$(msg "Docker kaldırıldı." "Docker removed.")"
  fi

  # ── 12. İsteğe bağlı: GNOME araçları ─────────────────────────
  if confirm "$(msg 'GNOME Tweaks ve dconf-editor kaldırılsın mı?'                    'Remove GNOME Tweaks and dconf-editor?')" "n"; then
    case "$DISTRO_FAMILY" in
      debian)
        sudo apt-get purge -y gnome-tweaks dconf-editor 2>/dev/null || true
        ;;
      fedora)
        sudo dnf remove -y gnome-tweaks dconf-editor 2>/dev/null || true
        ;;
      arch)
        sudo pacman -Rns --noconfirm gnome-tweaks 2>/dev/null || true
        ;;
    esac
    flatpak uninstall -y com.mattjakeman.ExtensionManager 2>/dev/null || true
    success "$(msg "GNOME araçları kaldırıldı." "GNOME tools removed.")"
  fi

  # ── Özet ──────────────────────────────────────────────────────
  echo ""
  echo -e "${GREEN}${BOLD}"
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Kaldırma İşlemi Tamamlandı! ✅                        ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  else
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Uninstallation Complete! ✅                            ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  fi
  echo -e "${NC}"
  msg "  Sistemden her şey temizlendi." "  Everything has been removed from the system."
  echo ""
}

main() {
  # Dil tespiti / Language detection
  detect_language

  banner

  # ── Dil seçimi / Language selection ───────────────────────────
  echo ""
  echo -e "  ${BOLD}Language / Dil:${NC}"
  echo "  [1] Türkçe"
  echo "  [2] English"
  echo ""
  read -rp "$(echo -e "  ${CYAN}Select / Seçin [1/2] [default/varsayılan: 1]: ${NC}")" lang_choice
  lang_choice="${lang_choice:-1}"
  if [[ "$lang_choice" == "2" ]]; then
    SCRIPT_LANG="en"
  else
    SCRIPT_LANG="tr"
  fi
  echo ""

  # ── Ana menü / Main menu ───────────────────────────────────────
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo -e "  ${BOLD}Ne yapmak istersiniz?${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Kurulum   — GNOME + Touchpad + WinApps + Yenileme Sistemi"
    echo -e "  ${CYAN}[2]${NC} Kaldırma  — Her şeyi temizle (Windows VM dahil)"
    echo -e "  ${CYAN}[3]${NC} Çıkış"
    echo ""
    read -rp "$(echo -e "  ${YELLOW}Seçiminiz [1/2/3]: ${NC}")" main_choice
  else
    echo -e "  ${BOLD}What would you like to do?${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Install  — GNOME + Touchpad + WinApps + Refresh System"
    echo -e "  ${CYAN}[2]${NC} Uninstall — Remove everything (including Windows VM)"
    echo -e "  ${CYAN}[3]${NC} Exit"
    echo ""
    read -rp "$(echo -e "  ${YELLOW}Your choice [1/2/3]: ${NC}")" main_choice
  fi

  case "${main_choice:-1}" in
    1)
      # ── KURULUM / INSTALL ──────────────────────────────────────
      if [[ "$SCRIPT_LANG" == "tr" ]]; then
        echo ""
        echo -e "${BOLD}  Bu script sırasıyla şunları yapacak:${NC}"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 1: GNOME ──────────────────────────────────────${NC}"
        echo "   1. GNOME Tweaks + dconf-editor + Flatpak + Extension Manager"
        echo "   2. Dash to Dock + Dash to Panel"
        echo "   3. dconf sistem override (TÜM kullanıcılar)"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 2: Touchpad ────────────────────────────────────${NC}"
        echo "   4. USB fare → touchpad kapat (TÜM kullanıcılar)"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 3: WinApps ─────────────────────────────────────${NC}"
        echo "   5. KVM + qemu-kvm + iptables"
        echo "   6. Docker Engine + Compose plugin"
        echo "   7. Tüm kullanıcıları docker grubuna ekle"
        echo "   8. WinApps bağımlılıkları"
        echo "   9. OEM + winapps.conf + compose.yaml"
        echo "  10. Tüm kullanıcılara config symlink"
        echo "  11. Windows VM başlat → kurulum → oem kapat → yeniden başlat"
        echo "  12. WinApps --system → /usr/share/applications"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 4: Yenileme ────────────────────────────────────${NC}"
        echo "  13. winapps-refresh komutu"
        echo "  14. Programlar menüsü kısayolu"
        echo "  15. Systemd timer (isteğe bağlı)"
        echo ""
        echo -e "  ${YELLOW}NOT: Windows 10 → SADECE Pro/Enterprise çalışır!${NC}"
        echo -e "  ${YELLOW}     Office/Adobe vb. Windows'a ayrıca kurulmalıdır.${NC}"
        echo ""
        confirm "Kuruluma başlayalım mı?" || { echo "  İptal edildi."; exit 0; }
      else
        echo ""
        echo -e "${BOLD}  This script will do the following:${NC}"
        echo ""
        echo -e "  ${CYAN}── SECTION 1: GNOME ─────────────────────────────────────${NC}"
        echo "   1. GNOME Tweaks + dconf-editor + Flatpak + Extension Manager"
        echo "   2. Dash to Dock + Dash to Panel"
        echo "   3. dconf system override (ALL users)"
        echo ""
        echo -e "  ${CYAN}── SECTION 2: Touchpad ──────────────────────────────────${NC}"
        echo "   4. USB mouse → disable touchpad (ALL users)"
        echo ""
        echo -e "  ${CYAN}── SECTION 3: WinApps ───────────────────────────────────${NC}"
        echo "   5. KVM + qemu-kvm + iptables"
        echo "   6. Docker Engine + Compose plugin"
        echo "   7. Add all users to docker group"
        echo "   8. WinApps dependencies"
        echo "   9. OEM + winapps.conf + compose.yaml"
        echo "  10. Config symlinks for all users"
        echo "  11. Start Windows VM → install → disable oem → restart"
        echo "  12. WinApps --system → /usr/share/applications"
        echo ""
        echo -e "  ${CYAN}── SECTION 4: Refresh ───────────────────────────────────${NC}"
        echo "  13. winapps-refresh command"
        echo "  14. App menu shortcut"
        echo "  15. Systemd timer (optional)"
        echo ""
        echo -e "  ${YELLOW}NOTE: Windows 10 → ONLY Pro/Enterprise works!${NC}"
        echo -e "  ${YELLOW}      Office/Adobe etc. must be installed inside Windows.${NC}"
        echo ""
        confirm "Start installation?" || { echo "  Cancelled."; exit 0; }
      fi

      check_prerequisites
      cleanup_existing

      install_gnome_tools
      install_dash_to_dock
      install_dash_to_panel
      apply_dconf_system_overrides
      configure_touchpad
      install_kvm
      install_docker
      add_all_users_to_docker
      install_winapps_deps
      setup_oem
      create_system_config
      symlink_for_all_users
      start_windows_vm
      run_winapps_installer
      install_refresh_system
      print_summary
      ;;

    2)
      # ── KALDIRMA / UNINSTALL ───────────────────────────────────
      check_prerequisites
      detect_distro
      uninstall_all
      ;;

    3)
      msg "  Çıkılıyor." "  Exiting."
      exit 0
      ;;

    *)
      msg "  Geçersiz seçim. Çıkılıyor." "  Invalid choice. Exiting."
      exit 1
      ;;
  esac
}

main "$@"
