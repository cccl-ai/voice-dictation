#!/bin/bash
# Test voice-dictation installation in a fresh LXC container
# Usage: ./test-container.sh [container-name]
# Requires: LXD/Incus installed (snap install lxd && lxd init --minimal)
set -euo pipefail

CONTAINER="${1:-voice-dictation-test}"
IMAGE="ubuntu:24.04"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Detect LXC command (lxd vs incus)
if command -v lxc &>/dev/null; then
    LXC="lxc"
elif command -v incus &>/dev/null; then
    LXC="incus"
else
    echo ""
    echo "LXD/Incus not found. Install with:"
    echo "  sudo snap install lxd"
    echo "  lxd init --minimal"
    echo ""
    echo "Then re-run this script."
    exit 1
fi

info "Using: $LXC"

# Check if container already exists
if $LXC info "$CONTAINER" &>/dev/null; then
    warn "Container '$CONTAINER' already exists. Deleting..."
    $LXC delete "$CONTAINER" --force
fi

# Launch container
info "Launching Ubuntu 24.04 container: $CONTAINER"
$LXC launch "$IMAGE" "$CONTAINER"

# Wait for container to be ready
info "Waiting for container to start..."
sleep 3

# Wait for cloud-init / network
for i in $(seq 1 30); do
    if $LXC exec "$CONTAINER" -- ping -c1 -W1 archive.ubuntu.com &>/dev/null; then
        break
    fi
    sleep 1
done

# Install git
info "Installing git in container..."
$LXC exec "$CONTAINER" -- bash -c "apt-get update -qq && apt-get install -y -qq git sudo" 2>&1 | tail -1

# Create a test user (not root — tests systemd user services)
info "Creating test user..."
$LXC exec "$CONTAINER" -- bash -c "
    useradd -m -s /bin/bash testuser
    echo 'testuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/testuser
    mkdir -p /home/testuser/.local/bin
    chown -R testuser:testuser /home/testuser
"

# Clone the repo
info "Cloning voice-dictation repo..."
$LXC exec "$CONTAINER" -- su - testuser -c \
    "git clone https://github.com/cccl-ai/voice-dictation.git ~/voice-dictation"

# Run install with 'local' backend (no API key needed) and skip interactive prompts
info "Running install.sh (local backend, non-interactive)..."
$LXC exec "$CONTAINER" -- su - testuser -c "
    mkdir -p ~/.config/dictation ~/.config/groq
    echo 'local' > ~/.config/dictation/backend
    cd ~/voice-dictation

    # Patch install.sh to skip interactive prompts (backend already configured)
    sed 's/setup_backend/info \"Backend pre-configured as local\"/' install.sh > install-ci.sh
    chmod +x install-ci.sh

    # Enable lingering for systemd user services without login session
    sudo loginctl enable-linger testuser

    # Need XDG_RUNTIME_DIR for systemd --user
    export XDG_RUNTIME_DIR=/run/user/\$(id -u)
    mkdir -p \$XDG_RUNTIME_DIR || true

    bash install-ci.sh 2>&1
" || warn "Install had issues (expected in container — no audio hardware)"

# Run the test script
info "Running test.sh..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
$LXC exec "$CONTAINER" -- su - testuser -c "
    export XDG_RUNTIME_DIR=/run/user/\$(id -u)
    cd ~/voice-dictation && bash test.sh 2>&1
" || true
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
info "Container '$CONTAINER' is still running."
echo ""
echo "  Shell into it:   $LXC exec $CONTAINER -- su - testuser"
echo "  Delete it:       $LXC delete $CONTAINER --force"
echo ""
echo "  NOTE: Audio recording and hotkey tests will fail in a container"
echo "  (no audio hardware or display server). The test verifies that"
echo "  all dependencies install correctly and scripts are in place."
