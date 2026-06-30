#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║         KEVIN'S CACHY OS — ELITE DEVELOPER ENVIRONMENT                     ║
# ║         CachyOS-Optimized · NVIDIA RTX 5060 · Catppuccin Mocha             ║
# ║         .NET / Next.js / Python · Kitty · ZSH · GNOME                      ║
# ║         Version: 1.0.0                                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Usage:
#   chmod +x KevinsCachyOSSetup.sh
#   ./KevinsCachyOSSetup.sh             # full install
#   ./KevinsCachyOSSetup.sh --dry-run   # preview without changes
#   ./KevinsCachyOSSetup.sh --validate  # check install status only
#
# Run as your REGULAR USER (NOT root). sudo will be invoked where needed.
# CachyOS ships with paru as the AUR helper; this script uses paru natively
# and falls back to building yay if paru is somehow absent.
# ──────────────────────────────────────────────────────────────────────────────

set -uo pipefail   # -e removed: we collect errors and continue
IFS=$'\n\t'

# ── Catppuccin Mocha ANSI Palette ────────────────────────────────────────────
MAUVE='\033[38;2;203;166;247m'
TEAL='\033[38;2;148;226;213m'
GREEN='\033[38;2;166;227;161m'
YELLOW='\033[38;2;249;226;175m'
PEACH='\033[38;2;250;179;135m'
RED='\033[38;2;243;139;168m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Globals ───────────────────────────────────────────────────────────────────
SCRIPT_VERSION="2.0.0"
LOGFILE="${HOME}/.local/share/kevins-cachyos-setup.log"
DRY_RUN="${DRY_RUN:-false}"
WITH_NOCTALIA="${WITH_NOCTALIA:-false}"   # opt-in: install Hyprland + Noctalia shell
REBOOT_REQUIRED=false
AUR_HELPER=""   # resolved in preflight: paru (CachyOS default) or yay
ERRORS=()       # collects non-fatal errors to display at end

# ── Logging helpers ───────────────────────────────────────────────────────────
banner() {
    echo ""
    echo -e "${MAUVE}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    printf "${MAUVE}${BOLD}║  %-60s║${NC}\n" "$*"
    echo -e "${MAUVE}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "[$(date '+%H:%M:%S')] === $* ===" >> "$LOGFILE" 2>/dev/null || true
}

step()  { echo -e "${GREEN}${BOLD}  ➜  $1${NC}"; echo "[$(date '+%H:%M:%S')] STEP: $1" >> "$LOGFILE" 2>/dev/null || true; }
info()  { echo -e "${TEAL}     $1${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠  $1${NC}"; echo "[$(date '+%H:%M:%S')] WARN: $1" >> "$LOGFILE" 2>/dev/null || true; }
ok()    { echo -e "${GREEN}  ✓  $1${NC}"; }
record_error() { local msg="[$(date '+%H:%M:%S')] ERROR in ${FUNCNAME[1]:-main}: $*"; ERRORS+=("$msg"); echo -e "${RED}  ✗  NON-FATAL: $*${NC}"; echo "$msg" >> "$LOGFILE" 2>/dev/null || true; }
fail()  { echo -e "${RED}${BOLD}  ✗  $1${NC}"; echo "[$(date '+%H:%M:%S')] FAIL: $1" >> "$LOGFILE" 2>/dev/null || true; exit 1; }

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] $*"; return 0
    fi
    echo "[$(date '+%H:%M:%S')] CMD: $*" >> "$LOGFILE" 2>/dev/null || true
    if ! "$@" 2>&1 | tee -a "$LOGFILE"; then
        record_error "Command failed: $*"
        return 1
    fi
}

pac_install() {
    if [[ "$DRY_RUN" == "true" ]]; then info "[DRY-RUN] pacman -S $*"; return 0; fi
    if ! sudo pacman -S --needed --noconfirm "$@" 2>&1 | tee -a "$LOGFILE"; then
        record_error "pacman install failed for: $*"
        return 1
    fi
}

aur_install() {
    # Uses paru (CachyOS default) or yay, whichever is available
    if [[ "$DRY_RUN" == "true" ]]; then info "[DRY-RUN] ${AUR_HELPER} -S $*"; return 0; fi
    if ! "${AUR_HELPER}" -S --needed --noconfirm "$@" 2>&1 | tee -a "$LOGFILE"; then
        record_error "${AUR_HELPER} install failed for: $*"
        return 1
    fi
}

# ── Resilient execution helpers ───────────────────────────────────────────────
# try "<human description>" <command...>
#   Runs a command. On non-zero exit it records a NON-FATAL error (added to the
#   end-of-run summary) and continues. Returns the command's exit status so
#   callers may branch on success/failure. Output is captured to the log only.
try() {
    local desc="$1"; shift
    if [[ "$DRY_RUN" == "true" ]]; then info "[DRY-RUN] ${desc}: $*"; return 0; fi
    echo "[$(date '+%H:%M:%S')] TRY: ${desc} :: $*" >> "$LOGFILE" 2>/dev/null || true
    local rc=0
    "$@" < /dev/null >> "$LOGFILE" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then
        ok "${desc}"
        return 0
    fi
    record_error "${desc} (exit ${rc})"
    return "$rc"
}

# gset <schema> <key> <value>
#   gsettings wrapper. A failure here usually means a real problem (missing
#   schema on a supported GNOME, or no D-Bus session) so it IS recorded.
gset() {
    local schema="$1" key="$2" value="$3"
    if [[ "$DRY_RUN" == "true" ]]; then info "[DRY-RUN] gsettings set ${schema} ${key} ${value}"; return 0; fi
    if gsettings set "$schema" "$key" "$value" 2>> "$LOGFILE"; then
        return 0
    fi
    record_error "gsettings set ${schema} ${key} '${value}' failed"
    return 1
}

# gset_soft <schema> <key> <value>
#   Like gset, but for keys that LEGITIMATELY may not exist yet — e.g. newer
#   GNOME-only keys, or extension schemas that only register after the next
#   login. Failures are logged but NOT added to the error summary (avoids noise).
gset_soft() {
    local schema="$1" key="$2" value="$3"
    if [[ "$DRY_RUN" == "true" ]]; then info "[DRY-RUN] gsettings set ${schema} ${key} ${value}"; return 0; fi
    gsettings set "$schema" "$key" "$value" 2>> "$LOGFILE" \
        || info "Skipped ${schema} ${key} (not available yet on this GNOME / pending relogin)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PREFLIGHT                                                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
preflight() {
    banner "PREFLIGHT CHECKS"

    [[ $EUID -eq 0 ]] && fail "Do NOT run as root. Run as your regular user — sudo is called internally."

    mkdir -p "$(dirname "$LOGFILE")"
    touch "$LOGFILE"

    step "Detecting OS..."
    if grep -qi 'cachyos' /etc/os-release 2>/dev/null; then
        ok "CachyOS detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    elif grep -qi 'arch' /etc/os-release 2>/dev/null; then
        warn "Arch-based OS detected — not CachyOS. CachyOS-specific optimizations may be unavailable."
    else
        fail "This script requires CachyOS or an Arch-based distribution."
    fi

    step "Checking kernel..."
    KERNEL=$(uname -r)
    info "Kernel: $KERNEL"
    if echo "$KERNEL" | grep -qiE 'cachyos|bore|bmq|pds|tt|hardened|zen'; then
        ok "Optimized kernel detected: $KERNEL"
    else
        warn "Standard kernel detected. Consider switching to linux-cachyos for better performance."
    fi

    step "Checking internet..."
    curl -sf --max-time 8 "https://github.com" > /dev/null || fail "No internet connection."
    ok "Internet reachable"

    step "Verifying sudo access..."
    sudo -v || fail "sudo access required."
    ok "sudo OK"

    # Keep sudo alive
    ( while true; do sudo -n true; sleep 55; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

    step "Resolving AUR helper..."
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
        ok "paru found (CachyOS native): $(paru --version | head -1)"
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        ok "yay found: $(yay --version | head -1)"
    else
        warn "No AUR helper found — will build paru from AUR (CachyOS standard)."
        AUR_HELPER="paru"
        _bootstrap_paru
    fi

    info "Log: $LOGFILE"
}

_bootstrap_paru() {
    step "Bootstrapping paru from AUR..."
    pac_install git base-devel
    if [[ "$DRY_RUN" != "true" ]]; then
        local tmpdir; tmpdir=$(mktemp -d)
        git clone --depth=1 -q "https://aur.archlinux.org/paru-bin.git" "$tmpdir"
        ( cd "$tmpdir" && makepkg -si --noconfirm )
        rm -rf "$tmpdir"
    fi
    ok "paru installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 1 — SYSTEM UPDATE & BASE PACKAGES                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_base_packages() {
    banner "SECTION 1 · SYSTEM UPDATE & BASE PACKAGES"

    step "Full system upgrade (CachyOS repos + AUR)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        # CachyOS uses its own optimized repo mirrors; standard pacman -Syu applies
        sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOGFILE"
    else
        info "[DRY-RUN] sudo pacman -Syu --noconfirm"
    fi
    ok "System updated"

    step "Installing base development & utility packages..."
    pac_install \
        base-devel \
        git \
        curl \
        wget \
        unzip \
        zip \
        tar \
        xz \
        jq \
        fzf \
        fontconfig \
        tree \
        htop \
        btop \
        ripgrep \
        fd \
        bat \
        openssh \
        man-db \
        xdg-utils \
        python \
        python-pip \
        python-pipx \
        vim \
        neovim \
        zsh \
        kitty \
        fastfetch \
        cowsay \
        fortune-mod \
        gcc \
        make \
        ripgrep \
        fd \
        ctags \
        lsd \
        starship \
        papirus-icon-theme
    ok "Base packages installed"

    step "Installing CachyOS-specific enhancements..."
    # CachyOS provides cachyos-hello, cachyos-settings, and optimised package
    # builds — ensure the helper meta-packages are present
    pac_install cachyos-hello || warn "cachyos-hello not found — skipping (normal on minimal installs)"
    ok "CachyOS enhancements applied"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 2 — NVIDIA RTX 5060 DRIVERS                                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
setup_nvidia() {
    banner "SECTION 2 · NVIDIA RTX 5060 DRIVERS"

    # CachyOS ships nvidia-open-dkms pre-patched against its optimized kernels.
    # RTX 5060 (Blackwell / GB206) requires the open-source nvidia-open variant
    # (driver series 570+).  CachyOS also ships nvidia-utils-tkg which includes
    # additional Wayland/Vulkan fixes.
    #
    # Strategy:
    #   1. Remove any conflicting closed / open driver mix
    #   2. Install nvidia-open-dkms (matches linux-cachyos)
    #   3. Install Wayland/Vulkan support packages
    #   4. Enable DRM modesetting (recommended for Wayland sessions, incl. GNOME)
    #   5. Rebuild initramfs

    step "Removing any conflicting NVIDIA packages..."
    # Pre-built kernel-specific nvidia-open packages (linux-cachyos-*-nvidia-open)
    # conflict with nvidia-open-dkms, which builds its own DKMS module for all kernels.
    # We dynamically discover any installed linux-cachyos-*-nvidia-open packages in
    # addition to the standard closed-driver packages.
    mapfile -t CONFLICT_PKGS < <(pacman -Qq 2>/dev/null | grep -E '^(nvidia$|nvidia-dkms$|linux-cachyos-.*nvidia-open$)' || true)
    if [[ ${#CONFLICT_PKGS[@]} -gt 0 ]]; then
        for pkg in "${CONFLICT_PKGS[@]}"; do
            warn "Removing conflicting package: $pkg"
            if [[ "$DRY_RUN" != "true" ]]; then
                if ! sudo pacman -Rns --noconfirm --nodeps "$pkg" 2>&1 | tee -a "$LOGFILE"; then
                    record_error "Failed to remove conflicting package: $pkg"
                fi
            fi
        done
    else
        info "No conflicting NVIDIA packages found"
    fi

    step "Installing nvidia-open-dkms (RTX 5060 / Blackwell)..."
    pac_install \
        nvidia-open-dkms \
        nvidia-utils \
        lib32-nvidia-utils \
        nvidia-settings \
        libvdpau \
        libva-nvidia-driver \
        vulkan-icd-loader \
        lib32-vulkan-icd-loader \
        opencl-nvidia

    step "Enabling NVIDIA DRM modesetting..."
    local modprobe_conf="/etc/modprobe.d/nvidia-options.conf"
    if [[ "$DRY_RUN" != "true" ]]; then
        echo 'options nvidia-drm modeset=1 fbdev=1' | sudo tee "$modprobe_conf" > /dev/null
        # Rebuild initcpio only for CachyOS kernels — the vanilla linux kernel
        # won't have NVIDIA DKMS modules and will emit harmless but alarming errors.
        if command -v mkinitcpio &>/dev/null; then
            local preset
            for preset in /etc/mkinitcpio.d/linux-cachyos*.preset; do
                [[ -f "$preset" ]] || continue
                local kname; kname=$(basename "$preset" .preset)
                info "Rebuilding initcpio for $kname..."
                if ! sudo mkinitcpio -p "$kname" 2>&1 | tee -a "$LOGFILE"; then
                    record_error "mkinitcpio failed for $kname — non-fatal, NVIDIA DKMS may still work after reboot"
                fi
            done
        fi
    else
        info "[DRY-RUN] write $modprobe_conf and rebuild initramfs"
    fi

    step "Blacklisting nouveau..."
    if [[ "$DRY_RUN" != "true" ]]; then
        echo 'blacklist nouveau' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
    fi

    REBOOT_REQUIRED=true
    ok "NVIDIA RTX 5060 driver installation complete — REBOOT REQUIRED"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 3 — JETBRAINS MONO NERD FONT                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
setup_fonts() {
    banner "SECTION 3 · FONTS (JETBRAINS MONO NERD + UI + EMOJI)"

    step "Installing JetBrainsMono Nerd Font + full UI/emoji coverage..."
    # JetBrainsMono Nerd = terminal/code glyphs; Cantarell = GNOME UI font;
    # Noto + emoji + symbols round out web/CJK/emoji so nothing renders as tofu.
    pac_install \
        ttf-jetbrains-mono-nerd \
        ttf-jetbrains-mono \
        cantarell-fonts \
        noto-fonts \
        noto-fonts-emoji \
        ttf-nerd-fonts-symbols \
        ttf-nerd-fonts-symbols-common

    step "Rebuilding font cache..."
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo fc-cache -fv > /dev/null 2>&1 || record_error "fc-cache rebuild failed"
    fi
    ok "Font cache rebuilt"

    step "Setting GNOME monospace font..."
    gset org.gnome.desktop.interface monospace-font-name "JetBrainsMono Nerd Font Mono 12"
    ok "JetBrainsMono Nerd Font installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 4 — CATPPUCCIN GNOME — FULL DESKTOP RICE                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# End-to-end Catppuccin Mocha (Mauve/"purple" accent) across the WHOLE stack:
#   • GTK3 + GTK4/libadwaita (modern apps) + GTK2 (legacy apps)
#   • GNOME Shell theme (top bar / overview / popups) via User Themes
#   • Catppuccin Mocha Mauve CURSORS
#   • Curated, version-matched Shell extensions (Blur my Shell, Dash to Dock …)
#   • Qt apps via Kvantum so they match GTK apps
#   • Flatpak apps inherit the theme
#   • Papirus (violet folders) icons, fonts, generated wallpaper, macOS buttons
#
# IMPORTANT — how this theme actually installs (this is what was wrong before):
#   The Fausto-Korpsvart repo does NOT ship prebuilt theme folders. It ships an
#   install.sh that GENERATES the theme from SCSS (needs `sassc`). Its CLI has
#   differed from the README across versions, so we read the installer's OWN
#   --help and pass only flags it supports. Confirmed on the current build:
#     -a/--accent mauve | -m/--mode dark | -s/--size | -l | --tweaks macos
#   ("-t" and "-c" from older docs are NOT valid here.) We then DISCOVER the
#   generated folder name and use it everywhere, so the gsettings theme name can
#   never drift from what was actually installed.
#
# Caveats (true, not flattery):
#   • GTK4/libadwaita theming is an UNSUPPORTED upstream hack — an app update can
#     break it. It is the brittle part of any GNOME rice.
#   • Extensions + the Shell theme only LOAD after a logout/login (Wayland can't
#     hot-restart the Shell). Re-run `--validate` after relogin to confirm.
#   • GDM/login-screen theming is intentionally omitted: a bad edit can lock you
#     out of the greeter. Ask me for a separate, reversible GDM script if wanted.
# ──────────────────────────────────────────────────────────────────────────────
setup_gnome_theme() {
    banner "SECTION 4 · CATPPUCCIN GNOME — FULL DESKTOP RICE"

    local THEME_DIR="$HOME/.themes"
    local ICON_DIR="$HOME/.local/share/icons"
    # Discovered at runtime from what the installer actually produced:
    local THEME_NAME=""          # e.g. Catppuccin-Purple-Dark
    local CURSOR_NAME=""         # e.g. catppuccin-mocha-mauve-cursors
    local ACTIVE_CURSOR="Bibata-Modern-Classic"   # safe fallback
    mkdir -p "$THEME_DIR" "$ICON_DIR"

    # ── 4.1 — Tooling: theme build deps, GNOME utilities, Qt bridge ────────────
    step "Installing theme build deps, GNOME tooling & Qt bridge..."
    # sassc is REQUIRED to compile the theme; murrine + gnome-themes-extra render it.
    pac_install \
        sassc \
        gtk-engine-murrine \
        gnome-themes-extra \
        gnome-tweaks \
        gnome-shell-extensions \
        dconf-editor \
        papirus-icon-theme \
        papirus-folders \
        qt5ct \
        qt6ct \
        kvantum \
        kvantum-qt5 \
        imagemagick

    step "Installing GNOME Extension Manager + scriptable CLI..."
    aur_install gnome-extension-manager
    if [[ "$DRY_RUN" != "true" ]] && ! command -v gext &>/dev/null; then
        try "Install gnome-extensions-cli (gext) via pipx" pipx install gnome-extensions-cli
        export PATH="$HOME/.local/bin:$PATH"
    fi

    # ── 4.2 — Generate & install the Catppuccin GTK + Shell theme ──────────────
    step "Cloning Catppuccin GTK/Shell theme (Fausto-Korpsvart)..."
    local THEME_REPO="$HOME/.cache/catppuccin-gtk-src"
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "$THEME_REPO"
        if try "Clone Catppuccin-GTK-Theme" git clone --depth=1 \
                "https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git" "$THEME_REPO"; then

            # The installer lives at the repo root OR in themes/ depending on revision.
            local INSTALLER=""
            if   [[ -f "$THEME_REPO/install.sh" ]];        then INSTALLER="$THEME_REPO/install.sh"
            elif [[ -f "$THEME_REPO/themes/install.sh" ]]; then INSTALLER="$THEME_REPO/themes/install.sh"
            fi

            if [[ -n "$INSTALLER" ]]; then
                step "Running theme installer (Mocha · mauve accent · dark · macOS buttons)..."
                # This installer's CLI has differed from its README across versions,
                # so we read its OWN --help and pass only the flags it actually
                # supports. Confirmed flags on the current build:
                #   -a/--accent mauve | -m/--mode dark | -s/--size | -l | --tweaks macos
                local HELP; HELP="$(bash "$INSTALLER" --help 2>&1 || true)"
                local -a IARGS=( -d "$THEME_DIR" -n Catppuccin )
                grep -qi -- '--accent'     <<<"$HELP" && IARGS+=( -a mauve )
                if   grep -qi -- '--mode'  <<<"$HELP"; then IARGS+=( -m dark )
                elif grep -qi -- '--color' <<<"$HELP"; then IARGS+=( -c dark )
                fi
                grep -qi -- '--size'       <<<"$HELP" && IARGS+=( -s standard )
                grep -qi -- '--libadwaita' <<<"$HELP" && IARGS+=( -l )
                grep -qi    'macos'        <<<"$HELP" && IARGS+=( --tweaks macos )
                info "Installer args: ${IARGS[*]}"
                # This installer is INTERACTIVE (asks "apply? / which variant?") and
                # its auto-apply step is XFCE-oriented (xfconf), which FAILS on GNOME
                # with a non-zero exit. So we (a) feed it /dev/null so it can't block,
                # and (b) judge success by whether the theme folder appears below —
                # NOT by its exit code. We apply the theme ourselves via gsettings.
                bash "$INSTALLER" "${IARGS[@]}" < /dev/null >> "$LOGFILE" 2>&1
                local irc=$?
                [[ $irc -ne 0 ]] && info "Installer exit ${irc} (its XFCE/xfconf auto-apply fails on GNOME — harmless; we apply via gsettings)"
            else
                record_error "Theme installer not found in repo — upstream layout changed"
            fi
        fi

        # ── Discover the folder the installer actually created ────────────────
        # Accent may or may not appear in the folder name depending on version,
        # so prefer a mauve-named dark folder, then fall back to any dark folder.
        THEME_NAME=$(find "$THEME_DIR" -maxdepth 1 -mindepth 1 -type d -iname '*mauve*dark*' -printf '%f\n' 2>/dev/null | sort | head -1)
        [[ -z "$THEME_NAME" ]] && THEME_NAME=$(find "$THEME_DIR" -maxdepth 1 -mindepth 1 -type d -iname '*dark*' -printf '%f\n' 2>/dev/null | sort | head -1)
        if [[ -n "$THEME_NAME" ]]; then
            ok "Installed GTK/Shell theme: ${THEME_NAME}"
            # Belt-and-suspenders: link the discovered dark GTK4 theme for libadwaita
            # (in case --libadwaita linked a different variant when several exist).
            local _g4="$THEME_DIR/$THEME_NAME/gtk-4.0" _d4="$HOME/.config/gtk-4.0"
            if [[ -d "$_g4" ]]; then
                mkdir -p "$_d4"
                local _f
                for _f in gtk.css gtk-dark.css; do
                    [[ -f "$_g4/$_f" ]] && ln -sf "$_g4/$_f" "$_d4/$_f"
                done
                [[ -d "$_g4/assets" ]] && ln -sfn "$_g4/assets" "$_d4/assets"
            fi
        else
            record_error "No Catppuccin theme folder found under $THEME_DIR — theme NOT installed (is 'sassc' present?)"
        fi
    fi

    # ── 4.3 — Catppuccin Mocha Mauve cursors ───────────────────────────────────
    step "Installing Catppuccin Mocha Mauve cursors..."
    aur_install catppuccin-cursors-mocha
    if [[ "$DRY_RUN" != "true" ]]; then
        CURSOR_NAME=$(find /usr/share/icons "$ICON_DIR" "$HOME/.icons" -maxdepth 1 -mindepth 1 -type d \
            -iname '*mocha*mauve*cursor*' -printf '%f\n' 2>/dev/null | head -1)
        [[ -z "$CURSOR_NAME" ]] && CURSOR_NAME=$(find /usr/share/icons "$ICON_DIR" "$HOME/.icons" -maxdepth 1 -mindepth 1 -type d \
            -iname 'catppuccin*mocha*mauve*' -printf '%f\n' 2>/dev/null | head -1)
        if [[ -n "$CURSOR_NAME" ]]; then
            ACTIVE_CURSOR="$CURSOR_NAME"
            ok "Catppuccin cursor: ${ACTIVE_CURSOR}"
        else
            record_error "Catppuccin cursor not found — falling back to Bibata (still installed)"
            aur_install bibata-cursor-theme
        fi
    fi

    # ── 4.4 — Papirus violet folders ────────────────────────────────────────────
    step "Setting Papirus violet folders..."
    try "Set Papirus folder colour to violet" papirus-folders -C violet --theme Papirus-Dark

    # ── 4.5 — GTK2 + GTK3 config (legacy + apps reading settings.ini directly) ──
    step "Writing GTK2/GTK3 config (using discovered theme name)..."
    if [[ "$DRY_RUN" != "true" && -n "$THEME_NAME" ]]; then
        cat > "$HOME/.gtkrc-2.0" << GTK2EOF
gtk-theme-name="${THEME_NAME}"
gtk-icon-theme-name="Papirus-Dark"
gtk-cursor-theme-name="${ACTIVE_CURSOR}"
gtk-font-name="Cantarell 11"
GTK2EOF
        mkdir -p "$HOME/.config/gtk-3.0"
        cat > "$HOME/.config/gtk-3.0/settings.ini" << GTK3EOF
[Settings]
gtk-theme-name=${THEME_NAME}
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=${ACTIVE_CURSOR}
gtk-font-name=Cantarell 11
gtk-application-prefer-dark-theme=true
GTK3EOF
    fi

    # ── 4.6 — Qt apps via Kvantum (match GTK) ──────────────────────────────────
    step "Theming Qt apps with Catppuccin Kvantum..."
    if [[ "$DRY_RUN" != "true" ]]; then
        local KV_REPO="$HOME/.cache/catppuccin-kvantum-src"
        rm -rf "$KV_REPO"
        if try "Clone Catppuccin Kvantum" git clone --depth=1 \
                "https://github.com/catppuccin/Kvantum.git" "$KV_REPO"; then
            mkdir -p "$HOME/.config/Kvantum" "$HOME/.config/qt5ct" "$HOME/.config/qt6ct"
            [[ -d "$KV_REPO/themes" ]] && cp -rf "$KV_REPO/themes/"* "$HOME/.config/Kvantum/" 2>>"$LOGFILE" \
                || record_error "Copying Kvantum themes failed (upstream layout?)"
            printf '[General]\ntheme=Catppuccin-Mocha-Mauve\n' > "$HOME/.config/Kvantum/kvantum.kvconfig"
            printf '[Appearance]\nstyle=kvantum-dark\nicon_theme=Papirus-Dark\n' > "$HOME/.config/qt5ct/qt5ct.conf"
            printf '[Appearance]\nstyle=kvantum-dark\nicon_theme=Papirus-Dark\n' > "$HOME/.config/qt6ct/qt6ct.conf"
            mkdir -p "$HOME/.config/environment.d"
            printf 'QT_QPA_PLATFORMTHEME=qt6ct\n' > "$HOME/.config/environment.d/qt-theme.conf"
            ok "Qt apps routed through Kvantum (Catppuccin-Mocha-Mauve)"
        fi
    fi

    # ── 4.7 — Flatpak apps inherit the theme (only if flatpak present) ─────────
    if command -v flatpak &>/dev/null && [[ -n "$THEME_NAME" ]]; then
        step "Granting Flatpak apps access to the Catppuccin theme..."
        try "Flatpak: expose ~/.themes"  flatpak override --user --filesystem="$HOME/.themes:ro"
        try "Flatpak: expose icon dirs"  flatpak override --user --filesystem="$ICON_DIR:ro"
        try "Flatpak: set GTK_THEME env" flatpak override --user --env=GTK_THEME="$THEME_NAME"
    else
        info "Flatpak not installed (or theme missing) — skipping Flatpak overrides"
    fi

    # ── 4.8 — Generate a tasteful Catppuccin wallpaper (no network dependency) ─
    step "Generating a Catppuccin Mocha wallpaper..."
    if [[ "$DRY_RUN" != "true" ]]; then
        local WALL_DIR="$HOME/Pictures/Wallpapers"
        local WALL="$WALL_DIR/catppuccin-mocha-glow.png"
        mkdir -p "$WALL_DIR"
        if command -v magick &>/dev/null; then
            try "Render wallpaper (ImageMagick)" \
                magick -size 3840x2160 radial-gradient:'#313244'-'#11111b' "$WALL"
        elif command -v convert &>/dev/null; then
            try "Render wallpaper (ImageMagick legacy)" \
                convert -size 3840x2160 radial-gradient:'#313244'-'#11111b' "$WALL"
        else
            record_error "ImageMagick not available — wallpaper not generated"
        fi
        if [[ -f "$WALL" ]]; then
            gset org.gnome.desktop.background picture-uri       "file://$WALL"
            gset org.gnome.desktop.background picture-uri-dark  "file://$WALL"
            gset org.gnome.desktop.background picture-options   "zoom"
            gset org.gnome.desktop.screensaver picture-uri      "file://$WALL"
        fi
    fi

    # ── 4.9 — Apply theme + dconf polish via gsettings ─────────────────────────
    step "Applying theme & dconf polish via gsettings..."
    if [[ -n "$THEME_NAME" ]]; then
        gset org.gnome.desktop.interface gtk-theme        "$THEME_NAME"
        gset org.gnome.desktop.wm.preferences theme       "$THEME_NAME"
    else
        record_error "Skipping gtk-theme apply — no theme was installed to point at"
    fi
    gset org.gnome.desktop.interface icon-theme           "Papirus-Dark"
    gset org.gnome.desktop.interface cursor-theme         "$ACTIVE_CURSOR"
    gset org.gnome.desktop.interface cursor-size          24
    gset org.gnome.desktop.interface color-scheme         "prefer-dark"
    gset org.gnome.desktop.interface font-name            "Cantarell 11"
    gset org.gnome.desktop.interface document-font-name   "Cantarell 11"
    gset org.gnome.desktop.interface monospace-font-name  "JetBrainsMono Nerd Font Mono 12"
    gset org.gnome.desktop.interface font-antialiasing    "rgba"
    gset org.gnome.desktop.interface font-hinting         "slight"
    gset org.gnome.desktop.interface clock-show-weekday   true
    gset org.gnome.desktop.interface show-battery-percentage true
    gset org.gnome.desktop.interface enable-animations    true
    # Window buttons on the RIGHT; --tweaks macos (in 4.2) gives the round
    # red/yellow/green styling, which is keyed by button function not position.
    gset org.gnome.desktop.wm.preferences button-layout   "appmenu:minimize,maximize,close"
    # Newer-GNOME-only keys (soft: may legitimately be absent) ──────────────────
    gset_soft org.gnome.desktop.interface accent-color    "purple"   # GNOME 47+, mauve-family
    gset_soft org.gnome.mutter center-new-windows         true

    # ── 4.10 — GNOME Shell extensions (load after relogin) ─────────────────────
    step "Installing & enabling GNOME Shell extensions..."
    local USER_THEME_UUID="user-theme@gnome-shell-extensions.gcampax.github.com"
    local EXTRA_EXT=(
        "blur-my-shell@aunetx"
        "dash-to-dock@micxgx.gmail.com"
        "just-perfection-desktop@just-perfection"
        "caffeine@patapon.info"
        "Vitals@CoreCoding.com"
        "appindicatorsupport@rgcjonas.gmail.com"
    )
    if [[ "$DRY_RUN" != "true" ]]; then
        if command -v gext &>/dev/null; then
            local uuid
            for uuid in "${EXTRA_EXT[@]}"; do
                try "Install extension ${uuid}" gext install "${uuid}"
            done
        else
            record_error "gext unavailable — install extensions manually via Extension Manager"
        fi
        if command -v gnome-extensions &>/dev/null; then
            local uuid
            for uuid in "$USER_THEME_UUID" "${EXTRA_EXT[@]}"; do
                try "Enable extension ${uuid}" gnome-extensions enable "${uuid}"
            done
        else
            record_error "gnome-extensions CLI unavailable — enable extensions after relogin"
        fi
    fi

    # ── 4.11 — Shell theme + extension dconf (soft: schemas appear post-login) ─
    step "Pointing the GNOME Shell theme at Catppuccin & tuning extensions..."
    if [[ -n "$THEME_NAME" ]]; then
        gset_soft org.gnome.shell.extensions.user-theme name "$THEME_NAME"
    fi
    # Dash to Dock — Catppuccin crust dock, transparent, bottom
    gset_soft org.gnome.shell.extensions.dash-to-dock dock-position            "BOTTOM"
    gset_soft org.gnome.shell.extensions.dash-to-dock transparency-mode        "FIXED"
    gset_soft org.gnome.shell.extensions.dash-to-dock background-opacity        0.80
    gset_soft org.gnome.shell.extensions.dash-to-dock custom-background-color   true
    gset_soft org.gnome.shell.extensions.dash-to-dock background-color          "#11111b"
    gset_soft org.gnome.shell.extensions.dash-to-dock apply-custom-theme        false
    # Blur my Shell — stronger overview/panel blur
    gset_soft org.gnome.shell.extensions.blur-my-shell brightness               0.75
    gset_soft org.gnome.shell.extensions.blur-my-shell sigma                    30

    ok "Catppuccin GNOME rice applied — log out & back in for Shell theme + extensions"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 5 — .NET SDK 10 & RUNTIMES                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_dotnet() {
    banner "SECTION 5 · .NET SDK 10 & RUNTIMES"

    # CachyOS inherits Arch's official extra repo — dotnet-sdk is .NET 10
    step "Installing .NET 10 SDK + ASP.NET runtimes..."
    pac_install \
        dotnet-sdk \
        aspnet-runtime \
        aspnet-targeting-pack

    step "Verifying .NET installation..."
    if [[ "$DRY_RUN" != "true" ]]; then
        dotnet --version && ok "dotnet $(dotnet --version) ready" \
            || warn ".NET version check failed — may need a new shell session"
    fi

    step "Installing dotnet global tools..."
    if [[ "$DRY_RUN" != "true" ]]; then
        dotnet tool install -g dotnet-script 2>/dev/null || true
        dotnet tool install -g dotnet-format 2>/dev/null || true
    fi

    ok ".NET 10 installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 6 — NODE.JS & NPM                                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_nodejs() {
    banner "SECTION 6 · NODE.JS & NPM"

    step "Installing Node.js LTS + NPM..."
    pac_install nodejs npm
    ok "Node.js: $(node --version 2>/dev/null || echo 'available after re-login')"
    ok "NPM:     $(npm --version 2>/dev/null || echo 'available after re-login')"

    step "Installing global NPM packages..."
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo npm install -g \
            typescript \
            ts-node \
            eslint \
            prettier \
            next \
            create-next-app \
            @biomejs/biome
    fi
    ok "Global NPM packages installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 7 — PYTHON DEV STACK                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_python() {
    banner "SECTION 7 · PYTHON DEV STACK"

    pac_install \
        python \
        python-pip \
        python-pipx \
        python-virtualenv \
        python-black \
        python-pylsp \
        flake8 \
        mypy

    ok "Python stack installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 8 — KITTY TERMINAL CONFIGURATION                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_kitty() {
    banner "SECTION 8 · KITTY TERMINAL (CATPPUCCIN MOCHA)"

    local KITTY_DIR="$HOME/.config/kitty"
    mkdir -p "$KITTY_DIR"

    step "Writing kitty.conf..."
    cat > "$KITTY_DIR/kitty.conf" << 'KITTYEOF'
# ╔══════════════════════════════════════════════════════╗
# ║  Kevin's Kitty — Catppuccin Mocha · CachyOS          ║
# ╚══════════════════════════════════════════════════════╝

# ── Font ─────────────────────────────────────────────
font_family      JetBrainsMono Nerd Font Mono
bold_font        JetBrainsMono Nerd Font Mono Bold
italic_font      JetBrainsMono Nerd Font Mono Italic
bold_italic_font JetBrainsMono Nerd Font Mono Bold Italic
font_size        13.0
disable_ligatures never

# ── Catppuccin Mocha Palette ─────────────────────────
foreground              #CDD6F4
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #F5E0DC
cursor                  #F5E0DC
cursor_text_color       #1E1E2E
cursor_shape            beam
cursor_beam_thickness   1.5
cursor_blink_interval   0.5
url_color               #89B4FA
url_style               curly

# Tabs
active_tab_foreground   #11111B
active_tab_background   #CBA6F7
inactive_tab_foreground #CDD6F4
inactive_tab_background #181825
tab_bar_style           powerline
tab_powerline_style     slanted
tab_bar_min_tabs        1

# 16 terminal colours (Catppuccin Mocha)
color0   #45475A   color8   #585B70
color1   #F38BA8   color9   #F38BA8
color2   #A6E3A1   color10  #A6E3A1
color3   #F9E2AF   color11  #F9E2AF
color4   #89B4FA   color12  #89B4FA
color5   #F5C2E7   color13  #F5C2E7
color6   #94E2D5   color14  #94E2D5
color7   #BAC2DE   color15  #A6ADC8

# ── Window ───────────────────────────────────────────
background_opacity       0.95
dynamic_background_opacity yes
window_padding_width     10
remember_window_size     yes
initial_window_width     220c
initial_window_height    50c

# ── Misc ─────────────────────────────────────────────
enable_audio_bell        no
shell                    /usr/bin/zsh
editor                   vim
copy_on_select           yes
repaint_delay            10
input_delay              3
sync_to_monitor          yes

# ── Keyboard ─────────────────────────────────────────
map ctrl+shift+c         copy_to_clipboard
map ctrl+shift+v         paste_from_clipboard
map ctrl+shift+t         new_tab_with_cwd
map ctrl+shift+w         close_tab
map ctrl+shift+right     next_tab
map ctrl+shift+left      previous_tab
map ctrl+shift+enter     new_window_with_cwd
map ctrl+equal           increase_font_size
map ctrl+minus           decrease_font_size
map ctrl+0               reset_font_size
map ctrl+shift+r         load_config_file
KITTYEOF
    ok "kitty.conf written"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 9 — ZSH AS DEFAULT SHELL                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_zsh_shell() {
    banner "SECTION 9 · ZSH AS DEFAULT SHELL"

    local ZSH_PATH; ZSH_PATH="$(which zsh)"
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_PATH" ]]; then
        step "Setting zsh as default shell for $USER..."
        if [[ "$DRY_RUN" != "true" ]]; then
            sudo chsh -s "$ZSH_PATH" "$USER"
        fi
        ok "Default shell → $ZSH_PATH"
    else
        ok "zsh is already the default shell"
    fi
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 10 — STARSHIP PROMPT                                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_starship() {
    banner "SECTION 10 · STARSHIP PROMPT (CATPPUCCIN MOCHA POWERLINE)"

    # starship was installed via pacman in Section 1
    command -v starship &>/dev/null && ok "Starship: $(starship --version)"

    step "Writing ~/.config/starship.toml..."
    mkdir -p "$HOME/.config"
    cat > "$HOME/.config/starship.toml" << 'STARSHIPEOF'
# ╔══════════════════════════════════════════════════════╗
# ║  Starship — Catppuccin Mocha Powerline · CachyOS     ║
# ╚══════════════════════════════════════════════════════╝
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[](mauve)\
$os\
$username\
[](fg:mauve bg:blue)\
$directory\
[](fg:blue bg:teal)\
$git_branch\
$git_status\
[](fg:teal bg:green)\
$dotnet\
$nodejs\
$python\
$c\
[](fg:green bg:surface1)\
$cmd_duration\
[ ](fg:surface1)\
$line_break\
$character"""

palette         = 'catppuccin_mocha'
add_newline     = true
command_timeout = 5000

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo  = "#f2cdcd"
pink      = "#f5c2e7"
mauve     = "#cba6f7"
red       = "#f38ba8"
maroon    = "#eba0ac"
peach     = "#fab387"
yellow    = "#f9e2af"
green     = "#a6e3a1"
teal      = "#94e2d5"
sky       = "#89dceb"
sapphire  = "#74c7ec"
blue      = "#89b4fa"
lavender  = "#b4befe"
text      = "#cdd6f4"
subtext1  = "#bac2de"
subtext0  = "#a6adc8"
overlay2  = "#9399b2"
overlay1  = "#7f849c"
overlay0  = "#6c7086"
surface2  = "#585b70"
surface1  = "#45475a"
surface0  = "#313244"
base      = "#1e1e2e"
mantle    = "#181825"
crust     = "#11111b"

[os]
disabled = false
style    = "bg:mauve fg:crust bold"

[os.symbols]
CachyOS    = " "
Arch       = "󰣇 "
EndeavourOS = " "
Linux      = "󰌽 "

[username]
show_always = true
style_user  = "bg:mauve fg:crust"
style_root  = "bg:red fg:crust bold"
format      = '[ $user ]($style)'

[directory]
style              = "bg:blue fg:crust bold"
format             = "[ 󰉋 $path ]($style)"
truncation_length  = 4
truncate_to_repo   = true
read_only          = " 󰌾"
read_only_style    = "bg:blue fg:red"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music"     = "󰝚 "
"Pictures"  = " "
"Projects"  = "󰲋 "
"dev"       = "󰲋 "
"src"       = " "

[git_branch]
style   = "bg:teal fg:crust bold"
symbol  = " "
format  = '[ $symbol$branch ]($style)'
truncation_length = 24

[git_status]
style      = "bg:teal fg:crust"
format     = '([$all_status$ahead_behind]($style) )'
conflicted = "⚡${count}"
ahead      = "⇡${count}"
behind     = "⇣${count}"
diverged   = "⇕⇡${ahead_count}⇣${behind_count}"
untracked  = "?${count}"
stashed    = "󰏗 "
modified   = "!${count}"
staged     = "+${count}"
renamed    = "»${count}"
deleted    = "✘${count}"

[dotnet]
style          = "bg:green fg:crust bold"
symbol         = "󰪮 "
format         = '[ $symbol($version )(🎯$tfm) ]($style)'
detect_files   = ["global.json","project.json","*.csproj","*.fsproj","*.sln","*.slnx","*.razor","*.cs"]
detect_folders = [".dotnet"]
heuristic      = true

[nodejs]
style          = "bg:green fg:crust bold"
symbol         = " "
format         = '[ $symbol($version )]($style)'
detect_files   = ["package.json",".node-version",".nvmrc"]
detect_folders = ["node_modules"]

[python]
style             = "bg:green fg:crust bold"
symbol            = " "
format            = '[ $symbol($version )(\($virtualenv\)) ]($style)'
detect_extensions = ["py"]
detect_files      = [".python-version","Pipfile","pyproject.toml","setup.py","requirements.txt"]
python_binary     = ["python","python3"]

[c]
style   = "bg:green fg:crust bold"
symbol  = " "
format  = '[ $symbol($version )]($style)'

[cmd_duration]
style    = "bg:surface1 fg:text"
format   = '[ ⏱ $duration ]($style)'
min_time = 2_000

[character]
success_symbol = '[❯](bold green)'
error_symbol   = '[❯](bold red)'
vimcmd_symbol  = '[❮](bold mauve)'

[package]
style  = "bg:surface1 fg:peach"
format = '[ 󰏗 $version ]($style)'

[docker_context]
style  = "bg:surface1 fg:blue"
format = '[ 󰡨 $context ]($style)'
STARSHIPEOF
    ok "starship.toml written"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 11 — .ZSHRC                                                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_zshrc() {
    banner "SECTION 11 · ZSH CONFIGURATION (.zshrc)"

    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d_%H%M%S)"
    step "Writing ~/.zshrc..."

    cat > "$HOME/.zshrc" << 'ZSHRCEOF'
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  .zshrc — Kevin's CachyOS Dev Shell · Catppuccin Mocha · Chuck Norris       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── PATH ─────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"
export PATH="$HOME/.dotnet/tools:$PATH"

# ── Environment ──────────────────────────────────────────────────────────────
export EDITOR="vim"
export VISUAL="vim"
export PAGER="less"
export LESS="-R"
export BAT_THEME="Catppuccin Mocha"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
# CachyOS: enable BORE/sched_ext awareness for dev tools
export MALLOC_CONF="background_thread:true,dirty_decay_ms:5000,muzzy_decay_ms:5000"

# ── NVM (optional) ───────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ]          && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

# ── History ──────────────────────────────────────────────────────────────────
HISTSIZE=100000
SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS HIST_IGNORE_SPACE
setopt SHARE_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY HIST_REDUCE_BLANKS

# ── ZSH Options ──────────────────────────────────────────────────────────────
setopt AUTO_CD CORRECT COMPLETE_ALIASES GLOBDOTS PROMPT_SUBST
setopt INTERACTIVE_COMMENTS NO_BEEP MULTIOS CDABLE_VARS
setopt PUSHD_IGNORE_DUPS AUTO_PUSHD PUSHD_SILENT

# ── Completion ───────────────────────────────────────────────────────────────
autoload -Uz compinit
compinit -d "$HOME/.zcompdump"
zstyle ':completion:*'              matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*'              menu select
zstyle ':completion:*'              list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings'     format '%F{red}-- no matches --%f'
zstyle ':completion::complete:*'    use-cache yes

# ── Key Bindings ─────────────────────────────────────────────────────────────
bindkey -e
bindkey '^[[A'    up-line-or-history
bindkey '^[[B'    down-line-or-history
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line
bindkey '^[[3~'   delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^R'      history-incremental-search-backward

# ── Aliases — File / System ──────────────────────────────────────────────────
if command -v lsd &>/dev/null; then
    alias ls='lsd --group-directories-first'
    alias ll='lsd -alh --group-directories-first'
    alias la='lsd -A --group-directories-first'
    alias lt='lsd -alh --sort=time'
    alias l='lsd -F --group-directories-first'
    alias tree='lsd --tree'
    alias ltree='lsd --tree -alh'
else
    alias ls='ls --color=auto --group-directories-first'
    alias ll='ls -alh --color=auto'
    alias la='ls -A --color=auto'
fi

alias grep='grep --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias mkdir='mkdir -pv'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias ports='ss -tlnp'
alias myip='curl -sf --max-time 5 ifconfig.me && echo'
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias reload='source ~/.zshrc && echo "zshrc reloaded"'
alias zshrc='vim ~/.zshrc'
alias vimrc='vim ~/.vimrc'
alias starshipcfg='vim ~/.config/starship.toml'
alias kittycfg='vim ~/.config/kitty/kitty.conf'
alias path='echo $PATH | tr ":" "\n"'
alias syslog='sudo journalctl -f'

if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
    alias catp='bat'
fi

# ── Aliases — Pacman / Paru (CachyOS) ────────────────────────────────────────
# CachyOS uses paru as its preferred AUR helper
alias pacs='sudo pacman -S --noconfirm --needed'
alias pacr='sudo pacman -Rns'
alias pacu='sudo pacman -Syu --noconfirm'
alias pacss='pacman -Ss'
alias pacsi='pacman -Si'
alias pacq='pacman -Q'
alias pacql='pacman -Ql'
alias pacqo='pacman -Qo'
alias pacclean='sudo pacman -Sc --noconfirm'
alias pacorphans='sudo pacman -Rns $(pacman -Qdtq) 2>/dev/null || echo "No orphans"'
alias pars='paru -S --noconfirm --needed'
alias paru='paru -Syu --noconfirm'
alias parss='paru -Ss'
alias parr='paru -Rns'
# yay aliases kept for muscle memory compatibility
alias yays='paru -S --noconfirm --needed'
alias yayu='paru -Syu --noconfirm'
alias yayss='paru -Ss'
alias mirror='sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syy'

# ── Aliases — Git ────────────────────────────────────────────────────────────
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gap='git add -p'
alias gc='git commit -m'
alias gca='git commit --amend --no-edit'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate --all'
alias gll='git log --format="%C(yellow)%h%Creset %C(blue)%an%Creset %C(green)%ar%Creset — %s"'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull'
alias gplr='git pull --rebase'
alias gs='git status -sb'
alias gst='git stash'
alias gstp='git stash pop'
alias gb='git branch'
alias gba='git branch -a'
alias gr='git remote -v'
alias grbi='git rebase -i'
alias gcl='git clone'
alias gclean='git clean -fd'

# ── Aliases — .NET ───────────────────────────────────────────────────────────
alias dn='dotnet'
alias dnr='dotnet run'
alias dnb='dotnet build'
alias dnt='dotnet test'
alias dnw='dotnet watch run'
alias dnwt='dotnet watch test'
alias dnn='dotnet new'
alias dnrp='dotnet restore'
alias dnpk='dotnet pack'
alias dnpb='dotnet publish'
alias dnls='dotnet list package'
alias dnadd='dotnet add package'
alias dnrm='dotnet remove package'
alias dnef='dotnet ef'
alias dnefmig='dotnet ef migrations add'
alias dnefdb='dotnet ef database update'
alias dnclean='dotnet clean && rm -rf bin obj'

# ── Aliases — Node / Next.js ─────────────────────────────────────────────────
alias ni='npm install'
alias nid='npm install --save-dev'
alias nig='npm install -g'
alias nrm='npm remove'
alias nr='npm run'
alias nrd='npm run dev'
alias nrb='npm run build'
alias nrs='npm run start'
alias nrt='npm run test'
alias nrl='npm run lint'
alias nls='npm list --depth=0'
alias nout='npm outdated'
alias nup='npm update'

# ── Aliases — Python ─────────────────────────────────────────────────────────
alias py='python'
alias pipu='pip install --upgrade'
alias venv='python -m venv .venv && source .venv/bin/activate && echo "✓ Venv activated"'
alias activate='source .venv/bin/activate 2>/dev/null || source venv/bin/activate 2>/dev/null || echo "No venv found"'
alias deact='deactivate'
alias pytest='python -m pytest'
alias mypy='python -m mypy'
alias black='python -m black'

# ── Functions ────────────────────────────────────────────────────────────────

mkcd() { mkdir -p "$1" && cd "$1" || return 1; echo "󰉋  Created: $(pwd)"; }

newdotnet() {
    local name="${1:-MyApp}" template="${2:-webapi}"
    dotnet new "$template" -n "$name" && cd "$name" || return 1
    git init && git add -A && git commit -m "chore: initial scaffold"
    echo "✓ .NET $template '$name' ready"
}

newnext() {
    local name="${1:-my-app}"
    npx create-next-app@latest "$name" --typescript --eslint --tailwind --app
    cd "$name" || return 1
    echo "✓ Next.js '$name' ready"
}

newpy() {
    local name="${1:-my_project}"
    mkdir -p "$name" && cd "$name" || return 1
    python -m venv .venv && source .venv/bin/activate
    echo "# Add dependencies here" > requirements.txt
    printf '#!/usr/bin/env python3\n\ndef main():\n    print("Hello, World!")\n\nif __name__ == "__main__":\n    main()\n' > main.py
    printf '.venv/\n__pycache__/\n*.pyc\n.env\n' > .gitignore
    echo "# $name" > README.md
    git init && git add -A && git commit -m "chore: initial scaffold"
    echo "✓ Python project '$name' ready"
}

extract() {
    [[ -f "$1" ]] || { echo "'$1' is not a file"; return 1; }
    case "$1" in
        *.tar.bz2) tar xjf "$1" ;; *.tar.gz)  tar xzf "$1" ;;
        *.tar.xz)  tar xJf "$1" ;; *.bz2)     bunzip2 "$1" ;;
        *.gz)      gunzip "$1"  ;; *.tar)      tar xf "$1"  ;;
        *.zip)     unzip "$1"   ;; *.7z)       7z x "$1"    ;;
        *) echo "Cannot extract '$1'" ;;
    esac
}

kp() {
    local pid; pid=$(pgrep -i "$1" | head -5)
    [[ -n "$pid" ]] && echo "Killing: $pid" && kill -9 $pid || echo "No process: $1"
}

serve() { python -m http.server "${1:-8000}"; }

gquick() { git add -A && git commit -m "${1:-wip}" && git push; }

gtree() {
    git log --graph \
        --pretty=format:'%C(yellow)%h%Creset %C(blue)%an%Creset %C(green)(%ar)%Creset %C(auto)%d%Creset %s' \
        --abbrev-commit --all
}

# ── CachyOS Performance Tweaks (Runtime) ────────────────────────────────────
# Boost interactive responsiveness; CachyOS kernel already handles the rest
if [[ -f /proc/sys/kernel/sched_latency_ns ]]; then
    # Politely request lower latency for interactive sessions (no-op if not root)
    echo 4000000 | sudo tee /proc/sys/kernel/sched_latency_ns > /dev/null 2>&1 || true
fi

# ── Greeting ─────────────────────────────────────────────────────────────────
fastfetch

# Chuck Norris wisdom
JOKE=$(curl -s --max-time 2 https://api.chucknorris.io/jokes/random \
       | jq -r '.value' 2>/dev/null)
[ -n "$JOKE" ] && echo "$JOKE" | cowsay

# ── Starship prompt ───────────────────────────────────────────────────────────
eval "$(starship init zsh)"
ZSHRCEOF
    ok ".zshrc written"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 12 — VIM IDE (PATHOGEN STACK)                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_vim() {
    banner "SECTION 12 · VIM IDE (PATHOGEN PLUGIN STACK)"

    VIM_BUNDLE="$HOME/.vim/bundle"
    VIM_AUTOLOAD="$HOME/.vim/autoload"
    mkdir -p "$VIM_BUNDLE" "$VIM_AUTOLOAD"

    step "Installing Pathogen..."
    if [[ "$DRY_RUN" != "true" ]]; then
        curl -LSso "$VIM_AUTOLOAD/pathogen.vim" \
            "https://tpo.pe/pathogen.vim" 2>/dev/null \
        || curl -LSso "$VIM_AUTOLOAD/pathogen.vim" \
            "https://raw.githubusercontent.com/tpope/vim-pathogen/master/autoload/pathogen.vim"
    fi

    step "Installing Vim plugins via git clone..."
    declare -A VIM_PLUGINS=(
        ["nerdtree"]="https://github.com/preservim/nerdtree"
        ["vim-airline"]="https://github.com/vim-airline/vim-airline"
        ["vim-airline-themes"]="https://github.com/vim-airline/vim-airline-themes"
        ["supertab"]="https://github.com/ervandew/supertab"
        ["catppuccin-vim"]="https://github.com/catppuccin/vim"
        ["ale"]="https://github.com/dense-analysis/ale"
        ["omnisharp-vim"]="https://github.com/OmniSharp/omnisharp-vim"
        ["emmet-vim"]="https://github.com/mattn/emmet-vim"
        ["vim-fugitive"]="https://github.com/tpope/vim-fugitive"
        ["vim-gitgutter"]="https://github.com/airblade/vim-gitgutter"
        ["vim-devicons"]="https://github.com/ryanoasis/vim-devicons"
        ["vim-commentary"]="https://github.com/tpope/vim-commentary"
        ["vim-surround"]="https://github.com/tpope/vim-surround"
        ["fzf-vim"]="https://github.com/junegunn/fzf.vim"
        ["vim-polyglot"]="https://github.com/sheerun/vim-polyglot"
        ["vim-tmux-navigator"]="https://github.com/christoomey/vim-tmux-navigator"
        ["vim-visual-multi"]="https://github.com/mg979/vim-visual-multi"
        ["vim-illuminate"]="https://github.com/RRethy/vim-illuminate"
        ["vim-startify"]="https://github.com/mhinz/vim-startify"
        ["indentLine"]="https://github.com/Yggdroot/indentLine"
        ["vim-auto-save"]="https://github.com/907th/vim-auto-save"
        # ── Enhancements (additive — nothing above was removed) ──────────────
        ["vim-repeat"]="https://github.com/tpope/vim-repeat"
        ["auto-pairs"]="https://github.com/jiangmiao/auto-pairs"
        ["rainbow"]="https://github.com/luochen1990/rainbow"
    )

    if [[ "$DRY_RUN" != "true" ]]; then
        for plugin in "${!VIM_PLUGINS[@]}"; do
            local url="${VIM_PLUGINS[$plugin]}"
            local dest="$VIM_BUNDLE/$plugin"
            if [[ -d "$dest" ]]; then
                ( cd "$dest" && git pull -q ) 2>/dev/null \
                    || record_error "Vim plugin update failed: $plugin"
            else
                git clone --depth=1 -q "$url" "$dest" 2>>"$LOGFILE" \
                    || record_error "Vim plugin clone failed: $plugin ($url)"
            fi
        done
    fi
    ok "Vim plugins installed"

    step "Writing ~/.vimrc..."
    cat > "$HOME/.vimrc" << 'VIMRCEOF'
" ╔══════════════════════════════════════════════════════╗
" ║  Kevin's Vim IDE — Catppuccin Mocha · CachyOS        ║
" ╚══════════════════════════════════════════════════════╝

execute pathogen#infect()
syntax on
filetype plugin indent on

" ── Core ──────────────────────────────────────────────
set encoding=utf-8
set fileencoding=utf-8
set hidden
set nobackup nowritebackup
set noswapfile
set undofile
set undodir=~/.vim/undodir
set updatetime=300
set signcolumn=yes
set termguicolors
set background=dark
" Catppuccin: pick the Mocha flavour before loading the colorscheme
let g:catppuccin_flavour = 'mocha'
colorscheme catppuccin_mocha

" ── Catppuccin transparency (lets Kitty's blur/opacity show through) ──
" Toggle off by setting g:rice_transparent = 0 here.
let g:rice_transparent = 1
if get(g:, 'rice_transparent', 1)
    highlight Normal       guibg=NONE ctermbg=NONE
    highlight NormalNC     guibg=NONE ctermbg=NONE
    highlight EndOfBuffer  guibg=NONE ctermbg=NONE
    highlight SignColumn   guibg=NONE ctermbg=NONE
    highlight LineNr       guibg=NONE ctermbg=NONE
endif

" ── UI ────────────────────────────────────────────────
set number
set norelativenumber
set cursorline
set ruler
set laststatus=2
set showcmd
set showmatch
set wildmenu
set wildmode=longest:full,full
set scrolloff=8
set sidescrolloff=8
set wrap
set linebreak
set breakindent
set list listchars=tab:»·,trail:·,extends:›,precedes:‹,nbsp:·
set noerrorbells novisualbell

" ── Editing ───────────────────────────────────────────
set tabstop=4 shiftwidth=4 expandtab
set smarttab autoindent smartindent
set backspace=indent,eol,start
set clipboard=unnamedplus
set mouse=a
set pastetoggle=<F2>

" ── Search ────────────────────────────────────────────
set incsearch hlsearch ignorecase smartcase
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

" ── Leader ────────────────────────────────────────────
let mapleader=" "
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :x<CR>
nnoremap <leader>Q :qa!<CR>
nnoremap <leader>e :NERDTreeToggle<CR>
nnoremap <leader>f :NERDTreeFind<CR>
nnoremap <leader>ff :FZF<CR>
nnoremap <leader>gs :Git status<CR>
nnoremap <leader>gb :Git blame<CR>
nnoremap <leader>gd :Git diff<CR>
nnoremap <leader>gc :Git commit<CR>
nnoremap <leader>gp :Git push<CR>

" ── NERDTree ──────────────────────────────────────────
let NERDTreeShowHidden=1
let NERDTreeMinimalUI=1
let NERDTreeDirArrows=1
let g:NERDTreeWinSize=30
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

" ── Airline ───────────────────────────────────────────
let g:airline_theme='catppuccin'
let g:airline_powerline_fonts=1
let g:airline#extensions#tabline#enabled=1
let g:airline#extensions#tabline#formatter='unique_tail'

" ── ALE ───────────────────────────────────────────────
let g:ale_linters = {
\   'cs':         ['OmniSharp'],
\   'python':     ['pylsp', 'flake8'],
\   'javascript': ['eslint'],
\   'typescript': ['eslint', 'tsserver'],
\}
let g:ale_fixers = {
\   '*':          ['remove_trailing_lines', 'trim_whitespace'],
\   'python':     ['black'],
\   'javascript': ['prettier'],
\   'typescript': ['prettier'],
\   'css':        ['prettier'],
\}
let g:ale_fix_on_save=1
let g:ale_sign_error='✗'
let g:ale_sign_warning='⚠'
nmap <silent> [e <Plug>(ale_previous_wrap)
nmap <silent> ]e <Plug>(ale_next_wrap)

" ── OmniSharp ─────────────────────────────────────────
let g:OmniSharp_server_stdio=1
let g:OmniSharp_highlight_types=3
autocmd FileType cs nmap <silent> gd :OmniSharpGotoDefinition<CR>
autocmd FileType cs nmap <silent> K  :OmniSharpDocumentation<CR>

" ── IndentLine ────────────────────────────────────────
let g:indentLine_char='│'
let g:indentLine_color_term=239

" ── Language Bindings ─────────────────────────────────
autocmd FileType cs         setlocal tabstop=4 shiftwidth=4 expandtab colorcolumn=120
autocmd FileType cs         nnoremap <buffer> <F9>  :!dotnet run<CR>
autocmd FileType cs         nnoremap <buffer> <F10> :!dotnet build<CR>
autocmd FileType javascript,typescript,typescriptreact,javascriptreact
                          \ setlocal tabstop=2 shiftwidth=2 expandtab
autocmd FileType python     setlocal tabstop=4 shiftwidth=4 expandtab colorcolumn=88
autocmd FileType python     nnoremap <buffer> <F9> :!python %<CR>
autocmd FileType html,css,scss,json,yaml
                          \ setlocal tabstop=2 shiftwidth=2 expandtab

autocmd BufNewFile,BufRead *.razor  set filetype=html
autocmd BufNewFile,BufRead *.cshtml set filetype=html
autocmd BufNewFile,BufRead *.tsx    set filetype=typescriptreact
autocmd BufNewFile,BufRead *.jsx    set filetype=javascriptreact

" ── Custom Commands ───────────────────────────────────
command! StripTrailing :%s/\s\+$//e
command! ReloadVimrc   :source $MYVIMRC | echo "vimrc reloaded"
command! FullPath      :echo expand('%:p')
command! VTerm         :vsplit | terminal

" ── Enhancements (Catppuccin polish + new plugins) ────
" Cleaner split borders & end-of-buffer (no ~ clutter)
set fillchars=eob:\ ,vert:│,fold:·

" rainbow: rainbow-coloured matching parens/brackets (Catppuccin-friendly)
let g:rainbow_active = 1

" auto-pairs: sensible defaults; disable in NERDTree/fzf buffers
let g:AutoPairsShortcutToggle = '<leader>p'

" vim-repeat needs no config — it makes surround/commentary repeatable with '.'

" GitGutter: Catppuccin sign colours + faster refresh
let g:gitgutter_map_keys = 0
highlight GitGutterAdd    guifg=#a6e3a1
highlight GitGutterChange guifg=#f9e2af
highlight GitGutterDelete guifg=#f38ba8

" Startify: Catppuccin-flavoured header
let g:startify_custom_header = [
\ '   ╔═══════════════════════════════════════╗',
\ '   ║   Kevin''s Vim · Catppuccin Mocha       ║',
\ '   ╚═══════════════════════════════════════╝',
\ ]
let g:startify_lists = [
\ { 'type': 'dir',       'header': ['   Recent in '. getcwd()] },
\ { 'type': 'files',     'header': ['   Recent files'] },
\ { 'type': 'bookmarks', 'header': ['   Bookmarks'] },
\ ]

" Illuminate: subtle highlight of the word under cursor (Catppuccin surface2)
let g:Illuminate_delay = 200
highlight illuminatedWord guibg=#585b70
VIMRCEOF

    mkdir -p "$HOME/.vim/undodir"
    ok ".vimrc written"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 13 — FASTFETCH CONFIGURATION                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_fastfetch() {
    banner "SECTION 13 · FASTFETCH CONFIGURATION"

    mkdir -p "$HOME/.config/fastfetch"
    step "Writing fastfetch config (CachyOS + Catppuccin Mocha)..."
    cat > "$HOME/.config/fastfetch/config.jsonc" << 'FFEOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "source": "cachyos",
        "color": { "1": "magenta", "2": "cyan" }
    },
    "display": {
        "separator": "  ",
        "color": { "keys": "magenta", "title": "magenta", "output": "cyan" }
    },
    "modules": [
        { "type": "title",    "format": "{user-name}@{host-name}" },
        "separator",
        { "type": "os",       "key": " OS"        },
        { "type": "kernel",   "key": " Kernel"    },
        { "type": "uptime",   "key": "󰔚 Uptime"   },
        { "type": "packages", "key": "󰏗 Packages" },
        { "type": "shell",    "key": " Shell"     },
        { "type": "de",       "key": " DE"        },
        { "type": "wm",       "key": " WM"        },
        { "type": "terminal", "key": " Terminal"  },
        { "type": "font",     "key": " Font"      },
        { "type": "cpu",      "key": " CPU"       },
        { "type": "gpu",      "key": "󰾲 GPU"      },
        { "type": "memory",   "key": "󰍛 Memory"   },
        { "type": "disk",     "key": "󰋊 Disk"     },
        { "type": "localip",  "key": "󰩟 Local IP" },
        "break",
        { "type": "colors",   "symbol": "circle", "paddingLeft": 2 }
    ]
}
FFEOF
    ok "fastfetch config written (CachyOS logo)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 14 — NOCTALIA SHELL (+ HYPRLAND COMPOSITOR) · OPT-IN              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Noctalia is a Wayland desktop SHELL (bar, launcher, control center, notifications,
# dock, lock screen, wallpaper, OSDs, session menu) — NOT a compositor and NOT a DE.
# It needs a Wayland compositor to run on; we pair it with Hyprland (CachyOS's
# flagship "Hyprland Noctalia" pairing). This whole section only runs when you pass
# --with-noctalia, because on a GNOME/Plasma box it is pure dead weight.
#
# What this does NOT install (Noctalia REPLACES all of these — do not add them):
#   waybar (bar) · wofi/rofi (launcher) · dunst/mako/swaync (notifications)
#   swww/hyprpaper (wallpaper) · hyprlock (lock) · wlogout (session menu)
#
# Honest caveats (true, not flattery):
#   • CachyOS ships Noctalia v4 (noctalia-shell, Quickshell/QML), launched via
#     `qs -c noctalia-shell`. Upstream main is a v5 C++ rewrite that is ALPHA with
#     breaking config changes — do NOT chase v5 yet. This targets the packaged v4.
#   • Noctalia is configured through its OWN GUI (SUPER+, settings / SUPER+S control
#     center) and stores config in ~/.config/noctalia/. We deliberately DON'T write
#     a Noctalia config here — hand-rolling its JSON would be brittle and pointless
#     when the shell ships sane defaults and a settings UI. Theme/Catppuccin is
#     selected in its settings (it has built-in palette support).
#   • We DO write a MINIMAL hyprland.conf — only launch glue, NVIDIA-Wayland env,
#     and Noctalia IPC keybinds. No bar/launcher/notify daemons (Noctalia owns them).
# ──────────────────────────────────────────────────────────────────────────────
configure_noctalia() {
    banner "SECTION 14 · NOCTALIA SHELL + HYPRLAND (OPT-IN)"

    step "Installing Hyprland compositor (minimal — Noctalia owns the shell)..."
    # Compositor + the pieces Noctalia does NOT provide: portal, polkit agent,
    # clipboard plumbing, screenshot grab tools, and basic Wayland utilities.
    pac_install \
        hyprland \
        xdg-desktop-portal-hyprland \
        polkit-gnome \
        wl-clipboard \
        cliphist \
        grim \
        slurp \
        qt6-multimedia

    step "Installing Noctalia shell (Quickshell-based v4)..."
    # Prefer the CachyOS repo package; fall back to AUR on plain Arch.
    # noctalia-shell pulls noctalia-qs (quickshell), imagemagick, brightnessctl,
    # ffmpeg, python, wlr-randr as hard deps automatically.
    if ! pac_install noctalia-shell; then
        warn "noctalia-shell not in repos — trying AUR..."
        aur_install noctalia-shell
    fi

    step "Installing recommended Noctalia optional deps..."
    # cliphist: clipboard history · wlsunset: night light ·
    # power-profiles-daemon: power profiles · ddcutil: external-monitor brightness
    aur_install wlsunset power-profiles-daemon ddcutil \
        || warn "Some Noctalia optional deps unavailable — non-fatal"

    step "Writing MINIMAL ~/.config/hypr/hyprland.conf (launch glue only)..."
    mkdir -p "$HOME/.config/hypr"
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$HOME/.config/hypr/hyprland.conf" << 'HYPREOF'
# ╔══════════════════════════════════════════════════════╗
# ║  Kevin's Hyprland — MINIMAL launcher for Noctalia    ║
# ║  Noctalia owns bar/launcher/notify/lock/wallpaper.   ║
# ╚══════════════════════════════════════════════════════╝

monitor = ,preferred,auto,1

$terminal = kitty
$browser  = firefox

# ── NVIDIA (RTX 5060 / Blackwell) Wayland env ──────────────────────────────────
# DRM modeset is already enabled in Section 2; these route GBM/VA-API to NVIDIA.
env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
env = ELECTRON_OZONE_PLATFORM_HINT,auto
cursor {
    no_hardware_cursors = true   # avoids the invisible-cursor NVIDIA quirk
}

# ── Autostart ──────────────────────────────────────────────────────────────────
# Noctalia IS the shell. Do NOT add waybar/wofi/dunst/swww here.
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = wl-paste --watch cliphist store
exec-once = qs -c noctalia-shell

# ── Input ──────────────────────────────────────────────────────────────────────
input {
    kb_layout    = us
    follow_mouse = 1
    sensitivity  = 0
    touchpad {
        natural_scroll = true
        tap-to-click   = true
    }
}

# ── Look & feel ────────────────────────────────────────────────────────────────
general {
    gaps_in             = 6
    gaps_out            = 12
    border_size         = 2
    col.active_border   = rgba(cba6f7ee) rgba(89b4faee) 45deg
    col.inactive_border = rgba(585b70aa)
    layout              = dwindle
}
decoration {
    rounding = 10
    blur {
        enabled = true
        size    = 6
        passes  = 2
    }
}
animations {
    enabled   = true
    bezier    = ease,0.25,0.1,0.25,1.0
    animation = windows,1,7,ease
    animation = fade,1,7,ease
    animation = workspaces,1,6,ease,slidevert
}
dwindle {
    pseudotile     = true
    preserve_split = true
}
misc {
    disable_hyprland_logo = true
}

# ── Noctalia IPC (its bar/launcher/control-center/notifications) ───────────────
$ipc = qs -c noctalia-shell ipc call
$mod = SUPER

bind = $mod, SPACE,  exec, $ipc launcher toggle
bind = $mod, D,      exec, $ipc launcher toggle
bind = $mod, S,      exec, $ipc controlCenter toggle
bind = $mod, comma,  exec, $ipc settings toggle
bind = $mod, N,      exec, $ipc notifications toggleHistory
bind = $mod, V,      exec, $ipc launcher clipboard
bind = $mod, X,      exec, $ipc sessionMenu toggle
bind = $mod, L,      exec, $ipc lockScreen lock

# ── Window management ──────────────────────────────────────────────────────────
bind = $mod, RETURN, exec, $terminal
bind = $mod, B,      exec, $browser
bind = $mod, Q,      killactive
bind = $mod, F,      fullscreen
bind = $mod, E,      exec, nautilus
bind = $mod SHIFT, E, exit

# Focus (vim-style)
bind = $mod, h, movefocus, l
bind = $mod, l, movefocus, r
bind = $mod, k, movefocus, u
bind = $mod, j, movefocus, d

# Workspaces 1-5
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5

# Screenshots (Noctalia has its own; grim is the raw fallback)
bind = ,     Print, exec, grim ~/Pictures/screenshot_$(date +%F_%H%M%S).png
bind = $mod, Print, exec, grim -g "$(slurp)" ~/Pictures/screenshot_$(date +%F_%H%M%S).png

# Audio / brightness routed through Noctalia OSD
bindel = ,XF86AudioRaiseVolume,  exec, $ipc volume increase
bindel = ,XF86AudioLowerVolume,  exec, $ipc volume decrease
bindl  = ,XF86AudioMute,         exec, $ipc volume muteOutput
bindel = ,XF86MonBrightnessUp,   exec, $ipc brightness increase
bindel = ,XF86MonBrightnessDown, exec, $ipc brightness decrease

# Mouse
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow
HYPREOF
        ok "Minimal hyprland.conf written (Noctalia is the shell)"
    else
        info "[DRY-RUN] write minimal ~/.config/hypr/hyprland.conf"
    fi

    info "Noctalia config is GUI-managed: log into Hyprland, press SUPER+, for"
    info "settings (pick Catppuccin palette there) and SUPER+S for the control center."
    ok "Noctalia + Hyprland configured (opt-in)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 15 — EXTRA APPS                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_extra_apps() {
    banner "SECTION 15 · EXTRA APPS (DBngin, JetBrains Toolbox)"

    step "Installing DBGate (database GUI — replaces DBngin)..."
    # dbgate-bin is available in AUR and is the actively maintained OSS fork
    aur_install dbgate-bin || warn "dbgate-bin unavailable — install manually later"

    step "Installing JetBrains Toolbox..."
    aur_install jetbrains-toolbox || warn "jetbrains-toolbox unavailable — install manually later"

    ok "Extra apps installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  VALIDATION                                                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
validate_installation() {
    banner "VALIDATION"
    local errors=0 warnings=0

    _check_cmd() { command -v "$1" &>/dev/null && ok "$1" || { warn "MISSING: $1"; ((warnings++)) || true; }; }
    _check_file() { [[ -f "$1" ]] && ok "$1" || { warn "MISSING: $1"; ((warnings++)) || true; }; }

    info "── Commands ──"
    for cmd in zsh kitty vim git node npm python3 starship dotnet fastfetch lsd bat fzf; do
        _check_cmd "$cmd"
    done
    _check_cmd "${AUR_HELPER:-paru}"

    info "── Config Files ──"
    _check_file "$HOME/.config/kitty/kitty.conf"
    _check_file "$HOME/.config/starship.toml"
    _check_file "$HOME/.zshrc"
    _check_file "$HOME/.vimrc"
    _check_file "$HOME/.config/fastfetch/config.jsonc"

    # Noctalia/Hyprland checks only surface if you actually opted in (config exists)
    if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
        info "── Noctalia + Hyprland (opt-in) ──"
        _check_cmd hyprland
        _check_cmd qs
        if pacman -Qq noctalia-shell &>/dev/null; then
            ok "noctalia-shell installed"
        else
            warn "noctalia-shell not installed"; ((warnings++)) || true
        fi
    fi

    info "── GNOME Theming ──"
    local _theme; _theme=$(find "$HOME/.themes" -maxdepth 1 -mindepth 1 -type d -iname '*atppuccin*dark*' -printf '%f\n' 2>/dev/null | head -1)
    if [[ -n "$_theme" ]]; then
        ok "Installed theme: $_theme"
        [[ -f "$HOME/.themes/$_theme/gnome-shell/gnome-shell.css" ]] \
            && ok "GNOME Shell theme present" \
            || warn "No gnome-shell/ in theme (Shell theme may be unavailable)"
    else
        warn "No Catppuccin theme found in ~/.themes (theme not installed)"
        ((warnings++)) || true
    fi
    _check_file "$HOME/.config/gtk-4.0/gtk.css"
    _check_file "$HOME/.gtkrc-2.0"
    _check_file "$HOME/.config/Kvantum/kvantum.kvconfig"
    if command -v gnome-extensions &>/dev/null; then
        local _en; _en=$(gnome-extensions list --enabled 2>/dev/null | wc -l)
        info "GNOME extensions enabled: ${_en} (load fully after relogin)"
    fi
    local _cursor; _cursor=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null)
    case "$_cursor" in
        *atppuccin*) ok "Active cursor is Catppuccin (${_cursor})" ;;
        *) warn "Active cursor is ${_cursor:-unset} (expected Catppuccin)"; ((warnings++)) || true ;;
    esac
    if [[ "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)" == *"atppuccin"* ]]; then
        ok "Active GTK theme is Catppuccin"
    else
        warn "Active GTK theme is not Catppuccin (apply via Tweaks, or relogin)"
        ((warnings++)) || true
    fi

    info "── NVIDIA ──"
    if pacman -Qq nvidia-open-dkms &>/dev/null; then
        ok "nvidia-open-dkms installed"
    else
        warn "nvidia-open-dkms not found (reboot may be needed)"
        ((warnings++)) || true
    fi

    info "── CachyOS Kernel ──"
    if uname -r | grep -qiE 'cachyos|bore|bmq'; then
        ok "Optimized kernel: $(uname -r)"
    else
        warn "Standard kernel detected — switch to linux-cachyos for best performance"
        ((warnings++)) || true
    fi

    echo ""
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}  ✅  VALIDATION PASSED — ${warnings} warning(s), 0 critical errors${NC}"
    else
        echo -e "${RED}${BOLD}  ❌  VALIDATION FAILED — $errors error(s), $warnings warning(s)${NC}"
    fi
    echo ""
    return "$errors"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  MAIN                                                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
main() {
    banner "KEVIN'S CACHY OS SETUP v${SCRIPT_VERSION}"

    preflight
    install_base_packages
    setup_nvidia
    setup_fonts
    setup_gnome_theme
    install_dotnet
    install_nodejs
    install_python
    configure_kitty
    configure_zsh_shell
    configure_starship
    configure_zshrc
    configure_vim
    configure_fastfetch
    [[ "$WITH_NOCTALIA" == "true" ]] && configure_noctalia
    install_extra_apps
    validate_installation || true

    banner "ALL DONE ON CACHY OS, BOSS 🎉"

    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║  KEVIN'S CACHYOS SETUP COMPLETE                             ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${TEAL}${BOLD}  What was installed:${NC}"
    echo -e "${GREEN}  ✓${NC} CachyOS + paru AUR helper"
    echo -e "${GREEN}  ✓${NC} NVIDIA RTX 5060 (nvidia-open-dkms + Wayland/Vulkan)"
    echo -e "${GREEN}  ✓${NC} JetBrainsMono Nerd Font"
    echo -e "${GREEN}  ✓${NC} Catppuccin GNOME: GTK3+GTK4/libadwaita+GTK2, GNOME Shell theme (User Themes)"
    echo -e "${GREEN}  ✓${NC} Catppuccin Mocha Mauve cursors + Papirus (violet) icons + Kvantum (Qt)"
    echo -e "${GREEN}  ✓${NC} macOS-style window buttons (close/min/max, left) + generated wallpaper"
    echo -e "${GREEN}  ✓${NC} .NET 10 SDK + ASP.NET Runtime"
    echo -e "${GREEN}  ✓${NC} Node.js LTS + global NPM tools (TS, ESLint, Prettier, Next)"
    echo -e "${GREEN}  ✓${NC} Python 3 + pip + black + pylsp + flake8"
    echo -e "${GREEN}  ✓${NC} Kitty terminal (Catppuccin Mocha)"
    echo -e "${GREEN}  ✓${NC} ZSH as default shell"
    echo -e "${GREEN}  ✓${NC} Starship prompt (Catppuccin Powerline)"
    echo -e "${GREEN}  ✓${NC} .zshrc with full alias/function set"
    echo -e "${GREEN}  ✓${NC} Vim IDE (Pathogen + 21 plugins)"
    echo -e "${GREEN}  ✓${NC} Fastfetch (CachyOS logo)"
    [[ "$WITH_NOCTALIA" == "true" ]] && \
        echo -e "${GREEN}  ✓${NC} Noctalia shell + Hyprland (opt-in Wayland session)"
    echo -e "${GREEN}  ✓${NC} DBGate + JetBrains Toolbox"
    echo ""
    echo -e "${YELLOW}${BOLD}  Next steps:${NC}"
    echo -e "${PEACH}  1.${NC} sudo reboot  (required for NVIDIA drivers)"
    echo -e "${PEACH}  2.${NC} LOG OUT & BACK IN — GNOME Shell extensions + Shell theme load on relogin"
    echo -e "${PEACH}  3.${NC} Then run: ./KevinsCachyOSSetup.sh --validate  (confirms theme is active)"
    echo -e "${PEACH}  4.${NC} CachyOS Hello app → enable linux-cachyos kernel if not already on it"
    [[ "$WITH_NOCTALIA" == "true" ]] && \
        echo -e "${PEACH}  5.${NC} Pick 'Hyprland' at the login screen → SUPER+, opens Noctalia settings (set Catppuccin palette there)"
    echo ""
    echo -e "${MAUVE}${BOLD}  Key aliases:${NC}"
    echo -e "${DIM}  dn dnr dnb dnt dnw         — .NET 10"
    echo -e "  nrd nrb nrt ni nig         — Node/NPM"
    echo -e "  py venv activate deact     — Python"
    echo -e "  g ga gaa gc gl gp gs       — Git"
    echo -e "  pars parss parr            — paru (CachyOS AUR)"
    echo -e "  pacu pacr pacss            — pacman"
    echo -e "  ls ll la lt tree           — lsd (icons + color)"
    echo -e "  mkcd newdotnet newnext newpy — Scaffolding${NC}"
    echo ""
    echo -e "  📝 Log: ${LOGFILE}"
    echo ""

    if [[ "$REBOOT_REQUIRED" == true ]]; then
        echo -e "${RED}${BOLD}  ⚠️  REBOOT REQUIRED for NVIDIA drivers.  Run: sudo reboot${NC}"
        echo ""
    fi

    # ── Error summary ────────────────────────────────────────────────────────────
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}${BOLD}  ║  NON-FATAL ERRORS ENCOUNTERED (${#ERRORS[@]})                        ║${NC}"
        echo -e "${RED}${BOLD}  ╚══════════════════════════════════════════════════════════════╝${NC}"
        for err in "${ERRORS[@]}"; do
            echo -e "${RED}  ✗  ${err}${NC}"
        done
        echo ""
        echo -e "${YELLOW}  These errors were non-fatal and the script continued.${NC}"
        echo -e "${YELLOW}  Review the log for full details: ${LOGFILE}${NC}"
        echo ""
    else
        echo -e "${GREEN}${BOLD}  ✅  No errors encountered during setup.${NC}"
        echo ""
    fi
}

# ── CLI dispatch ──────────────────────────────────────────────────────────────
ACTION="main"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN=true ;;
        --with-noctalia)  WITH_NOCTALIA=true ;;
        --validate)       ACTION="validate" ;;
        --help|-h)        ACTION="help" ;;
        *) echo "Unknown option: $1 (use --help)"; exit 1 ;;
    esac
    shift
done

case "$ACTION" in
    help)
        cat << USAGE
Usage: ./KevinsCachyOSSetup.sh [OPTIONS]

Options:
  --dry-run         Print all actions without making changes
  --with-noctalia   Also install Hyprland + the Noctalia Wayland shell
                    (opt-in; skipped by default — pointless on GNOME/Plasma alone)
  --validate        Run validation checks only (no install)
  --help, -h        Show this help

Flags combine, e.g.:  ./KevinsCachyOSSetup.sh --dry-run --with-noctalia

Environment:
  DRY_RUN=true        Same as --dry-run
  WITH_NOCTALIA=true  Same as --with-noctalia

Run as your normal user (NOT root). sudo is used internally where needed.
CachyOS with NVIDIA RTX 5060, Catppuccin Mocha, .NET/Node/Python dev stack.
USAGE
        exit 0 ;;
    validate)  preflight; validate_installation ;;
    main)      main ;;
esac