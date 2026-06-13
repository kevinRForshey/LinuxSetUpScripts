#!/usr/bin/env bash
#
# setup-plasma-catppuccin.sh
#
# EndeavourOS (Arch) : install KDE Plasma 6 on Wayland, fix Electron/Chromium
# Wayland sluggishness (VSCodium etc.), apply a system-wide Catppuccin theme,
# and dress Konsole to look like Garuda "Mokka" (Catppuccin Mocha + glass + Nerd Font).
#
# Design notes:
#   - Single-responsibility functions, no hidden side effects (SOLID in spirit).
#   - Never run as root; uses sudo only where required.
#   - Idempotent where practical; safe to re-run.
#   - Does NOT touch your bootloader. NVIDIA Wayland advice is printed, not applied.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Constants (edit these if you want a different Nerd Font / opacity)
# ---------------------------------------------------------------------------
readonly NERD_FONT_PKG="ttf-firacode-nerd"
readonly NERD_FONT_NAME="FiraCode Nerd Font"
readonly KONSOLE_PROFILE="Mokka"
readonly KONSOLE_SCHEME="CatppuccinMocha"
readonly KONSOLE_OPACITY="0.85"     # Garuda Mokka glassiness; 1.0 = opaque
readonly CATPPUCCIN_REPO="https://github.com/catppuccin/kde"

log()  { printf '\033[1;35m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Preconditions
# ---------------------------------------------------------------------------
preflight() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root. It will sudo when needed."
  command -v pacman >/dev/null || die "pacman not found — this is for Arch/EndeavourOS."
  command -v sudo   >/dev/null || die "sudo is required."
  sudo -v || die "sudo authentication failed."
  ok "Preflight checks passed."
}

# ---------------------------------------------------------------------------
# 2. System update + package installation
# ---------------------------------------------------------------------------
install_packages() {
  log "Refreshing databases and updating system…"
  sudo pacman -Syu --noconfirm

  # plasma-meta = full Plasma 6 desktop (includes Wayland session, qt6-wayland,
  # xdg-desktop-portal-kde, kscreen, plasma-nm, plasma-pa, powerdevil, etc.).
  # In Plasma 6 the Wayland session ships inside plasma-workspace — there is NO
  # separate "plasma-wayland-session" package to install.
  local pkgs=(
    plasma-meta sddm
    konsole dolphin ark kate spectacle gwenview
    kde-gtk-config            # keeps GTK apps in step with the Plasma theme
    qt5-wayland qt6-wayland   # qt6 is pulled by meta; qt5 helps legacy Qt apps
    git wget unzip
    "$NERD_FONT_PKG" noto-fonts noto-fonts-emoji
  )
  log "Installing KDE Plasma 6 + tools (this is the big step)…"
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
  ok "Packages installed."
}

enable_sddm() {
  log "Enabling SDDM display manager…"
  # Disable a previously-enabled DM (e.g. gdm) so they don't fight at boot.
  for dm in gdm lightdm lxdm; do
    systemctl is-enabled "$dm" &>/dev/null && sudo systemctl disable "$dm" || true
  done
  sudo systemctl enable sddm.service
  ok "SDDM enabled (Plasma (Wayland) will be selectable on the login screen)."
}

# ---------------------------------------------------------------------------
# 3. Wayland fixes for Electron / Chromium / Firefox
#    Root cause of VSCodium being slow/blurry on Wayland: it runs through
#    XWayland with software-ish compositing instead of native Wayland (Ozone).
#    Fix = tell Electron/Chromium to use the Wayland Ozone backend.
# ---------------------------------------------------------------------------
fix_wayland_apps() {
  log "Applying Wayland fixes for Electron/Chromium/Firefox…"

  # Session-wide env (Plasma sources ~/.config/environment.d on login).
  # ELECTRON_OZONE_PLATFORM_HINT=auto -> native Wayland when available,
  # graceful X11 fallback otherwise (won't break apps if you switch back).
  mkdir -p "$HOME/.config/environment.d"
  cat > "$HOME/.config/environment.d/10-wayland.conf" <<'EOF'
ELECTRON_OZONE_PLATFORM_HINT=auto
MOZ_ENABLE_WAYLAND=1
EOF

  # Per-app flag files, for apps/older Electron that ignore the env hint.
  # One flag per line; harmless if the app isn't installed.
  local flags=$'--enable-features=UseOzonePlatform,WaylandWindowDecorations\n--ozone-platform-hint=auto'
  for app in codium code chromium; do
    printf '%s\n' "$flags" > "$HOME/.config/${app}-flags.conf"
  done
  ok "Wayland app fixes written (logout required to take effect)."
}

# ---------------------------------------------------------------------------
# 4. Catppuccin system-wide global theme (interactive flavour/accent pick)
# ---------------------------------------------------------------------------
install_catppuccin_global() {
  log "Cloning Catppuccin KDE…"
  local dir; dir="$(mktemp -d)"
  git clone --depth=1 "$CATPPUCCIN_REPO" "$dir/kde"

  warn "The installer will now ask for FLAVOUR and ACCENT."
  warn ">>> Choose MOCHA for the Garuda-Mokka look, then your accent colour. <<<"
  sleep 5
  ( cd "$dir/kde" && ./install.sh )

  rm -rf "$dir"
  ok "Catppuccin global theme installed."
}

# ---------------------------------------------------------------------------
# 5. Konsole "Mokka" profile — Catppuccin Mocha + transparency + blur
#    Opacity & Blur live in the .colorscheme [General] section (Konsole quirk).
# ---------------------------------------------------------------------------
configure_konsole() {
  log "Building Garuda-Mokka-style Konsole profile…"
  local kdir="$HOME/.local/share/konsole"
  mkdir -p "$kdir"

  # --- Catppuccin Mocha colour scheme (official palette mapping) ---
  cat > "$kdir/${KONSOLE_SCHEME}.colorscheme" <<EOF
[Background]
Color=30,30,46
[BackgroundIntense]
Color=24,24,37
[Foreground]
Color=205,214,244
[ForegroundIntense]
Color=205,214,244
[Color0]
Color=69,71,90
[Color0Intense]
Color=88,91,112
[Color1]
Color=243,139,168
[Color1Intense]
Color=243,139,168
[Color2]
Color=166,227,161
[Color2Intense]
Color=166,227,161
[Color3]
Color=249,226,175
[Color3Intense]
Color=249,226,175
[Color4]
Color=137,180,250
[Color4Intense]
Color=137,180,250
[Color5]
Color=245,194,231
[Color5Intense]
Color=245,194,231
[Color6]
Color=148,226,213
[Color6Intense]
Color=148,226,213
[Color7]
Color=186,194,222
[Color7Intense]
Color=166,173,200
[General]
Blur=true
ColorRandomization=false
Description=Catppuccin Mocha
Opacity=${KONSOLE_OPACITY}
Wallpaper=
EOF

  # --- Profile that uses the scheme + a Nerd Font (Mokka vibe) ---
  cat > "$kdir/${KONSOLE_PROFILE}.profile" <<EOF
[Appearance]
ColorScheme=${KONSOLE_SCHEME}
Font=${NERD_FONT_NAME},11,-1,5,50,0,0,0,0,0
[General]
Name=${KONSOLE_PROFILE}
Parent=FALLBACK/
TerminalColumns=110
TerminalRows=28
[Scrolling]
HistoryMode=2
[Terminal Features]
BlinkingCursorEnabled=true
EOF

  # --- Make it the default + hide menubar + minimal tab bar (Mokka chrome) ---
  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "${KONSOLE_PROFILE}.profile"
    kwriteconfig6 --file konsolerc --group KonsoleWindow --key ShowMenuBarByDefault false
    kwriteconfig6 --file konsolerc --group TabBar --key TabBarVisibility ShowTabBarWhenNeeded
  else
    warn "kwriteconfig6 missing; writing konsolerc directly."
    cat > "$HOME/.config/konsolerc" <<EOF
[Desktop Entry]
DefaultProfile=${KONSOLE_PROFILE}.profile

[KonsoleWindow]
ShowMenuBarByDefault=false

[TabBar]
TabBarVisibility=ShowTabBarWhenNeeded
EOF
  fi
  ok "Konsole '${KONSOLE_PROFILE}' profile ready (Mocha, ${KONSOLE_OPACITY} opacity, blur on)."
}

# ---------------------------------------------------------------------------
# 6. Apply the global theme. plasma-apply-* only works inside a live Plasma
#    session, so apply now if we're in Plasma, otherwise hand back the commands.
# ---------------------------------------------------------------------------
apply_global_theme() {
  local laf
  laf="$(find "$HOME/.local/share/plasma/look-and-feel" -maxdepth 1 -iname 'Catppuccin*' \
         -printf '%f\n' 2>/dev/null | head -n1 || true)"
  [[ -n "$laf" ]] || { warn "No Catppuccin look-and-feel found; skipping apply."; return; }

  if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] && command -v plasma-apply-lookandfeel >/dev/null; then
    log "Applying global theme '$laf'…"
    plasma-apply-lookandfeel --apply "$laf" || warn "Apply failed; set it in System Settings → Global Theme."
    ok "Global theme applied."
  else
    warn "Not in a Plasma session yet — apply after first login with:"
    printf '    plasma-apply-lookandfeel --apply %s\n' "$laf"
  fi
}

# ---------------------------------------------------------------------------
# 7. NVIDIA Wayland advisory (printed, never auto-applied)
# ---------------------------------------------------------------------------
nvidia_notice() {
  if lspci 2>/dev/null | grep -qi 'vga.*nvidia'; then
    warn "NVIDIA GPU detected. For a clean Plasma Wayland session, confirm KMS:"
    echo  "    - 'nvidia_drm.modeset=1' should be set (kernel param or modprobe.d)."
    echo  "    - Blackwell (RTX 50xx) needs the nvidia-open driver (560+/570+ series)."
    echo  "    Verify with: cat /sys/module/nvidia_drm/parameters/modeset  (expect: Y)"
  fi
}

# ---------------------------------------------------------------------------
main() {
  preflight
  install_packages
  enable_sddm
  fix_wayland_apps
  install_catppuccin_global
  configure_konsole
  apply_global_theme
  nvidia_notice
  echo
  ok "Done. Log out, pick 'Plasma (Wayland)' at the SDDM session selector, log in."
  echo "   First Plasma login is when the Wayland env + Electron fixes take effect."
}
main "$@"