#!/bin/sh
# swift_build.sh - Swift compilation functions for Claude Monitor
# This file is sourced by install.sh

# ================= Swift Build Functions =================

# Swift source files in compilation order
SWIFT_FILES="Utils/Logger.swift Utils/PermissionManager.swift Services/DatabaseModels.swift Services/DatabaseManager.swift Services/DatabaseManager+Timeline.swift Services/SettingsManager.swift UI/SessionCardView.swift UI/SessionListView.swift UI/SessionDetailView.swift UI/StatusBarController.swift Core/AppDelegate.swift UI/SettingsWindow.swift Core/Main.swift"

# Compile Swift application
# Arguments: $1 = SWIFT_DIR, $2 = BINARY_PATH
compile_swift() {
    local swift_dir="$1"
    local binary_path="$2"

    # Verify all files exist
    for swiftfile in $SWIFT_FILES; do
        if [ ! -f "$swift_dir/$swiftfile" ]; then
            cecho "${RED}Error: $swiftfile not found in $swift_dir${NC}"
            return 1
        fi
    done

    # Compile
    swiftc \
        "$swift_dir/Utils/Logger.swift" \
        "$swift_dir/Utils/PermissionManager.swift" \
        "$swift_dir/Services/DatabaseModels.swift" \
        "$swift_dir/Services/DatabaseManager.swift" \
        "$swift_dir/Services/DatabaseManager+Timeline.swift" \
        "$swift_dir/Services/SettingsManager.swift" \
        "$swift_dir/UI/SessionCardView.swift" \
        "$swift_dir/UI/SessionListView.swift" \
        "$swift_dir/UI/SessionDetailView.swift" \
        "$swift_dir/UI/StatusBarController.swift" \
        "$swift_dir/Core/AppDelegate.swift" \
        "$swift_dir/UI/SettingsWindow.swift" \
        "$swift_dir/Core/Main.swift" \
        -o "$binary_path" \
        -target arm64-apple-macosx12.0

    chmod +x "$binary_path"
    return 0
}

# Create Info.plist
# Arguments: $1 = INSTALL_DIR, $2 = APP_NAME
create_info_plist() {
    local install_dir="$1"
    local app_name="$2"

    cat << EOF > "$install_dir/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.custom.claude.monitor</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>ClaudeMonitor needs automation access to restore minimized windows.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
</dict>
</plist>
EOF
}

# Copy app icons
# Arguments: $1 = ASSETS_DIR, $2 = INSTALL_DIR
copy_app_icons() {
    local assets_dir="$1"
    local install_dir="$2"

    mkdir -p "$install_dir/Contents/Resources"

    # Copy PNG icon
    if [ -f "$assets_dir/app_icon.png" ]; then
        cp "$assets_dir/app_icon.png" "$install_dir/Contents/Resources/app_icon.png"
        cecho "${GREEN}✅ App icon copied${NC}"
    else
        cecho "${YELLOW}[!] No app_icon.png found in assets/, skipping icon installation${NC}"
    fi

    # Copy or create .icns icon
    if [ -f "$assets_dir/AppIcon.icns" ]; then
        cp "$assets_dir/AppIcon.icns" "$install_dir/Contents/Resources/"
        cecho "${GREEN}✅ .icns icon installed${NC}"
    elif command -v iconutil >/dev/null 2>&1 && [ -f "$assets_dir/app_icon.png" ]; then
        # Create .icns from png if not exists
        mkdir -p "$assets_dir/AppIcon.iconset"
        sips -z 16 16 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_16x16.png" >/dev/null 2>&1
        sips -z 32 32 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_16x16@2x.png" >/dev/null 2>&1
        sips -z 32 32 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_32x32.png" >/dev/null 2>&1
        sips -z 64 64 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_32x32@2x.png" >/dev/null 2>&1
        sips -z 128 128 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_128x128.png" >/dev/null 2>&1
        sips -z 256 256 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_128x128@2x.png" >/dev/null 2>&1
        sips -z 256 256 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_256x256.png" >/dev/null 2>&1
        sips -z 512 512 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_256x256@2x.png" >/dev/null 2>&1
        sips -z 512 512 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_512x512.png" >/dev/null 2>&1
        sips -z 1024 1024 "$assets_dir/app_icon.png" --out "$assets_dir/AppIcon.iconset/icon_512x512@2x.png" >/dev/null 2>&1

        if iconutil -c icns "$assets_dir/AppIcon.iconset" -o "$assets_dir/AppIcon.icns" 2>/dev/null; then
            cp "$assets_dir/AppIcon.icns" "$install_dir/Contents/Resources/"
            cecho "${GREEN}✅ .icns icon created and installed${NC}"
        fi
    fi
}

# Sign and register app
# Arguments: $1 = INSTALL_DIR, $2 = APP_NAME
sign_and_register_app() {
    local install_dir="$1"
    local app_name="$2"

    codesign --force --deep --sign - "$install_dir"
    open "$install_dir"
    sleep 0.5
    pkill -f "$app_name" || true
}
