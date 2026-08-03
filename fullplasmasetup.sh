# ---------------------------------------------------------------------------
# 2. Package Installation (CachyOS / Arch Repos & AUR)
# ---------------------------------------------------------------------------
install_packages() {
  log "Updating system databases..."
  sudo pacman -Syu --noconfirm

  # Determine AUR Helper (CachyOS usually ships with paru or yay)
  local aur_helper=""
  if command -v paru >/dev/null; then
    aur_helper="paru"
  elif command -v yay >/dev/null; then
    aur_helper="yay"
  else
    warn "No AUR helper (paru/yay) found. Installing yay..."
    sudo pacman -S --needed --noconfirm yay
    aur_helper="yay"
  fi

  # Official repo packages ONLY
  local pkgs=(
    plasma-meta sddm
    konsole dolphin ark kate spectacle gwenview
    kde-gtk-config qt5-wayland qt6-wayland
    git wget unzip jq
    ttf-firacode-nerd noto-fonts-emoji
    cava                      # Console Audio Visualizer
    papirus-icon-theme        # Icon base
  )

  log "Installing core desktop packages from main repos..."
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"

  # AUR packages installed via yay/paru
  local aur_pkgs=(
    "$CURSOR_PKG"
    "papirus-folders"
    "ttf-catppuccin-mcp"
    "kwin-effects-blur-respect-rounded-corners-git"
  )

  log "Installing AUR eye-candy & font packages..."
  $aur_helper -S --needed --noconfirm "${aur_pkgs[@]}" || true

  # Fallback for papirus-folders in case AUR fails
  if ! command -v papirus-folders >/dev/null; then
    log "Installing papirus-folders directly from GitHub fallback..."
    wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/install.sh | sh || true
  fi

  ok "Packages successfully installed."
}

# ---------------------------------------------------------------------------
# 3. KWin Tiling (Polonium) & Plasma Aesthetics
# ---------------------------------------------------------------------------
configure_kwin_and_plasma() {
  log "Configuring KWin Tiling & Plasma Effects..."

  # Install/Enable Polonium (Auto-Tiling Manager for Plasma 6)
  if command -v kpackagetool6 >/dev/null; then
    log "Setting up Polonium auto-tiling script..."
    kpackagetool6 --type KWin/Script -i com.github.zeroching.polonium 2>/dev/null || \
    kpackagetool6 --type KWin/Script -u com.github.zeroching.polonium 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key poloniumEnabled true
  fi

  # Enable Blur & Glass Effects in KWin
  kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
  kwriteconfig6 --file kwinrc --group Plugins --key contrastEnabled true
  kwriteconfig6 --file kwinrc --group Compositing --key LatencyPolicy "Low"

  # Apply Papirus Mauve Icons
  if command -v papirus-folders >/dev/null; then
    log "Applying Catppuccin Mauve accent to Papirus icons..."
    papirus-folders -c cat-mocha-mauve --theme Papirus-Dark || sudo papirus-folders -c cat-mocha-mauve --theme Papirus-Dark || true
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "Papirus-Dark"
  else
    warn "papirus-folders command not found, skipping icon accenting."
  fi

  # Set Cursor
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "Catppuccin-Mocha-Mauve-Cursors"
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize 24

  ok "KWin tiling and desktop aesthetics configured."
}