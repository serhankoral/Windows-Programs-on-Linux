#!/usr/bin/env bash
# ==============================================================================
#  Ubuntu Full System Setup Script v7 — Podman Edition
#  Türkçe/English — TR/EN bilingual support
#  ─────────────────────────────────────────────────────────────────────────────
#  SECTIONS / BÖLÜMLER:
#   1 — GNOME Tools (Tweaks, dconf-editor, Extension Manager, Dash to Panel/Dock)
#   2 — Touchpad (auto-disable on external mouse / USB fare takılınca kapat)
#   3 — WinApps  (KVM + Podman + Windows VM)
#   4 — App Refresh System / Uygulama Yenileme Sistemi
#
#  MODES / MODLAR:
#   install   — Full installation / Tam kurulum
#   uninstall — Complete removal   / Tam kaldırma
#
#  Usage / Kullanım:
#    chmod +x ubuntu-full-setup.sh
#    ./ubuntu-full-setup.sh
#
#  NOTE: WinApps setup.sh içeriği script içine gömülmüştür — depo silinse
#        bile çalışmaya devam eder.
# ==============================================================================

set -euo pipefail

# ─────────────────────────────────────────────
# Sabitler / Constants
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
readonly PODMAN_SOCKET="/run/podman/podman.sock"

# Mevcut Windows VM'i koruyarak sadece WinApps config yenileme modu için bayrak.
# When 1: Windows installation is skipped; only config files and WinApps are (re)configured.
# Set via main menu option [4] (Reconfigure) or interactively in cleanup_existing().
KEEP_EXISTING_WINDOWS=0

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ─────────────────────────────────────────────
# Renkler ve yardımcı fonksiyonlar
# ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ─────────────────────────────────────────────
# Dil / Language (tr | en)
# ─────────────────────────────────────────────
SCRIPT_LANG="tr"

detect_language() {
  local sys_lang="${LANG:-}"
  if [[ "$sys_lang" =~ ^tr ]]; then
    SCRIPT_LANG="tr"
  else
    SCRIPT_LANG="en"
  fi
}

msg() { [[ "$SCRIPT_LANG" == "tr" ]] && echo -e "$1" || echo -e "$2"; }

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
    echo "║       Ubuntu Tam Sistem Kurulum Scripti v7 — Podman Edition       ║"
    echo "║   GNOME + Touchpad + WinApps (Podman) + Yenileme  [TR/EN]         ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  else
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║       Ubuntu Full System Setup Script v7 — Podman Edition        ║"
    echo "║   GNOME + Touchpad + WinApps (Podman) + Refresh  [TR/EN]          ║"
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
    read -rsp "$(echo -e "  ${CYAN}Tekrar girin / Re-enter: ${NC}")" p2; echo
    [[ "$p1" == "$p2" ]] && { printf -v "$var" '%s' "$p1"; break; }
    warn "$(msg 'Parolalar eşleşmedi, tekrar deneyin.' 'Passwords did not match, try again.')"
  done
}

# ─────────────────────────────────────────────
# Podman compose çalıştırıcı
# Rootful podman (sudo) ile çalışır (KVM erişimi için).
# Önce Python tabanlı 'podman-compose' kullanılır; Docker plugin'ini
# devre dışı bırakır. Fallback: podman compose --compose-provider olmadan.
# ─────────────────────────────────────────────
podman_compose_run() {
  # Her zaman doğrudan 'podman-compose' (Python) kullan.
  # 'podman compose' komutu, sistemde /usr/libexec/docker/cli-plugins/docker-compose
  # varsa Docker plugin'ine devreder — bunu asla kullanma.
  if command -v podman-compose &>/dev/null; then
    sudo podman-compose "$@"
    return
  fi
  error "$(msg \
    'podman-compose bulunamadı! Kurmak için: sudo pip3 install podman-compose' \
    'podman-compose not found! Install with: sudo pip3 install podman-compose')"
}

# Ham podman komut çalıştırıcı (rootful)
podman_run() {
  sudo podman "$@"
}

# ─────────────────────────────────────────────
# GÖMÜLÜ WinApps setup.sh
# Bu içerik https://github.com/winapps-org/winapps adresinden alınmıştır.
# Depo silinse bile script çalışmaya devam eder.
# ─────────────────────────────────────────────
_write_winapps_setup_sh() {
  local target="$1"
  cat > "$target" <<'__WINAPPS_SETUP_SH_END__'
#!/usr/bin/env bash

# shellcheck disable=SC2034           # Silence warnings regarding unused variables globally.

### GLOBAL CONSTANTS ###
# ANSI ESCAPE SEQUENCES
readonly BOLD_TEXT="\033[1m"          # Bold
readonly CLEAR_TEXT="\033[0m"         # Clear
readonly COMMAND_TEXT="\033[0;37m"    # Grey
readonly DONE_TEXT="\033[0;32m"       # Green
readonly ERROR_TEXT="\033[1;31m"      # Bold + Red
readonly EXIT_TEXT="\033[1;41;37m"    # Bold + White + Red Background
readonly FAIL_TEXT="\033[0;91m"       # Bright Red
readonly INFO_TEXT="\033[0;33m"       # Orange/Yellow
readonly SUCCESS_TEXT="\033[1;42;37m" # Bold + White + Green Background
readonly WARNING_TEXT="\033[1;33m"    # Bold + Orange/Yellow

# ERROR CODES
readonly EC_FAILED_CD="1"        # Failed to change directory to location of script.
readonly EC_BAD_ARGUMENT="2"     # Unsupported argument passed to script.
readonly EC_EXISTING_INSTALL="3" # Existing conflicting WinApps installation.
readonly EC_NO_CONFIG="4"        # Absence of a valid WinApps configuration file.
readonly EC_MISSING_DEPS="5"     # Missing dependencies.
readonly EC_NO_SUDO="6"          # Insufficient privileges to invoke superuser access.
readonly EC_NOT_IN_GROUP="7"     # Current user not in group 'libvirt' and/or 'kvm'.
readonly EC_VM_OFF="8"           # Windows 'libvirt' VM powered off.
readonly EC_VM_PAUSED="9"        # Windows 'libvirt' VM paused.
readonly EC_VM_ABSENT="10"       # Windows 'libvirt' VM does not exist.
readonly EC_CONTAINER_OFF="11"   # Windows Docker container is not running.
readonly EC_NO_IP="12"           # Windows does not have an IP address.
readonly EC_BAD_PORT="13"        # Windows is unreachable via RDP_PORT.
readonly EC_RDP_FAIL="14"        # FreeRDP failed to establish a connection with Windows.
readonly EC_APPQUERY_FAIL="15"   # Failed to query Windows for installed applications.
readonly EC_INVALID_FLAVOR="16"  # Backend specified is not 'libvirt', 'docker' or 'podman'.

# PATHS
# 'BIN'
readonly SYS_BIN_PATH="/usr/local/bin"                  # UNIX path to 'bin' directory for a '--system' WinApps installation.
readonly USER_BIN_PATH="${HOME}/.local/bin"             # UNIX path to 'bin' directory for a '--user' WinApps installation.
readonly USER_BIN_PATH_WIN='\\tsclient\home\.local\bin' # WINDOWS path to 'bin' directory for a '--user' WinApps installation.
# 'SOURCE'
readonly SYS_SOURCE_PATH="${SYS_BIN_PATH}/winapps-src" # UNIX path to WinApps source directory for a '--system' WinApps installation.
readonly USER_SOURCE_PATH="${USER_BIN_PATH}/winapps-src" # UNIX path to WinApps source directory for a '--user' WinApps installation.
# 'APP'
readonly SYS_APP_PATH="/usr/share/applications"                        # UNIX path to 'applications' directory for a '--system' WinApps installation.
readonly USER_APP_PATH="${HOME}/.local/share/applications"             # UNIX path to 'applications' directory for a '--user' WinApps installation.
readonly USER_APP_PATH_WIN='\\tsclient\home\.local\share\applications' # WINDOWS path to 'applications' directory for a '--user' WinApps installation.
# 'APPDATA'
readonly SYS_APPDATA_PATH="/usr/local/share/winapps"                  # UNIX path to 'application data' directory for a '--system' WinApps installation.
readonly USER_APPDATA_PATH="${HOME}/.local/share/winapps"             # UNIX path to 'application data' directory for a '--user' WinApps installation.
readonly USER_APPDATA_PATH_WIN='\\tsclient\home\.local\share\winapps' # WINDOWS path to 'application data' directory for a '--user' WinApps installation.
# 'Installed Batch Script'
readonly BATCH_SCRIPT_PATH="${USER_APPDATA_PATH}/installed.bat"          # UNIX path to a batch script used to search Windows for applications.
readonly BATCH_SCRIPT_PATH_WIN="${USER_APPDATA_PATH_WIN}\\installed.bat" # WINDOWS path to a batch script used to search Windows for applications.
# 'Installed File'
readonly TMP_INST_FILE_PATH="${USER_APPDATA_PATH}/installed.tmp"          # UNIX path to a temporary file containing the names of detected officially supported applications.
readonly TMP_INST_FILE_PATH_WIN="${USER_APPDATA_PATH_WIN}\\installed.tmp" # WINDOWS path to a temporary file containing the names of detected officially supported applications.
readonly INST_FILE_PATH="${USER_APPDATA_PATH}/installed"                  # UNIX path to a file containing the names of detected officially supported applications.
readonly INST_FILE_PATH_WIN="${USER_APPDATA_PATH_WIN}\\installed"         # WINDOWS path to a file containing the names of detected officially supported applications.
# 'PowerShell Script'
readonly PS_SCRIPT_PATH="./install/ExtractPrograms.ps1"                          # UNIX path to a PowerShell script used to store the names, executable paths and icons (base64) of detected applications.
readonly PS_SCRIPT_HOME_PATH="${USER_APPDATA_PATH}/ExtractPrograms.ps1"          # UNIX path to a copy of the PowerShell script within the user's home directory to enable access by Windows.
readonly PS_SCRIPT_HOME_PATH_WIN="${USER_APPDATA_PATH_WIN}\\ExtractPrograms.ps1" # WINDOWS path to a copy of the PowerShell script within the user's home directory to enable access by Windows.
# 'Detected File'
readonly DETECTED_FILE_PATH="${USER_APPDATA_PATH}/detected"          # UNIX path to a file containing the output generated by the PowerShell script, formatted to define bash arrays.
readonly DETECTED_FILE_PATH_WIN="${USER_APPDATA_PATH_WIN}\\detected" # WINDOWS path to a file containing the output generated by the PowerShell script, formatted to define bash arrays.
# 'FreeRDP Connection Test File'
readonly TEST_PATH="${USER_APPDATA_PATH}/FreeRDP_Connection_Test"          # UNIX path to temporary file whose existence is used to confirm a successful RDP connection was established.
readonly TEST_PATH_WIN="${USER_APPDATA_PATH_WIN}\\FreeRDP_Connection_Test" # WINDOWS path to temporary file whose existence is used to confirm a successful RDP connection was established.
# 'WinApps Configuration File'
readonly CONFIG_PATH="${HOME}/.config/winapps/winapps.conf" # UNIX path to the WinApps configuration file.
# 'Inquirer Bash Script'
readonly INQUIRER_PATH="./install/inquirer.sh" # UNIX path to the 'inquirer' script, which is used to produce selection menus.

# REMOTE DESKTOP CONFIGURATION
readonly RDP_PORT=3389         # Port used for RDP on Windows.
readonly DOCKER_IP="127.0.0.1" # Localhost.

### GLOBAL VARIABLES ###
# USER INPUT
OPT_SYSTEM=0    # Set to '1' if the user specifies '--system'.
OPT_USER=0      # Set to '1' if the user specifies '--user'.
OPT_UNINSTALL=0 # Set to '1' if the user specifies '--uninstall'.
OPT_AOSA=0      # Set to '1' if the user specifies '--setupAllOfficiallySupportedApps'.
OPT_ADD_APPS=0  # Set to '1' if the user specifies '--add-apps'.

# WINAPPS CONFIGURATION FILE
RDP_USER=""          # Imported variable.
RDP_PASS=""          # Imported variable.
RDP_ASKPASS=""       # Imported variable.
RDP_DOMAIN=""        # Imported variable.
RDP_IP=""            # Imported variable.
VM_NAME="RDPWindows" # Name of the Windows VM (FOR 'libvirt' ONLY).
WAFLAVOR="docker"    # Imported variable.
RDP_SCALE=100        # Imported variable.
RDP_FLAGS=""         # Imported variable.
DEBUG="true"         # Imported variable.
FREERDP_COMMAND=""   # Imported variable.

PORT_TIMEOUT=5      # Default port check timeout.
RDP_TIMEOUT=30      # Default RDP connection test timeout.
APP_SCAN_TIMEOUT=60 # Default application scan timeout.

# PERMISSIONS AND DIRECTORIES
SUDO=""         # Set to "sudo" if the user specifies '--system', or "" if the user specifies '--user'.
BIN_PATH=""     # Set to $SYS_BIN_PATH if the user specifies '--system', or $USER_BIN_PATH if the user specifies '--user'.
APP_PATH=""     # Set to $SYS_APP_PATH if the user specifies '--system', or $USER_APP_PATH if the user specifies '--user'.
APPDATA_PATH="" # Set to $SYS_APPDATA_PATH if the user specifies '--system', or $USER_APPDATA_PATH if the user specifies '--user'.
SOURCE_PATH=""  # Set to $SYS_SOURCE_PATH if the user specifies '--system', or $USER_SOURCE_PATH if the user specifies '--user'.

# INSTALLATION PROCESS
INSTALLED_EXES=() # List of executable file names of officially supported applications that have already been configured during the current installation process.

### TRAPS ###
set -o errtrace              # Ensure traps are inherited by all shell functions and subshells.
trap "waTerminateScript" ERR # Catch non-zero return values.

### FUNCTIONS ###
# Name: 'waTerminateScript'
# Role: Terminates the script when a non-zero return value is encountered.
# shellcheck disable=SC2329 # Silence warning regarding this function never being invoked (shellCheck is currently bad at figuring out functions that are invoked via trap).
function waTerminateScript() {
    # Store the non-zero exit status received by the trap.
    local EXIT_STATUS=$?

    # Display the exit status.
    echo -e "${EXIT_TEXT}Exiting with status '${EXIT_STATUS}'.${CLEAR_TEXT}"

    # Terminate the script.
    exit "$EXIT_STATUS"
}
# Name: 'waUsage'
# Role: Displays usage information for the script.
function waUsage() {
    echo -e "Usage:
  ${COMMAND_TEXT}    --user${CLEAR_TEXT}                                        # Install WinApps and selected applications in ${HOME}
  ${COMMAND_TEXT}    --system${CLEAR_TEXT}                                      # Install WinApps and selected applications in /usr
  ${COMMAND_TEXT}    --user --setupAllOfficiallySupportedApps${CLEAR_TEXT}      # Install WinApps and all officially supported applications in ${HOME}
  ${COMMAND_TEXT}    --system --setupAllOfficiallySupportedApps${CLEAR_TEXT}    # Install WinApps and all officially supported applications in /usr
  ${COMMAND_TEXT}    --user --uninstall${CLEAR_TEXT}                            # Uninstall everything in ${HOME}
  ${COMMAND_TEXT}    --system --uninstall${CLEAR_TEXT}                          # Uninstall everything in /usr
  ${COMMAND_TEXT}    --user --add-apps${CLEAR_TEXT}                             # Add new applications to existing installation in ${HOME}
  ${COMMAND_TEXT}    --system --add-apps${CLEAR_TEXT}                           # Add new applications to existing installation in /usr
  ${COMMAND_TEXT}    --help${CLEAR_TEXT}                                        # Display this usage message."
}


# Name: 'waGetSourceCode'
# Role: Grab the WinApps source code using Git.
function waGetSourceCode() {
    # Declare variables.
    local SCRIPT_DIR_PATH="" # Stores the absolute path of the directory containing the script.

    # Determine the absolute path to the directory containing the script.
    SCRIPT_DIR_PATH=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")

    # Check if winapps is currently installed on $SOURCE_PATH
    if [[ -f "$SCRIPT_DIR_PATH/winapps" && "$SCRIPT_DIR_PATH" != "$SOURCE_PATH" ]]; then
        # Display a warning.
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT} You are running a WinApps installation located outside of default location '${SOURCE_PATH}'. A new installation will be created."
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT} You might want to remove your old installation on '${SCRIPT_DIR_PATH}'."
    fi

    if [[ ! -d "$SOURCE_PATH" ]]; then
        $SUDO git clone --recurse-submodules --remote-submodules https://github.com/winapps-org/winapps.git "$SOURCE_PATH"
    else
        echo -e "${INFO_TEXT}WinApps installation already present at ${CLEAR_TEXT}${COMMAND_TEXT}${SOURCE_PATH}${CLEAR_TEXT}${INFO_TEXT}. Updating...${CLEAR_TEXT}"
        $SUDO git -C "$SOURCE_PATH" pull --no-rebase
    fi

    # Silently change the working directory.
    if ! cd "$SOURCE_PATH" &>/dev/null; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}DIRECTORY CHANGE FAILURE.${CLEAR_TEXT}"

        # Display error details.
        echo -e "${INFO_TEXT}Failed to change the working directory to ${CLEAR_TEXT}${COMMAND_TEXT}${SOURCE_PATH}${CLEAR_TEXT}${INFO_TEXT}.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Ensure:"
        echo -e "  - ${COMMAND_TEXT}${SOURCE_PATH}${CLEAR_TEXT} exists."
        echo -e "  - ${COMMAND_TEXT}${SOURCE_PATH}${CLEAR_TEXT} has been cloned and checked out properly."
        echo -e "  - The current user has sufficient permissions to access and write to ${COMMAND_TEXT}${SOURCE_PATH}${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_FAILED_CD"
    fi
}

# Name: 'waGetInquirer'
# Role: Loads the inquirer script, even if the source isn't cloned yet
function waGetInquirer() {
    local INQUIRER=$INQUIRER_PATH

    if [ -d "$SYS_SOURCE_PATH" ]; then
        INQUIRER=$SYS_SOURCE_PATH/$INQUIRER_PATH
    elif [ -d "$USER_SOURCE_PATH" ] ; then
        INQUIRER=$USER_SOURCE_PATH/$INQUIRER_PATH
    else
        INQUIRER="/tmp/waInquirer.sh"
        rm -f "$INQUIRER"

        curl -o "$INQUIRER" "https://raw.githubusercontent.com/winapps-org/winapps/main/install/inquirer.sh"
    fi

    # shellcheck source=/dev/null # Exclude this file from being checked by ShellCheck.
    source "$INQUIRER"
}

# Name: 'waCheckInput'
# Role: Sanitises input and guides users through selecting appropriate options if no arguments are provided.
function waCheckInput() {
    # Declare variables.
    local OPTIONS=()      # Stores the options.
    local SELECTED_OPTION # Stores the option selected by the user.

    if [[ $# -gt 0 ]]; then
        # Parse arguments.
        for argument in "$@"; do
            case "$argument" in
            "--user")
                OPT_USER=1
                ;;
            "--system")
                OPT_SYSTEM=1
                ;;
            "--setupAllOfficiallySupportedApps")
                OPT_AOSA=1
                ;;
            "--uninstall")
                OPT_UNINSTALL=1
                ;;
            "--add-apps")
                OPT_ADD_APPS=1
                ;;
            "--help")
                waUsage
                exit 0
                ;;
            *)
                # Display the error type.
                echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}INVALID ARGUMENT.${CLEAR_TEXT}"

                # Display the error details.
                echo -e "${INFO_TEXT}Unsupported argument${CLEAR_TEXT} ${COMMAND_TEXT}${argument}${CLEAR_TEXT}${INFO_TEXT}.${CLEAR_TEXT}"

                # Display the suggested action(s).
                echo "--------------------------------------------------------------------------------"
                waUsage
                echo "--------------------------------------------------------------------------------"

                # Terminate the script.
                return "$EC_BAD_ARGUMENT"
                ;;
            esac
        done
    else
        # Install vs. uninstall?
        OPTIONS=("Install" "Uninstall")
        inqMenu "Install or uninstall WinApps?" OPTIONS SELECTED_OPTION

        # Set flags.
        if [[ $SELECTED_OPTION == "Uninstall" ]]; then
            OPT_UNINSTALL=1
        fi

        # User vs. system?
        OPTIONS=("Current User" "System")
        inqMenu "Configure WinApps for the current user '$(whoami)' or the whole system?" OPTIONS SELECTED_OPTION

        # Set flags.
        if [[ $SELECTED_OPTION == "Current User" ]]; then
            OPT_USER=1
        elif [[ $SELECTED_OPTION == "System" ]]; then
            OPT_SYSTEM=1
        fi

        # Automatic vs. manual?
        if [ "$OPT_UNINSTALL" -eq 0 ]; then
            OPTIONS=("Manual (Default)" "Automatic")
            inqMenu "Automatically install supported applications or choose manually?" OPTIONS SELECTED_OPTION

            # Set flags.
            if [[ $SELECTED_OPTION == "Automatic" ]]; then
                OPT_AOSA=1
            fi
        fi

        # Newline.
        echo ""
    fi

    # Simultaneous 'User' and 'System'.
    if [ "$OPT_SYSTEM" -eq 1 ] && [ "$OPT_USER" -eq 1 ]; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}CONFLICTING ARGUMENTS.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}You cannot specify both${CLEAR_TEXT} ${COMMAND_TEXT}--user${CLEAR_TEXT} ${INFO_TEXT}and${CLEAR_TEXT} ${COMMAND_TEXT}--system${CLEAR_TEXT} ${INFO_TEXT}simultaneously.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        waUsage
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_BAD_ARGUMENT"
    fi

    # Simultaneous 'Uninstall' and 'AOSA'.
    if [ "$OPT_UNINSTALL" -eq 1 ] && [ "$OPT_AOSA" -eq 1 ]; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}CONFLICTING ARGUMENTS.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}You cannot specify both${CLEAR_TEXT} ${COMMAND_TEXT}--uninstall${CLEAR_TEXT} ${INFO_TEXT}and${CLEAR_TEXT} ${COMMAND_TEXT}--aosa${CLEAR_TEXT} ${INFO_TEXT}simultaneously.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        waUsage
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_BAD_ARGUMENT"
    fi

    # Simultaneous 'Uninstall' and 'Add Apps'.
    if [ "$OPT_UNINSTALL" -eq 1 ] && [ "$OPT_ADD_APPS" -eq 1 ]; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}CONFLICTING ARGUMENTS.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}You cannot specify both${CLEAR_TEXT} ${COMMAND_TEXT}--uninstall${CLEAR_TEXT} ${INFO_TEXT}and${CLEAR_TEXT} ${COMMAND_TEXT}--add-apps${CLEAR_TEXT} ${INFO_TEXT}simultaneously.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        waUsage
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_BAD_ARGUMENT"
    fi

    # Simultaneous 'AOSA' and 'Add Apps'.
    if [ "$OPT_AOSA" -eq 1 ] && [ "$OPT_ADD_APPS" -eq 1 ]; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}CONFLICTING ARGUMENTS.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}You cannot specify both${CLEAR_TEXT} ${COMMAND_TEXT}--setupAllOfficiallySupportedApps${CLEAR_TEXT} ${INFO_TEXT}and${CLEAR_TEXT} ${COMMAND_TEXT}--add-apps${CLEAR_TEXT} ${INFO_TEXT}simultaneously.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        waUsage
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_BAD_ARGUMENT"
    fi

    # No 'User' or 'System'.
    if [ "$OPT_SYSTEM" -eq 0 ] && [ "$OPT_USER" -eq 0 ]; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}INSUFFICIENT ARGUMENTS.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}You must specify either${CLEAR_TEXT} ${COMMAND_TEXT}--user${CLEAR_TEXT} ${INFO_TEXT}or${CLEAR_TEXT} ${COMMAND_TEXT}--system${CLEAR_TEXT} ${INFO_TEXT}to proceed.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        waUsage
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_BAD_ARGUMENT"
    fi
}

# Name: 'waConfigurePathsAndPermissions'
# Role: Sets paths and adjusts permissions as specified.
function waConfigurePathsAndPermissions() {
    if [ "$OPT_USER" -eq 1 ]; then
        SUDO=""
        SOURCE_PATH="$USER_SOURCE_PATH"
        BIN_PATH="$USER_BIN_PATH"
        APP_PATH="$USER_APP_PATH"
        APPDATA_PATH="$USER_APPDATA_PATH"
    elif [ "$OPT_SYSTEM" -eq 1 ]; then
        SUDO="sudo"
        SOURCE_PATH="$SYS_SOURCE_PATH"
        BIN_PATH="$SYS_BIN_PATH"
        APP_PATH="$SYS_APP_PATH"
        APPDATA_PATH="$SYS_APPDATA_PATH"

        # Preemptively obtain superuser privileges.
        sudo -v || {
            # Display the error type.
            echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}AUTHENTICATION FAILURE.${CLEAR_TEXT}"

            # Display the error details.
            echo -e "${INFO_TEXT}Failed to gain superuser privileges.${CLEAR_TEXT}"

            # Display the suggested action(s).
            echo "--------------------------------------------------------------------------------"
            echo "Please check your password and try again."
            echo "If you continue to experience issues, contact your system administrator."
            echo "--------------------------------------------------------------------------------"

            # Terminate the script.
            return "$EC_NO_SUDO"
        }
    fi
}
# Name: 'waCheckExistingInstall'
# Role: Identifies any existing WinApps installations that may conflict with the new installation.
function waCheckExistingInstall() {
    # Print feedback.
    echo -n "Checking for existing conflicting WinApps installations... "

    # If --add-apps is specified, we don't want to fail if an installation exists
    if [ "$OPT_ADD_APPS" -eq 1 ]; then
        # Check for an existing 'user' installation.
        if [[ -f "${USER_BIN_PATH}/winapps" && -d "${USER_SOURCE_PATH}/winapps" ]]; then
            # Complete the previous line.
            echo -e "${DONE_TEXT}Found!${CLEAR_TEXT}"
            echo -e "${INFO_TEXT}Adding new applications to existing user installation.${CLEAR_TEXT}"
            return 0
        fi

        # Check for an existing 'system' installation.
        if [[ -f "${SYS_BIN_PATH}/winapps" && -d "${SYS_SOURCE_PATH}/winapps" ]]; then
            # Complete the previous line.
            echo -e "${DONE_TEXT}Found!${CLEAR_TEXT}"
            echo -e "${INFO_TEXT}Adding new applications to existing system installation.${CLEAR_TEXT}"
            return 0
        fi

        # If we're adding apps but no installation exists, that's an error
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}NO EXISTING WINAPPS INSTALLATION.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}No existing WinApps installation was detected.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please install WinApps first using ${COMMAND_TEXT}winapps-setup --user${CLEAR_TEXT} or ${COMMAND_TEXT}winapps-setup --system${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_EXISTING_INSTALL"
    fi

    # Check for an existing 'user' installation.
    if [[ -f "${USER_BIN_PATH}/winapps" || -d "${USER_SOURCE_PATH}/winapps" ]]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}EXISTING 'USER' WINAPPS INSTALLATION.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}A previous WinApps installation was detected for the current user.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please remove the existing WinApps installation using ${COMMAND_TEXT}winapps-setup --user --uninstall${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_EXISTING_INSTALL"
    fi

    # Check for an existing 'system' installation.
    if [[ -f "${SYS_BIN_PATH}/winapps" || -d "${SYS_SOURCE_PATH}/winapps" ]]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}EXISTING 'SYSTEM' WINAPPS INSTALLATION.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}A previous system-wide WinApps installation was detected.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please remove the existing WinApps installation using ${COMMAND_TEXT}winapps-setup --system --uninstall${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_EXISTING_INSTALL"
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}


# Name: 'waFixScale'
# Role: Since FreeRDP only supports '/scale' values of 100, 140 or 180, find the closest supported argument to the user's configuration.
function waFixScale() {
    # Define variables.
    local OLD_SCALE=100
    local VALID_SCALE_1=100
    local VALID_SCALE_2=140
    local VALID_SCALE_3=180

    # Check for an unsupported value.
    if [ "$RDP_SCALE" != "$VALID_SCALE_1" ] && [ "$RDP_SCALE" != "$VALID_SCALE_2" ] && [ "$RDP_SCALE" != "$VALID_SCALE_3" ]; then
        # Save the unsupported scale.
        OLD_SCALE="$RDP_SCALE"

        # Calculate the absolute differences.
        local DIFF_1=$(( RDP_SCALE > VALID_SCALE_1 ? RDP_SCALE - VALID_SCALE_1 : VALID_SCALE_1 - RDP_SCALE ))
        local DIFF_2=$(( RDP_SCALE > VALID_SCALE_2 ? RDP_SCALE - VALID_SCALE_2 : VALID_SCALE_2 - RDP_SCALE ))
        local DIFF_3=$(( RDP_SCALE > VALID_SCALE_3 ? RDP_SCALE - VALID_SCALE_3 : VALID_SCALE_3 - RDP_SCALE ))

        # Set the final scale to the valid scale value with the smallest absolute difference.
        if (( DIFF_1 <= DIFF_2 && DIFF_1 <= DIFF_3 )); then
            RDP_SCALE="$VALID_SCALE_1"
        elif (( DIFF_2 <= DIFF_1 && DIFF_2 <= DIFF_3 )); then
            RDP_SCALE="$VALID_SCALE_2"
        else
            RDP_SCALE="$VALID_SCALE_3"
        fi

        # Print feedback.
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT} Unsupported RDP_SCALE value '${OLD_SCALE}' detected. Defaulting to '${RDP_SCALE}'."
    fi
}

# Name: 'waLoadConfig'
# Role: Loads settings specified within the WinApps configuration file.
function waLoadConfig() {
    # Print feedback.
    echo -n "Attempting to load WinApps configuration file... "

    if [ ! -f "$CONFIG_PATH" ]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING CONFIGURATION FILE.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}A valid WinApps configuration file was not found.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please create a configuration file at ${COMMAND_TEXT}${CONFIG_PATH}${CLEAR_TEXT}."
        echo -e "See https://github.com/winapps-org/winapps?tab=readme-ov-file#step-3-create-a-winapps-configuration-file"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_NO_CONFIG"
    else
        # Load the WinApps configuration file.
        # shellcheck source=/dev/null # Exclude this file from being checked by ShellCheck.
        source "$CONFIG_PATH"

        # Send password on the command line if a command to retrieve the password from is not given
        # Otherwise, set FREERDP_ASKPASS which freerdp will read the stdout of to use as the password
        RDP_PASSWORD_ARG="/p:$RDP_PASS"

        if [[ ! -z "$RDP_ASKPASS" ]]; then
            export FREERDP_ASKPASS="$RDP_ASKPASS"
            unset RDP_PASSWORD_ARG
        fi
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waCheckScriptDependencies'
# Role: Terminate script if dependencies are missing.
function waCheckScriptDependencies() {
    # 'Git'
    if ! command -v git &>/dev/null; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Please install 'git' to proceed.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Debian/Ubuntu-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo apt install git${CLEAR_TEXT}"
        echo "Red Hat/Fedora-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo dnf install git${CLEAR_TEXT}"
        echo "Arch Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo pacman -S git${CLEAR_TEXT}"
        echo "Gentoo Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo emerge --ask dev-vcs/git${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_MISSING_DEPS"
    fi

    # 'curl'
    if ! command -v curl &>/dev/null; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Please install 'curl' to proceed.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Debian/Ubuntu-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo apt install curl${CLEAR_TEXT}"
        echo "Red Hat/Fedora-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo dnf install curl${CLEAR_TEXT}"
        echo "Arch Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo pacman -S curl${CLEAR_TEXT}"
        echo "Gentoo Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo emerge --ask net-misc/curl${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_MISSING_DEPS"
    fi

    # 'Dialog'.
    if ! command -v dialog &>/dev/null; then
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Please install 'dialog' to proceed.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Debian/Ubuntu-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo apt install dialog${CLEAR_TEXT}"
        echo "Red Hat/Fedora-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo dnf install dialog${CLEAR_TEXT}"
        echo "Arch Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo pacman -S dialog${CLEAR_TEXT}"
        echo "Gentoo Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo emerge --ask dialog${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_MISSING_DEPS"
    fi
}

# Name: 'waCheckInstallDependencies'
# Role: Terminate script if dependencies required to install WinApps are missing.
function waCheckInstallDependencies() {
    # Declare variables.
    local FREERDP_MAJOR_VERSION="" # Stores the major version of the installed copy of FreeRDP.

    # Print feedback.
    echo -n "Checking whether dependencies are installed... "

    # 'libnotify'
    if ! command -v notify-send &>/dev/null; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Please install 'libnotify' to proceed.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Debian/Ubuntu-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo apt install libnotify-bin${CLEAR_TEXT}"
        echo "Red Hat/Fedora-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo dnf install libnotify${CLEAR_TEXT}"
        echo "Arch Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo pacman -S libnotify${CLEAR_TEXT}"
        echo "Gentoo Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo emerge --ask x11-libs/libnotify${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_MISSING_DEPS"
    fi

    # 'Netcat'
    if ! command -v nc &>/dev/null; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Please install 'netcat' to proceed.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Debian/Ubuntu-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo apt install netcat${CLEAR_TEXT}"
        echo "Red Hat/Fedora-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo dnf install nmap-ncat${CLEAR_TEXT}"
        echo "Arch Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo pacman -S openbsd-netcat${CLEAR_TEXT}"
        echo "Gentoo Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo emerge --ask net-analyzer/netcat${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_MISSING_DEPS"
    fi

    # 'FreeRDP' (Version 3).
    # Attempt to set a FreeRDP command if the command variable is empty.
    if [ -z "$FREERDP_COMMAND" ]; then
        # Check common commands used to launch FreeRDP.
        if command -v xfreerdp &>/dev/null; then
            # Check FreeRDP major version is 3 or greater.
            FREERDP_MAJOR_VERSION=$(xfreerdp --version | head -n 1 | grep -o -m 1 '\b[0-9]\S*' | head -n 1 | cut -d'.' -f1)
            if [[ $FREERDP_MAJOR_VERSION =~ ^[0-9]+$ ]] && ((FREERDP_MAJOR_VERSION >= 3)); then
                FREERDP_COMMAND="xfreerdp"
            fi
        fi

        # Check for xfreerdp3 command as a fallback option.
        if [ -z "$FREERDP_COMMAND" ]; then
            if command -v xfreerdp3 &>/dev/null; then
                # Check FreeRDP major version is 3 or greater.
                FREERDP_MAJOR_VERSION=$(xfreerdp3 --version | head -n 1 | grep -o -m 1 '\b[0-9]\S*' | head -n 1 | cut -d'.' -f1)
                if [[ $FREERDP_MAJOR_VERSION =~ ^[0-9]+$ ]] && ((FREERDP_MAJOR_VERSION >= 3)); then
                    FREERDP_COMMAND="xfreerdp3"
                fi
            fi
        fi

        # Check for FreeRDP flatpak as a fallback option.
        if [ -z "$FREERDP_COMMAND" ]; then
            if command -v flatpak &>/dev/null; then
                if flatpak list --columns=application | grep -q "^com.freerdp.FreeRDP$"; then
                    # Check FreeRDP major version is 3 or greater.
                    FREERDP_MAJOR_VERSION=$(flatpak list --columns=application,version | grep "^com.freerdp.FreeRDP" | awk '{print $2}' | cut -d'.' -f1)
                    if [[ $FREERDP_MAJOR_VERSION =~ ^[0-9]+$ ]] && ((FREERDP_MAJOR_VERSION >= 3)); then
                        FREERDP_COMMAND="flatpak run --command=xfreerdp com.freerdp.FreeRDP"
                    fi
                fi
            fi
        fi
    fi

    if ! command -v "$FREERDP_COMMAND" &>/dev/null && [ "$FREERDP_COMMAND" != "flatpak run --command=xfreerdp com.freerdp.FreeRDP" ]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Please install 'FreeRDP' version 3 to proceed.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Debian/Ubuntu-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo apt install freerdp3-x11${CLEAR_TEXT}"
        echo "Red Hat/Fedora-based systems:"
        echo -e "  ${COMMAND_TEXT}sudo dnf install freerdp${CLEAR_TEXT}"
        echo "Arch Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo pacman -S freerdp${CLEAR_TEXT}"
        echo "Gentoo Linux systems:"
        echo -e "  ${COMMAND_TEXT}sudo emerge --ask net-misc/freerdp${CLEAR_TEXT}"
        echo ""
        echo "You can also install FreeRDP as a Flatpak."
        echo "Install Flatpak, add the Flathub repository and then install FreeRDP:"
        echo -e "${COMMAND_TEXT}flatpak install flathub com.freerdp.FreeRDP${CLEAR_TEXT}"
        echo -e "${COMMAND_TEXT}sudo flatpak override --filesystem=home com.freerdp.FreeRDP${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_MISSING_DEPS"
    fi

    # 'libvirt'/'virt-manager' + 'iproute2'.
    if [ "$WAFLAVOR" = "libvirt" ]; then
        if ! command -v virsh &>/dev/null; then
            # Complete the previous line.
            echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

            # Display the error type.
            echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

            # Display the error details.
            echo -e "${INFO_TEXT}Please install 'Virtual Machine Manager' to proceed.${CLEAR_TEXT}"

            # Display the suggested action(s).
            echo "--------------------------------------------------------------------------------"
            echo "Debian/Ubuntu-based systems:"
            echo -e "  ${COMMAND_TEXT}sudo apt install virt-manager${CLEAR_TEXT}"
            echo "Red Hat/Fedora-based systems:"
            echo -e "  ${COMMAND_TEXT}sudo dnf install virt-manager${CLEAR_TEXT}"
            echo "Arch Linux systems:"
            echo -e "  ${COMMAND_TEXT}sudo pacman -S virt-manager${CLEAR_TEXT}"
            echo "Gentoo Linux systems:"
            echo -e "  ${COMMAND_TEXT}sudo emerge --ask app-emulation/virt-manager${CLEAR_TEXT}"
            echo "--------------------------------------------------------------------------------"

            # Terminate the script.
            return "$EC_MISSING_DEPS"
        fi

        if ! command -v ip &>/dev/null; then
            # Complete the previous line.
            echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

            # Display the error type.
            echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

            # Display the error details.
            echo -e "${INFO_TEXT}Please install 'iproute2' to proceed.${CLEAR_TEXT}"

            # Display the suggested action(s).
            echo "--------------------------------------------------------------------------------"
            echo "Debian/Ubuntu-based systems:"
            echo -e "  ${COMMAND_TEXT}sudo apt install iproute2${CLEAR_TEXT}"
            echo "Red Hat/Fedora-based systems:"
            echo -e "  ${COMMAND_TEXT}sudo dnf install iproute${CLEAR_TEXT}"
            echo "Arch Linux systems:"
            echo -e "  ${COMMAND_TEXT}sudo pacman -S iproute2${CLEAR_TEXT}"
            echo "Gentoo Linux systems:"
            echo -e "  ${COMMAND_TEXT}sudo emerge --ask net-misc/iproute2${CLEAR_TEXT}"
            echo "--------------------------------------------------------------------------------"

            # Terminate the script.
            return "$EC_MISSING_DEPS"
        fi
    elif [ "$WAFLAVOR" = "docker" ]; then
        if ! command -v docker &>/dev/null; then
            # Complete the previous line.
            echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

            # Display the error type.
            echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

            # Display the error details.
            echo -e "${INFO_TEXT}Please install 'Docker Engine' to proceed.${CLEAR_TEXT}"

            # Display the suggested action(s).
            echo "--------------------------------------------------------------------------------"
            echo "Please visit https://docs.docker.com/engine/install/ for more information."
            echo "--------------------------------------------------------------------------------"

            # Terminate the script.
            return "$EC_MISSING_DEPS"
        fi
    elif [ "$WAFLAVOR" = "podman" ]; then
        if ! command -v podman-compose &>/dev/null || ! command -v podman &>/dev/null; then
            # Complete the previous line.
            echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

            # Display the error type.
            echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}MISSING DEPENDENCIES.${CLEAR_TEXT}"

            # Display the error details.
            echo -e "${INFO_TEXT}Please install 'podman' and 'podman-compose' to proceed.${CLEAR_TEXT}"

            # Display the suggested action(s).
            echo "--------------------------------------------------------------------------------"
            echo "Please visit https://podman.io/docs/installation for more information."
            echo "Please visit https://github.com/containers/podman-compose for more information."
            echo "--------------------------------------------------------------------------------"

            # Terminate the script.
            return "$EC_MISSING_DEPS"
        fi
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waCheckGroupMembership'
# Role: Ensures the current user is part of the required groups.
function waCheckGroupMembership() {
    # Print feedback.
    echo -n "Checking whether the user '$(whoami)' is part of the required groups... "

    # Declare variables.
    local USER_GROUPS="" # Stores groups the current user belongs to.

    # Identify groups the current user belongs to.
    USER_GROUPS=$(groups "$(whoami)")

    if ! (echo "$USER_GROUPS" | grep -q -E "\blibvirt\b") || ! (echo "$USER_GROUPS" | grep -q -E "\bkvm\b"); then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}GROUP MEMBERSHIP CHECK ERROR.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}The current user '$(whoami)' is not part of group 'libvirt' and/or group 'kvm'.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Please run the below commands, followed by a system reboot:"
        echo -e "${COMMAND_TEXT}sudo usermod -a -G libvirt $(whoami)${CLEAR_TEXT}"
        echo -e "${COMMAND_TEXT}sudo usermod -a -G kvm $(whoami)${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_NOT_IN_GROUP"
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waCheckVMRunning'
# Role: Checks the state of the Windows 'libvirt' VM to ensure it is running.
function waCheckVMRunning() {
    # Print feedback.
    echo -n "Checking the status of the Windows VM... "

    # Obtain VM Status
    VM_PAUSED=0
    virsh list --state-paused --name | grep -Fxq -- "$VM_NAME" || VM_PAUSED="$?"
    VM_RUNNING=0
    virsh list --state-running --name | grep -Fxq -- "$VM_NAME" || VM_RUNNING="$?"
    VM_SHUTOFF=0
    virsh list --state-shutoff --name | grep -Fxq -- "$VM_NAME" || VM_SHUTOFF="$?"

    if [[ $VM_SHUTOFF == "0" ]]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}WINDOWS VM NOT RUNNING.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}The Windows VM '${VM_NAME}' is powered off.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Please run the below command to start the Windows VM:"
        echo -e "${COMMAND_TEXT}virsh start ${VM_NAME}${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_VM_OFF"
    elif [[ $VM_PAUSED == "0" ]]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}WINDOWS VM NOT RUNNING.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}The Windows VM '${VM_NAME}' is paused.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Please run the below command to resume the Windows VM:"
        echo -e "${COMMAND_TEXT}virsh resume ${VM_NAME}${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_VM_PAUSED"
    elif [[ $VM_RUNNING != "0" ]]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}WINDOWS VM DOES NOT EXIST.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}The Windows VM '${VM_NAME}' could not be found.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Please ensure a Windows VM with the name '${VM_NAME}' exists."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_VM_ABSENT"
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waCheckContainerRunning'
# Role: Throw an error if the Docker/Podman container is not running.
function waCheckContainerRunning() {
    # Print feedback.
    echo -n "Checking container status... "

    # Declare variables.
    local CONTAINER_STATE=""
    local COMPOSE_COMMAND=""

    # Determine the state of the container.
    # For rootful Podman (PODMAN_ROOTFUL=1) the socket is owned by root; use sudo.
    if [ "$WAFLAVOR" = "podman" ] && [ "${PODMAN_ROOTFUL:-0}" = "1" ]; then
        CONTAINER_STATE=$(sudo podman ps --all --filter name="WinApps" --format '{{.Status}}')
    else
        CONTAINER_STATE=$("$WAFLAVOR" ps --all --filter name="WinApps" --format '{{.Status}}')
    fi
    CONTAINER_STATE=${CONTAINER_STATE,,} # Convert the string to lowercase.
    CONTAINER_STATE=${CONTAINER_STATE%% *} # Extract the first word.

    # Determine the compose command.
    case "$WAFLAVOR" in
        "docker") COMPOSE_COMMAND="docker compose" ;;
        "podman") COMPOSE_COMMAND="podman-compose" ;;
    esac

    # Check container state.
    if [[ "$CONTAINER_STATE" != "up" ]]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}CONTAINER NOT RUNNING.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Windows is not running.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Please ensure Windows is powered on:"
        echo -e "${COMMAND_TEXT}${COMPOSE_COMMAND} --file ~/.config/winapps/compose.yaml start${CLEAR_TEXT}"
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_CONTAINER_OFF"
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waCheckPortOpen'
# Role: Assesses whether the RDP port on Windows is open.
function waCheckPortOpen() {
    # Print feedback.
    echo -n "Checking for an open RDP Port on Windows... "

    # Declare variables.
    local VM_MAC="" # Stores the MAC address of the Windows VM.

    # Obtain Windows VM IP Address (FOR 'libvirt' ONLY)
    # Note: 'RDP_IP' should not be empty if 'WAFLAVOR' is 'docker', since it is set to localhost before this function is called.
    if [ -z "$RDP_IP" ] && [ "$WAFLAVOR" = "libvirt" ]; then
        VM_MAC=$(virsh domiflist "$VM_NAME" | grep -oE "([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})") # VM MAC address.
        RDP_IP=$(ip neigh show | grep "$VM_MAC" | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")         # VM IP address.

        if [ -z "$RDP_IP" ]; then
            # Complete the previous line.
            echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

            # Display the error type.
            echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}NETWORK CONFIGURATION ERROR.${CLEAR_TEXT}"

            # Display the error details.
            echo -e "${INFO_TEXT}The IP address of the Windows VM '${VM_NAME}' could not be found.${CLEAR_TEXT}"

            # Display the suggested action(s).
            echo "--------------------------------------------------------------------------------"
            echo "Please ensure networking is properly configured for the Windows VM."
            echo "--------------------------------------------------------------------------------"

            # Terminate the script.
            return "$EC_NO_IP"
        fi
    fi

    # Check for an open RDP port.
    if ! timeout "$PORT_TIMEOUT" nc -z "$RDP_IP" "$RDP_PORT" &>/dev/null; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}NETWORK CONFIGURATION ERROR.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Failed to establish a connection with Windows at '${RDP_IP}:${RDP_PORT}'.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo "Please ensure Remote Desktop is configured on Windows as per the WinApps README."
        echo -e "Then you can try increasing the ${COMMAND_TEXT}PORT_TIMEOUT${CLEAR_TEXT} in ${COMMAND_TEXT}${CONFIG_PATH}${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_BAD_PORT"
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waCheckRDPAccess'
# Role: Tests if Windows is accessible via RDP.
function waCheckRDPAccess() {
    # Print feedback.
    echo -n "Attempting to establish a Remote Desktop connection with Windows... "

    # Declare variables.
    local FREERDP_LOG=""  # Stores the path of the FreeRDP log file.
    local FREERDP_PROC="" # Stores the FreeRDP process ID.
    local ELAPSED_TIME="" # Stores the time counter.

    # Log file path.
    FREERDP_LOG="${USER_APPDATA_PATH}/FreeRDP_Test_$(date +'%Y%m%d_%H%M_%N').log"

    # Ensure the output directory exists.
    mkdir -p "$USER_APPDATA_PATH"

    # Remove existing 'FreeRDP Connection Test' file.
    rm -f "$TEST_PATH"

    # This command should create a file on the host filesystem before terminating the RDP session. This command is silently executed as a background process.
    # If the file is created, it means Windows received the command via FreeRDP successfully and can read and write to the Linux home folder.
    # Note: The following final line is expected within the log, indicating successful execution of the 'tsdiscon' command and termination of the RDP session.
    # [INFO][com.freerdp.core] - [rdp_print_errinfo]: ERRINFO_LOGOFF_BY_USER (0x0000000C):The disconnection was initiated by the user logging off their session on the server.
    # shellcheck disable=SC2140,SC2027,SC2086 # Disable warnings regarding unquoted strings.
    $FREERDP_COMMAND \
        $RDP_FLAGS_NON_WINDOWS \
        /cert:tofu \
        /d:"$RDP_DOMAIN" \
        /u:"$RDP_USER" \
        ${RDP_PASSWORD_ARG:+"$RDP_PASSWORD_ARG"} \
        /scale:"$RDP_SCALE" \
        +auto-reconnect \
        +home-drive \
        /app:program:"C:\Windows\System32\cmd.exe",cmd:"/C type NUL > $TEST_PATH_WIN && tsdiscon" \
        /v:"$RDP_IP" &>"$FREERDP_LOG" &

    # Store the FreeRDP process ID.
    FREERDP_PROC=$!

    # Initialise the time counter.
    ELAPSED_TIME=0

    # Wait a maximum of $RDP_TIMEOUT seconds for the background process to complete.
    while [ "$ELAPSED_TIME" -lt "$RDP_TIMEOUT" ]; do
        # Check if the FreeRDP process is complete or if the test file exists.
        if ! ps -p "$FREERDP_PROC" &>/dev/null || [ -f "$TEST_PATH" ]; then
            break
        fi

        # Wait for 5 seconds.
        sleep 5
        ELAPSED_TIME=$((ELAPSED_TIME + 5))
    done

    # Check if FreeRDP process is not complete.
    if ps -p "$FREERDP_PROC" &>/dev/null; then
        # SIGKILL FreeRDP.
        kill -9 "$FREERDP_PROC" &>/dev/null
    fi

    # Check if test file does not exist.
    if ! [ -f "$TEST_PATH" ]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}REMOTE DESKTOP PROTOCOL FAILURE.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}FreeRDP failed to establish a connection with Windows.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please view the log at ${COMMAND_TEXT}${FREERDP_LOG}${CLEAR_TEXT}."
        echo "Troubleshooting Tips:"
        echo "  - Ensure the user is logged out of Windows prior to initiating the WinApps installation."
        echo "  - Ensure the credentials within the WinApps configuration file are correct."
        echo -e "  - Utilise a new certificate by removing relevant certificate(s) in ${COMMAND_TEXT}${HOME}/.config/freerdp/server${CLEAR_TEXT}."
        echo -e "  - Try increasing the ${COMMAND_TEXT}RDP_TIMEOUT${CLEAR_TEXT} in ${COMMAND_TEXT}${CONFIG_PATH}${CLEAR_TEXT}."
        echo "  - If using 'libvirt', ensure the Windows VM is correctly named as specified within the README."
        echo "  - If using 'libvirt', ensure 'Remote Desktop' is enabled within the Windows VM."
        echo "  - If using 'libvirt', ensure you have merged 'RDPApps.reg' into the Windows VM's registry."
        echo "  - If using 'libvirt', try logging into and back out of the Windows VM within 'virt-manager' prior to initiating the WinApps installation."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_RDP_FAIL"
    else
        # Remove the temporary test file.
        rm -f "$TEST_PATH"
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waFindInstalled'
# Role: Identifies installed applications on Windows.
function waFindInstalled() {
    # Print feedback.
    echo -n "Checking for installed Windows applications... "

    # Declare variables.
    local FREERDP_LOG=""  # Stores the path of the FreeRDP log file.
    local FREERDP_PROC="" # Stores the FreeRDP process ID.
    local ELAPSED_TIME="" # Stores the time counter.

    # Log file path.
    FREERDP_LOG="${USER_APPDATA_PATH}/FreeRDP_Scan_$(date +'%Y%m%d_%H%M_%N').log"

    # Make the output directory if required.
    mkdir -p "$USER_APPDATA_PATH"

    # Remove temporary files from previous WinApps installations.
    rm -f "$BATCH_SCRIPT_PATH" "$TMP_INST_FILE_PATH" "$INST_FILE_PATH" "$PS_SCRIPT_HOME_PATH" "$DETECTED_FILE_PATH"

    # Copy PowerShell script to a directory within the user's home folder.
    # This will enable the PowerShell script to be accessed and executed by Windows.
    cp "$PS_SCRIPT_PATH" "$PS_SCRIPT_HOME_PATH"

    # Enumerate over each officially supported application.
    for APPLICATION in ./apps/*; do
        # Extract the name of the application from the absolute path of the folder.
        APPLICATION="$(basename "$APPLICATION")"

        if [[ "$APPLICATION" == "ms-office-protocol-handler.desktop" ]]; then
            continue
        fi

        # Source 'Info' File Containing:
        # - The Application Name          (FULL_NAME)
        # - The Shortcut Name             (NAME)
        # - Application Categories        (CATEGORIES)
        # - Executable Path               (WIN_EXECUTABLE)
        # - Supported MIME Types          (MIME_TYPES)
        # - Application Icon              (ICON)
        # shellcheck source=/dev/null # Exclude this file from being checked by ShellCheck.
        source "./apps/${APPLICATION}/info"

        # Append commands to batch file.
        echo "IF EXIST \"${WIN_EXECUTABLE}\" ECHO ${APPLICATION}^|^|^|${WIN_EXECUTABLE} >> ${TMP_INST_FILE_PATH_WIN}" >>"$BATCH_SCRIPT_PATH"
    done

    # Append a command to the batch script to run the PowerShell script and store its output in the 'detected' file.
    # shellcheck disable=SC2129 # Silence warning regarding repeated redirects.
    echo "powershell.exe -ExecutionPolicy Bypass -File ${PS_SCRIPT_HOME_PATH_WIN} > ${DETECTED_FILE_PATH_WIN}" >>"$BATCH_SCRIPT_PATH"

    # Append a command to the batch script to rename the temporary file containing the names of all detected officially supported applications.
    echo "RENAME ${TMP_INST_FILE_PATH_WIN} installed" >>"$BATCH_SCRIPT_PATH"

    # Append a command to the batch script to terminate the remote desktop session once all previous commands are complete.
    echo "tsdiscon" >>"$BATCH_SCRIPT_PATH"

    # Silently execute the batch script within Windows in the background (Log Output To File)
    # Note: The following final line is expected within the log, indicating successful execution of the 'tsdiscon' command and termination of the RDP session.
    # [INFO][com.freerdp.core] - [rdp_print_errinfo]: ERRINFO_LOGOFF_BY_USER (0x0000000C):The disconnection was initiated by the user logging off their session on the server.
    # shellcheck disable=SC2140,SC2027,SC2086 # Disable warnings regarding unquoted strings.
    $FREERDP_COMMAND \
        $RDP_FLAGS_NON_WINDOWS \
        /cert:tofu \
        /d:"$RDP_DOMAIN" \
        /u:"$RDP_USER" \
        ${RDP_PASSWORD_ARG:+"$RDP_PASSWORD_ARG"} \
        /scale:"$RDP_SCALE" \
        +auto-reconnect \
        +home-drive \
        /app:program:"C:\Windows\System32\cmd.exe",cmd:"/C "$BATCH_SCRIPT_PATH_WIN"" \
        /v:"$RDP_IP" &>"$FREERDP_LOG" &

    # Store the FreeRDP process ID.
    FREERDP_PROC=$!

    # Initialise the time counter.
    ELAPSED_TIME=0

    # Wait a maximum of $APP_SCAN_TIMEOUT seconds for the batch script to finish running.
    while [ $ELAPSED_TIME -lt "$APP_SCAN_TIMEOUT" ]; do
        # Check if the FreeRDP process is complete or if the 'installed' file exists.
        if ! ps -p "$FREERDP_PROC" &>/dev/null || [ -f "$INST_FILE_PATH" ]; then
            break
        fi

        # Wait for 5 seconds.
        sleep 5
        ELAPSED_TIME=$((ELAPSED_TIME + 5))
    done

    # Check if the FreeRDP process is not complete.
    if ps -p "$FREERDP_PROC" &>/dev/null; then
        # SIGKILL FreeRDP.
        kill -9 "$FREERDP_PROC" &>/dev/null
    fi

    # Check if test file does not exist.
    if ! [ -f "$INST_FILE_PATH" ]; then
        # Complete the previous line.
        echo -e "${FAIL_TEXT}Failed!${CLEAR_TEXT}\n"

        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}APPLICATION QUERY FAILURE.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}Failed to query Windows for installed applications.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please view the log at ${COMMAND_TEXT}${FREERDP_LOG}${CLEAR_TEXT}."
        echo -e "You can try increasing the ${COMMAND_TEXT}APP_SCAN_TIMEOUT${CLEAR_TEXT} in ${COMMAND_TEXT}${CONFIG_PATH}${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_APPQUERY_FAIL"
    fi

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waConfigureWindows'
# Role: Create an application entry for launching Windows via Remote Desktop.
function waConfigureWindows() {
    # Print feedback.
    echo -n "Creating an application entry for Windows... "

    # Declare variables.
    local WIN_BASH=""    # Stores the bash script to launch a Windows RDP session.
    local WIN_DESKTOP="" # Stores the '.desktop' file to launch a Windows RDP session.

    # Populate variables.
    WIN_BASH="\
#!/usr/bin/env bash
${BIN_PATH}/winapps windows"
    WIN_DESKTOP="\
[Desktop Entry]
Name=Windows
Exec=${BIN_PATH}/winapps windows %F
Terminal=false
Type=Application
Icon=${APPDATA_PATH}/icons/windows.svg
StartupWMClass=Microsoft Windows
Comment=Microsoft Windows RDP Session"

    # Copy the 'Windows' icon.
    $SUDO cp "./install/windows.svg" "${APPDATA_PATH}/icons/windows.svg"

    # Write the desktop entry content to a file.
    echo "$WIN_DESKTOP" | $SUDO tee "${APP_PATH}/windows.desktop" &>/dev/null

    # Write the bash script to a file.
    echo "$WIN_BASH" | $SUDO tee "${BIN_PATH}/windows" &>/dev/null

    # Mark the bash script as executable.
    $SUDO chmod a+x "${BIN_PATH}/windows"

    # Print feedback.
    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
}

# Name: 'waConfigureApp'
# Role: Create application entries for a given application installed on Windows.
function waConfigureApp() {
    # Declare variables.
    local APP_ICON=""         # Stores the path to the application icon.
    local APP_BASH=""         # Stores the bash script used to launch the application.
    local APP_DESKTOP_FILE="" # Stores the '.desktop' file used to launch the application.

    # Source 'Info' File Containing:
    # - The Application Name          (FULL_NAME)
    # - The Shortcut Name             (NAME)
    # - Application Categories        (CATEGORIES)
    # - Executable Path               (WIN_EXECUTABLE)
    # - Supported MIME Types          (MIME_TYPES)
    # - Application Icon              (ICON)
    # shellcheck source=/dev/null # Exclude this file from being checked by ShellCheck.
    source "${APPDATA_PATH}/apps/${1}/info"

    # Determine path to application icon using arguments passed to function.
    APP_ICON="${APPDATA_PATH}/apps/${1}/icon.${2}"

    # Determine the content of the bash script for the application.
    APP_BASH="\
#!/usr/bin/env bash
${BIN_PATH}/winapps ${1}"

    # Determine the content of the '.desktop' file for the application.
    APP_DESKTOP_FILE="\
[Desktop Entry]
Name=${NAME}
Exec=${BIN_PATH}/winapps ${1} %F
Terminal=false
Type=Application
Icon=${APP_ICON}
StartupWMClass=${FULL_NAME}
Comment=${FULL_NAME}
Categories=${CATEGORIES}
MimeType=${MIME_TYPES}"

    # Store the '.desktop' file for the application.
    echo "$APP_DESKTOP_FILE" | $SUDO tee "${APP_PATH}/${1}.desktop" &>/dev/null

    # Store the bash script for the application.
    echo "$APP_BASH" | $SUDO tee "${BIN_PATH}/${1}" &>/dev/null

    # Mark bash script as executable.
    $SUDO chmod a+x "${BIN_PATH}/${1}"
}

# Name: 'waConfigureOfficiallySupported'
# Role: Create application entries for officially supported applications installed on Windows.
function waConfigureOfficiallySupported() {
    # Declare variables.
    local OSA_LIST=() # Stores a list of all officially supported applications installed on Windows.
    local OFFICE_APPS=("access" "access-o365" "access-o365-x86" "access-x86" "adobe-cc" "acrobat9" "acrobat-x-pro" "aftereffects-cc" "audition-cc" "bridge-cc" "bridge-cc-x86" "bridge-cs6" "bridge-cs6-x86" "cmd" "dymo-connect" "excel" "excel-o365" "excel-o365-x86" "excel-x86" "excel-x86-2010" "explorer" "iexplorer" "illustrator-cc" "lightroom-cc" "linqpad8" "mirc" "mspaint" "onenote" "onenote-o365" "onenote-o365-x86" "onenote-x86" "outlook" "outlook-o365" "outlook-o365-x86" "powerbi" "powerbi-store" "powerpoint" "powerpoint-o365" "powerpoint-o365-x86" "powerpoint-x86" "publisher" "publisher-o365" "publisher-o365-x86" "publisher-x86" "project" "project-x86" "remarkable-desktop" "ssms20" "visual-studio-comm" "visual-studio-ent" "visual-studio-pro" "visio" "visio-x86" "word" "word-o365" "word-o365-x86" "word-x86" "word-x86-2010")

    # Read the list of officially supported applications that are installed on Windows into an array, returning an empty array if no such files exist.
    readarray -t OSA_LIST < <(grep -v '^[[:space:]]*$' "$INST_FILE_PATH" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2>/dev/null || true)

    # Create application entries for each officially supported application.
    for OSA in "${OSA_LIST[@]}"; do
        # Split the line by the '|||' delimiter
        local APP_NAME="${OSA%%|||*}"
        local ACTUAL_WIN_EXECUTABLE="${OSA##*|||}"

        # If splitting failed for some reason, skip this line to be safe.
        if [[ -z "$APP_NAME" || -z "$ACTUAL_WIN_EXECUTABLE" ]]; then
            continue
        fi

        # Print feedback using the clean application name.
        echo -n "Creating an application entry for ${APP_NAME}... "

        # Copy the original, unmodified application assets.
        # --no-preserve=mode is needed to avoid missing write permissions when copying from Nix store.
        $SUDO cp -r --no-preserve=mode "./apps/${APP_NAME}" "${APPDATA_PATH}/apps"

        local DESTINATION_INFO_FILE="${APPDATA_PATH}/apps/${APP_NAME}/info"

        # Sanitize the string using pure Bash. This is fast and safe.
        local SED_SAFE_PATH="${ACTUAL_WIN_EXECUTABLE//&/\\&}"
        SED_SAFE_PATH="${SED_SAFE_PATH//\\/\\\\}"

        # Use the sanitized string to safely edit the file.
        $SUDO sed -i "s|^WIN_EXECUTABLE=.*|WIN_EXECUTABLE=\"${SED_SAFE_PATH}\"|" "$DESTINATION_INFO_FILE"

        # Configure the application using the clean name.
        waConfigureApp "$APP_NAME" svg

        # Check if the application is an Office app and copy the protocol handler.
        if [[ " ${OFFICE_APPS[*]} " == *" $APP_NAME "* ]]; then
            # Determine the target directory based on whether the installation is for the system or user.
            if [[ "$OPT_SYSTEM" -eq 1 ]]; then
                TARGET_DIR="$SYS_APP_PATH"
            else
                TARGET_DIR="$USER_APP_PATH"
            fi

            # Copy the protocol handler to the appropriate directory.
            $SUDO cp "./apps/ms-office-protocol-handler.desktop" "$TARGET_DIR/ms-office-protocol-handler.desktop"
        fi

        # Print feedback.
        echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
    done

    # Delete 'install' file.
    rm -f "$INST_FILE_PATH"
}

# Name: 'waConfigureApps'
# Role: Allow the user to select which officially supported applications to configure.
function waConfigureApps() {
    # Declare variables.
    local OSA_LIST=()      # Stores a list of all officially supported applications installed on Windows.
    local APPS=()          # Stores a list of both the simplified and full names of each installed officially supported application.
    local OPTIONS=()       # Stores a list of options presented to the user.
    local APP_INSTALL=""   # Stores the option selected by the user.
    local SELECTED_APPS=() # Stores the officially supported applications selected by the user.
    local TEMP_ARRAY=()    # Temporary array used for sorting elements of an array.
    declare -A APP_DATA_MAP # Associative array to map short names back to their full data line.

    # Read the list of officially supported applications that are installed on Windows into an array, returning an empty array if no such files exist.
    # This will remove leading and trailing whitespace characters as well as ignore empty lines.
    readarray -t OSA_LIST < <(grep -v '^[[:space:]]*$' "$INST_FILE_PATH" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2>/dev/null || true)

    # Loop over each officially supported application installed on Windows.
    for OSA in "${OSA_LIST[@]}"; do
        # Source 'Info' File Containing:
        # - The Application Name          (FULL_NAME)
        # - The Shortcut Name             (NAME)
        # - Application Categories        (CATEGORIES)
        # - Executable Path               (WIN_EXECUTABLE)
        # - Supported MIME Types          (MIME_TYPES)
        # - Application Icon              (ICON)

        # Split the line to get the clean application name
        local APP_NAME="${OSA%%|||*}"
        local ACTUAL_WIN_EXECUTABLE="${OSA##*|||*}"

        # If splitting failed, skip this entry.
        if [[ -z "$APP_NAME" ]]; then
            continue
        fi

        # Use the clean APP_NAME to source the info file
        # shellcheck source=/dev/null # Exclude this file from being checked by ShellCheck.
        source "./apps/${APP_NAME}/info"

        # Add both the simplified and full name of the application to an array.
        APPS+=("${FULL_NAME} (${APP_NAME})")

        # Store the original data line in our map so we can retrieve it later.
        APP_DATA_MAP["$APP_NAME"]="$OSA"

        # Extract the executable file name (e.g. 'MyApp.exe') from the absolute path.
        WIN_EXECUTABLE="${ACTUAL_WIN_EXECUTABLE##*\\}"

        # Trim any leading or trailing whitespace characters from the executable file name.
        read -r WIN_EXECUTABLE <<<"$(echo "$WIN_EXECUTABLE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # Add the executable file name (in lowercase) to the array.
        INSTALLED_EXES+=("${WIN_EXECUTABLE,,}")
    done

    # Sort the 'APPS' array in alphabetical order.
    IFS=$'\n'
    # shellcheck disable=SC2207 # Silence warnings regarding preferred use of 'mapfile' or 'read -a'.
    TEMP_ARRAY=($(sort <<<"${APPS[*]}"))
    unset IFS
    APPS=("${TEMP_ARRAY[@]}")

    # Prompt user to select which officially supported applications to configure.
    OPTIONS=(
        "Set up all detected officially supported applications"
        "Choose specific officially supported applications to set up"
        "Skip setting up any officially supported applications"
    )
    inqMenu "How would you like to handle officially supported applications?" OPTIONS APP_INSTALL

    # Remove unselected officially supported applications from the 'install' file.
    if [[ $APP_INSTALL == "Choose specific officially supported applications to set up" ]]; then
        inqChkBx "Which officially supported applications would you like to set up?" APPS SELECTED_APPS

        # Clear/create the 'install' file.
        echo "" >"$INST_FILE_PATH"

        # Add each selected officially supported application back to the 'install' file.
        for SELECTED_APP in "${SELECTED_APPS[@]}"; do
            # Capture the substring within (but not including) the parentheses.
            # This substring represents the officially supported application name (see above loop).
            local SHORT_NAME="${SELECTED_APP##*(}"
            SHORT_NAME="${SHORT_NAME%%)}"

            # Use the map to find the original data line (e.g., "word|||C:\...") and write it back.
            echo "${APP_DATA_MAP[$SHORT_NAME]}" >>"$INST_FILE_PATH"
        done
    fi

    # Configure selected (or all) officially supported applications.
    if [[ $APP_INSTALL != "Skip setting up any officially supported applications" ]]; then
        waConfigureOfficiallySupported
    fi
}

# Name: 'waConfigureDetectedApps'
# Role: Allow the user to select which detected applications to configure.
function waConfigureDetectedApps() {
    # Declare variables.
    local APPS=()                   # Stores a list of both the simplified and full names of each detected application.
    local EXE_FILENAME=""           # Stores the executable filename of a given detected application.
    local EXE_FILENAME_NOEXT=""     # Stores the executable filename without the file extension of a given detected application.
    local EXE_FILENAME_LOWERCASE="" # Stores the executable filename of a given detected application in lowercase letters only.
    local OPTIONS=()                # Stores a list of options presented to the user.
    local APP_INSTALL=""            # Stores the option selected by the user.
    local SELECTED_APPS=()          # Detected applications selected by the user.
    local APP_DESKTOP_FILE=""       # Stores the '.desktop' file used to launch the application.
    local TEMP_ARRAY=()             # Temporary array used for sorting elements of an array.

    if [ -f "$DETECTED_FILE_PATH" ]; then
        # On UNIX systems, lines are terminated with a newline character (\n).
        # On WINDOWS systems, lines are terminated with both a carriage return (\r) and a newline (\n) character.
        # Remove all carriage returns (\r) within the 'detected' file, as the file was written by Windows.
        sed -i 's/\r//g' "$DETECTED_FILE_PATH"

        # Import the detected application information:
        # - Application Names               (NAMES)
        # - Application Icons in base64     (ICONS)
        # - Application Executable Paths    (EXES)
        # shellcheck source=/dev/null # Exclude this file from being checked by ShellCheck.
        source "$DETECTED_FILE_PATH"

        # shellcheck disable=SC2153 # Silence warnings regarding possible misspellings.
        for INDEX in "${!NAMES[@]}"; do
            # Extract the executable file name (e.g. 'MyApp.exe').
            EXE_FILENAME=${EXES[$INDEX]##*\\}

            # Convert the executable file name to lower-case (e.g. 'myapp.exe').
            EXE_FILENAME_LOWERCASE="${EXE_FILENAME,,}"

            # Remove the file extension (e.g. 'MyApp').
            EXE_FILENAME_NOEXT="${EXE_FILENAME%.*}"

            # Check if the executable was previously configured as part of setting up officially supported applications.
            if [[ " ${INSTALLED_EXES[*]} " != *" ${EXE_FILENAME_LOWERCASE} "* ]]; then
                # If not previously configured, add the application to the list of detected applications.
                APPS+=("${NAMES[$INDEX]} (${EXE_FILENAME_NOEXT})")
            fi
        done

        # Sort the 'APPS' array in alphabetical order.
        IFS=$'\n'
        # shellcheck disable=SC2207 # Silence warnings regarding preferred use of 'mapfile' or 'read -a'.
        TEMP_ARRAY=($(sort <<<"${APPS[*]}"))
        unset IFS
        APPS=("${TEMP_ARRAY[@]}")

        # Prompt user to select which other detected applications to configure.
        OPTIONS=(
            "Set up all detected applications"
            "Select which applications to set up"
            "Do not set up any applications"
        )
        inqMenu "How would you like to handle other detected applications?" OPTIONS APP_INSTALL

        # Store selected detected applications.
        if [[ $APP_INSTALL == "Select which applications to set up" ]]; then
            inqChkBx "Which other applications would you like to set up?" APPS SELECTED_APPS
        elif [[ $APP_INSTALL == "Set up all detected applications" ]]; then
            for APP in "${APPS[@]}"; do
                SELECTED_APPS+=("$APP")
            done
        fi

        for SELECTED_APP in "${SELECTED_APPS[@]}"; do
            # Capture the substring within (but not including) the parentheses.
            # This substring represents the executable filename without the file extension (see above loop).
            EXE_FILENAME_NOEXT="${SELECTED_APP##*(}"
            EXE_FILENAME_NOEXT="${EXE_FILENAME_NOEXT%%)}"

            # Capture the substring prior to the space and parentheses.
            # This substring represents the detected application name (see above loop).
            PROGRAM_NAME="${SELECTED_APP% (*}"

            # Loop through all detected applications to find the detected application being processed.
            for INDEX in "${!NAMES[@]}"; do
                # Check for a matching detected application entry.
                if [[ ${NAMES[$INDEX]} == "$PROGRAM_NAME" ]] && [[ ${EXES[$INDEX]} == *"\\$EXE_FILENAME_NOEXT"* ]]; then
                    # Print feedback.
                    echo -n "Creating an application entry for ${PROGRAM_NAME}... "

                    # Create directory to store application icon and information.
                    $SUDO mkdir -p "${APPDATA_PATH}/apps/${EXE_FILENAME_NOEXT}"

                    # Determine the content of the '.desktop' file for the application.
                    APP_DESKTOP_FILE="\
# GNOME Shortcut Name
NAME=\"${PROGRAM_NAME}\"
# Used for Descriptions and Window Class
FULL_NAME=\"${PROGRAM_NAME}\"
# Path to executable inside Windows
WIN_EXECUTABLE=\"${EXES[$INDEX]}\"
# GNOME Categories
CATEGORIES=\"WinApps\"
# GNOME MIME Types
MIME_TYPES=\"\""

                    # Store the '.desktop' file for the application.
                    echo "$APP_DESKTOP_FILE" | $SUDO tee "${APPDATA_PATH}/apps/${EXE_FILENAME_NOEXT}/info" &>/dev/null

                    # Write application icon to file.
                    echo "${ICONS[$INDEX]}" | base64 -d | $SUDO tee "${APPDATA_PATH}/apps/${EXE_FILENAME_NOEXT}/icon.png" &>/dev/null

                    # Configure the application.
                    waConfigureApp "$EXE_FILENAME_NOEXT" png

                    # Print feedback.
                    echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
                fi
            done
        done
    fi
}

# Name: 'waInstall'
# Role: Installs WinApps.
function waInstall() {
    # Print feedback.
    echo -e "${BOLD_TEXT}Installing WinApps.${CLEAR_TEXT}"

    # Check for existing conflicting WinApps installations.
    waCheckExistingInstall

    # Load the WinApps configuration file.
    waLoadConfig

    # Check for missing dependencies.
    waCheckInstallDependencies

    # Update $RDP_SCALE.
    waFixScale

    # Append additional FreeRDP flags if required.
    if [[ -n $RDP_FLAGS ]]; then
        FREERDP_COMMAND="${FREERDP_COMMAND} ${RDP_FLAGS}"
    fi

    # If using 'docker' or 'podman', set RDP_IP to localhost.
    if [ "$WAFLAVOR" = "docker" ] || [ "$WAFLAVOR" = "podman" ]; then
        RDP_IP="$DOCKER_IP"
    fi

    # If using podman backend, modify the FreeRDP command to enter a new namespace.
    # Skip for rootful Podman (PODMAN_ROOTFUL=1): ports are already mapped to localhost directly.
    if [ "$WAFLAVOR" = "podman" ] && [ "${PODMAN_ROOTFUL:-0}" != "1" ]; then
        FREERDP_COMMAND="podman unshare --rootless-netns ${FREERDP_COMMAND}"
    fi

    if [ "$WAFLAVOR" = "docker" ] || [ "$WAFLAVOR" = "podman" ]; then
        # Check if Windows is powered on.
        waCheckContainerRunning
    elif [ "$WAFLAVOR" = "libvirt" ]; then
        # Verify the current user's group membership.
        waCheckGroupMembership

        # Check if the Windows VM is powered on.
        waCheckVMRunning
    elif [ "$WAFLAVOR" = "manual" ]; then
        waCheckPortOpen
    else
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}INVALID WINAPPS BACKEND.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}An invalid WinApps backend '${WAFLAVOR}' was specified.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please ensure 'WAFLAVOR' is set to 'docker', 'podman' or 'libvirt' in ${COMMAND_TEXT}${CONFIG_PATH}${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_INVALID_FLAVOR"
    fi

    # Check if the RDP port on Windows is open.
    waCheckPortOpen

    # Test RDP access to Windows.
    waCheckRDPAccess

    # Create required directories.
    $SUDO mkdir -p "$BIN_PATH"
    $SUDO mkdir -p "$APP_PATH"
    $SUDO mkdir -p "$APPDATA_PATH/apps"
    $SUDO mkdir -p "$APPDATA_PATH/icons"

    # Check for installed applications.
    waFindInstalled

    # Install the WinApps bash scripts.
    $SUDO ln -sf "${SOURCE_PATH}/bin/winapps" "${BIN_PATH}/winapps"
    $SUDO ln -sf "${SOURCE_PATH}/setup.sh" "${BIN_PATH}/winapps-setup"

    # Configure the Windows RDP session application launcher.
    waConfigureWindows

    if [ "$OPT_AOSA" -eq 1 ]; then
        # Automatically configure all officially supported applications.
        waConfigureOfficiallySupported
    else
        # Configure officially supported applications.
        waConfigureApps

        # Configure other detected applications.
        waConfigureDetectedApps
    fi

    # Ensure BIN_PATH is on PATH
    waEnsureOnPath

    # Print feedback.
    echo -e "${SUCCESS_TEXT}INSTALLATION COMPLETE.${CLEAR_TEXT}"
}

# Name: 'waEnsureOnPath'
# Role: Ensures that $BIN_PATH is on $PATH.
function waEnsureOnPath() {
    if [[ ":$PATH:" != *":$BIN_PATH:"* ]]; then
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT} It seems like '${BIN_PATH}' is not on PATH."
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT} You can add it by running:"
        # shellcheck disable=SC2086
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT}   - For Bash: ${COMMAND_TEXT}echo 'export PATH="${BIN_PATH}:\$PATH"' >> ~/.bashrc && source ~/.bashrc${CLEAR_TEXT}"
        # shellcheck disable=SC2086
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT}   - For ZSH: ${COMMAND_TEXT}echo 'export PATH="${BIN_PATH}:\$PATH"' >> ~/.zshrc && source ~/.zshrc${CLEAR_TEXT}"
        echo -e "${WARNING_TEXT}[WARNING]${CLEAR_TEXT} Make sure to restart your Terminal afterwards.\n"
    fi
}

# Name: 'waUninstall'
# Role: Uninstalls WinApps.
function waUninstall() {

    # Print feedback.
    [ "$OPT_SYSTEM" -eq 1 ] && echo -e "${BOLD_TEXT}REMOVING SYSTEM INSTALLATION.${CLEAR_TEXT}"
    [ "$OPT_USER" -eq 1 ] && echo -e "${BOLD_TEXT}REMOVING USER INSTALLATION.${CLEAR_TEXT}"

    # Determine the target directory for the protocol handler based on the installation type.
    if [[ "$OPT_SYSTEM" -eq 1 ]]; then
        TARGET_DIR="$SYS_APP_PATH"
    else
        TARGET_DIR="$USER_APP_PATH"
    fi

    # Remove the 'ms-office-protocol-handler.desktop' file if it exists.
    $SUDO rm -f "$TARGET_DIR/ms-office-protocol-handler.desktop"

    # Declare variables.
    local WINAPPS_DESKTOP_FILES=()    # Stores a list of '.desktop' file paths.
    local WINAPPS_APP_BASH_SCRIPTS=() # Stores a list of bash script paths.
    local DESKTOP_FILE_NAME=""        # Stores the name of the '.desktop' file for the application.
    local BASH_SCRIPT_NAME=""         # Stores the name of the application.

    # Remove the 'WinApps' bash scripts.
    $SUDO rm -f "${BIN_PATH}/winapps"
    $SUDO rm -f "${BIN_PATH}/winapps-setup"

    # Remove WinApps configuration data, temporary files and logs.
    rm -rf "$USER_APPDATA_PATH"

    # Remove application icons and shortcuts.
    $SUDO rm -rf "$APPDATA_PATH"

    # Store '.desktop' files containing "${BIN_PATH}/winapps" in an array, returning an empty array if no such files exist.
    readarray -t WINAPPS_DESKTOP_FILES < <(grep -l -d skip "${BIN_PATH}/winapps" "${APP_PATH}/"* 2>/dev/null || true)

    # Remove each '.desktop' file.
    for DESKTOP_FILE_PATH in "${WINAPPS_DESKTOP_FILES[@]}"; do
        # Trim leading and trailing whitespace from '.desktop' file path.
        DESKTOP_FILE_PATH=$(echo "$DESKTOP_FILE_PATH" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        # Extract the file name.
        DESKTOP_FILE_NAME=$(basename "$DESKTOP_FILE_PATH" | sed 's/\.[^.]*$//')

        # Print feedback.
        echo -n "Removing '.desktop' file for '${DESKTOP_FILE_NAME}'... "

        # Delete the file.
        $SUDO rm "$DESKTOP_FILE_PATH"

        # Print feedback.
        echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
    done

    # Store the paths of bash scripts calling 'WinApps' to launch specific applications in an array, returning an empty array if no such files exist.
    readarray -t WINAPPS_APP_BASH_SCRIPTS < <(grep -l -d skip "${BIN_PATH}/winapps" "${BIN_PATH}/"* 2>/dev/null || true)

    # Remove each bash script.
    for BASH_SCRIPT_PATH in "${WINAPPS_APP_BASH_SCRIPTS[@]}"; do
        # Trim leading and trailing whitespace from bash script path.
        BASH_SCRIPT_PATH=$(echo "$BASH_SCRIPT_PATH" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        # Extract the file name.
        BASH_SCRIPT_NAME=$(basename "$BASH_SCRIPT_PATH" | sed 's/\.[^.]*$//')

        # Print feedback.
        echo -n "Removing bash script for '${BASH_SCRIPT_NAME}'... "

        # Delete the file.
        $SUDO rm "$BASH_SCRIPT_PATH"

        # Print feedback.
        echo -e "${DONE_TEXT}Done!${CLEAR_TEXT}"
    done

    # Print caveats.
    echo -e "\n${INFO_TEXT}Please note that your WinApps configuration and the WinApps source code were not removed.${CLEAR_TEXT}"
    echo -e "${INFO_TEXT}You can remove these manually by running:${CLEAR_TEXT}"
    echo -e "${COMMAND_TEXT}rm -r $(dirname "$CONFIG_PATH")${CLEAR_TEXT}"
    echo -e "${COMMAND_TEXT}rm -r ${SOURCE_PATH}${CLEAR_TEXT}\n"

    # Print feedback.
    echo -e "${SUCCESS_TEXT}UNINSTALLATION COMPLETE.${CLEAR_TEXT}"
}

# Name: 'waAddApps'
# Role: Adds new applications to an existing WinApps installation.
function waAddApps() {
    # Print feedback.
    echo -e "${BOLD_TEXT}Adding new applications to existing WinApps installation.${CLEAR_TEXT}"

    # Load the WinApps configuration file.
    waLoadConfig

    # Check for missing dependencies.
    waCheckInstallDependencies

    # Update $RDP_SCALE.
    waFixScale

    # Append additional FreeRDP flags if required.
    if [[ -n $RDP_FLAGS ]]; then
        FREERDP_COMMAND="${FREERDP_COMMAND} ${RDP_FLAGS}"
    fi

    # If using 'docker' or 'podman', set RDP_IP to localhost.
    if [ "$WAFLAVOR" = "docker" ] || [ "$WAFLAVOR" = "podman" ]; then
        RDP_IP="$DOCKER_IP"
    fi

    # If using podman backend, modify the FreeRDP command to enter a new namespace.
    # Skip for rootful Podman (PODMAN_ROOTFUL=1): ports are already mapped to localhost directly.
    if [ "$WAFLAVOR" = "podman" ] && [ "${PODMAN_ROOTFUL:-0}" != "1" ]; then
        FREERDP_COMMAND="podman unshare --rootless-netns ${FREERDP_COMMAND}"
    fi

    if [ "$WAFLAVOR" = "docker" ] || [ "$WAFLAVOR" = "podman" ]; then
        # Check if Windows is powered on.
        waCheckContainerRunning
    elif [ "$WAFLAVOR" = "libvirt" ]; then
        # Verify the current user's group membership.
        waCheckGroupMembership

        # Check if the Windows VM is powered on.
        waCheckVMRunning
    elif [ "$WAFLAVOR" = "manual" ]; then
        waCheckPortOpen
    else
        # Display the error type.
        echo -e "${ERROR_TEXT}ERROR:${CLEAR_TEXT} ${BOLD_TEXT}INVALID WINAPPS BACKEND.${CLEAR_TEXT}"

        # Display the error details.
        echo -e "${INFO_TEXT}An invalid WinApps backend '${WAFLAVOR}' was specified.${CLEAR_TEXT}"

        # Display the suggested action(s).
        echo "--------------------------------------------------------------------------------"
        echo -e "Please ensure 'WAFLAVOR' is set to 'docker', 'podman' or 'libvirt' in ${COMMAND_TEXT}${CONFIG_PATH}${CLEAR_TEXT}."
        echo "--------------------------------------------------------------------------------"

        # Terminate the script.
        return "$EC_INVALID_FLAVOR"
    fi

    # Check if the RDP port on Windows is open.
    waCheckPortOpen

    # Test RDP access to Windows.
    waCheckRDPAccess

    # Check for installed applications.
    waFindInstalled

    # Configure officially supported applications.
    waConfigureApps

    # Configure other detected applications.
    waConfigureDetectedApps
    # Print feedback.
    echo -e "${SUCCESS_TEXT}ADDING NEW APPS COMPLETE.${CLEAR_TEXT}"
}



### SEQUENTIAL LOGIC ###
# Welcome the user.
echo -e "${BOLD_TEXT}\
################################################################################
#                                                                              #
#                            WinApps Install Wizard                            #
#                                                                              #
################################################################################
${CLEAR_TEXT}"

# Check dependencies for the script.
waCheckScriptDependencies

# Source the contents of 'inquirer.sh'.
waGetInquirer

# Sanitise and parse the user input.
waCheckInput "$@"

# Configure paths and permissions.
waConfigurePathsAndPermissions

# Get the source code
waGetSourceCode
# Install or uninstall WinApps.
if [ "$OPT_UNINSTALL" -eq 1 ]; then
    waUninstall
elif [ "$OPT_ADD_APPS" -eq 1 ]; then
    waAddApps
else
    waInstall
fi

exit 0
__WINAPPS_SETUP_SH_END__
  chmod +x "$target"
}


# ══════════════════════════════════════════════════════════════════
#  ÖN KOŞULLAR / PREREQUISITES
# ══════════════════════════════════════════════════════════════════
detect_distro() {
  [[ -f /etc/os-release ]] || error "/etc/os-release bulunamadı / not found."
  # shellcheck source=/dev/null
  source /etc/os-release

  DISTRO_ID="${ID,,}"
  DISTRO_ID_LIKE="${ID_LIKE:-}"
  DISTRO_ID_LIKE="${DISTRO_ID_LIKE,,}"

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
        warn "$(msg "Dağıtım tanımlanamadı: '$DISTRO_ID' — Debian varsayılıyor." "Unknown distro: '$DISTRO_ID' — assuming Debian.")"
        DISTRO_FAMILY="debian"
      fi ;;
  esac

  success "$(msg "Dağıtım: ${DISTRO_ID} (${DISTRO_FAMILY} ailesi)" "Distro: ${DISTRO_ID} (${DISTRO_FAMILY} family)")"
}

check_prerequisites() {
  step "$(msg 'Ön Koşul Kontrolü' 'Prerequisite Check')"
  if [[ "$EUID" -eq 0 ]]; then
    error "$(msg 'Root olarak çalıştırmayın. Sudo yetkili normal kullanıcı ile çalıştırın.' 'Do not run as root. Run as a regular user with sudo privileges.')"
  fi
  command -v sudo &>/dev/null || error "'sudo' $(msg 'bulunamadı' 'not found')."
  sudo -v || error "$(msg 'sudo yetkisi alınamadı.' 'Could not obtain sudo privileges.')"
  info "$(msg 'Kullanıcı' 'User')    : ${REAL_USER}"
  info "Home      : ${REAL_HOME}"
  detect_distro
  success "$(msg 'Ön koşullar geçti.' 'Prerequisites passed.')"
}

# ══════════════════════════════════════════════════════════════════
#  MEVCUT KURULUM DOSYALARINI TEMİZLE
# ══════════════════════════════════════════════════════════════════
cleanup_existing() {
  step "$(msg 'Mevcut Kurulum Dosyaları Temizleniyor' 'Cleaning Existing Installation Files')"

  # ── Windows VM varlık kontrolü (Podman) ──────────────────────
  local vm_exists=0
  local vm_running=0
  local has_volume=0

  if command -v podman &>/dev/null; then
    if sudo podman ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^WinApps$"; then
      vm_exists=1
      if sudo podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^WinApps$"; then
        vm_running=1
      fi
    fi

    if sudo podman volume ls --format '{{.Name}}' 2>/dev/null | grep -qE "(^|_)data$|^winapps_data$"; then
      has_volume=1
    fi
  fi

  if [[ $vm_exists -eq 1 ]] || [[ $has_volume -eq 1 ]]; then

    # In reconfigure mode (KEEP_EXISTING_WINDOWS=1 already set), skip VM menu
    if [[ $KEEP_EXISTING_WINDOWS -eq 1 ]]; then
      echo ""
      info "$(msg 'Yeniden yapılandırma modu: Mevcut Windows VM korunuyor.' 'Reconfigure mode: Keeping existing Windows VM.')"
      if [[ $vm_running -eq 0 ]] && [[ -f "$WINAPPS_COMPOSE" ]]; then
        info "$(msg 'Windows VM başlatılıyor...' 'Starting Windows VM...')"
        podman_compose_run --file "$WINAPPS_COMPOSE" up -d 2>/dev/null || true
      fi
    else
      echo ""
      echo -e "  ${BOLD}${YELLOW}⚠️  $(msg 'Mevcut Windows VM Tespit Edildi!' 'Existing Windows VM Detected!')${NC}"
      echo "  ──────────────────────────────────────────────────────"

      if [[ $vm_running -eq 1 ]]; then
        echo -e "  $(msg 'Durum' 'Status') : ${GREEN}$(msg 'ÇALIŞIYOR' 'RUNNING')${NC}"
      else
        echo -e "  $(msg 'Durum' 'Status') : ${YELLOW}$(msg 'DURDURULMUŞ' 'STOPPED')${NC}"
      fi

      if [[ $has_volume -eq 1 ]]; then
        echo -e "  $(msg 'Disk' 'Disk')   : ${CYAN}winapps_data${NC} (Podman volume)"
      fi

      echo ""
      echo "  $(msg 'Ne yapmak istersiniz?' 'What do you want to do?')"
      echo ""
      echo -e "  ${BOLD}[1]${NC} $(msg "Mevcut Windows'u SİL, sıfırdan kur" 'DELETE existing Windows, fresh install')"
      echo -e "      ${RED}$(msg '(Dikkat: Windows diski ve tüm veriler kalıcı silinir!)' '(Warning: Windows disk and all data permanently deleted!)')${NC}"
      echo ""
      echo -e "  ${BOLD}[2]${NC} $(msg "Mevcut Windows'u KORU, sadece config/ayarları güncelle" 'KEEP existing Windows, only update config/settings')"
      echo -e "      ${GREEN}$(msg '(Windows kurulu ve ayarları korunur, sadece WinApps config yenilenir)' '(Windows install kept, only WinApps config refreshed)')${NC}"
      echo ""
      echo -e "  ${BOLD}[3]${NC} $(msg 'İptal et, çık' 'Cancel, exit')"
      echo ""

      local choice=""
      while true; do
        read -rp "$(echo -e "  ${YELLOW}$(msg 'Seçiminiz' 'Your choice') [1/2/3]: ${NC}")" choice
        case "$choice" in
          1)
            echo ""
            warn "$(msg 'Windows VM ve tüm veriler SİLİNECEK!' 'Windows VM and all data will be DELETED!')"
            if confirm "$(msg 'Emin misiniz? Bu işlem GERİ ALINAMAZ' 'Are you sure? This CANNOT BE UNDONE')" "n"; then
              info "$(msg 'Windows VM durduruluyor ve siliniyor...' 'Stopping and removing Windows VM...')"
              if [[ -f "$WINAPPS_COMPOSE" ]]; then
                podman_compose_run --file "$WINAPPS_COMPOSE" down --volumes 2>/dev/null || true
              fi
              sudo podman rm -f WinApps 2>/dev/null || true
              sudo podman volume rm winapps_data 2>/dev/null || true
              sudo podman volume prune -f 2>/dev/null || true
              success "$(msg 'Windows VM ve disk verisi silindi. Sıfırdan kurulum yapılacak.' 'Windows VM and disk data removed. Fresh install will proceed.')"
            else
              info "$(msg 'Silme iptal edildi. Seçim yapın:' 'Deletion cancelled. Make a choice:')"
              continue
            fi
            break
            ;;
          2)
            echo ""
            info "$(msg 'Mevcut Windows korunuyor. Sadece config dosyaları güncellenecek.' 'Keeping existing Windows. Only config files will be updated.')"
            KEEP_EXISTING_WINDOWS=1
            if [[ $vm_running -eq 0 ]] && [[ -f "$WINAPPS_COMPOSE" ]]; then
              info "$(msg 'Windows VM başlatılıyor...' 'Starting Windows VM...')"
              podman_compose_run --file "$WINAPPS_COMPOSE" up -d 2>/dev/null || true
            fi
            break
            ;;
          3)
            echo ""
            info "$(msg 'İptal edildi.' 'Cancelled.')"
            exit 0
            ;;
          *)
            warn "$(msg 'Geçersiz seçim. 1, 2 veya 3 girin.' 'Invalid choice. Enter 1, 2 or 3.')"
            ;;
        esac
      done
    fi
    echo ""
  fi

  # ── WinApps config dosyaları ──────────────────────────────────
  if [[ -f "$WINAPPS_CONF" ]] || [[ -f "$WINAPPS_COMPOSE" ]]; then
    info "$(msg 'Eski WinApps config dosyaları siliniyor...' 'Removing old WinApps config files...')"
    sudo rm -f "$WINAPPS_CONF" "$WINAPPS_COMPOSE"
    sudo rm -rf "$WINAPPS_OEM_DIR"
    success "$(msg 'WinApps config temizlendi.' 'WinApps config cleaned.')"
  fi

  # ── dconf override dosyaları ──────────────────────────────────
  if [[ -d "$DCONF_DIR" ]]; then
    info "$(msg 'Eski dconf override dosyaları siliniyor...' 'Removing old dconf override files...')"
    sudo rm -f \
      "${DCONF_DIR}/00-gnome-shell" \
      "${DCONF_DIR}/01-touchpad" \
      "${DCONF_DIR}/02-gnome-misc"
    sudo dconf update 2>/dev/null || true
    success "$(msg 'dconf override temizlendi.' 'dconf overrides cleaned.')"
  fi

  # ── Kullanıcı symlink'leri ────────────────────────────────────
  info "$(msg "Eski config symlink'leri temizleniyor..." 'Cleaning old config symlinks...')"

  sudo rm -f \
    "${WINAPPS_SKEL_DIR}/winapps.conf" \
    "${WINAPPS_SKEL_DIR}/compose.yaml" 2>/dev/null || true

  sudo rm -f \
    "/root/.config/winapps/winapps.conf" \
    "/root/.config/winapps/compose.yaml" 2>/dev/null || true

  while IFS=: read -r uname _ uid _ _ uhome ushell; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      sudo rm -f \
        "${uhome}/.config/winapps/winapps.conf" \
        "${uhome}/.config/winapps/compose.yaml" 2>/dev/null || true
    fi
  done < /etc/passwd

  success "$(msg "Symlink'ler temizlendi." 'Symlinks cleaned.')"

  # ── winapps-refresh dosyaları ─────────────────────────────────
  sudo rm -f \
    "$REFRESH_BIN" \
    "$REFRESH_DESKTOP" \
    "$REFRESH_LAUNCHER" 2>/dev/null || true

  # ── Systemd timer/service ─────────────────────────────────────
  if systemctl is-enabled winapps-refresh.timer &>/dev/null 2>&1; then
    sudo systemctl disable --now winapps-refresh.timer 2>/dev/null || true
    sudo rm -f \
      /etc/systemd/system/winapps-refresh.timer \
      /etc/systemd/system/winapps-refresh.service
    sudo systemctl daemon-reload
    info "$(msg 'Eski systemd timer temizlendi.' 'Old systemd timer cleaned.')"
  fi

  # ── Mevcut WinApps sistem kurulumunu kaldır ───────────────────
  # waCheckExistingInstall, /usr/local/bin/winapps gibi eski
  # ikili dosyaları tespit edip EC_EXISTING_INSTALL (3) ile
  # çıkacağından bunları temizlemek gerekir.
  if [[ -f /usr/local/bin/winapps ]] || [[ -d /usr/local/share/winapps ]]; then
    info "$(msg 'Mevcut WinApps sistem kurulumu kaldırılıyor...' 'Removing existing WinApps system installation...')"
    local TMP_UNINSTALL
    TMP_UNINSTALL=$(mktemp /tmp/winapps-uninstall-XXXXX.sh)
    if [[ -f /usr/local/share/winapps/embedded-setup.sh ]]; then
      sudo cp /usr/local/share/winapps/embedded-setup.sh "$TMP_UNINSTALL"
    else
      _write_winapps_setup_sh "$TMP_UNINSTALL"
    fi
    chmod +x "$TMP_UNINSTALL"
    sudo -E env \
        DOCKER_HOST="unix://${PODMAN_SOCKET}" \
        CONTAINER_MANAGER="podman" \
        WAFLAVOR="podman" \
      bash "$TMP_UNINSTALL" --system --uninstall 2>/dev/null || true
    rm -f "$TMP_UNINSTALL"
    # Fallback: ikili dosyalar hâlâ duruyorsa elle sil
    sudo rm -f /usr/local/bin/winapps /usr/local/bin/winapps-setup 2>/dev/null || true
    sudo rm -rf /usr/local/share/winapps 2>/dev/null || true
    sudo find /usr/share/applications/ -name "*.desktop" \
      -exec grep -l "winapps" {} \; 2>/dev/null | xargs -r sudo rm -f 2>/dev/null || true
    success "$(msg 'Mevcut WinApps kaldırıldı.' 'Existing WinApps removed.')"
  fi

  success "$(msg 'Temizlik tamamlandı — yeniden kurulum başlıyor.' 'Cleanup complete — reinstall starting.')"
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 1 — GNOME ARAÇLARI
# ══════════════════════════════════════════════════════════════════
install_gnome_tools() {
  step "$(msg 'BÖLÜM 1A — GNOME Araçları' 'SECTION 1A — GNOME Tools')"

  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-get update -y -qq
      sudo apt-get install -y gnome-tweaks dconf-editor dconf-cli
      sudo apt-get install -y flatpak gnome-software-plugin-flatpak 2>/dev/null \
        || sudo apt-get install -y flatpak
      ;;
    fedora)   sudo dnf install -y gnome-tweaks dconf-editor flatpak ;;
    arch)     sudo pacman -Syu --needed --noconfirm gnome-tweaks dconf flatpak ;;
    opensuse) sudo zypper install -y gnome-tweaks dconf-editor flatpak ;;
  esac
  success "GNOME Tweaks + dconf-editor + Flatpak $(msg 'kuruldu.' 'installed.')"

  sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

  flatpak install flathub com.mattjakeman.ExtensionManager \
    --noninteractive -y 2>/dev/null \
    && success "Extension Manager (Flatpak) $(msg 'kuruldu.' 'installed.')" \
    || warn "$(msg 'Extension Manager kurulamadı.' 'Extension Manager could not be installed.')"
}

install_dash_to_dock() {
  step "$(msg 'BÖLÜM 1B — Dash to Dock' 'SECTION 1B — Dash to Dock')"

  local EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_DASH_TO_DOCK}"
  if [[ -d "$EXT_DIR" ]]; then info "$(msg 'Dash to Dock zaten kurulu.' 'Dash to Dock already installed.')"; return; fi

  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    if sudo apt-get install -y gnome-shell-extension-dash-to-dock 2>/dev/null; then
      success "Dash to Dock $(msg 'apt ile kuruldu.' 'installed via apt.')"
      return
    fi
  fi

  info "$(msg "Dash to Dock GitHub'dan indiriliyor..." 'Downloading Dash to Dock from GitHub...')"
  local TMP_ZIP="/tmp/dash-to-dock.zip"
  local LATEST_URL=""
  LATEST_URL=$(curl -fsSL https://api.github.com/repos/micheleg/dash-to-dock/releases/latest \
    2>/dev/null | grep "browser_download_url.*zip" | head -1 | cut -d'"' -f4 || true)

  if [[ -n "$LATEST_URL" ]]; then
    curl -fsSL "$LATEST_URL" -o "$TMP_ZIP"
    sudo mkdir -p "$EXT_DIR"
    sudo unzip -o "$TMP_ZIP" -d "$EXT_DIR" >/dev/null
    rm -f "$TMP_ZIP"
    success "Dash to Dock $(msg 'kuruldu' 'installed'): $EXT_DIR"
  else
    info "$(msg "GitHub releases bulunamadı, main branch'ten indiriliyor..." 'GitHub releases not found, downloading from main branch...')"
    local ZIP_URL="https://github.com/micheleg/dash-to-dock/archive/refs/heads/master.zip"
    curl -fsSL "$ZIP_URL" -o "$TMP_ZIP" 2>/dev/null || {
      warn "$(msg 'Dash to Dock indirilemedi.' 'Could not download Dash to Dock.')"
      return
    }
    local TMP_DIR; TMP_DIR=$(mktemp -d)
    sudo unzip -o "$TMP_ZIP" -d "$TMP_DIR" >/dev/null
    sudo mkdir -p "$EXT_DIR"
    sudo cp -r "${TMP_DIR}/dash-to-dock-master/." "$EXT_DIR/"
    rm -rf "$TMP_DIR" "$TMP_ZIP"
    success "Dash to Dock $(msg 'kuruldu' 'installed') (main): $EXT_DIR"
  fi
}

install_dash_to_panel() {
  step "$(msg 'BÖLÜM 1C — Dash to Panel' 'SECTION 1C — Dash to Panel')"
  local EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_DASH_TO_PANEL}"
  if [[ -d "$EXT_DIR" ]]; then info "$(msg 'Zaten kurulu.' 'Already installed.')"; return; fi

  local TMP_ZIP="/tmp/dash-to-panel.zip"
  local LATEST_URL=""

  info "$(msg "Dash to Panel GitHub'dan indiriliyor..." 'Downloading Dash to Panel from GitHub...')"
  LATEST_URL=$(curl -fsSL https://api.github.com/repos/home-sweet-gnome/dash-to-panel/releases/latest \
    2>/dev/null | grep "browser_download_url.*zip" | head -1 | cut -d'"' -f4 || true)

  if [[ -n "$LATEST_URL" ]]; then
    curl -fsSL "$LATEST_URL" -o "$TMP_ZIP"
    sudo mkdir -p "$EXT_DIR"
    sudo unzip -o "$TMP_ZIP" -d "$EXT_DIR" >/dev/null
    rm -f "$TMP_ZIP"
    success "Dash to Panel $(msg 'kuruldu' 'installed'): $EXT_DIR"
  else
    local ZIP_URL="https://github.com/home-sweet-gnome/dash-to-panel/archive/refs/heads/master.zip"
    curl -fsSL "$ZIP_URL" -o "$TMP_ZIP" 2>/dev/null || {
      warn "$(msg 'Dash to Panel indirilemedi.' 'Could not download Dash to Panel.')"
      return
    }
    local TMP_DIR; TMP_DIR=$(mktemp -d)
    sudo unzip -o "$TMP_ZIP" -d "$TMP_DIR" >/dev/null
    sudo mkdir -p "$EXT_DIR"
    sudo cp -r "${TMP_DIR}/dash-to-panel-master/." "$EXT_DIR/"
    rm -rf "$TMP_DIR" "$TMP_ZIP"
    success "Dash to Panel $(msg 'kuruldu' 'installed') (main): $EXT_DIR"
  fi
}

apply_dconf_system_overrides() {
  step "$(msg 'BÖLÜM 1D — dconf Sistem Override (Tüm Kullanıcılar)' 'SECTION 1D — dconf System Override (All Users)')"
  sudo mkdir -p "$DCONF_DIR" "${DCONF_DIR}/locks"

  sudo tee "${DCONF_DIR}/00-gnome-shell" >/dev/null <<'EOF'
[org/gnome/shell]
enabled-extensions=['dash-to-panel@jderose9.github.com', 'dash-to-dock@micxgx.gmail.com']
disable-user-extensions=false
EOF

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
  success "$(msg 'dconf sistem override uygulandı.' 'dconf system overrides applied.')"
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 2 — TOUCHPAD
# ══════════════════════════════════════════════════════════════════
configure_touchpad() {
  step "$(msg 'BÖLÜM 2 — Touchpad (USB Fare → Touchpad Kapat)' 'SECTION 2 — Touchpad (USB Mouse → Disable Touchpad)')"

  sudo mkdir -p "$DCONF_DIR"
  sudo tee "${DCONF_DIR}/01-touchpad" >/dev/null <<'EOF'
[org/gnome/desktop/peripherals/touchpad]
send-events='disabled-on-external-mouse'
EOF

  sudo dconf update
  success "$(msg 'Touchpad ayarı uygulandı (tüm kullanıcılar).' 'Touchpad setting applied (all users).')"

  local SCHEMA="org.gnome.desktop.peripherals.touchpad"
  if command -v gsettings &>/dev/null && \
     gsettings list-schemas 2>/dev/null | grep -q "$SCHEMA"; then
    gsettings set "$SCHEMA" send-events 'disabled-on-external-mouse' 2>/dev/null \
      && info "$(msg 'Mevcut oturuma anlık uygulandı.' 'Applied to current session.')" || true
  fi
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 3 — WinApps (Podman)
# ══════════════════════════════════════════════════════════════════
install_kvm() {
  step "$(msg 'BÖLÜM 3A — KVM Kontrolü ve Kurulumu' 'SECTION 3A — KVM Check and Installation')"

  grep -qE '(vmx|svm)' /proc/cpuinfo \
    || error "$(msg "CPU sanallaştırma (VT-x/AMD-V) bulunamadı. BIOS/UEFI'dan etkinleştirin." 'CPU virtualization (VT-x/AMD-V) not found. Enable in BIOS/UEFI.')"
  success "$(msg 'CPU sanallaştırma mevcut.' 'CPU virtualization available.')"

  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-get update -y -qq
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

  [[ -e /dev/kvm ]] || error "/dev/kvm $(msg 'oluşturulamadı. BIOS sanallaştırma ayarını kontrol edin.' 'could not be created. Check BIOS virtualization setting.')"
  success "/dev/kvm $(msg 'hazır.' 'ready.')"
  command -v kvm-ok &>/dev/null \
    && { sudo kvm-ok && success "kvm-ok: $(msg 'KVM kullanılabilir.' 'KVM available.')" || warn "kvm-ok $(msg 'uyarı verdi.' 'reported a warning.')"; }

  # iptables (klasör paylaşımı için zorunlu)
  local changed=0
  lsmod | grep -q '^ip_tables'   || { sudo modprobe ip_tables;   changed=1; }
  lsmod | grep -q '^iptable_nat' || { sudo modprobe iptable_nat; changed=1; }
  if [[ $changed -eq 1 ]]; then
    printf 'ip_tables\niptable_nat\n' \
      | sudo tee /etc/modules-load.d/iptables.conf >/dev/null
    success "iptables $(msg 'modülleri yüklendi ve kalıcı hale getirildi.' 'modules loaded and persisted.')"
  else
    success "iptables $(msg 'modülleri zaten aktif.' 'modules already active.')"
  fi
}

install_podman() {
  step "$(msg 'BÖLÜM 3B — Podman + Compose' 'SECTION 3B — Podman + Compose')"

  local podman_ok=0 compose_ok=0
  command -v podman &>/dev/null \
    && { success "Podman $(msg 'mevcut' 'present'): $(podman --version)"; podman_ok=1; }
  # Sadece podman-compose (Python) kabul edilir — Docker plugin değil
  if command -v podman-compose &>/dev/null; then
    success "podman-compose $(msg 'mevcut' 'present'): $(podman-compose --version 2>&1 | head -1)"
    compose_ok=1
  elif sudo podman compose version 2>&1 | grep -qiv "docker-compose\|docker/cli-plugins"; then
    success "podman compose native $(msg 'mevcut' 'present')."
    compose_ok=1
  fi

  if [[ $podman_ok -eq 1 && $compose_ok -eq 1 ]]; then
    success "Podman + podman-compose $(msg 'zaten kurulu — atlanıyor.' 'already installed — skipping.')"
    _podman_service_start
    return
  fi

  info "$(msg 'Podman kuruluyor...' 'Installing Podman...')"
  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-get update -y -qq
      sudo apt-get install -y podman podman-compose 2>/dev/null \
        || sudo apt-get install -y podman
      # podman-docker KURULMAMALI — Docker plugin'ini önce getirir ve
      # 'podman compose' komutunu Docker'ın compose plugin'ine devreder!
      ;;
    fedora)
      sudo dnf install -y podman podman-compose
      ;;
    arch)
      sudo pacman -Syu --needed --noconfirm podman podman-compose
      ;;
    opensuse)
      sudo zypper install -y podman podman-compose 2>/dev/null \
        || sudo zypper install -y podman
      ;;
  esac

  # podman-compose (Python) yoksa pip ile kur — Docker plugin'i kabul etme
  if ! command -v podman-compose &>/dev/null; then
    info "$(msg "podman-compose pip ile kuruluyor..." 'Installing podman-compose via pip...')"
    sudo apt-get install -y python3-pip 2>/dev/null \
      || sudo dnf install -y python3-pip 2>/dev/null \
      || sudo pacman -Syu --needed --noconfirm python-pip 2>/dev/null \
      || true
    sudo pip3 install podman-compose --break-system-packages 2>/dev/null \
      || sudo pip3 install podman-compose 2>/dev/null \
      || warn "podman-compose $(msg 'kurulamadı.' 'could not be installed.')"
  fi

  command -v podman &>/dev/null || error "Podman $(msg 'kurulumu başarısız.' 'installation failed.')"

  _podman_service_start
  success "Podman $(msg 'kuruldu' 'installed'): $(podman --version)"
}

_podman_service_start() {
  # Rootful podman socket aktif et — DOCKER_HOST uyumluluğu için
  info "$(msg 'Podman socket etkinleştiriliyor...' 'Enabling Podman socket...')"
  sudo systemctl enable --now podman.socket 2>/dev/null \
    || warn "podman.socket $(msg 'etkinleştirilemedi (sistemd olmayabilir).' 'could not be enabled (no systemd?).')"

  # /etc/environment içine DOCKER_HOST yaz (WinApps / Compose uyumu)
  if ! grep -q "DOCKER_HOST" /etc/environment 2>/dev/null; then
    echo "DOCKER_HOST=unix://${PODMAN_SOCKET}" | sudo tee -a /etc/environment >/dev/null
  else
    sudo sed -i "s|^DOCKER_HOST=.*|DOCKER_HOST=unix://${PODMAN_SOCKET}|" /etc/environment
  fi
  export DOCKER_HOST="unix://${PODMAN_SOCKET}"

  # /var/run/docker.sock symlink — Docker Compose uyumluluğu (eski araçlar için)
  if [[ -S "$PODMAN_SOCKET" ]] && [[ ! -e /var/run/docker.sock ]]; then
    sudo ln -sf "$PODMAN_SOCKET" /var/run/docker.sock 2>/dev/null || true
  fi

  # WinApps setup.sh ~/.docker/desktop/docker.sock arar — symlink ekle
  sudo mkdir -p /root/.docker/desktop
  sudo ln -sf "$PODMAN_SOCKET" /root/.docker/desktop/docker.sock 2>/dev/null || true
  while IFS=: read -r uname _ uid _ _ uhome _; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      sudo mkdir -p "${uhome}/.docker/desktop"
      sudo ln -sf "$PODMAN_SOCKET" "${uhome}/.docker/desktop/docker.sock" 2>/dev/null || true
      sudo chown -R "${uname}:${uname}" "${uhome}/.docker" 2>/dev/null || true
    fi
  done < /etc/passwd

  # ── podman-docker kaldır (varsa) — Docker plugin karışıklığını önler ──
  if dpkg -l podman-docker &>/dev/null 2>&1; then
    info "$(msg \
      'podman-docker paketi bulundu — kaldırılıyor (Docker plugin çakışması önleniyor)...' \
      'podman-docker package found — removing (prevents Docker plugin conflict)...')"
    sudo apt-get remove -y podman-docker 2>/dev/null \
      || sudo dnf remove -y podman-docker 2>/dev/null \
      || sudo pacman -R --noconfirm podman-docker 2>/dev/null \
      || true
    # Docker plugin binary'sini de doğrudan sil
    sudo rm -f /usr/libexec/docker/cli-plugins/docker-compose 2>/dev/null || true
    success "podman-docker $(msg 'kaldırıldı.' 'removed.')"
  fi
  # Docker plugin dosyası varsa direkt sil (farklı kurulum yollarından gelmiş olabilir)
  if [[ -f /usr/libexec/docker/cli-plugins/docker-compose ]]; then
    warn "$(msg \
      '/usr/libexec/docker/cli-plugins/docker-compose bulundu — siliniyor...' \
      '/usr/libexec/docker/cli-plugins/docker-compose found — removing...')"
    sudo rm -f /usr/libexec/docker/cli-plugins/docker-compose
    success "$(msg 'Docker compose plugin silindi.' 'Docker compose plugin removed.')"
  fi

  # ── /etc/containers/policy.json ─────────────────────────────────
  # Podman'ın container image'larını kabul etmesi için trust policy zorunludur.
  # Yoksa "no policy.json file found" hatası alınır.
  sudo mkdir -p /etc/containers
  if [[ ! -f /etc/containers/policy.json ]]; then
    info "$(msg '/etc/containers/policy.json oluşturuluyor...' 'Creating /etc/containers/policy.json...')"
    sudo tee /etc/containers/policy.json >/dev/null <<'POLICYJSON'
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ],
    "transports": {
        "docker-daemon": {
            "": [{"type": "insecureAcceptAnything"}]
        }
    }
}
POLICYJSON
    success "/etc/containers/policy.json $(msg 'oluşturuldu.' 'created.')"
  fi

  # ── Registry TLS yapılandırması ─────────────────────────────────
  sudo mkdir -p /etc/containers/registries.conf.d
  sudo tee /etc/containers/registries.conf.d/winapps-registries.conf >/dev/null <<'REGCONF'
# WinApps için gerekli registry tanımları
[[registry]]
location = "ghcr.io"
insecure = false

[[registry]]
location = "docker.io"
insecure = false
REGCONF

  # Sistem CA sertifikalarını güncelle (x509 hatalarını giderir)
  if command -v update-ca-certificates &>/dev/null; then
    sudo update-ca-certificates --fresh 2>/dev/null || true
  elif command -v update-ca-trust &>/dev/null; then
    sudo update-ca-trust extract 2>/dev/null || true
  fi

  success "Podman socket $(msg 'aktif' 'active'): ${PODMAN_SOCKET}"
}

install_winapps_deps() {
  step "$(msg 'BÖLÜM 3C — WinApps Bağımlılıkları' 'SECTION 3C — WinApps Dependencies')"
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
  success "WinApps $(msg 'bağımlılıkları kuruldu.' 'dependencies installed.')"
}

setup_oem() {
  step "$(msg 'BÖLÜM 3D — OEM (Windows RDP + Otomatik Sign-Out)' 'SECTION 3D — OEM (Windows RDP + Auto Sign-Out)')"
  sudo mkdir -p "$WINAPPS_OEM_DIR"

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

  sudo tee "${WINAPPS_OEM_DIR}/AutoSignOut.reg" >/dev/null <<'AUTORF'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]
"AutoAdminLogon"=dword:00000000
"ForceAutoLogon"=dword:00000000
AUTORF

  sudo tee "${WINAPPS_OEM_DIR}/AutoSignOut.ps1" >/dev/null <<'PSEOF'
# AutoSignOut.ps1 — Konsol oturumunu otomatik kapat
$sessions = query session 2>&1
foreach ($line in $sessions) {
    if ($line -match "console\s+(\d+)\s+(Active|Bağlı)") {
        $sessionId = $Matches[1]
        Write-Host "Konsol oturumu bulundu (ID: $sessionId), kapatılıyor..."
        Start-Sleep -Seconds 5
        logoff $sessionId
        Write-Host "Oturum kapatıldı."
    }
}
PSEOF

  sudo tee "${WINAPPS_OEM_DIR}/install.bat" >/dev/null <<'BATEOF'
@echo off
echo [WinApps OEM] Kurulum basliyor...

echo [1/4] RDP registry ayarlari uygulanıyor...
regedit.exe /s "%~dp0RDPApps.reg"
regedit.exe /s "%~dp0AutoSignOut.reg"

echo [2/4] RDP guvenlik duvari kurali ekleniyor...
netsh advfirewall firewall add rule name="WinApps-RDP" protocol=TCP dir=in localport=3389 action=allow

echo [3/4] AutoSignOut gorevi ekleniyor...
schtasks /create /tn "WinApps-AutoSignOut" ^
  /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\oem\AutoSignOut.ps1" ^
  /sc onstart ^
  /ru SYSTEM ^
  /rl HIGHEST ^
  /f

echo [4/4] PowerShell execution policy ayarlaniyor...
powershell.exe -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force"

echo [WinApps OEM] Kurulum tamamlandi!
BATEOF

  sudo chmod 644 \
    "${WINAPPS_OEM_DIR}/RDPApps.reg" \
    "${WINAPPS_OEM_DIR}/AutoSignOut.reg" \
    "${WINAPPS_OEM_DIR}/AutoSignOut.ps1" \
    "${WINAPPS_OEM_DIR}/install.bat"

  success "OEM $(msg 'dosyaları hazır' 'files ready'): $WINAPPS_OEM_DIR"
}

create_system_config() {
  step "$(msg 'BÖLÜM 3E — WinApps Yapılandırması' 'SECTION 3E — WinApps Configuration')"
  sudo mkdir -p "$WINAPPS_ETC_DIR"

  echo ""
  echo -e "  ${BOLD}$(msg 'Windows VM Kimlik Bilgileri' 'Windows VM Credentials')${NC}"
  echo "  ─────────────────────────────────────"
  ask WIN_USER "  $(msg 'Windows kullanıcı adı' 'Windows username')" "MyWindowsUser"
  ask_password WIN_PASS "  $(msg 'Windows kullanıcı parolası' 'Windows user password')"

  echo ""
  echo -e "  ${BOLD}$(msg 'Windows Sürümü' 'Windows Version')${NC}"
  echo "  ─────────────────────────────────────"
  echo -e "  ${YELLOW}⚠️  $(msg 'Windows Home RDP DESTEKLEMİYOR!' 'Windows Home does NOT support RDP!')${NC}"
  echo -e "  ${YELLOW}   $(msg 'Sadece Pro, Enterprise veya Server kullanın.' 'Use only Pro, Enterprise or Server.')${NC}"
  echo "  $(msg 'Geçerli değerler' 'Valid values'): 11, 10, tiny11, 2022, 2019, 2016"
  ask WIN_VERSION "  $(msg 'Windows sürümü' 'Windows version')" "11"
  ask WIN_RAM     "  RAM (4G, 8G, ...)" "4G"
  ask WIN_CORES   "  $(msg 'CPU çekirdek sayısı' 'CPU cores')" "4"
  ask WIN_DISK    "  $(msg 'Disk boyutu' 'Disk size') (64G)" "64G"
  echo ""
  # Windows is always English; Turkish keyboard layout is always added.
  # Per project requirement: "Türkçe klavye özelliği ekle, Türkçe Windows'u kaldır"
  # (Add Turkish keyboard support, remove Turkish Windows UI language option.)
  # To change the keyboard layout, update WIN_KEYBOARD below.
  WIN_LANGUAGE="English"; WIN_REGION="en-US"; WIN_KEYBOARD="tr-TR"
  info "  $(msg 'Windows: İngilizce (en-US) | Klavye düzeni: Türkçe (tr-TR)' 'Windows: English (en-US) | Keyboard layout: Turkish (tr-TR)')"

  echo "  100 → Normal  |  140 → HD  |  180 → 4K"
  ask RDP_SCALE   "  $(msg 'Ekran ölçeği' 'Display scale')" "100"

  # winapps.conf — WAFLAVOR=podman
  sudo tee "$WINAPPS_CONF" >/dev/null <<CONF
##################################
#   WINAPPS CONFIGURATION FILE   #
#   (Podman backend)             #
##################################
RDP_USER="${WIN_USER}"
RDP_PASS="${WIN_PASS}"
RDP_ASKPASS=""
RDP_DOMAIN=""
RDP_IP="127.0.0.1"
VM_NAME="RDPWindows"
WAFLAVOR="podman"
CONTAINER_MANAGER="podman"
RDP_SCALE="${RDP_SCALE}"
REMOVABLE_MEDIA="/run/media"
RDP_FLAGS="/cert:tofu /sound /microphone +home-drive"
RDP_FLAGS_NON_WINDOWS=""
RDP_FLAGS_WINDOWS=""
DEBUG="true"
AUTOPAUSE="off"
AUTOPAUSE_TIME="300"
FREERDP_COMMAND=""
PORT_TIMEOUT="10"
RDP_TIMEOUT="60"
APP_SCAN_TIMEOUT="60"
BOOT_TIMEOUT="120"
HIDEF="on"
CONF

  sudo chown root:root "$WINAPPS_CONF"
  sudo chmod 644 "$WINAPPS_CONF"
  success "winapps.conf → $WINAPPS_CONF (WAFLAVOR=podman)"

  _write_compose_yaml "with_oem"
}

_write_compose_yaml() {
  local mode="${1:-with_oem}"
  local OEM_LINE
  if [[ "$mode" == "with_oem" ]]; then
    OEM_LINE="      - ${WINAPPS_OEM_DIR}:/oem"
  else
    OEM_LINE="#      - ${WINAPPS_OEM_DIR}:/oem  # Windows kurulum sonrası devre dışı"
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
  step "$(msg 'BÖLÜM 3F — Config Symlink → Tüm Kullanıcılar' 'SECTION 3F — Config Symlinks → All Users')"

  sudo mkdir -p "$WINAPPS_SKEL_DIR"
  sudo ln -sf "$WINAPPS_CONF"    "${WINAPPS_SKEL_DIR}/winapps.conf"
  sudo ln -sf "$WINAPPS_COMPOSE" "${WINAPPS_SKEL_DIR}/compose.yaml"
  success "/etc/skel symlink $(msg 'eklendi' 'added')."

  sudo mkdir -p /root/.config/winapps
  sudo ln -sf "$WINAPPS_CONF"    /root/.config/winapps/winapps.conf
  sudo ln -sf "$WINAPPS_COMPOSE" /root/.config/winapps/compose.yaml
  success "root → /root/.config/winapps/ symlink $(msg 'eklendi' 'added')."

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
  success "$(msg 'Tüm kullanıcı oturumları yapılandırıldı.' 'All user sessions configured.')"
}

start_windows_vm() {
  step "$(msg 'BÖLÜM 3G — Windows VM Başlatma' 'SECTION 3G — Starting Windows VM')"

  # ── Yeniden yapılandırma modu: Windows kurulumu atla ──────────
  if [[ $KEEP_EXISTING_WINDOWS -eq 1 ]]; then
    info "$(msg 'Mevcut Windows korunuyor — container yeni config ile yeniden başlatılıyor.' 'Keeping existing Windows — restarting container with new config.')"

    # OEM olmadan compose yaz (Windows zaten kurulu)
    _write_compose_yaml "without_oem"

    info "$(msg 'FreeRDP sertifikaları temizleniyor...' 'Cleaning FreeRDP certificates...')"
    sudo rm -rf /root/.config/freerdp/server/ 2>/dev/null || true
    rm -rf "${REAL_HOME}/.config/freerdp/server/" 2>/dev/null || true
    while IFS=: read -r uname _ uid _ _ uhome _; do
      if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
        rm -rf "${uhome}/.config/freerdp/server/" 2>/dev/null || true
      fi
    done < /etc/passwd
    success "FreeRDP $(msg 'sertifikaları temizlendi.' 'certificates cleaned.')"

    info "$(msg 'Container yeniden başlatılıyor...' 'Restarting container...')"
    podman_compose_run --file "$WINAPPS_COMPOSE" down 2>/dev/null || true
    podman_compose_run --file "$WINAPPS_COMPOSE" up -d
    success "$(msg 'Container başlatıldı.' 'Container started.')"

    echo ""
    echo -e "  ${BOLD}${YELLOW}⚠️  $(msg 'ÖNEMLİ' 'IMPORTANT')${NC}"
    echo ""
    echo "  $(msg "Windows'ta oturum AÇIKSA kapatın (Sign Out)." 'If you are logged into Windows, SIGN OUT (not just lock).')"
    echo "  $(msg 'Oturum açıkken RDP bağlantısı başarısız olur.' 'RDP will fail if a Windows user session is active.')"
    echo ""
    echo -e "  $(msg 'VNC ile kontrol edin' 'Check via VNC'): ${CYAN}http://127.0.0.1:8006${NC}"
    echo ""

    confirm "$(msg "Windows oturumu kapalı, devam edelim" 'Windows session is signed out, continue')" \
      || { echo "  $(msg 'Hazır olunca tekrar çalıştırın.' 'Re-run when ready.')"; exit 0; }
    return
  fi

  # ── Windows image'ı önce çek (x509 hatasını erken yakalar) ──────
  info "$(msg 'Windows container image indiriliyor (ghcr.io/dockur/windows)...' 'Pulling Windows container image (ghcr.io/dockur/windows)...')"
  info "$(msg 'Bu işlem internet hızına bağlı olarak birkaç dakika sürebilir.' 'This may take several minutes depending on your internet speed.')"
  if ! sudo podman pull ghcr.io/dockur/windows:latest; then
    warn "$(msg \
      'Image indirme başarısız. TLS doğrulaması devre dışı bırakılarak tekrar deneniyor...' \
      'Image pull failed. Retrying with TLS verification disabled...')"
    sudo podman pull --tls-verify=false ghcr.io/dockur/windows:latest \
      || error "$(msg \
        'Image indirilemedi. İnternet bağlantısını ve firewall ayarlarını kontrol edin.' \
        'Could not pull image. Check internet connection and firewall settings.')"
  fi
  success "$(msg 'Image hazır.' 'Image ready.')"

  podman_compose_run --file "$WINAPPS_COMPOSE" up -d
  success "$(msg 'Windows VM başlatıldı (oem aktif → RDP ayarları otomatik uygulanacak).' 'Windows VM started (oem active → RDP settings will be applied automatically).')"

  echo ""
  echo -e "  ${BOLD}━━━ $(msg 'Şu anda yapmanız gerekenler' 'What to do now') ━━━${NC}"
  echo ""
  echo -e "  1. $(msg 'Tarayıcıda açın' 'Open in browser')  → ${CYAN}http://127.0.0.1:8006${NC}"
  echo "  2. $(msg 'Windows kurulumunu tamamlayın (10–20 dakika)' 'Complete Windows install (10–20 minutes)')"
  echo -e "  3. ${YELLOW}$(msg "İstediğiniz uygulamaları Windows'a kurun" 'Install desired apps inside Windows')${NC}"
  echo -e "  4. ${YELLOW}$(msg 'Windows kullanıcı oturumunu KAPATIP çıkın' 'SIGN OUT of the Windows user session')${NC}"
  echo "  5. $(msg "Bu terminale dönüp Enter'a basın" 'Return here and press Enter')"
  echo ""

  confirm "$(msg 'Windows hazır ve oturum kapatıldı, devam edelim' 'Windows is ready and signed out, continue')" \
    || { echo "  $(msg 'Hazır olunca tekrar çalıştırın.' 'Re-run when ready.')"; exit 0; }

  info "$(msg 'oem mount kapatılıyor (Windows kurulumu tamamlandı)...' 'Disabling oem mount (Windows install complete)...')"
  _write_compose_yaml "without_oem"

  info "$(msg 'FreeRDP sertifikaları temizleniyor...' 'Cleaning FreeRDP certificates...')"
  sudo rm -rf /root/.config/freerdp/server/ 2>/dev/null || true
  rm -rf "${REAL_HOME}/.config/freerdp/server/" 2>/dev/null || true
  while IFS=: read -r uname _ uid _ _ uhome _; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      rm -rf "${uhome}/.config/freerdp/server/" 2>/dev/null || true
    fi
  done < /etc/passwd
  success "FreeRDP $(msg 'sertifikaları temizlendi.' 'certificates cleaned.')"

  info "$(msg 'Container yeni yapılandırmayla yeniden başlatılıyor...' 'Restarting container with new config...')"
  podman_compose_run --file "$WINAPPS_COMPOSE" down
  podman_compose_run --file "$WINAPPS_COMPOSE" up -d
  success "$(msg 'Container yeniden başlatıldı (oem devre dışı).' 'Container restarted (oem disabled).')"
}

run_winapps_installer() {
  step "$(msg 'BÖLÜM 3H — WinApps Sistem Geneli Kurulumu' 'SECTION 3H — WinApps System-Wide Installation')"

  echo ""
  echo "  $(msg 'Kurulum hedefleri' 'Install targets') (--system):"
  echo "  /usr/local/bin/           → winapps, winapps-setup"
  echo "  /usr/share/applications/  → .desktop"
  echo "  /usr/local/share/winapps/"
  echo ""

  if confirm "$(msg 'WinApps kurulumunu başlat' 'Start WinApps installation')"; then

    local TMP_SETUP
    TMP_SETUP=$(mktemp /tmp/winapps-setup-XXXXX.sh)
    info "$(msg 'Gömülü WinApps setup.sh çıkartılıyor...' 'Extracting embedded WinApps setup.sh...')"
    _write_winapps_setup_sh "$TMP_SETUP"

    export DOCKER_HOST="unix://${PODMAN_SOCKET}"
    export CONTAINER_MANAGER="podman"

    sudo -E env \
        DOCKER_HOST="unix://${PODMAN_SOCKET}" \
        CONTAINER_MANAGER="podman" \
        WAFLAVOR="podman" \
        PODMAN_ROOTFUL="1" \
      bash "$TMP_SETUP" --system --setupAllOfficiallySupportedApps
    rm -f "$TMP_SETUP"
  else
    echo ""
    info "$(msg 'Daha sonra çalıştırmak için' 'To run later'):"
    echo "  export DOCKER_HOST=unix://${PODMAN_SOCKET}"
    echo "  sudo -E winapps-setup --system --setupAllOfficiallySupportedApps"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  BÖLÜM 4 — WinApps UYGULAMA YENİLEME SİSTEMİ
# ══════════════════════════════════════════════════════════════════
install_refresh_system() {
  step "$(msg 'BÖLÜM 4 — WinApps Uygulama Yenileme Sistemi' 'SECTION 4 — WinApps App Refresh System')"

  # ── 4.1 Ana refresh scripti ─────────────────────────────────
  # Gömülü setup.sh'ı kullanır — depo silinse bile çalışır
  sudo tee "$REFRESH_BIN" >/dev/null <<REFRESH_EOF
#!/usr/bin/env bash
# winapps-refresh — Podman edition
# Gömülü setup.sh kullanır (depo bağımlılığı yok)
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

COMPOSE_FILE="${WINAPPS_COMPOSE}"
PODMAN_SOCKET="${PODMAN_SOCKET}"
EMBEDDED_SETUP="/usr/local/share/winapps/embedded-setup.sh"

echo ""
echo -e "\${BOLD}\${CYAN}╔══════════════════════════════════════════════════╗\${NC}"
echo -e "\${BOLD}\${CYAN}║  WinApps — Uygulama Listesi Yenileniyor (Podman) ║\${NC}"
echo -e "\${BOLD}\${CYAN}╚══════════════════════════════════════════════════╝\${NC}"
echo ""

echo -n "  Windows VM kontrol ediliyor... "
if ! sudo podman ps --filter name=WinApps --filter status=running \
     --format '{{.Names}}' 2>/dev/null | grep -q "WinApps"; then
  echo -e "\${RED}[KAPALI]\${NC}"
  echo ""
  echo -e "  \${RED}Windows VM çalışmıyor!\${NC}"
  echo "  Başlatmak için:"
  echo "    sudo podman compose --file \${COMPOSE_FILE} start"
  exit 1
fi
echo -e "\${GREEN}[ÇALIŞIYOR]\${NC}"

echo ""
echo -e "  \${YELLOW}⚠️  Windows kullanıcı oturumu KAPALI olmalı!\${NC}"
read -rp "  Oturum kapalı, devam edeyim mi? [E/h]: " ans
ans="\${ans:-e}"
[[ "\$ans" =~ ^[EeYy]\$ ]] || { echo "  İptal edildi."; exit 0; }
echo ""

echo -e "  \${CYAN}Windows'taki yeni uygulamalar taranıyor...\${NC}"
echo "  (1-2 dakika sürebilir)"
echo ""

if [[ ! -f "\$EMBEDDED_SETUP" ]]; then
  echo -e "  \${RED}HATA: \$EMBEDDED_SETUP bulunamadı.\${NC}"
  echo "  ubuntu-full-setup.sh scriptini yeniden çalıştırın."
  exit 1
fi

export DOCKER_HOST="unix://\${PODMAN_SOCKET}"
export CONTAINER_MANAGER="podman"
export WAFLAVOR="podman"

if sudo -E env \\
    DOCKER_HOST="unix://\${PODMAN_SOCKET}" \\
    CONTAINER_MANAGER="podman" \\
    WAFLAVOR="podman" \\
    PODMAN_ROOTFUL="1" \\
    bash "\$EMBEDDED_SETUP" --system --add-apps; then
  echo ""
  echo -e "  \${GREEN}\${BOLD}✅ Tamamlandı!\${NC}"
  echo ""
  echo "  Yeni uygulamalar → /usr/share/applications/"
  command -v notify-send &>/dev/null && \\
    DISPLAY="\${DISPLAY:-:0}" notify-send "WinApps" \\
      "Uygulama listesi güncellendi." \\
      --icon=system-run 2>/dev/null || true
else
  echo ""
  echo -e "  \${RED}Hata oluştu! Kontrol edin:\${NC}"
  echo "  • Windows VM çalışıyor mu?"
  echo "  • Windows oturumu kapalı mı?"
  echo "  • /etc/winapps/winapps.conf doğru mu?"
  exit 1
fi
REFRESH_EOF

  sudo chmod +x "$REFRESH_BIN"
  success "winapps-refresh → $REFRESH_BIN"

  # Gömülü setup.sh'ı kalıcı yere yerleştir
  sudo mkdir -p /usr/local/share/winapps
  _write_winapps_setup_sh /usr/local/share/winapps/embedded-setup.sh
  sudo chmod 755 /usr/local/share/winapps/embedded-setup.sh
  success "$(msg "Gömülü setup.sh kuruldu" 'Embedded setup.sh installed'): /usr/local/share/winapps/embedded-setup.sh"

  # ── 4.2 GUI launcher ───────────────────────────────────────
  sudo tee "$REFRESH_LAUNCHER" >/dev/null <<'LAUNCHER_EOF'
#!/usr/bin/env bash
CMD="winapps-refresh; echo ''; echo 'Çıkmak için Enter / Press Enter to exit...'; read"

for term in gnome-terminal konsole xfce4-terminal tilix xterm; do
  command -v "$term" &>/dev/null || continue
  case "$term" in
    gnome-terminal) exec gnome-terminal --title="WinApps Refresh" -- bash -c "$CMD" ;;
    konsole)        exec konsole --title "WinApps Refresh" -e bash -c "$CMD" ;;
    xfce4-terminal) exec xfce4-terminal --title="WinApps Refresh" -x bash -c "$CMD" ;;
    tilix)          exec tilix -e bash -c "$CMD" ;;
    xterm)          exec xterm -title "WinApps Refresh" -e bash -c "$CMD" ;;
  esac
done

notify-send "WinApps" \
  "Terminal bulunamadı. Terminalde 'winapps-refresh' çalıştırın." \
  --icon=dialog-error 2>/dev/null || true
LAUNCHER_EOF

  sudo chmod +x "$REFRESH_LAUNCHER"
  success "GUI launcher → $REFRESH_LAUNCHER"

  # ── 4.3 .desktop ─────────────────────────────────────────────
  sudo tee "$REFRESH_DESKTOP" >/dev/null <<'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=WinApps — Uygulamaları Yenile
GenericName=WinApps Application Scanner
Comment=Windows'a yeni program kurduğunuzda menüyü günceller
Exec=/usr/local/bin/winapps-refresh-gui
Icon=system-run
Terminal=false
Categories=System;Utility;
Keywords=winapps;windows;refresh;yenile;podman;
StartupNotify=true
DESKTOP_EOF

  sudo chmod 644 "$REFRESH_DESKTOP"
  success ".desktop → $REFRESH_DESKTOP"

  # ── 4.4 Systemd timer ────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}$(msg 'Otomatik Yenileme (Systemd Timer)' 'Auto Refresh (Systemd Timer)')${NC}"
  echo "  $(msg 'Sistem başladığında + haftada bir otomatik tarama yapar.' 'Scans on boot + weekly.')"
  echo ""

  if confirm "  $(msg "Otomatik timer'ı kur" 'Install auto timer')" "n"; then

    sudo tee /etc/systemd/system/winapps-refresh.service >/dev/null <<'SERVICE_EOF'
[Unit]
Description=WinApps Application List Refresh (Podman)
After=podman.socket network-online.target
Wants=network-online.target podman.socket

[Service]
Type=oneshot
ExecStart=/usr/local/bin/winapps-refresh
SuccessExitStatus=0 1
RemainAfterExit=no
StandardOutput=journal
StandardError=journal
SERVICE_EOF

    sudo tee /etc/systemd/system/winapps-refresh.timer >/dev/null <<'TIMER_EOF'
[Unit]
Description=WinApps Application List Weekly Refresh
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
    success "winapps-refresh.timer $(msg 'etkinleştirildi.' 'enabled.')"
  else
    info "$(msg "Timer atlandı. Manuel" 'Timer skipped. Manual'): winapps-refresh"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  ÖZET / SUMMARY
# ══════════════════════════════════════════════════════════════════
print_summary() {
  echo ""
  echo -e "${BOLD}${GREEN}"
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Kurulum Tamamlandı! ✅ (Podman Edition)               ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  else
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║          Installation Complete! ✅ (Podman Edition)                ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  fi
  echo -e "${NC}"

  echo -e "${BOLD}WinApps:${NC}"
  echo "  winapps windows                    → $(msg 'Tam Windows masaüstü' 'Full Windows desktop')"
  echo "  winapps manual \"app.exe\"           → $(msg 'Manuel başlat' 'Manual launch')"
  echo "  winapps-setup --system --uninstall → $(msg 'Kaldır' 'Uninstall')"
  echo ""

  echo -e "${BOLD}🔄 $(msg "Yeni Program Kurduğunuzda" 'When You Install New App'):${NC}"
  echo -e "  ${CYAN}Terminal:${NC}          winapps-refresh"
  echo ""

  echo -e "${BOLD}Windows VM (Podman):${NC}"
  echo "  http://127.0.0.1:8006                                      → VNC"
  echo "  sudo podman compose --file ${WINAPPS_COMPOSE} start       → $(msg 'Aç' 'Start')"
  echo "  sudo podman compose --file ${WINAPPS_COMPOSE} stop        → $(msg 'Kapat' 'Stop')"
  echo "  sudo podman compose --file ${WINAPPS_COMPOSE} restart     → $(msg 'Yeniden başlat' 'Restart')"
  echo ""

  echo -e "${BOLD}$(msg 'Sıfırdan başlamak' 'Start over'):${NC}"
  echo "  sudo podman compose --file ${WINAPPS_COMPOSE} down --volumes"
  echo ""

  echo -e "${BOLD}Podman Socket:${NC}"
  echo "  ${PODMAN_SOCKET}"
  echo "  DOCKER_HOST=unix://${PODMAN_SOCKET}"
  echo ""
}

# ══════════════════════════════════════════════════════════════════
#  TAM KALDIRMA / COMPLETE UNINSTALL
# ══════════════════════════════════════════════════════════════════
uninstall_all() {
  step "$(msg 'Tam Kaldırma Başlıyor...' 'Starting Complete Uninstall...')"
  echo ""
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo -e "  ${RED}${BOLD}⚠️  Aşağıdakiler kalıcı olarak silinecek:${NC}"
    echo "  • Windows VM ve tüm Windows disk verisi"
    echo "  • WinApps kurulumu ve tüm uygulama kısayolları"
    echo "  • /etc/winapps/ dizini"
    echo "  • GNOME extension'lar"
    echo "  • dconf sistem override dosyaları"
    echo "  • winapps-refresh komutu"
    echo "  • Systemd timer/service"
    echo "  • Tüm kullanıcılardaki config symlink'leri"
    echo ""
    warn "Podman ve KVM paketleri KORUNACAK"
    echo ""
    confirm "Devam etmek istiyor musunuz? GERİ ALINAMAZ" "n" || { echo "  İptal."; exit 0; }
  else
    echo -e "  ${RED}${BOLD}⚠️  The following will be permanently deleted:${NC}"
    echo "  • Windows VM and all data"
    echo "  • WinApps and all shortcuts"
    echo "  • /etc/winapps/ directory"
    echo "  • GNOME extensions"
    echo "  • dconf overrides"
    echo "  • winapps-refresh"
    echo "  • Systemd timer"
    echo "  • All user config symlinks"
    echo ""
    warn "Podman and KVM packages will be KEPT"
    echo ""
    confirm "Continue? CANNOT BE UNDONE" "n" || { echo "  Cancelled."; exit 0; }
  fi

  # ── 1. Windows VM ve volume ──────────────────────────────────
  msg "  Windows VM durduruluyor..." "  Stopping Windows VM..."
  export DOCKER_HOST="unix://${PODMAN_SOCKET}"
  if command -v podman &>/dev/null; then
    if [[ -f "$WINAPPS_COMPOSE" ]]; then
      podman_compose_run --file "$WINAPPS_COMPOSE" down --volumes 2>/dev/null || true
    fi
    sudo podman rm -f WinApps 2>/dev/null || true
    sudo podman volume rm winapps_data 2>/dev/null || true
    sudo podman volume prune -f 2>/dev/null || true
    success "$(msg 'Windows VM ve disk verisi silindi.' 'Windows VM and data removed.')"
  else
    warn "Podman $(msg 'bulunamadı.' 'not found.')"
  fi

  # ── 2. WinApps kurulumunu kaldır (gömülü setup.sh) ──────────
  msg "  WinApps kaldırılıyor..." "  Removing WinApps..."
  local TMP_UNINSTALL
  TMP_UNINSTALL=$(mktemp /tmp/winapps-uninstall-XXXXX.sh)
  if [[ -f /usr/local/share/winapps/embedded-setup.sh ]]; then
    sudo cp /usr/local/share/winapps/embedded-setup.sh "$TMP_UNINSTALL"
  else
    _write_winapps_setup_sh "$TMP_UNINSTALL"
  fi
  chmod +x "$TMP_UNINSTALL"
  sudo -E env \
      DOCKER_HOST="unix://${PODMAN_SOCKET}" \
      CONTAINER_MANAGER="podman" \
      WAFLAVOR="podman" \
    bash "$TMP_UNINSTALL" --system --uninstall 2>/dev/null || true
  rm -f "$TMP_UNINSTALL"
  # Manuel temizlik
  sudo rm -f /usr/local/bin/winapps /usr/local/bin/winapps-setup 2>/dev/null || true
  sudo rm -rf /usr/local/share/winapps 2>/dev/null || true
  sudo find /usr/share/applications/ -name "*.desktop" \
    -exec grep -l "winapps" {} \; 2>/dev/null | xargs sudo rm -f 2>/dev/null || true
  success "WinApps $(msg 'kaldırıldı.' 'removed.')"

  # ── 3. /etc/winapps/ ─────────────────────────────────────────
  sudo rm -rf "$WINAPPS_ETC_DIR" 2>/dev/null || true
  success "$WINAPPS_ETC_DIR $(msg 'silindi' 'removed')."

  # ── 4. dconf ─────────────────────────────────────────────────
  sudo rm -f \
    "${DCONF_DIR}/00-gnome-shell" \
    "${DCONF_DIR}/01-touchpad" \
    "${DCONF_DIR}/02-gnome-misc" 2>/dev/null || true
  sudo dconf update 2>/dev/null || true
  success "dconf $(msg 'override silindi' 'overrides removed')."

  # ── 5. GNOME extension'lar ───────────────────────────────────
  sudo rm -rf \
    "/usr/share/gnome-shell/extensions/${EXT_DASH_TO_PANEL}" \
    "/usr/share/gnome-shell/extensions/${EXT_DASH_TO_DOCK}" 2>/dev/null || true
  success "GNOME extensions $(msg 'silindi' 'removed')."

  # ── 6. winapps-refresh ───────────────────────────────────────
  sudo rm -f "$REFRESH_BIN" "$REFRESH_LAUNCHER" "$REFRESH_DESKTOP" 2>/dev/null || true

  # ── 7. Systemd ───────────────────────────────────────────────
  sudo systemctl disable --now winapps-refresh.timer 2>/dev/null || true
  sudo rm -f \
    /etc/systemd/system/winapps-refresh.timer \
    /etc/systemd/system/winapps-refresh.service 2>/dev/null || true
  sudo systemctl daemon-reload 2>/dev/null || true

  # ── 8. Symlink'ler ───────────────────────────────────────────
  sudo rm -f \
    "${WINAPPS_SKEL_DIR}/winapps.conf" \
    "${WINAPPS_SKEL_DIR}/compose.yaml" 2>/dev/null || true
  sudo rm -f \
    /root/.config/winapps/winapps.conf \
    /root/.config/winapps/compose.yaml \
    /root/.docker/desktop/docker.sock 2>/dev/null || true
  while IFS=: read -r uname _ uid _ _ uhome _; do
    if [[ "$uid" -ge 1000 ]] && [[ -d "$uhome" ]]; then
      sudo rm -f \
        "${uhome}/.config/winapps/winapps.conf" \
        "${uhome}/.config/winapps/compose.yaml" \
        "${uhome}/.docker/desktop/docker.sock" 2>/dev/null || true
      rm -rf "${uhome}/.config/freerdp/server/" 2>/dev/null || true
    fi
  done < /etc/passwd
  sudo rm -rf /root/.config/freerdp/server/ 2>/dev/null || true

  # ── 9. /etc/environment ──────────────────────────────────────
  sudo sed -i '/^DOCKER_HOST=/d' /etc/environment 2>/dev/null || true

  # ── 10. /var/run/docker.sock symlink ─────────────────────────
  if [[ -L /var/run/docker.sock ]]; then
    sudo rm -f /var/run/docker.sock 2>/dev/null || true
  fi

  # ── 11. İsteğe bağlı: Podman'ı kaldır ────────────────────────
  echo ""
  if confirm "$(msg 'Podman kaldırılsın mı? (Başka container kullanmıyorsanız)' 'Remove Podman? (Only if you do not use containers elsewhere)')" "n"; then
    sudo systemctl disable --now podman.socket 2>/dev/null || true
    case "$DISTRO_FAMILY" in
      debian)
        sudo apt-get purge -y podman podman-compose podman-docker 2>/dev/null || true
        sudo apt-get autoremove -y 2>/dev/null || true
        sudo rm -rf /var/lib/containers /etc/containers 2>/dev/null || true
        ;;
      fedora)
        sudo dnf remove -y podman podman-compose podman-docker 2>/dev/null || true
        ;;
      arch)
        sudo pacman -Rns --noconfirm podman podman-compose podman-docker 2>/dev/null || true
        ;;
      opensuse)
        sudo zypper remove -y podman podman-compose 2>/dev/null || true
        ;;
    esac
    sudo pip3 uninstall -y podman-compose 2>/dev/null || true
    success "Podman $(msg 'kaldırıldı.' 'removed.')"
  fi

  # ── 12. İsteğe bağlı: GNOME araçları ─────────────────────────
  if confirm "$(msg 'GNOME Tweaks ve dconf-editor kaldırılsın mı?' 'Remove GNOME Tweaks and dconf-editor?')" "n"; then
    case "$DISTRO_FAMILY" in
      debian)  sudo apt-get purge -y gnome-tweaks dconf-editor 2>/dev/null || true ;;
      fedora)  sudo dnf remove -y gnome-tweaks dconf-editor 2>/dev/null || true ;;
      arch)    sudo pacman -Rns --noconfirm gnome-tweaks 2>/dev/null || true ;;
    esac
    flatpak uninstall -y com.mattjakeman.ExtensionManager 2>/dev/null || true
    success "GNOME tools $(msg 'kaldırıldı.' 'removed.')"
  fi

  echo ""
  echo -e "${GREEN}${BOLD}"
  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Kaldırma İşlemi Tamamlandı! ✅                        ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  else
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Uninstallation Complete! ✅                           ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
  fi
  echo -e "${NC}"
}

main() {
  detect_language

  banner

  echo ""
  echo -e "  ${BOLD}Language / Dil:${NC}"
  echo "  [1] Türkçe"
  echo "  [2] English"
  echo ""
  read -rp "$(echo -e "  ${CYAN}Select / Seçin [1/2] [1]: ${NC}")" lang_choice
  lang_choice="${lang_choice:-1}"
  [[ "$lang_choice" == "2" ]] && SCRIPT_LANG="en" || SCRIPT_LANG="tr"
  echo ""

  if [[ "$SCRIPT_LANG" == "tr" ]]; then
    echo -e "  ${BOLD}Ne yapmak istersiniz?${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Kurulum       — GNOME + Touchpad + WinApps (Podman) + Yenileme"
    echo -e "  ${CYAN}[2]${NC} Kaldırma      — Her şeyi temizle"
    echo -e "  ${CYAN}[3]${NC} Çıkış"
    echo -e "  ${CYAN}[4]${NC} Config Yenile — Windows'u koruyarak WinApps ayarlarını yenile"
    echo -e "      ${GREEN}(RDP hatası aldıysanız veya credentials değiştirmek istiyorsanız)${NC}"
    echo ""
    read -rp "$(echo -e "  ${YELLOW}Seçiminiz [1/2/3/4]: ${NC}")" main_choice
  else
    echo -e "  ${BOLD}What would you like to do?${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Install       — GNOME + Touchpad + WinApps (Podman) + Refresh"
    echo -e "  ${CYAN}[2]${NC} Uninstall     — Remove everything"
    echo -e "  ${CYAN}[3]${NC} Exit"
    echo -e "  ${CYAN}[4]${NC} Reconfigure   — Keep Windows, rebuild WinApps config only"
    echo -e "      ${GREEN}(Use if you had an RDP error or want to change credentials)${NC}"
    echo ""
    read -rp "$(echo -e "  ${YELLOW}Your choice [1/2/3/4]: ${NC}")" main_choice
  fi

  case "${main_choice:-1}" in
    1)
      if [[ "$SCRIPT_LANG" == "tr" ]]; then
        echo ""
        echo -e "${BOLD}  Bu script sırasıyla şunları yapacak:${NC}"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 1: GNOME ──${NC}"
        echo "   1. GNOME Tweaks + dconf-editor + Flatpak + Extension Manager"
        echo "   2. Dash to Dock + Dash to Panel"
        echo "   3. dconf sistem override"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 2: Touchpad ──${NC}"
        echo "   4. USB fare → touchpad kapat"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 3: WinApps (Podman) ──${NC}"
        echo "   5. KVM + qemu"
        echo "   6. Podman + podman-compose"
        echo "   7. Podman socket aktivasyonu (DOCKER_HOST uyumlu)"
        echo "   8. WinApps bağımlılıkları"
        echo "   9. OEM + winapps.conf (WAFLAVOR=podman) + compose.yaml"
        echo "  10. Tüm kullanıcılara symlink"
        echo "  11. Windows VM başlat → kurulum → yeniden başlat"
        echo "  12. WinApps --system (gömülü setup.sh ile)"
        echo ""
        echo -e "  ${CYAN}── BÖLÜM 4: Yenileme ──${NC}"
        echo "  13. winapps-refresh (gömülü setup.sh)"
        echo "  14. Programlar menüsü kısayolu"
        echo "  15. Systemd timer (isteğe bağlı)"
        echo ""
        echo -e "  ${YELLOW}NOT: WinApps setup.sh script içine gömülüdür — depo silinse bile çalışır!${NC}"
        echo ""
        confirm "Kuruluma başlayalım mı?" || { echo "  İptal."; exit 0; }
      else
        echo ""
        echo -e "${BOLD}  This script will do the following:${NC}"
        echo ""
        echo -e "  ${CYAN}── SECTION 1: GNOME ──${NC}"
        echo "   1-3. GNOME Tweaks + Extensions + dconf"
        echo -e "  ${CYAN}── SECTION 2: Touchpad ──${NC}"
        echo "   4. USB mouse → disable touchpad"
        echo -e "  ${CYAN}── SECTION 3: WinApps (Podman) ──${NC}"
        echo "   5. KVM + qemu"
        echo "   6. Podman + podman-compose"
        echo "   7. Podman socket (DOCKER_HOST compatible)"
        echo "   8-12. OEM, config, VM start, WinApps install"
        echo -e "  ${CYAN}── SECTION 4: Refresh ──${NC}"
        echo "  13-15. winapps-refresh + timer"
        echo ""
        echo -e "  ${YELLOW}NOTE: WinApps setup.sh is embedded — works even if upstream repo is removed!${NC}"
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
      install_podman
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
      check_prerequisites
      detect_distro
      uninstall_all
      ;;

    3)
      msg "  Çıkılıyor." "  Exiting."
      exit 0
      ;;

    4)
      # Config Yenile / Reconfigure — Windows'u koru, WinApps'i yeniden kur
      KEEP_EXISTING_WINDOWS=1
      check_prerequisites
      cleanup_existing
      setup_oem
      create_system_config
      symlink_for_all_users
      start_windows_vm
      run_winapps_installer
      install_refresh_system
      print_summary
      ;;

    *)
      msg "  Geçersiz seçim." "  Invalid choice."
      exit 1
      ;;
  esac
}

main "$@"
