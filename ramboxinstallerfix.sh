#!/bin/bash
# fix-rambox-gnome.sh
# Installs rambox-pro-bin and fixes it not appearing (with icon) in the GNOME app launcher on CachyOS/Arch

set -e

# ── 1. Install rambox-pro-bin via paru/yay ────────────────────────────────────
echo "==> Installing rambox-pro-bin..."
if command -v paru &>/dev/null; then
    paru -S --noconfirm rambox-pro-bin
elif command -v yay &>/dev/null; then
    yay -S --noconfirm rambox-pro-bin
else
    echo "ERROR: No AUR helper found (paru or yay). Please install one first."
    exit 1
fi

# ── 2. Fix directory/binary permissions ──────────────────────────────────────
echo "==> Fixing /opt/rambox permissions..."
sudo chmod 755 /opt/rambox
sudo chmod 755 /opt/rambox/rambox

# ── 3. Extract icon from app.asar ────────────────────────────────────────────
echo "==> Extracting icon from app.asar..."

ICON_DEST=/usr/share/pixmaps/rambox.png
ICON_FOUND=false

# Install asar if needed
if ! command -v asar &>/dev/null; then
    echo "==> Installing asar..."
    sudo npm install -g asar
fi

# Extract the asar and look for the icon
TMPDIR=$(mktemp -d)
asar extract /opt/rambox/resources/app.asar "$TMPDIR/app" 2>/dev/null

# Search for a suitable icon inside the extracted contents
for candidate in \
    "$TMPDIR/app/icon.png" \
    "$TMPDIR/app/build/icon.png" \
    "$TMPDIR/app/assets/icon.png" \
    "$TMPDIR/app/resources/icon.png" \
    "$TMPDIR/app/src/icon.png"; do
    if [ -f "$candidate" ]; then
        echo "==> Found icon at $candidate"
        sudo cp "$candidate" "$ICON_DEST"
        ICON_FOUND=true
        break
    fi
done

# Fallback: grab the largest PNG in the extracted folder (most likely to be the app icon)
if [ "$ICON_FOUND" = false ]; then
    BEST=$(find "$TMPDIR/app" -name "*.png" 2>/dev/null | xargs ls -S 2>/dev/null | head -1)
    if [ -n "$BEST" ]; then
        echo "==> Using fallback icon: $BEST"
        sudo cp "$BEST" "$ICON_DEST"
        ICON_FOUND=true
    fi
fi

rm -rf "$TMPDIR"

if [ "$ICON_FOUND" = false ]; then
    echo "==> WARNING: Could not find an icon. Rambox will appear without one."
    ICON_LINE="Icon=rambox"
else
    echo "==> Icon installed to $ICON_DEST"
    sudo gtk-update-icon-cache -f /usr/share/icons/hicolor/ 2>/dev/null || true
    ICON_LINE="Icon=$ICON_DEST"
fi

# ── 4. Write a clean desktop entry ───────────────────────────────────────────
echo "==> Writing desktop entry..."
sudo tee /usr/share/applications/rambox.desktop > /dev/null <<EOF
[Desktop Entry]
Name=Rambox
Exec=/opt/rambox/rambox --no-sandbox %U
Terminal=false
Type=Application
${ICON_LINE}
StartupWMClass=rambox
Categories=Network;
MimeType=x-scheme-handler/rambox;
Comment=Workspace simplifier
NoDisplay=false
EOF

# ── 5. Refresh desktop database ──────────────────────────────────────────────
echo "==> Updating desktop database..."
sudo update-desktop-database /usr/share/applications

echo ""
echo "All done! Log out and back in for GNOME to show Rambox in the app launcher."
echo "You can test launching now with: rambox &"
