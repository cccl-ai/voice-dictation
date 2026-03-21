#!/bin/bash
# Voice Dictation Installer
# Supports Linux (Ubuntu/Debian with PipeWire + Wayland) and macOS (Apple Silicon)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
WHISPER_MODEL_DIR="$HOME/tools/whisper-models"
CONFIG_DIR="$HOME/.config/dictation"
GROQ_CONFIG_DIR="$HOME/.config/groq"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

detect_os() {
    case "$(uname -s)" in
        Linux*)  OS="linux" ;;
        Darwin*) OS="mac" ;;
        *)       error "Unsupported OS: $(uname -s)" ;;
    esac
    echo "$OS"
}

check_python3() {
    if ! command -v python3 &>/dev/null; then
        error "Python 3 is required but not found. Install it first."
    fi
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    info "Found Python $PYTHON_VERSION"
}

# Fix shebangs in Python scripts to use portable #!/usr/bin/env python3
fix_shebangs() {
    local file="$1"
    if head -1 "$file" | grep -q '^#!.*python'; then
        if [ "$OS" = "mac" ]; then
            sed -i '' '1s|^#!.*python[0-9.]*|#!/usr/bin/env python3|' "$file"
        else
            sed -i '1s|^#!.*python[0-9.]*|#!/usr/bin/env python3|' "$file"
        fi
    fi
}

# --- Transcription Backend ---

setup_backend() {
    mkdir -p "$CONFIG_DIR"

    echo ""
    echo "Choose transcription backend:"
    echo "  1) groq  - Groq Cloud API (fast, requires API key, needs internet)"
    echo "  2) local - Local whisper.cpp (offline, slower, uses CPU/GPU)"
    echo ""
    read -rp "Backend [1/2] (default: 1): " choice

    case "$choice" in
        2|local)
            echo "local" > "$CONFIG_DIR/backend"
            info "Backend set to: local"
            setup_whisper
            ;;
        *)
            echo "groq" > "$CONFIG_DIR/backend"
            info "Backend set to: groq"
            setup_groq_key
            setup_whisper  # Also install whisper as fallback
            ;;
    esac
}

setup_groq_key() {
    mkdir -p "$GROQ_CONFIG_DIR"
    if [ -f "$GROQ_CONFIG_DIR/api_key" ]; then
        info "Groq API key already configured."
        read -rp "Replace existing key? [y/N]: " replace
        [ "$replace" != "y" ] && [ "$replace" != "Y" ] && return
    fi

    echo ""
    echo "Get a free API key at: https://console.groq.com/keys"
    read -rp "Enter your Groq API key: " api_key
    if [ -n "$api_key" ]; then
        echo "$api_key" > "$GROQ_CONFIG_DIR/api_key"
        chmod 600 "$GROQ_CONFIG_DIR/api_key"
        info "API key saved to $GROQ_CONFIG_DIR/api_key"
    else
        warn "No API key provided. You can add it later to $GROQ_CONFIG_DIR/api_key"
    fi
}

setup_whisper() {
    mkdir -p "$WHISPER_MODEL_DIR"

    if [ "$OS" = "mac" ]; then
        if ! command -v whisper-cli &>/dev/null; then
            info "Installing whisper-cpp via Homebrew..."
            brew install whisper-cpp
        else
            info "whisper-cpp already installed."
        fi
    else
        # Linux: build from source
        if [ ! -f "$HOME/tools/whisper.cpp/build/bin/whisper-cli" ]; then
            info "Building whisper.cpp from source..."
            mkdir -p "$HOME/tools"
            cd "$HOME/tools"
            if [ ! -d "whisper.cpp" ]; then
                git clone https://github.com/ggerganov/whisper.cpp.git
            fi
            cd whisper.cpp
            cmake -B build
            cmake --build build --config Release -j$(nproc)
            info "whisper.cpp built successfully."
        else
            info "whisper.cpp already built."
        fi
    fi

    # Download base model if not present
    if [ ! -f "$WHISPER_MODEL_DIR/ggml-base.bin" ]; then
        info "Downloading Whisper base model (142MB)..."
        curl -L -o "$WHISPER_MODEL_DIR/ggml-base.bin" \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
        info "Model downloaded."
    else
        info "Whisper base model already present."
    fi
}

# --- Linux Installation ---

install_linux() {
    info "Installing for Linux..."
    check_python3

    # Install system dependencies
    info "Installing system packages..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        pipewire-pulse \
        sox \
        wl-clipboard \
        python3-evdev \
        xdotool \
        bc \
        python3-tk \
        curl \
        cmake \
        g++ \
        git

    # Check ydotool
    if ! command -v ydotool &>/dev/null; then
        warn "ydotool not found. Installing..."
        sudo apt-get install -y -qq ydotool
    fi

    # Ensure ydotoold service is running
    if ! systemctl --user is-active ydotoold &>/dev/null; then
        info "Enabling ydotoold service..."
        systemctl --user enable --now ydotoold 2>/dev/null || \
            warn "Could not enable ydotoold user service. You may need to start it manually."
    fi

    # Add user to input group if not already
    if ! groups | grep -q '\binput\b'; then
        info "Adding $USER to input group (needed for keyboard event access)..."
        sudo usermod -aG input "$USER"
        warn "You'll need to log out and back in for the group change to take effect."
    fi

    # Copy scripts and fix shebangs
    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_DIR/linux/dictate-daemon" "$INSTALL_DIR/dictate-daemon"
    cp "$SCRIPT_DIR/linux/dictation-listener" "$INSTALL_DIR/dictation-listener"
    cp "$SCRIPT_DIR/linux/dictation-overlay" "$INSTALL_DIR/dictation-overlay"
    fix_shebangs "$INSTALL_DIR/dictation-listener"
    fix_shebangs "$INSTALL_DIR/dictation-overlay"
    chmod +x "$INSTALL_DIR/dictate-daemon" "$INSTALL_DIR/dictation-listener" "$INSTALL_DIR/dictation-overlay"
    info "Scripts installed to $INSTALL_DIR/"

    # Install systemd services
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    cp "$SCRIPT_DIR/linux/dictation-daemon.service" "$SYSTEMD_DIR/"
    cp "$SCRIPT_DIR/linux/dictation-listener.service" "$SYSTEMD_DIR/"
    systemctl --user daemon-reload
    info "Systemd services installed."

    # Setup backend
    setup_backend

    # Enable and start services
    systemctl --user enable dictation-daemon dictation-listener
    systemctl --user restart dictation-daemon dictation-listener
    info "Services enabled and started."

    echo ""
    info "Installation complete! Voice dictation is running."
    echo ""
    echo "  Hotkeys:"
    echo "    Caps Lock tap (<300ms):  Toggle mode (start/stop)"
    echo "    Caps Lock hold (>300ms): Push-to-talk"
    echo "    Ctrl+Shift+Space:        Toggle mode (legacy)"
    echo ""
    echo "  Check status:  systemctl --user status dictation-daemon dictation-listener"
    echo "  View logs:     journalctl --user -u dictation-daemon -f"
}

# --- macOS Installation ---

install_mac() {
    info "Installing for macOS..."
    check_python3

    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        error "Homebrew is required. Install it from https://brew.sh"
    fi

    # Install dependencies
    info "Installing dependencies via Homebrew..."
    brew install sox whisper-cpp
    brew install --cask hammerspoon

    # Copy daemon script
    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_DIR/mac/dictate-daemon" "$INSTALL_DIR/dictate-daemon"
    chmod +x "$INSTALL_DIR/dictate-daemon"
    info "Daemon script installed to $INSTALL_DIR/"

    # Setup Caps Lock remap
    info "Setting up Caps Lock remap to F18..."
    bash "$SCRIPT_DIR/mac/setup-capslock.sh"

    # Install Hammerspoon module
    HAMMERSPOON_DIR="$HOME/.hammerspoon/modules/dictation"
    mkdir -p "$HAMMERSPOON_DIR"
    cp "$SCRIPT_DIR/mac/dictation.lua" "$HAMMERSPOON_DIR/init.lua"
    info "Hammerspoon module installed."

    # Check if dictation module is loaded in Hammerspoon init
    HS_INIT="$HOME/.hammerspoon/init.lua"
    if [ -f "$HS_INIT" ]; then
        if ! grep -q 'modules.dictation' "$HS_INIT"; then
            echo '' >> "$HS_INIT"
            echo '-- Voice Dictation' >> "$HS_INIT"
            echo 'local dictationModule = require("modules.dictation")' >> "$HS_INIT"
            echo 'dictationModule.setup()' >> "$HS_INIT"
            info "Added dictation module to Hammerspoon init.lua"
        else
            info "Dictation module already referenced in Hammerspoon init.lua"
        fi
    else
        mkdir -p "$HOME/.hammerspoon"
        cat > "$HS_INIT" << 'EOF'
-- Voice Dictation
local dictationModule = require("modules.dictation")
dictationModule.setup()
EOF
        info "Created Hammerspoon init.lua with dictation module"
    fi

    # Setup backend
    setup_backend

    # Install launchd agent to start daemon on login
    DICTATION_PLIST="$HOME/Library/LaunchAgents/com.user.dictation.plist"
    if [ ! -f "$DICTATION_PLIST" ]; then
        info "Creating launchd agent for auto-start on login..."
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$DICTATION_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.dictation</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/dictate-daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
        launchctl load "$DICTATION_PLIST" 2>/dev/null || true
        info "Daemon will auto-start on login."
    else
        info "Launchd agent already exists."
    fi

    # Reload Hammerspoon
    if pgrep -x Hammerspoon &>/dev/null; then
        hs -c "hs.reload()" 2>/dev/null || warn "Could not reload Hammerspoon. Please reload manually."
    fi

    echo ""
    info "Installation complete!"
    echo ""
    echo "  Hotkeys:"
    echo "    Caps Lock tap (<300ms):  Toggle mode (start/stop)"
    echo "    Caps Lock hold (>300ms): Push-to-talk"
    echo "    Ctrl+Shift+Space:        Toggle mode (legacy)"
    echo ""
    echo "  Permissions needed (System Settings > Privacy & Security):"
    echo "    - Accessibility: Terminal.app"
    echo "    - Microphone: Terminal.app, sox"
    echo ""
    echo "  The daemon auto-starts on login via launchd."
    echo "  To start it now:  ~/.local/bin/dictate-daemon &"
}

# --- Main ---

OS=$(detect_os)
info "Detected OS: $OS"

case "$OS" in
    linux) install_linux ;;
    mac)   install_mac ;;
esac
