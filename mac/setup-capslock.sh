#!/bin/bash
# Remap Caps Lock to F18 on macOS
# This is required for Hammerspoon to detect Caps Lock as a hotkey
#
# macOS intercepts Caps Lock at a low level, so we remap it to F18 using hidutil,
# then Hammerspoon detects F18.

set -e

echo "Remapping Caps Lock to F18..."

# Apply immediately
hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'

echo "Caps Lock remapped to F18 (immediate)."

# Persist across reboots via LaunchAgent
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.capslock-remap.plist"

if [ ! -f "$PLIST_PATH" ]; then
    echo "Creating LaunchAgent for persistence across reboots..."
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST_PATH" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.capslock-remap</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    launchctl load "$PLIST_PATH"
    echo "LaunchAgent created and loaded."
else
    echo "LaunchAgent already exists at $PLIST_PATH"
fi

echo ""
echo "Important: In System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys,"
echo "ensure Caps Lock is set to 'Caps Lock' (default), not 'No Action' or 'Escape'."
