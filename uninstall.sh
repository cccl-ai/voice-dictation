#!/bin/bash
# Voice Dictation Uninstaller
# Supports Linux (Ubuntu/Debian) and macOS
set -e

INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/dictation"
GROQ_CONFIG_DIR="$HOME/.config/groq"
WHISPER_MODEL_DIR="$HOME/tools/whisper-models"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "mac" ;;
        *)       echo "unknown" ;;
    esac
}

uninstall_linux() {
    info "Uninstalling for Linux..."

    # Stop and disable services
    if systemctl --user is-active dictation-daemon &>/dev/null; then
        info "Stopping dictation-daemon service..."
        systemctl --user stop dictation-daemon
    fi
    if systemctl --user is-active dictation-listener &>/dev/null; then
        info "Stopping dictation-listener service..."
        systemctl --user stop dictation-listener
    fi
    systemctl --user disable dictation-daemon dictation-listener 2>/dev/null || true

    # Remove scripts
    for script in dictate-daemon dictation-listener dictation-overlay; do
        if [ -f "$INSTALL_DIR/$script" ]; then
            rm "$INSTALL_DIR/$script"
            info "Removed $INSTALL_DIR/$script"
        fi
    done

    # Remove systemd services
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    for svc in dictation-daemon.service dictation-listener.service; do
        if [ -f "$SYSTEMD_DIR/$svc" ]; then
            rm "$SYSTEMD_DIR/$svc"
            info "Removed $SYSTEMD_DIR/$svc"
        fi
    done
    systemctl --user daemon-reload

    # Remove temp files
    rm -f /tmp/dictation_control /tmp/dictation.pid /tmp/dictation_daemon.pid \
          /tmp/dictation_recording.wav /tmp/dictation_notify.id
    info "Removed temp files."
}

uninstall_mac() {
    info "Uninstalling for macOS..."

    # Stop running daemon
    if [ -f /tmp/dictation_daemon.pid ]; then
        DPID=$(cat /tmp/dictation_daemon.pid)
        if kill -0 "$DPID" 2>/dev/null; then
            info "Stopping daemon (PID: $DPID)..."
            kill "$DPID" 2>/dev/null || true
        fi
    fi
    pkill -f "dictate-daemon" 2>/dev/null || true

    # Unload and remove launchd agent for daemon
    DICTATION_PLIST="$HOME/Library/LaunchAgents/com.user.dictation.plist"
    if [ -f "$DICTATION_PLIST" ]; then
        launchctl unload "$DICTATION_PLIST" 2>/dev/null || true
        rm "$DICTATION_PLIST"
        info "Removed launchd agent: com.user.dictation"
    fi

    # Remove daemon script
    if [ -f "$INSTALL_DIR/dictate-daemon" ]; then
        rm "$INSTALL_DIR/dictate-daemon"
        info "Removed $INSTALL_DIR/dictate-daemon"
    fi

    # Remove Hammerspoon dictation module
    HS_DICTATION="$HOME/.hammerspoon/modules/dictation"
    if [ -d "$HS_DICTATION" ]; then
        rm -rf "$HS_DICTATION"
        info "Removed Hammerspoon dictation module"
    fi

    # Remove dictation lines from Hammerspoon init.lua
    HS_INIT="$HOME/.hammerspoon/init.lua"
    if [ -f "$HS_INIT" ] && grep -q 'modules.dictation' "$HS_INIT"; then
        # Remove the dictation-related lines
        sed -i '' '/-- Voice Dictation/d' "$HS_INIT"
        sed -i '' '/modules\.dictation/d' "$HS_INIT"
        sed -i '' '/dictationModule\.setup/d' "$HS_INIT"
        info "Removed dictation references from $HS_INIT"
    fi

    # Unload and remove Caps Lock remap launchd agent
    CAPSLOCK_PLIST="$HOME/Library/LaunchAgents/com.user.capslock-remap.plist"
    if [ -f "$CAPSLOCK_PLIST" ]; then
        launchctl unload "$CAPSLOCK_PLIST" 2>/dev/null || true
        rm "$CAPSLOCK_PLIST"
        info "Removed launchd agent: com.user.capslock-remap"
    fi

    # Restore Caps Lock mapping
    hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1
    info "Restored Caps Lock to default mapping"

    # Reload Hammerspoon
    if pgrep -x Hammerspoon &>/dev/null; then
        hs -c "hs.reload()" 2>/dev/null || warn "Could not reload Hammerspoon. Please reload manually."
    fi

    # Remove temp files
    rm -f /tmp/dictation_control /tmp/dictation.pid /tmp/dictation_daemon.pid \
          /tmp/dictation_recording.wav /tmp/dictation_debug.log
    info "Removed temp files."
}

remove_shared() {
    # Config
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        info "Removed $CONFIG_DIR"
    fi

    # Groq config (ask first since it has API key)
    if [ -d "$GROQ_CONFIG_DIR" ]; then
        read -rp "Remove Groq config (includes API key)? [y/N]: " choice
        if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
            rm -rf "$GROQ_CONFIG_DIR"
            info "Removed $GROQ_CONFIG_DIR"
        else
            info "Kept $GROQ_CONFIG_DIR"
        fi
    fi

    # Whisper models (ask first since they're large downloads)
    if [ -d "$WHISPER_MODEL_DIR" ]; then
        read -rp "Remove Whisper models (~142MB+)? [y/N]: " choice
        if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
            rm -rf "$WHISPER_MODEL_DIR"
            info "Removed $WHISPER_MODEL_DIR"
        else
            info "Kept $WHISPER_MODEL_DIR"
        fi
    fi

    # Linux whisper.cpp build
    if [ -d "$HOME/tools/whisper.cpp" ]; then
        read -rp "Remove whisper.cpp build (~500MB)? [y/N]: " choice
        if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
            rm -rf "$HOME/tools/whisper.cpp"
            info "Removed ~/tools/whisper.cpp"
        else
            info "Kept ~/tools/whisper.cpp"
        fi
    fi
}

# --- Main ---

OS=$(detect_os)
info "Detected OS: $OS"

echo ""
echo "This will remove voice dictation scripts, services, and config."
read -rp "Continue? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""

case "$OS" in
    linux) uninstall_linux ;;
    mac)   uninstall_mac ;;
    *)     echo "Unsupported OS"; exit 1 ;;
esac

remove_shared

echo ""
info "Uninstall complete."
echo ""
echo "  Note: Homebrew packages (sox, whisper-cpp, hammerspoon) were NOT removed."
echo "  To remove them manually: brew uninstall sox whisper-cpp hammerspoon"
