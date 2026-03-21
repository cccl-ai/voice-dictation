#!/bin/bash
# Voice Dictation - Installation Verification Script
# Run after install.sh to verify everything is set up correctly
set +e  # Don't exit on failures — this script checks for them

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; ((WARN++)); }

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "mac" ;;
        *)       echo "unknown" ;;
    esac
}

OS=$(detect_os)
echo "Voice Dictation — Installation Test"
echo "OS: $OS"
echo ""

# ─── 1. Core Dependencies ───

echo "1. Core Dependencies"

if command -v python3 &>/dev/null; then
    pass "Python 3 ($(python3 --version 2>&1 | awk '{print $2}'))"
else
    fail "Python 3 not found"
fi

if command -v curl &>/dev/null; then
    pass "curl"
else
    fail "curl not found"
fi

if command -v bc &>/dev/null; then
    pass "bc"
else
    fail "bc not found"
fi

if command -v sox &>/dev/null; then
    pass "sox"
else
    fail "sox not found"
fi

# ─── 2. Platform-Specific Dependencies ───

echo ""
echo "2. Platform Dependencies ($OS)"

if [ "$OS" = "linux" ]; then
    if command -v parecord &>/dev/null; then
        pass "parecord (PipeWire/PulseAudio)"
    else
        fail "parecord not found — install pipewire-pulse or pulseaudio-utils"
    fi

    if command -v ydotool &>/dev/null; then
        pass "ydotool"
    else
        fail "ydotool not found"
    fi

    if command -v wl-copy &>/dev/null; then
        pass "wl-clipboard"
    else
        fail "wl-copy not found — install wl-clipboard"
    fi

    python3 -c "import evdev" 2>/dev/null && pass "Python evdev module" || fail "Python evdev module not found — install python3-evdev"
    python3 -c "import tkinter" 2>/dev/null && pass "Python tkinter module" || fail "Python tkinter module not found — install python3-tk"

    if groups | grep -q '\binput\b'; then
        pass "User in 'input' group"
    else
        fail "User not in 'input' group — run: sudo usermod -aG input \$USER (then re-login)"
    fi

elif [ "$OS" = "mac" ]; then
    if command -v whisper-cli &>/dev/null; then
        pass "whisper-cli (Homebrew)"
    else
        fail "whisper-cli not found — run: brew install whisper-cpp"
    fi

    if [ -d "/Applications/Hammerspoon.app" ] || [ -d "$HOME/Applications/Hammerspoon.app" ]; then
        pass "Hammerspoon installed"
    else
        fail "Hammerspoon not found — run: brew install --cask hammerspoon"
    fi

    if [ -f "$HOME/.hammerspoon/modules/dictation/init.lua" ]; then
        pass "Hammerspoon dictation module"
    else
        fail "Hammerspoon dictation module not installed"
    fi
fi

# ─── 3. Installed Scripts ───

echo ""
echo "3. Installed Scripts"

INSTALL_DIR="$HOME/.local/bin"

for script in dictate-daemon dictation-listener dictation-overlay; do
    if [ "$OS" = "mac" ] && [ "$script" != "dictate-daemon" ]; then
        continue  # listener and overlay are Linux-only
    fi
    if [ -f "$INSTALL_DIR/$script" ]; then
        if [ -x "$INSTALL_DIR/$script" ]; then
            pass "$script (executable)"
        else
            fail "$script exists but not executable"
        fi
    else
        fail "$script not found in $INSTALL_DIR"
    fi
done

# Check shebangs are portable
if [ "$OS" = "linux" ]; then
    for script in dictation-listener dictation-overlay; do
        if [ -f "$INSTALL_DIR/$script" ]; then
            shebang=$(head -1 "$INSTALL_DIR/$script")
            if echo "$shebang" | grep -q '/home/'; then
                fail "$script has hardcoded home path in shebang: $shebang"
            else
                pass "$script shebang is portable"
            fi
        fi
    done
fi

# ─── 4. Transcription Backend ───

echo ""
echo "4. Transcription Backend"

CONFIG_DIR="$HOME/.config/dictation"
BACKEND=$(cat "$CONFIG_DIR/backend" 2>/dev/null || echo "not set")

if [ "$BACKEND" = "groq" ] || [ "$BACKEND" = "local" ]; then
    pass "Backend configured: $BACKEND"
else
    fail "Backend not configured — run install.sh or echo 'groq' > $CONFIG_DIR/backend"
fi

if [ "$BACKEND" = "groq" ] || [ "$BACKEND" = "not set" ]; then
    if [ -f "$HOME/.config/groq/api_key" ] && [ -s "$HOME/.config/groq/api_key" ]; then
        pass "Groq API key present"
        # Test API key validity
        API_KEY=$(cat "$HOME/.config/groq/api_key")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_KEY" \
            "https://api.groq.com/openai/v1/models" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            pass "Groq API key is valid"
        elif [ "$HTTP_CODE" = "000" ]; then
            warn "Could not reach Groq API (no internet?)"
        else
            fail "Groq API key appears invalid (HTTP $HTTP_CODE)"
        fi
    else
        fail "Groq API key not found at $HOME/.config/groq/api_key"
    fi
fi

if [ "$BACKEND" = "local" ] || [ "$BACKEND" = "groq" ]; then
    # Check local whisper as fallback
    WHISPER_MODEL="$HOME/tools/whisper-models/ggml-base.bin"
    if [ -f "$WHISPER_MODEL" ]; then
        pass "Whisper model present ($(du -h "$WHISPER_MODEL" | awk '{print $1}'))"
    else
        if [ "$BACKEND" = "local" ]; then
            fail "Whisper model not found at $WHISPER_MODEL"
        else
            warn "Whisper model not found (local fallback unavailable)"
        fi
    fi

    if [ "$OS" = "linux" ]; then
        WHISPER_CLI="$HOME/tools/whisper.cpp/build/bin/whisper-cli"
    else
        WHISPER_CLI=$(command -v whisper-cli 2>/dev/null || echo "")
    fi
    if [ -n "$WHISPER_CLI" ] && [ -x "$WHISPER_CLI" ]; then
        pass "whisper-cli binary"
    else
        if [ "$BACKEND" = "local" ]; then
            fail "whisper-cli not found"
        else
            warn "whisper-cli not found (local fallback unavailable)"
        fi
    fi
fi

# ─── 5. Services ───

echo ""
echo "5. Services"

if [ "$OS" = "linux" ]; then
    for svc in dictation-daemon dictation-listener; do
        if systemctl --user is-active "$svc" &>/dev/null; then
            pass "$svc is running"
        elif systemctl --user is-enabled "$svc" &>/dev/null; then
            warn "$svc is enabled but not running"
        else
            fail "$svc is not enabled"
        fi
    done

    if systemctl --user is-active ydotoold &>/dev/null || pgrep ydotoold &>/dev/null; then
        pass "ydotoold is running"
    else
        fail "ydotoold is not running"
    fi

elif [ "$OS" = "mac" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.user.dictation.plist"
    if [ -f "$PLIST" ]; then
        pass "launchd agent installed"
    else
        fail "launchd agent not found"
    fi

    if pgrep -f "dictate-daemon" &>/dev/null; then
        pass "dictate-daemon is running"
    else
        warn "dictate-daemon is not running (start with: ~/.local/bin/dictate-daemon &)"
    fi
fi

# ─── 6. Audio Test ───

echo ""
echo "6. Audio (quick test)"

if [ "$OS" = "linux" ]; then
    # Try recording 1 second of audio
    AUDIO_TEST="/tmp/dictation_test_audio.wav"
    rm -f "$AUDIO_TEST"
    timeout 2 parecord --channels=1 --rate=16000 --format=s16le "$AUDIO_TEST" &>/dev/null &
    RECORD_PID=$!
    sleep 1
    kill $RECORD_PID 2>/dev/null || true
    wait $RECORD_PID 2>/dev/null || true

    if [ -f "$AUDIO_TEST" ] && [ -s "$AUDIO_TEST" ]; then
        SIZE=$(du -h "$AUDIO_TEST" | awk '{print $1}')
        pass "Audio recording works ($SIZE captured)"
        rm -f "$AUDIO_TEST"
    else
        fail "Audio recording failed — check microphone and PipeWire"
        rm -f "$AUDIO_TEST"
    fi

elif [ "$OS" = "mac" ]; then
    AUDIO_TEST="/tmp/dictation_test_audio.wav"
    rm -f "$AUDIO_TEST"
    timeout 2 sox -d -r 16000 -c 1 -b 16 "$AUDIO_TEST" trim 0 1 &>/dev/null &
    RECORD_PID=$!
    sleep 2
    kill $RECORD_PID 2>/dev/null || true
    wait $RECORD_PID 2>/dev/null || true

    if [ -f "$AUDIO_TEST" ] && [ -s "$AUDIO_TEST" ]; then
        pass "Audio recording works"
        rm -f "$AUDIO_TEST"
    else
        warn "Audio recording test failed — check microphone permissions"
        rm -f "$AUDIO_TEST"
    fi
fi

# ─── 7. dt Tools ───

echo ""
echo "7. Dictation Tools (dt)"

if [ -f "$INSTALL_DIR/dt" ] && [ -x "$INSTALL_DIR/dt" ]; then
    pass "dt CLI installed"
else
    warn "dt CLI not found (optional — history/replay tools)"
fi

# ─── Summary ───

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL + WARN))
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC} (out of $TOTAL checks)"

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}All checks passed!${NC} Voice dictation should be working."
    echo "Try tapping Caps Lock and speaking."
else
    echo ""
    echo -e "${RED}Some checks failed.${NC} Fix the issues above, then re-run: ./test.sh"
fi
