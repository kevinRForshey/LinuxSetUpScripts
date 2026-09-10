#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║         KODE WITH KEVIN — ULTIMATE ARCH + GNOME DEV ENVIRONMENT             ║
# ║         Arch / EndeavourOS · GNOME Shell · Material You + Konsole-Mocha    ║
# ║         .NET / Node / Python 3.13 / Rust · Vim + NeoVim IDE · Kitty       ║
# ║         Version: 1.0.0                                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Usage:
#   chmod +x KodeWithKevinArchGnomeConfig.sh
#   ./KodeWithKevinArchGnomeConfig.sh             # full install
#   ./KodeWithKevinArchGnomeConfig.sh --dry-run   # preview without changes
#   ./KodeWithKevinArchGnomeConfig.sh --validate  # check install status only
#
# Run as your REGULAR USER (NOT root). sudo is invoked internally where needed.
#
# This script is meant to be re-run on a fresh machine (or the same one) as
# many times as needed — every install uses --needed/idempotent flags and
# every config file is rewritten unconditionally, regardless of what's
# already present. Nothing is skipped just because it looks installed.
#
# Companion scripts (must live alongside this one):
#   material-you-gnome-rice.sh  — Material You GNOME theme/wallpaper/extensions
#   ramboxinstallerfix.sh       — installs rambox-pro-bin + fixes GNOME launcher entry
#   install-vim-ide.sh + vimrc  — the Vim IDE stack documented in VIM_IDE_Setup.pdf
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ── Catppuccin Mocha ANSI Palette ────────────────────────────────────────────
MAUVE='\033[38;2;203;166;247m'
TEAL='\033[38;2;148;226;213m'
GREEN='\033[38;2;166;227;161m'
YELLOW='\033[38;2;249;226;175m'
RED='\033[38;2;243;139;168m'
BOLD='\033[1m'
NC='\033[0m'

# ── Globals ───────────────────────────────────────────────────────────────────
SCRIPT_VERSION="1.0.0"
LOGFILE="${HOME}/.local/share/kode-with-kevin-setup.log"
DRY_RUN="${DRY_RUN:-false}"
REBOOT_REQUIRED=false
AUR_HELPER="paru"   # preferred; falls back to yay if paru bootstrap fails
SCRIPT_ERRORS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDO_KEEPALIVE_PID=""

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
fail()  { echo -e "${RED}${BOLD}  ✗  $1${NC}"; echo "[$(date '+%H:%M:%S')] FAIL: $1" >> "$LOGFILE" 2>/dev/null || true; cleanup_sudo_keepalive; exit 1; }

# Records a non-fatal section failure so it can be reported in the final
# summary instead of aborting the whole run.
record_error() {
    local ctx="$1" rc="${2:-1}"
    SCRIPT_ERRORS+=("$ctx (exit code $rc)")
    echo -e "${RED}${BOLD}  ✗  $ctx failed — logged, continuing with remaining setup${NC}"
    echo "[$(date '+%H:%M:%S')] ERROR: $ctx failed (exit code $rc)" >> "$LOGFILE" 2>/dev/null || true
}

cleanup_sudo_keepalive() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

pac_install() {
    if [[ "$DRY_RUN" == "true" ]]; then info "[DRY-RUN] sudo pacman -S --needed --noconfirm $*"; return 0; fi
    sudo pacman -S --needed --noconfirm "$@" 2>&1 | tee -a "$LOGFILE"
}

aur_install() {
    if [[ "$DRY_RUN" == "true" ]]; then info "[DRY-RUN] ${AUR_HELPER} -S --needed --noconfirm $*"; return 0; fi
    "${AUR_HELPER}" -S --needed --noconfirm "$@" 2>&1 | tee -a "$LOGFILE"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PREFLIGHT                                                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
preflight() {
    banner "PREFLIGHT CHECKS"

    [[ $EUID -eq 0 ]] && fail "Do NOT run as root. Run as your regular user — sudo is called internally."

    mkdir -p "$(dirname "$LOGFILE")"
    : > "$LOGFILE"

    step "Checking distro..."
    if [[ -f /etc/arch-release ]] || grep -qiE 'arch|endeavour|cachyos|manjaro|garuda' /etc/os-release 2>/dev/null; then
        ok "Arch-based distro detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    else
        fail "This script requires an Arch-based distribution."
    fi

    step "Checking for GNOME Shell..."
    if command -v gnome-shell &>/dev/null; then
        ok "GNOME Shell: $(gnome-shell --version 2>/dev/null)"
    else
        warn "gnome-shell not found — the Material You rice section will fail; base dev tooling will still install."
    fi

    step "Checking internet..."
    curl -sf --max-time 8 "https://github.com" > /dev/null || fail "No internet connection."
    ok "Internet reachable"

    if [[ "$DRY_RUN" != "true" ]]; then
        step "Verifying sudo access..."
        sudo -v || fail "sudo access required."
        ok "sudo OK"

        ( while true; do sudo -n true 2>/dev/null; sleep 55; kill -0 "$$" 2>/dev/null || exit; done ) &
        SUDO_KEEPALIVE_PID=$!
        trap 'cleanup_sudo_keepalive; exit' EXIT INT TERM
    else
        info "[DRY-RUN] Skipping sudo verification"
    fi

    info "Log: $LOGFILE"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 1 — BASE PACKAGES                                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_base_packages() {
    banner "SECTION 1 · SYSTEM UPDATE & BASE PACKAGES"

    step "Full system upgrade..."
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOGFILE" || return 1
    else
        info "[DRY-RUN] sudo pacman -Syu --noconfirm"
    fi
    ok "System updated"

    step "Installing base development & utility packages..."
    pac_install \
        base-devel git curl wget unzip zip tar xz jq fzf fontconfig tree \
        htop btop ripgrep fd bat openssh man-db xdg-utils \
        vim neovim zsh kitty fastfetch flatpak || return 1
    ok "Base packages installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 2 — AUR HELPERS: yay + paru                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_aur_helpers() {
    banner "SECTION 2 · AUR HELPERS — yay + paru"

    step "Installing yay..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would bootstrap yay-bin from AUR if missing"
    elif command -v yay &>/dev/null; then
        ok "yay present: $(yay --version | head -1)"
    else
        local tmpdir; tmpdir=$(mktemp -d)
        git clone --depth=1 -q "https://aur.archlinux.org/yay-bin.git" "$tmpdir"
        ( cd "$tmpdir" && makepkg -si --noconfirm )
        rm -rf "$tmpdir"
        ok "yay installed"
    fi

    step "Installing paru..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would bootstrap paru-bin from AUR if missing"
    elif command -v paru &>/dev/null; then
        ok "paru present: $(paru --version | head -1)"
    elif command -v yay &>/dev/null; then
        yay -S --needed --noconfirm paru-bin 2>&1 | tee -a "$LOGFILE"
        ok "paru installed via yay"
    else
        local tmpdir; tmpdir=$(mktemp -d)
        git clone --depth=1 -q "https://aur.archlinux.org/paru-bin.git" "$tmpdir"
        ( cd "$tmpdir" && makepkg -si --noconfirm )
        rm -rf "$tmpdir"
        ok "paru installed from source"
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        command -v paru &>/dev/null && AUR_HELPER="paru" || AUR_HELPER="yay"
    fi
    info "Using ${AUR_HELPER} for subsequent AUR installs"

    step "Installing pacseek + rtk (rust token killer) from AUR..."
    aur_install pacseek rtk || return 1
    ok "pacseek + rtk installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 3 — NERD FONTS                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_nerd_fonts() {
    banner "SECTION 3 · NERD FONTS"

    step "Installing a solid Nerd Font lineup..."
    pac_install \
        ttf-jetbrains-mono-nerd \
        ttf-firacode-nerd \
        ttf-cascadia-code-nerd \
        ttf-hack-nerd \
        ttf-meslo-nerd \
        ttf-iosevka-nerd \
        ttf-nerd-fonts-symbols-common || return 1

    step "Rebuilding font cache..."
    if [[ "$DRY_RUN" != "true" ]]; then
        fc-cache -f > /dev/null 2>&1
    fi
    ok "Nerd Fonts installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 4 — .NET SDK                                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_dotnet() {
    banner "SECTION 4 · .NET SDK"

    pac_install dotnet-sdk aspnet-runtime aspnet-targeting-pack || return 1

    if [[ "$DRY_RUN" != "true" ]]; then
        dotnet --version && ok "dotnet $(dotnet --version) ready" \
            || warn ".NET version check failed — may need a new shell session"
        dotnet tool install -g dotnet-script 2>/dev/null || true
        dotnet tool install -g dotnet-format 2>/dev/null || true
    fi
    ok ".NET SDK installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 5 — PYTHON 3.13 + uv                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_python() {
    banner "SECTION 5 · PYTHON 3.13 + uv"

    step "Installing Python 3.13 (AUR)..."
    aur_install python313 || return 1

    step "Installing uv (Python package/tool manager)..."
    pac_install python-uv || return 1

    ok "Python 3.13 + uv installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 6 — NODE.JS & NPM                                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_nodejs() {
    banner "SECTION 6 · NODE.JS & NPM"

    pac_install nodejs npm || return 1
    ok "Node.js + npm installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 7 — RUST (stable/default channel)                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_rust() {
    banner "SECTION 7 · RUST (default/stable channel)"

    # Arch's `rust` package always tracks the current stable/default release —
    # no rustup toolchain juggling needed.
    pac_install rust || return 1
    if [[ "$DRY_RUN" != "true" ]]; then
        ok "rustc $(rustc --version 2>/dev/null || echo '(new shell needed)')"
    fi
    ok "Rust installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 8 — STEAM (+ multilib)                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_steam() {
    banner "SECTION 8 · STEAM"

    step "Ensuring [multilib] repo is enabled (required for Steam)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
            sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
            sudo pacman -Sy --noconfirm
            ok "[multilib] enabled"
        else
            ok "[multilib] already enabled"
        fi
    else
        info "[DRY-RUN] Would enable [multilib] in /etc/pacman.conf and pacman -Sy"
    fi

    pac_install steam || return 1
    ok "Steam installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 9 — NVIDIA DRIVERS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
setup_nvidia() {
    banner "SECTION 9 · NVIDIA DRIVERS"

    if ! lspci 2>/dev/null | grep -qi 'nvidia'; then
        warn "No NVIDIA GPU detected via lspci — skipping NVIDIA driver install."
        return 0
    fi
    ok "NVIDIA GPU detected: $(lspci | grep -i nvidia | head -1 | cut -d: -f3)"

    step "Installing nvidia-open-dkms (auto-rebuilds against any kernel) + support packages..."
    pac_install nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
        libva-nvidia-driver vulkan-icd-loader lib32-vulkan-icd-loader opencl-nvidia || return 1

    step "Enabling NVIDIA DRM modesetting (required for Wayland/GNOME)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        echo 'options nvidia-drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia-options.conf > /dev/null
        echo 'blacklist nouveau' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
        command -v mkinitcpio &>/dev/null && sudo mkinitcpio -P 2>&1 | tee -a "$LOGFILE"
    else
        info "[DRY-RUN] Would write modprobe.d configs and rebuild initramfs"
    fi

    REBOOT_REQUIRED=true
    ok "NVIDIA driver stack installed — REBOOT REQUIRED"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 10 — HEADROOM AI (uv tool)                                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_headroom_ai() {
    banner "SECTION 10 · HEADROOM AI (uv + python 3.13)"

    if [[ "$DRY_RUN" != "true" ]]; then
        uv tool install --python 3.13 "headroom-ai[all]" 2>&1 | tee -a "$LOGFILE" || return 1
    else
        info "[DRY-RUN] uv tool install --python 3.13 \"headroom-ai[all]\""
    fi
    ok "Headroom AI installed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 11 — ZSH AS DEFAULT SHELL                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_zsh_shell() {
    banner "SECTION 11 · ZSH AS DEFAULT SHELL"

    local ZSH_PATH; ZSH_PATH="$(command -v zsh)"
    step "Setting zsh as default shell for $USER..."
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo chsh -s "$ZSH_PATH" "$USER"
    else
        info "[DRY-RUN] sudo chsh -s $ZSH_PATH $USER"
    fi
    ok "Default shell → $ZSH_PATH"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 12 — MATERIAL YOU GNOME RICE                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
run_material_rice() {
    banner "SECTION 12 · MATERIAL YOU GNOME RICE"

    local script="$SCRIPT_DIR/material-you-gnome-rice.sh"
    if [[ ! -f "$script" ]]; then
        warn "material-you-gnome-rice.sh not found next to this script — skipping."
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        bash "$script" --dry-run
    else
        bash "$script"
    fi
    ok "Material You GNOME rice applied"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 13 — RAMBOX                                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
run_rambox_fix() {
    banner "SECTION 13 · RAMBOX (install + GNOME launcher fix)"

    local script="$SCRIPT_DIR/ramboxinstallerfix.sh"
    if [[ ! -f "$script" ]]; then
        warn "ramboxinstallerfix.sh not found next to this script — skipping."
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] bash $script"
        return 0
    fi

    bash "$script"
    ok "Rambox installed and GNOME launcher entry fixed"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 14 — VIM IDE (pathogen stack, VIM_IDE_Setup.pdf)                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
run_vim_ide_setup() {
    banner "SECTION 14 · VIM IDE (per VIM_IDE_Setup.pdf)"

    local script="$SCRIPT_DIR/install-vim-ide.sh"
    if [[ ! -f "$script" ]]; then
        warn "install-vim-ide.sh not found next to this script — skipping."
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] bash $script"
        return 0
    fi

    bash "$script"
    ok "Vim IDE stack installed (pathogen bundle + vimrc)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 15 — NEOVIM (shares the Vim IDE stack)                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_neovim() {
    banner "SECTION 15 · NEOVIM (shares the Vim IDE pathogen stack)"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would write ~/.config/nvim/init.vim"
        return 0
    fi

    mkdir -p "$HOME/.config/nvim"
    cat > "$HOME/.config/nvim/init.vim" << 'NVIMEOF'
" Kevin's Neovim — reuses the pathogen-based Vim IDE stack documented in
" VIM_IDE_Setup.pdf, so Vim and Neovim share one plugin set and one config.
" Update plugins with install-vim-ide.sh; do not duplicate config here.
set runtimepath^=~/.vim
set runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc
NVIMEOF

    ok "~/.config/nvim/init.vim written (sources ~/.vimrc + ~/.vim/bundle plugins)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 16 — KITTY: Konsole (Garuda Mocha) + Material Feel               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_kitty() {
    banner "SECTION 16 · KITTY — Konsole (Garuda Mocha) + Material Feel"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would write ~/.config/kitty/kitty.conf"
        return 0
    fi

    mkdir -p "$HOME/.config/kitty"
    cat > "$HOME/.config/kitty/kitty.conf" << 'KITTYEOF'
# ╔══════════════════════════════════════════════════════╗
# ║  Kevin's Kitty — Konsole (Garuda Mocha) + Material    ║
# ╚══════════════════════════════════════════════════════╝
# Palette: Catppuccin Mocha (same theme Garuda's Dr460nized Konsole profile
# ships). Feel: translucent + blurred glass surface, à la Material You,
# layered on top of the rounded-window-corners + blur-my-shell "kitty"
# whitelist configured by material-you-gnome-rice.sh (real blur under
# GNOME/mutter comes from that shell extension, not kitty's own
# background_blur, which is a no-op outside KDE/KWin).

# ── Font ─────────────────────────────────────────────
font_family      JetBrainsMono Nerd Font
bold_font        JetBrainsMono Nerd Font Bold
italic_font      JetBrainsMono Nerd Font Italic
bold_italic_font JetBrainsMono Nerd Font Bold Italic
font_size        14.0
disable_ligatures never
adjust_line_height 110%

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

color0   #45475A   color8   #585B70
color1   #F38BA8   color9   #F38BA8
color2   #A6E3A1   color10  #A6E3A1
color3   #F9E2AF   color11  #F9E2AF
color4   #89B4FA   color12  #89B4FA
color5   #F5C2E7   color13  #F5C2E7
color6   #94E2D5   color14  #94E2D5
color7   #BAC2DE   color15  #A6ADC8

# ── Tabs (Konsole-style, bottom powerline) ───────────
active_tab_foreground   #11111B
active_tab_background   #CBA6F7
inactive_tab_foreground #CDD6F4
inactive_tab_background #181825
tab_bar_edge            bottom
tab_bar_style           powerline
tab_powerline_style     slanted
tab_bar_min_tabs        1

# ── Window — glass/material surface ──────────────────
background_opacity         0.85
dynamic_background_opacity yes
background_blur             20
window_padding_width         10
remember_window_size        yes
initial_window_width         180c
initial_window_height        45c
confirm_os_window_close      0

# ── Misc ─────────────────────────────────────────────
scrollback_lines     10000
enable_audio_bell    no
visual_bell_duration 0
shell                /usr/bin/zsh
editor               vim
copy_on_select       yes
repaint_delay        10
input_delay          3
sync_to_monitor      yes

# ── Keyboard ─────────────────────────────────────────
map ctrl+shift+c     copy_to_clipboard
map ctrl+shift+v     paste_from_clipboard
map ctrl+shift+t     new_tab_with_cwd
map ctrl+shift+w     close_tab
map ctrl+shift+right next_tab
map ctrl+shift+left  previous_tab
map ctrl+shift+enter new_window_with_cwd
map ctrl+equal       increase_font_size
map ctrl+minus       decrease_font_size
map ctrl+0           reset_font_size
map ctrl+shift+r     load_config_file
KITTYEOF

    ok "kitty.conf written (JetBrainsMono Nerd Font 14pt, Catppuccin Mocha, translucent)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 17 — FISH SHELL                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
install_fish_shell() {
    banner "SECTION 17 · FISH SHELL"

    pac_install fish

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would write ~/.config/fish/config.fish"
        return 0
    fi

    mkdir -p "$HOME/.config/fish"
    cat > "$HOME/.config/fish/config.fish" << 'FISHEOF'
# ╔══════════════════════════════════════════════════════╗
# ║  Kevin's Fish — Starship prompt + fzf/atuin history   ║
# ╚══════════════════════════════════════════════════════╝
# Font is a terminal-level setting, not a shell-level one — Kitty already
# renders every shell (zsh, fish, bash) in JetBrainsMono Nerd Font 14pt,
# see ~/.config/kitty/kitty.conf. Fish ships autosuggestions and syntax
# highlighting on by default, so no plugin manager is needed for those.

set -gx EDITOR vim
set -gx VISUAL vim
set -gx PATH $HOME/.local/bin $HOME/bin $HOME/.dotnet/tools $HOME/.cargo/bin $PATH

set -g fish_greeting

# fzf key bindings (Ctrl+R history, Ctrl+T file find, Alt+C cd)
if test -f /usr/share/fzf/key-bindings.fish
    source /usr/share/fzf/key-bindings.fish
    fzf_key_bindings
end
if test -f /usr/share/fzf/completion.fish
    source /usr/share/fzf/completion.fish
end

# atuin — shared shell history search (Ctrl+R), same DB as zsh
if type -q atuin
    atuin init fish | source
end

# Starship prompt — same Catppuccin Mocha config as zsh (~/.config/starship.toml)
if type -q starship
    starship init fish | source
end

# ── Abbreviations (fish's alias equivalent — expand on Space/Enter) ──
abbr -a ll 'ls -alh'
abbr -a la 'ls -A'
abbr -a g 'git'
abbr -a gs 'git status -sb'
abbr -a ga 'git add'
abbr -a gc 'git commit -m'
abbr -a gp 'git push'
abbr -a gpl 'git pull'
abbr -a gd 'git diff'
abbr -a gl 'git log --oneline --graph --decorate --all'
abbr -a pars 'paru -S --noconfirm --needed'
abbr -a paru 'paru -Syu --noconfirm'
abbr -a parss 'paru -Ss'
abbr -a dn 'dotnet'
abbr -a dnr 'dotnet run'
abbr -a dnb 'dotnet build'
abbr -a dnw 'dotnet watch run'
FISHEOF

    ok "config.fish written (Starship + fzf/atuin history + abbreviations)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 18 — STARSHIP + ZSH HISTORY/AUTOCOMPLETE STACK                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_starship_and_history() {
    banner "SECTION 18 · STARSHIP + ZSH HISTORY/AUTOCOMPLETE STACK"

    pac_install starship zsh-autosuggestions zsh-syntax-highlighting \
        zsh-history-substring-search atuin cowsay lsd
    aur_install zsh-fzf-tab-git

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would write ~/.config/starship.toml"
        return 0
    fi

    mkdir -p "$HOME/.config"
    cat > "$HOME/.config/starship.toml" << 'STARSHIPEOF'
# ╔══════════════════════════════════════════════════════╗
# ║  Starship — Catppuccin Mocha Powerline                ║
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
Arch        = "󰣇 "
EndeavourOS = " "
CachyOS     = " "
Linux       = "󰌽 "

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

    if command -v atuin &>/dev/null; then
        step "Importing existing shell history into atuin..."
        atuin import auto 2>/dev/null || true
    fi

    ok "starship.toml written (Catppuccin Mocha powerline); zsh-autosuggestions/syntax-highlighting/history-substring-search/fzf-tab/atuin ready for ~/.zshrc"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 19 — .ZSHRC DEPLOYMENT                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
deploy_zshrc() {
    banner "SECTION 19 · .ZSHRC DEPLOYMENT"

    local src="$SCRIPT_DIR/.zshrc"
    if [[ ! -f "$src" ]]; then
        warn "$src not found — skipping .zshrc deployment"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would back up ~/.zshrc and deploy $src -> ~/.zshrc"
        return 0
    fi

    if [[ -f "$HOME/.zshrc" ]]; then
        cp -f "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
        info "Backed up existing ~/.zshrc"
    fi

    cp -f "$src" "$HOME/.zshrc"
    ok "~/.zshrc deployed (aliases, functions, history-driven autocomplete, Bible verse, Starship prompt)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SECTION 20 — FASTFETCH: KodeWithKevin (KWK) LOGO                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
configure_fastfetch_logo() {
    banner "SECTION 20 · FASTFETCH — KodeWithKevin (KWK) Logo"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would write ~/.config/fastfetch/kwk-logo.txt and config.jsonc"
        return 0
    fi

    mkdir -p "$HOME/.config/fastfetch"

    cat > "$HOME/.config/fastfetch/kwk-logo.txt" << 'LOGOEOF'
$1  ██╗  ██╗ $2██╗    ██╗ $1██╗  ██╗
$1  ██║ ██╔╝ $2██║    ██║ $1██║ ██╔╝
$1  █████╔╝  $2██║ █╗ ██║ $1█████╔╝
$1  ██╔═██╗  $2██║███╗██║ $1██╔═██╗
$1  ██║  ██╗ $2╚███╔███╔╝ $1██║  ██╗
$1  ╚═╝  ╚═╝  $2╚══╝╚══╝  $1╚═╝  ╚═╝
LOGOEOF

    cat > "$HOME/.config/fastfetch/config.jsonc" << EOF
{
    "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "file",
        "source": "$HOME/.config/fastfetch/kwk-logo.txt",
        "padding": { "top": 1, "right": 2 },
        "color": { "1": "#CDD6F4", "2": "#89B4FA" }
    },
    "display": {
        "separator": "  ",
        "color": { "keys": "#89B4FA", "title": "#CBA6F7", "output": "#CDD6F4" }
    },
    "modules": [
        { "type": "title",    "format": "{user-name}@{host-name}" },
        "separator",
        { "type": "os",       "key": " OS       " },
        { "type": "kernel",   "key": " Kernel   " },
        { "type": "uptime",   "key": "󰔚 Uptime   " },
        { "type": "packages", "key": "󰏗 Packages " },
        { "type": "shell",    "key": " Shell    " },
        { "type": "de",       "key": " DE       " },
        { "type": "wm",       "key": " WM       " },
        { "type": "theme",    "key": "󰉼 Theme    " },
        { "type": "icons",    "key": "󰀻 Icons    " },
        { "type": "terminal", "key": " Terminal " },
        { "type": "terminalfont", "key": " Font     " },
        { "type": "cpu",      "key": " CPU      " },
        { "type": "gpu",      "key": "󰾲 GPU      " },
        { "type": "memory",   "key": "󰍛 Memory   " },
        { "type": "disk",     "key": "󰋊 Disk     " },
        { "type": "localip",  "key": "󰩟 Local IP " },
        "break",
        {
            "type": "colors",
            "symbol": "circle",
            "paddingLeft": 2
        }
    ]
}
EOF

    ok "fastfetch config.jsonc written (custom KWK logo, Catppuccin Mocha keys)"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  VALIDATION                                                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
validate_installation() {
    banner "VALIDATION"
    local warnings=0

    _check_cmd()  { command -v "$1" &>/dev/null && ok "$1" || { warn "MISSING: $1"; ((warnings++)) || true; }; }
    _check_file() { [[ -f "$1" ]] && ok "$1" || { warn "MISSING: $1"; ((warnings++)) || true; }; }
    _check_dir()  { [[ -d "$1" ]] && ok "$1" || { warn "MISSING: $1"; ((warnings++)) || true; }; }

    info "── Commands ──"
    for cmd in vim nvim kitty fastfetch zsh fish git node npm dotnet rustc cargo \
               python3.13 uv yay paru steam pacseek rtk gnome-shell starship atuin; do
        _check_cmd "$cmd"
    done

    info "── Headroom AI ──"
    if uv tool list 2>/dev/null | grep -q '^headroom-ai'; then
        ok "headroom-ai (uv tool)"
    else
        warn "MISSING: headroom-ai (uv tool)"
        ((warnings++)) || true
    fi

    info "── Config Files ──"
    _check_file "$HOME/.vimrc"
    _check_file "$HOME/.config/nvim/init.vim"
    _check_file "$HOME/.config/kitty/kitty.conf"
    _check_file "$HOME/.config/fish/config.fish"
    _check_file "$HOME/.config/starship.toml"
    _check_file "$HOME/.zshrc"
    _check_file "$HOME/.config/fastfetch/kwk-logo.txt"
    _check_file "$HOME/.config/fastfetch/config.jsonc"
    _check_dir  "$HOME/.vim/bundle/ale"
    _check_dir  "$HOME/.vim/autoload"

    info "── NVIDIA ──"
    if pacman -Qq 2>/dev/null | grep -qE '^nvidia'; then
        ok "NVIDIA driver package present"
    else
        info "No NVIDIA driver installed (OK if no NVIDIA GPU present)"
    fi

    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  Validation complete — ${warnings} warning(s)"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  MAIN                                                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
main() {
    banner "KODE WITH KEVIN — ARCH GNOME CONFIG v${SCRIPT_VERSION}"

    preflight

    install_base_packages       || record_error "Base packages" $?
    install_aur_helpers         || record_error "AUR helpers (yay/paru/pacseek/rtk)" $?
    install_nerd_fonts          || record_error "Nerd Fonts" $?
    install_dotnet              || record_error ".NET SDK" $?
    install_python              || record_error "Python 3.13 + uv" $?
    install_nodejs              || record_error "Node.js + npm" $?
    install_rust                || record_error "Rust" $?
    install_steam               || record_error "Steam" $?
    setup_nvidia                || record_error "NVIDIA drivers" $?
    install_headroom_ai         || record_error "Headroom AI" $?
    configure_zsh_shell         || record_error "ZSH default shell" $?
    run_material_rice           || record_error "Material You GNOME rice" $?
    run_rambox_fix              || record_error "Rambox" $?
    run_vim_ide_setup           || record_error "Vim IDE setup" $?
    configure_neovim            || record_error "NeoVim config" $?
    configure_kitty             || record_error "Kitty config" $?
    install_fish_shell          || record_error "Fish shell" $?
    configure_starship_and_history || record_error "Starship + history/autocomplete stack" $?
    deploy_zshrc                || record_error ".zshrc deployment" $?
    configure_fastfetch_logo    || record_error "Fastfetch KWK logo" $?

    validate_installation || true

    banner "Setup Complete!"
    cat <<ENDMSG
  Installed:
     Base dev tools · yay + paru · pacseek · rtk (rust token killer)
     .NET SDK · Python 3.13 + uv · Node.js/npm · Rust (stable)
     Steam · NVIDIA drivers (if GPU detected) · headroom-ai (uv tool)
     Nerd Fonts (JetBrainsMono, FiraCode, Cascadia Code, Hack, Meslo, Iosevka)
     ZSH set as default shell
     Material You GNOME rice (theme, wallpaper, extensions)
     Rambox (installed + GNOME launcher fixed)
     Vim + NeoVim IDE (shared pathogen stack, per VIM_IDE_Setup.pdf)
     Kitty — JetBrainsMono Nerd Font 14pt, Konsole/Garuda Mocha + material feel
     Fish shell — Starship + fzf/atuin history (Nerd Font via Kitty, 14pt)
     Starship prompt (Catppuccin Mocha) + zsh-autosuggestions/syntax-highlighting/
       history-substring-search/fzf-tab/atuin — wired into ~/.zshrc
     ~/.zshrc deployed (aliases, functions, Bible verse after fastfetch)
     Fastfetch — custom KodeWithKevin (KWK) ASCII logo

  Log: ${LOGFILE}
ENDMSG

    if [[ ${#SCRIPT_ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}  The following sections reported errors:${NC}"
        for err in "${SCRIPT_ERRORS[@]}"; do
            echo -e "${RED}    - ${err}${NC}"
        done
        echo ""
    fi

    if [[ "$REBOOT_REQUIRED" == "true" ]]; then
        echo -e "${YELLOW}${BOLD}  ⚠  REBOOT REQUIRED (NVIDIA driver install)${NC}"
    fi

    echo -e "${YELLOW}  Log out/in for the zsh default shell and GNOME theme to fully apply.${NC}"
    echo ""
    cleanup_sudo_keepalive
}

# ── CLI ───────────────────────────────────────────────────────────────────────
case "${1:-}" in
    --dry-run)  DRY_RUN=true; main ;;
    --validate) mkdir -p "$(dirname "$LOGFILE")"; touch "$LOGFILE"; validate_installation ;;
    --help|-h)
        echo "Usage: ./KodeWithKevinArchGnomeConfig.sh [--dry-run|--validate|--help]"
        exit 0
        ;;
    "") main ;;
    *) echo "Unknown: $1 (try --help)" >&2; exit 1 ;;
esac
