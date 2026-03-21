# Voice Dictation

Offline and cloud-based voice dictation for Linux and macOS using OpenAI's Whisper model. Tap Caps Lock to start speaking, tap again to stop — transcribed text appears in the active window.

## Features

- **Two hotkey modes**: Caps Lock tap (toggle) and Caps Lock hold (push-to-talk)
- **Dual transcription backends**: Groq Cloud API (fast, accurate) or local whisper.cpp (offline)
- **Daemon architecture**: Model stays loaded in memory, instant response
- **Audio energy detection**: Skips silent recordings to avoid Whisper hallucinations
- **Visual feedback**: Recording overlay (Linux), sound effects on start/stop

## Hotkeys

| Hotkey | Mode | Description |
|--------|------|-------------|
| `Caps Lock` tap | Toggle | Quick tap to start, tap again to stop |
| `Caps Lock` hold | Push-to-talk | Hold >300ms to record, release to stop |
| `Ctrl+Shift+Space` | Toggle (legacy) | Press to start, press again to stop |

## Installation

```bash
git clone https://github.com/cccl-ai/voice-dictation.git
cd voice-dictation
./install.sh
```

The installer will:
1. Detect your OS (Linux or macOS)
2. Install system dependencies
3. Download the Whisper base model (142MB)
4. Ask for your preferred transcription backend (Groq or local)
5. Prompt for your Groq API key (if using Groq)
6. Install scripts and start services

### Prerequisites

**Linux:**
- Ubuntu/Debian with PipeWire and Wayland
- `sudo` access for package installation

**macOS:**
- Apple Silicon (M1/M2/M3/M4) recommended
- [Homebrew](https://brew.sh) installed

## Architecture

```
User presses Caps Lock
    │
    ▼
Hotkey Listener (evdev / Hammerspoon)
    │  detects tap vs hold (300ms threshold)
    ▼
Writes "start" or "stop" to /tmp/dictation_control
    │
    ▼
Dictation Daemon (bash, runs continuously)
    │
    ├─ start → Record audio (parecord / sox)
    │          Show overlay, play start sound
    │
    └─ stop  → Stop recording
               Check audio energy (RMS via sox)
               ├─ Too quiet → Skip (avoids hallucinations)
               └─ Has speech → Transcribe via Groq API or whisper.cpp
                               Paste text into active window
                               Play done sound
```

### Components

| Component | Linux | macOS |
|-----------|-------|-------|
| Hotkey detection | `evdev` (Python) | Hammerspoon (Lua) |
| Audio recording | `parecord` (PipeWire) | `sox` (rec) |
| Transcription | Groq API / whisper.cpp | Groq API / whisper.cpp (Metal) |
| Text input | `ydotool` + clipboard paste | AppleScript keystroke |
| Visual feedback | Tkinter overlay | Hammerspoon alert |
| Service manager | systemd user services | Manual / launchd |

## Configuration

### Change Transcription Backend

```bash
# Switch to local
echo "local" > ~/.config/dictation/backend

# Switch to groq
echo "groq" > ~/.config/dictation/backend

# Restart daemon (Linux)
systemctl --user restart dictation-daemon
```

### Groq API Key

```bash
# Set or update API key
echo "YOUR_KEY" > ~/.config/groq/api_key
chmod 600 ~/.config/groq/api_key
```

Get a free key at [console.groq.com/keys](https://console.groq.com/keys).

### Prompt Hints

Prompt hints give Whisper context about what you're likely to say, significantly improving accuracy for technical terms, names, and domain-specific vocabulary. This works with **both** the Groq and local whisper.cpp backends.

```bash
echo "I work with Python, React, and AWS. Technical terms I use: Kubernetes, PostgreSQL, FastAPI." > ~/.config/groq/prompt_hints
```

The hints file should contain a short block of natural text (under 200 words) covering:

- **Technical terms**: languages, frameworks, tools, services you mention often
- **People names**: colleagues, clients — names Whisper might otherwise misspell
- **Domain vocabulary**: project names, product names, industry-specific terms
- **Abbreviations**: acronyms that Whisper might misinterpret (e.g., "CI/CD", "LINX")

Example:

```bash
cat > ~/.config/groq/prompt_hints << 'EOF'
I work with Python, TypeScript, React, and AWS. Technical terms: Kubernetes, PostgreSQL,
FastAPI, Docker, Terraform, GitHub Actions, CI/CD. People: Alice, Bob, Casey, Dana.
Projects: Luminate, Initiate, LINX, ARS. Company terms: PipeWire, Wayland, systemd.
EOF
```

Restart the daemon after changing hints:

```bash
pkill -f dictate-daemon && ~/.local/bin/dictate-daemon &
```

### Change Whisper Model

Edit the `WHISPER_MODEL` variable in `~/.local/bin/dictate-daemon`:

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| ggml-tiny.bin | 75 MB | Fastest | Basic |
| **ggml-base.bin** | 142 MB | Fast | Good (default) |
| ggml-small.bin | 466 MB | Medium | Better |
| ggml-medium.bin | 1.5 GB | Slower | Great |
| ggml-large-v3.bin | 3 GB | Slowest | Best |

Download additional models:
```bash
cd ~/tools/whisper-models
curl -L -O "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
```

### Sound Volume (Linux)

Edit `~/.local/bin/dictate-daemon`:
```bash
SOUND_VOLUME="30"  # 0-100, default 50
```

## Usage

### Linux

Services start automatically on login. Check status:

```bash
systemctl --user status dictation-daemon dictation-listener
journalctl --user -u dictation-daemon -f   # Live logs
```

Restart after configuration changes:
```bash
systemctl --user restart dictation-daemon
```

### macOS

Start the daemon each login session:
```bash
~/.local/bin/dictate-daemon &
```

Hammerspoon handles hotkey detection automatically.

**Required permissions** (System Settings > Privacy & Security):
- Accessibility: Terminal.app
- Microphone: Terminal.app

## Troubleshooting

### Text not appearing (Linux)

```bash
# Check all services
systemctl --user status dictation-daemon dictation-listener ydotoold

# Test ydotool
/usr/local/bin/ydotool type "hello world"

# Check input group membership
groups | grep input
```

### Text not appearing (macOS)

```bash
# Test AppleScript keystroke
osascript -e 'tell application "System Events" to keystroke "hello world"'
```

If this fails, check Accessibility permissions for Terminal.app.

### No audio recording

```bash
# Linux: test parecord
parecord --channels=2 --rate=16000 --format=s16le /tmp/test.wav &
sleep 2 && kill %1
ls -la /tmp/test.wav

# macOS: test sox
rec -q -c 1 /tmp/test.wav trim 0 3
ls -la /tmp/test.wav
```

### "Thank you" hallucination on silence

The RMS energy check should prevent this. If it still happens, increase the threshold in `dictate-daemon`:
```bash
# Change 0.02 to a higher value like 0.03 or 0.04
if [ -n "$RMS" ] && [ "$(echo "$RMS < 0.03" | bc -l)" = "1" ]; then
```

### Daemon not transcribing

```bash
# Check logs
journalctl --user -u dictation-daemon -n 20

# Test whisper-cli manually
~/tools/whisper.cpp/build/bin/whisper-cli -m ~/tools/whisper-models/ggml-base.bin /tmp/test.wav
```

## Uninstall

### Linux

```bash
systemctl --user stop dictation-daemon dictation-listener
systemctl --user disable dictation-daemon dictation-listener
rm ~/.local/bin/dictate-daemon ~/.local/bin/dictation-listener ~/.local/bin/dictation-overlay
rm ~/.config/systemd/user/dictation-daemon.service ~/.config/systemd/user/dictation-listener.service
rm -rf ~/tools/whisper.cpp ~/tools/whisper-models
rm -rf ~/.config/dictation ~/.config/groq
systemctl --user daemon-reload
```

### macOS

```bash
rm ~/.local/bin/dictate-daemon
rm -rf ~/.hammerspoon/modules/dictation
rm -rf ~/tools/whisper-models
rm -rf ~/.config/dictation ~/.config/groq
rm ~/Library/LaunchAgents/com.user.capslock-remap.plist
# Remove dictation lines from ~/.hammerspoon/init.lua manually
```

## License

MIT
