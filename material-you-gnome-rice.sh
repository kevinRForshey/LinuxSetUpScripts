#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Material You Rice — GNOME Shell 50 Edition                                ║
# ║  Target: EndeavourOS / Arch-based, GNOME Shell 50.x, Wayland                ║
# ║  Version: 1.0.0                                                            ║
# ║                                                                            ║
# ║  Components:                                                               ║
# ║    • Orchis-Dark GTK + Shell theme, Tela-circle-purple-dark icons,         ║
# ║      Vimix-white-cursors — Indigo/Violet Material Design palette           ║
# ║    • matugen — real Material You color engine, derives the full tonal      ║
# ║      palette from a procedurally generated wallpaper and propagates it     ║
# ║      into GTK4 + Kitty                                                     ║
# ║    • Retuned extensions: rounded-window-corners, blur-my-shell,            ║
# ║      dash-to-dock, tilingshell, burn-my-windows (aura-glow, violet hue)    ║
# ║    • Kitty terminal, colors driven by matugen                              ║
# ║                                                                            ║
# ║  Usage:                                                                    ║
# ║    chmod +x material-you-gnome-rice.sh                                     ║
# ║    ./material-you-gnome-rice.sh             # full install                 ║
# ║    ./material-you-gnome-rice.sh --dry-run   # preview without changes      ║
# ║    ./material-you-gnome-rice.sh --validate  # check install status only    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# IMPORTANT: We intentionally do NOT use "set -e". Every external command is
# handled explicitly so one non-critical failure doesn't silently abort the
# rest of the rice before later sections run.

set -uo pipefail
IFS=$'\n\t'

# ─── Globals ──────────────────────────────────────────────────────────────────

LOGFILE="${HOME}/.local/share/material-you-rice-setup.log"
SCRIPT_VERSION="1.0.0"
DRY_RUN="${DRY_RUN:-false}"
SUDO_KEEPALIVE_PID=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_GEN="${SCRIPT_DIR}/assets/generate-material-wallpaper.py"
WALLPAPER_OUT="${HOME}/Pictures/Wallpapers/material-you-indigo.png"
FORCE_WALLPAPER=false

# Material You Indigo/Violet palette — seeded from the M3 baseline primary #6750A4
GTK_THEME="Orchis-Dark"
ICON_THEME="Tela-circle-purple-dark"
CURSOR_THEME="Vimix-white-cursors"
ACCENT_COLOR="purple"
ACCENT_HUE="258.0"     # HSL hue of the violet seed, used to tune burn-my-windows

# ─── Logging ──────────────────────────────────────────────────────────────────

log() {
    printf '[%s] [INFO]  %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOGFILE"
}

warn() {
    printf '[%s] [WARN]  %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOGFILE" >&2
}

error() {
    printf '[%s] [ERROR] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOGFILE" >&2
}

fatal() {
    error "$*"
    cleanup_sudo_keepalive
    exit 1
}

banner() {
    printf '\n══════════════════════════════════════════════════════════════\n' | tee -a "$LOGFILE"
    printf '  %s\n' "$*" | tee -a "$LOGFILE"
    printf '══════════════════════════════════════════════════════════════\n\n' | tee -a "$LOGFILE"
}

# ─── Sudo keep-alive with proper cleanup ─────────────────────────────────────

start_sudo_keepalive() {
    if [[ "$DRY_RUN" == "true" ]]; then return 0; fi
    (while true; do sudo -n true 2>/dev/null; sleep 55; done) &
    SUDO_KEEPALIVE_PID=$!
    trap cleanup_sudo_keepalive EXIT INT TERM
}

cleanup_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

# ─── Package wrapper (never abort on already-installed) ───────────────────────

pac_install() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] sudo pacman -S --needed --noconfirm $*"
        return 0
    fi
    log "pacman: installing $*"
    local rc=0
    sudo pacman -S --needed --noconfirm "$@" >>"$LOGFILE" 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        warn "pacman returned $rc for: $* (may be already installed or group prompt)"
    fi
    return 0
}

# gsettings against a locally-installed extension's own (uncompiled search-path)
# schema, since it isn't in the default glib schema dirs.
# Usage: ext_gsettings <uuid> <schema> <verb> <key> [value]
ext_gsettings() {
    local uuid="$1" schema="$2" verb="$3"
    shift 3
    local ext_dir="${HOME}/.local/share/gnome-shell/extensions/${uuid}"
    if [[ ! -d "${ext_dir}/schemas" ]]; then
        warn "  schema dir missing for ${uuid}, skipping"
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] gsettings --schemadir ${ext_dir}/schemas ${verb} ${schema} $*"
        return 0
    fi
    gsettings --schemadir "${ext_dir}/schemas" "$verb" "$schema" "$@" >>"$LOGFILE" 2>&1
}

# ─── Preflight ────────────────────────────────────────────────────────────────

preflight() {
    banner "Preflight Checks"

    if [[ $EUID -eq 0 ]]; then
        fatal "Do NOT run as root. Run as your normal user — sudo is called where needed."
    fi

    if [[ ! -f /etc/arch-release ]]; then
        fatal "This script requires an Arch-based distro (EndeavourOS, Arch, etc.)."
    fi

    if ! command -v gnome-shell &>/dev/null; then
        fatal "GNOME Shell not found. This rice targets GNOME Shell 50.x."
    fi

    local gnome_ver
    gnome_ver=$(gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1)
    if [[ -n "$gnome_ver" ]] && [[ "$gnome_ver" -lt 46 ]]; then
        warn "GNOME Shell ${gnome_ver} detected — accent-color / some features need 46+."
    fi

    if [[ ! -f "$WALLPAPER_GEN" ]]; then
        fatal "Missing companion script: ${WALLPAPER_GEN}"
    fi

    log "Kernel: $(uname -r)"
    log "User:   ${USER}"
    log "Home:   ${HOME}"
    log "GNOME:  $(gnome-shell --version 2>/dev/null || echo 'unknown')"

    mkdir -p "$(dirname "$LOGFILE")"
    : > "$LOGFILE"
    log "Log:    ${LOGFILE}"

    if [[ "$DRY_RUN" != "true" ]]; then
        log "Verifying sudo access (password prompt may appear)..."
        sudo -v || fatal "sudo access required."
        start_sudo_keepalive
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 1: Theme Packages
# ═══════════════════════════════════════════════════════════════════════════════

install_theme_packages() {
    banner "Section 1: Theme Packages"

    log "Installing Material You rice stack (official repos only, no AUR)..."
    pac_install orchis-theme tela-circle-icon-theme-all vimix-cursors matugen \
        python-pillow ttf-roboto ttf-jetbrains-mono-nerd fastfetch gnome-tweaks

    log "Theme packages installed."
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 2: Wallpaper Generation
# ═══════════════════════════════════════════════════════════════════════════════

generate_wallpaper() {
    banner "Section 2: Material You Wallpaper"

    if [[ -f "$WALLPAPER_OUT" ]] && [[ "$FORCE_WALLPAPER" != "true" ]]; then
        log "Wallpaper already exists, skipping (use --force-wallpaper to regenerate):"
        log "  ${WALLPAPER_OUT}"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] python3 ${WALLPAPER_GEN} ${WALLPAPER_OUT}"
        return 0
    fi

    log "Generating deterministic Material You mesh-gradient wallpaper..."
    if python3 "$WALLPAPER_GEN" "$WALLPAPER_OUT" >>"$LOGFILE" 2>&1; then
        log "✓ Wallpaper written: ${WALLPAPER_OUT}"
    else
        error "✗ Wallpaper generation failed — see ${LOGFILE}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 3: matugen — derive + propagate the palette
# ═══════════════════════════════════════════════════════════════════════════════

run_matugen() {
    banner "Section 3: matugen — Material You Color Pipeline"

    local matugen_dir="${HOME}/.config/matugen"
    local templates_dir="${matugen_dir}/templates"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would write ${matugen_dir}/config.toml + templates"
        log "[DRY-RUN] matugen image ${WALLPAPER_OUT} -m dark -t scheme-tonal-spot --prefer saturation -c ${matugen_dir}/config.toml"
        return 0
    fi

    mkdir -p "$templates_dir"

    log "Writing matugen kitty template..."
    cat > "${templates_dir}/kitty-colors.conf" <<'KITTYTMPL'
# Auto-generated by matugen — Material You palette
# Regenerate: matugen image <wallpaper>

background              {{colors.background.default.hex}}
foreground               {{colors.on_background.default.hex}}

cursor                    {{colors.primary.default.hex}}
cursor_text_color         {{colors.on_primary.default.hex}}

selection_background      {{colors.primary_container.default.hex}}
selection_foreground      {{colors.on_primary_container.default.hex}}

url_color                 {{colors.tertiary.default.hex}}

active_border_color       {{colors.primary.default.hex}}
inactive_border_color     {{colors.outline.default.hex}}
bell_border_color         {{colors.error.default.hex}}

wayland_titlebar_color    {{colors.background.default.hex}}

active_tab_background     {{colors.primary.default.hex}}
active_tab_foreground     {{colors.on_primary.default.hex}}
inactive_tab_background   {{colors.surface_container.default.hex}}
inactive_tab_foreground   {{colors.on_surface_variant.default.hex}}
tab_bar_background        {{colors.surface_container_lowest.default.hex}}

mark1_background {{colors.primary.default.hex}}
mark1_foreground {{colors.on_primary.default.hex}}
mark2_background {{colors.tertiary.default.hex}}
mark2_foreground {{colors.on_tertiary.default.hex}}
mark3_background {{colors.secondary.default.hex}}
mark3_foreground {{colors.on_secondary.default.hex}}

# black
color0  {{colors.surface_container_lowest.default.hex}}
color8  {{colors.outline_variant.default.hex}}

# red — dynamic (M3 error tone)
color1  {{colors.error.default.hex}}
color9  {{colors.on_error_container.default.hex}}

# green — fixed accent (Material has no native "green" role)
color2  #A6DA95
color10 #C4E7B0

# yellow — fixed accent
color3  #EED49F
color11 #F5E3B3

# blue — dynamic (primary, violet-leaning)
color4  {{colors.primary.default.hex}}
color12 {{colors.on_primary_container.default.hex}}

# magenta — dynamic (tertiary, pink)
color5  {{colors.tertiary.default.hex}}
color13 {{colors.tertiary_container.default.hex}}

# cyan — fixed accent
color6  #8BD5CA
color14 #A8E0D4

# white
color7  {{colors.on_surface_variant.default.hex}}
color15 {{colors.on_background.default.hex}}
KITTYTMPL

    log "Writing matugen GTK4/libadwaita template..."
    cat > "${templates_dir}/gtk4-colors.css" <<'GTK4TMPL'
/* Auto-generated by matugen — Material You palette for libadwaita/GTK4 */
@define-color accent_color {{colors.primary.default.hex}};
@define-color accent_bg_color {{colors.primary.default.hex}};
@define-color accent_fg_color {{colors.on_primary.default.hex}};

@define-color destructive_color {{colors.error.default.hex}};
@define-color destructive_bg_color {{colors.error.default.hex}};
@define-color destructive_fg_color {{colors.on_error.default.hex}};

@define-color success_color #A6DA95;
@define-color warning_color #EED49F;
@define-color error_color {{colors.error.default.hex}};

@define-color window_bg_color {{colors.background.default.hex}};
@define-color window_fg_color {{colors.on_background.default.hex}};

@define-color view_bg_color {{colors.surface_container_lowest.default.hex}};
@define-color view_fg_color {{colors.on_background.default.hex}};

@define-color headerbar_bg_color {{colors.surface_container.default.hex}};
@define-color headerbar_fg_color {{colors.on_surface.default.hex}};
@define-color headerbar_border_color {{colors.outline_variant.default.hex}};
@define-color headerbar_backdrop_color @headerbar_bg_color;
@define-color headerbar_shade_color rgba(0, 0, 0, 0.16);

@define-color card_bg_color {{colors.surface_container.default.hex}};
@define-color card_fg_color {{colors.on_surface.default.hex}};
@define-color card_shade_color rgba(0, 0, 0, 0.20);

@define-color dialog_bg_color {{colors.surface_container_high.default.hex}};
@define-color dialog_fg_color {{colors.on_surface.default.hex}};

@define-color popover_bg_color {{colors.surface_container_highest.default.hex}};
@define-color popover_fg_color {{colors.on_surface.default.hex}};

@define-color shade_color rgba(0, 0, 0, 0.25);
@define-color scrollbar_outline_color {{colors.outline_variant.default.hex}};
GTK4TMPL

    log "Writing ${matugen_dir}/config.toml ..."
    cat > "${matugen_dir}/config.toml" <<TOMLEOF
[config]
mode = "dark"

[templates.kitty]
input_path = "${templates_dir}/kitty-colors.conf"
output_path = "${HOME}/.config/kitty/material-colors.conf"

[templates.gtk4]
input_path = "${templates_dir}/gtk4-colors.css"
output_path = "${HOME}/.config/gtk-4.0/colors.css"
TOMLEOF

    log "Running matugen against the generated wallpaper..."
    if matugen image "$WALLPAPER_OUT" -t scheme-tonal-spot --prefer saturation \
        -c "${matugen_dir}/config.toml" >>"$LOGFILE" 2>&1; then
        log "✓ matugen palette applied to kitty + gtk4"
    else
        error "✗ matugen run failed — see ${LOGFILE}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 4: GNOME Theme Application (gsettings)
# ═══════════════════════════════════════════════════════════════════════════════

apply_gnome_theme() {
    banner "Section 4: GNOME Desktop Theming"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would set gtk-theme, icon-theme, cursor-theme, accent-color,"
        log "[DRY-RUN]   fonts, wm theme, shell theme, wallpaper, flatpak overrides"
        return 0
    fi

    log "Interface settings..."
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface accent-color "$ACCENT_COLOR"
    gsettings set org.gnome.desktop.interface font-name 'Roboto 10'
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 14'

    log "Window manager theme..."
    gsettings set org.gnome.desktop.wm.preferences theme "$GTK_THEME"

    if gnome-extensions list --enabled 2>/dev/null | grep -q 'user-theme@gnome-shell-extensions.gcampax.github.com'; then
        log "Shell theme via user-theme extension..."
        gsettings set org.gnome.shell.extensions.user-theme name "$GTK_THEME"
    else
        warn "user-theme extension not enabled — shell chrome won't pick up ${GTK_THEME}."
    fi

    if [[ -f "$WALLPAPER_OUT" ]]; then
        log "Wallpaper..."
        gsettings set org.gnome.desktop.background picture-uri "file://${WALLPAPER_OUT}"
        gsettings set org.gnome.desktop.background picture-uri-dark "file://${WALLPAPER_OUT}"
        gsettings set org.gnome.desktop.background picture-options 'zoom'
        gsettings set org.gnome.desktop.screensaver picture-uri "file://${WALLPAPER_OUT}"
    else
        warn "No wallpaper found at ${WALLPAPER_OUT} — skipping background gsettings."
    fi

    if command -v flatpak &>/dev/null; then
        log "Flatpak theme overrides..."
        sudo flatpak override --filesystem="${HOME}/.themes" 2>/dev/null || true
        sudo flatpak override --filesystem="${HOME}/.icons" 2>/dev/null || true
        flatpak override --user --filesystem=xdg-config/gtk-4.0 2>/dev/null || true
    fi

    log "GNOME theming applied."
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 5: GTK settings.ini cleanup
# ═══════════════════════════════════════════════════════════════════════════════

configure_gtk_settings() {
    banner "Section 5: GTK 3/4 settings.ini"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would rewrite ~/.config/gtk-3.0/settings.ini and gtk-4.0/settings.ini"
        return 0
    fi

    local gtk3_dir="${HOME}/.config/gtk-3.0"
    local gtk4_dir="${HOME}/.config/gtk-4.0"
    mkdir -p "$gtk3_dir" "$gtk4_dir"

    log "Writing ${gtk3_dir}/settings.ini ..."
    cat > "${gtk3_dir}/settings.ini" <<INIEOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=${GTK_THEME}
gtk-icon-theme-name=${ICON_THEME}
gtk-cursor-theme-name=${CURSOR_THEME}
gtk-font-name=Roboto 10
INIEOF

    log "Writing ${gtk4_dir}/settings.ini ..."
    cat > "${gtk4_dir}/settings.ini" <<INIEOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=${GTK_THEME}
gtk-icon-theme-name=${ICON_THEME}
gtk-cursor-theme-name=${CURSOR_THEME}
gtk-font-name=Roboto 10
INIEOF

    # Ensure gtk.css imports the matugen-generated colors.css (keep any existing
    # rules already in the file, e.g. ripple-animation keyframes — just make sure
    # the @import is present and points at the right file).
    local gtk4_css="${gtk4_dir}/gtk.css"
    if [[ -f "$gtk4_css" ]] && grep -q '@import.*colors.css' "$gtk4_css"; then
        log "gtk.css already imports colors.css — leaving other rules intact."
    else
        log "Prepending @import \"colors.css\" to ${gtk4_css}..."
        local tmp
        tmp=$(mktemp)
        { echo '@import "colors.css";'; echo; [[ -f "$gtk4_css" ]] && cat "$gtk4_css"; } > "$tmp"
        mv "$tmp" "$gtk4_css"
    fi

    [[ -f "${gtk4_dir}/settings.ini" ]] && log "✓ settings.ini written." || error "✗ settings.ini FAILED!"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 6: Extension Retuning
# ═══════════════════════════════════════════════════════════════════════════════

configure_extensions() {
    banner "Section 6: Extension Retuning"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would retune rounded-window-corners, blur-my-shell, dash-to-dock,"
        log "[DRY-RUN]   tilingshell, burn-my-windows"
        return 0
    fi

    log "rounded-window-corners-reborn..."
    ext_gsettings "rounded-window-corners@fxgn" \
        org.gnome.shell.extensions.rounded-window-corners-reborn \
        set global-rounded-corner-settings \
        "{'padding': <{'left': <uint32 1>, 'right': <uint32 1>, 'top': <uint32 1>, 'bottom': <uint32 1>}>, 'keepRoundedCorners': <{'maximized': <true>, 'fullscreen': <false>}>, 'borderRadius': <uint32 20>, 'smoothing': <1.0>, 'borderColor': <(0.518, 0.365, 0.729, 0.6)>, 'enabled': <true>}"
    ext_gsettings "rounded-window-corners@fxgn" \
        org.gnome.shell.extensions.rounded-window-corners-reborn \
        set tweak-kitty-terminal true

    log "blur-my-shell (panel, dash-to-dock, overview)..."
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.panel set blur true
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.panel set sigma 30
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.panel set brightness 0.6
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.panel set customize true
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.panel set color "(0.518, 0.365, 0.729, 0.15)"

    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.dash-to-dock set blur true
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.dash-to-dock set sigma 30
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.dash-to-dock set brightness 0.6
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.dash-to-dock set customize true
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.dash-to-dock set color "(0.518, 0.365, 0.729, 0.15)"

    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.overview set blur true
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.overview set sigma 15
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.overview set brightness 0.75

    log "blur-my-shell (per-app blur behind Kitty — mutter has no Wayland"
    log "  background-blur protocol, so kitty's own background_blur is a"
    log "  no-op under GNOME; this is what actually blurs the desktop"
    log "  behind the transparent kitty window)..."
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.applications set blur true
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.applications set whitelist "['kitty']"
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.applications set customize true
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.applications set sigma 24
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.applications set brightness 0.7
    ext_gsettings "blur-my-shell@aunetx" \
        org.gnome.shell.extensions.blur-my-shell.applications set dynamic-opacity true

    log "dash-to-dock..."
    ext_gsettings "dash-to-dock@micxgx.gmail.com" \
        org.gnome.shell.extensions.dash-to-dock set running-indicator-style 'DOTS'
    ext_gsettings "dash-to-dock@micxgx.gmail.com" \
        org.gnome.shell.extensions.dash-to-dock set apply-glossy-effect false
    ext_gsettings "dash-to-dock@micxgx.gmail.com" \
        org.gnome.shell.extensions.dash-to-dock set transparency-mode 'FIXED'
    ext_gsettings "dash-to-dock@micxgx.gmail.com" \
        org.gnome.shell.extensions.dash-to-dock set dock-position 'BOTTOM'

    log "tilingshell..."
    ext_gsettings "tilingshell@ferrarodomenico.com" \
        org.gnome.shell.extensions.tilingshell set inner-gaps 8
    ext_gsettings "tilingshell@ferrarodomenico.com" \
        org.gnome.shell.extensions.tilingshell set outer-gaps 8
    ext_gsettings "tilingshell@ferrarodomenico.com" \
        org.gnome.shell.extensions.tilingshell set enable-smart-window-border-radius true
    ext_gsettings "tilingshell@ferrarodomenico.com" \
        org.gnome.shell.extensions.tilingshell set window-use-custom-border-color true
    ext_gsettings "tilingshell@ferrarodomenico.com" \
        org.gnome.shell.extensions.tilingshell set window-border-color "'#8A5CF6'"

    log "burn-my-windows (aura-glow profile, tuned to violet hue)..."
    local bmw_ext_dir="${HOME}/.local/share/gnome-shell/extensions/burn-my-windows@schneegans.github.com"
    local bmw_active
    bmw_active=$(gsettings --schemadir "${bmw_ext_dir}/schemas" get org.gnome.shell.extensions.burn-my-windows active-profile 2>/dev/null | tr -d "'")
    if [[ -n "$bmw_active" ]] && [[ -f "$bmw_active" ]]; then
        log "  Writing active profile: ${bmw_active}"
        cat > "$bmw_active" <<BMWEOF
[burn-my-windows-profile]
fire-enable-effect=false
aura-glow-enable-effect=true
aura-glow-random-color=false
aura-glow-start-hue=${ACCENT_HUE}
BMWEOF
    else
        warn "  No active burn-my-windows profile file found — leaving effect selection as-is."
    fi

    log "Extension retuning complete."
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 7: Kitty Terminal Config
# ═══════════════════════════════════════════════════════════════════════════════

configure_kitty() {
    banner "Section 7: Kitty Terminal — Material You"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would write ~/.config/kitty/kitty.conf"
        return 0
    fi

    local kitty_dir="${HOME}/.config/kitty"
    mkdir -p "$kitty_dir"

    log "Writing ${kitty_dir}/kitty.conf ..."
    cat > "${kitty_dir}/kitty.conf" <<'KITTYEOF'
# Kitty Terminal — Material You (colors from matugen, see material-colors.conf)

font_family      JetBrainsMono Nerd Font
bold_font        JetBrainsMono Nerd Font Bold
italic_font      JetBrainsMono Nerd Font Italic
bold_italic_font JetBrainsMono Nerd Font Bold Italic
font_size        14.0
adjust_line_height 110%

# Transparency + blur — Material You "glass surface" feel.
# background_blur only takes effect on compositors that implement the
# Wayland background-blur protocol (currently KDE/KWin); mutter (GNOME)
# does not, so it's a harmless no-op here and the real blur comes from
# blur-my-shell's per-app "applications" whitelist (see configure_extensions
# in this script), which blurs the desktop behind this window instead.
background_opacity         0.82
dynamic_background_opacity yes
background_blur            20

cursor_shape          beam
cursor_beam_thickness 1.5
cursor_blink_interval 0.5
scrollback_lines 10000

window_padding_width  8 12
remember_window_size  yes
initial_window_width  120c
initial_window_height 35c
confirm_os_window_close 0

tab_bar_edge        bottom
tab_bar_style       powerline
tab_powerline_style slanted
tab_bar_min_tabs    2

shell /usr/bin/zsh
enable_audio_bell no
visual_bell_duration 0

# Material You colors — regenerated by `matugen image <wallpaper>`
include material-colors.conf
KITTYEOF

    [[ -f "${kitty_dir}/kitty.conf" ]] && log "✓ kitty.conf written." || error "✗ kitty.conf FAILED!"

    if [[ ! -f "${kitty_dir}/material-colors.conf" ]]; then
        warn "material-colors.conf not found — run_matugen() must run before kitty picks up colors."
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 8: Fastfetch — Material You theme
# ═══════════════════════════════════════════════════════════════════════════════

configure_fastfetch() {
    banner "Section 8: Fastfetch — Material You"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would write ~/.config/fastfetch/config.jsonc"
        return 0
    fi

    local ff_dir="${HOME}/.config/fastfetch"
    mkdir -p "$ff_dir"

    log "Writing ${ff_dir}/config.jsonc ..."
    cat > "${ff_dir}/config.jsonc" <<'FFEOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "source": "auto",
        "padding": { "top": 1, "right": 2 },
        "color": { "1": "#8A5CF6", "2": "#D0BCFF" }
    },
    "display": {
        "separator": "  ",
        "color": { "keys": "#D0BCFF", "title": "#8A5CF6", "output": "#E8DEF8" }
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
FFEOF

    [[ -f "${ff_dir}/config.jsonc" ]] && log "✓ fastfetch config.jsonc written (Material You violet)." || error "✗ fastfetch config FAILED!"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

validate_installation() {
    banner "Validation"

    local errors=0 warnings=0

    _ok()   { log "  ✓ $1"; }
    _fail() { error "  ✗ $1"; ((errors++)) || true; }
    _warn() { warn "  △ $1"; ((warnings++)) || true; }

    _cmd()  { command -v "$2" &>/dev/null && _ok "$1" || _fail "$1: '$2' not found"; }
    _file() { [[ -f "$2" ]] && _ok "$1" || _fail "$1: missing"; }
    _pkg()  { pacman -Qi "$2" &>/dev/null && _ok "$1" || _fail "$1: package '$2' not installed"; }

    log "── Packages ──"
    _pkg "Orchis theme"        orchis-theme
    _pkg "Tela-circle icons"   tela-circle-icon-theme-all
    _pkg "Vimix cursors"       vimix-cursors
    _pkg "matugen"             matugen
    _pkg "python-pillow"       python-pillow
    _pkg "ttf-roboto"          ttf-roboto
    _pkg "ttf-jetbrains-mono-nerd" ttf-jetbrains-mono-nerd
    _pkg "fastfetch"           fastfetch

    log ""
    log "── Commands ──"
    _cmd "matugen" matugen
    _cmd "kitty"   kitty
    _cmd "fastfetch" fastfetch
    _cmd "gsettings" gsettings

    log ""
    log "── Files ──"
    _file "Wallpaper"          "$WALLPAPER_OUT"
    _file "matugen config"     "${HOME}/.config/matugen/config.toml"
    _file "kitty material-colors.conf" "${HOME}/.config/kitty/material-colors.conf"
    _file "kitty.conf"         "${HOME}/.config/kitty/kitty.conf"
    _file "gtk4 colors.css"    "${HOME}/.config/gtk-4.0/colors.css"
    _file "gtk3 settings.ini"  "${HOME}/.config/gtk-3.0/settings.ini"
    _file "gtk4 settings.ini"  "${HOME}/.config/gtk-4.0/settings.ini"
    _file "fastfetch config"   "${HOME}/.config/fastfetch/config.jsonc"

    log ""
    log "── Kitty Transparency/Blur/Font ──"
    if [[ -f "${HOME}/.config/kitty/kitty.conf" ]]; then
        grep -q '^background_opacity' "${HOME}/.config/kitty/kitty.conf" && _ok "background_opacity set" || _fail "background_opacity missing from kitty.conf"
        grep -q '^background_blur' "${HOME}/.config/kitty/kitty.conf" && _ok "background_blur set" || _fail "background_blur missing from kitty.conf"
        grep -q '^font_size *14' "${HOME}/.config/kitty/kitty.conf" && _ok "font_size 14.0" || _fail "font_size is not 14"
    else
        _fail "kitty.conf missing, cannot check transparency/blur/font"
    fi

    log ""
    log "── GNOME Desktop Settings ──"
    if command -v gsettings &>/dev/null; then
        local gtk_theme icon_theme cursor_theme accent mono_font
        gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
        icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
        cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
        accent=$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null | tr -d "'")
        mono_font=$(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null | tr -d "'")

        [[ "$gtk_theme" == "$GTK_THEME" ]] && _ok "gtk-theme: $gtk_theme" || _fail "gtk-theme: got '$gtk_theme', expected '$GTK_THEME'"
        [[ "$icon_theme" == "$ICON_THEME" ]] && _ok "icon-theme: $icon_theme" || _fail "icon-theme: got '$icon_theme', expected '$ICON_THEME'"
        [[ "$cursor_theme" == "$CURSOR_THEME" ]] && _ok "cursor-theme: $cursor_theme" || _fail "cursor-theme: got '$cursor_theme', expected '$CURSOR_THEME'"
        [[ "$accent" == "$ACCENT_COLOR" ]] && _ok "accent-color: $accent" || _fail "accent-color: got '$accent', expected '$ACCENT_COLOR'"
        [[ "$mono_font" == "JetBrainsMono Nerd Font 14" ]] && _ok "monospace-font-name: $mono_font" || _fail "monospace-font-name: got '$mono_font', expected 'JetBrainsMono Nerd Font 14'"
    else
        _fail "gsettings not available"
    fi

    log ""
    log "── Extensions Enabled ──"
    if command -v gnome-extensions &>/dev/null; then
        local enabled
        enabled=$(gnome-extensions list --enabled 2>/dev/null)
        for uuid in rounded-window-corners@fxgn blur-my-shell@aunetx \
            dash-to-dock@micxgx.gmail.com tilingshell@ferrarodomenico.com \
            burn-my-windows@schneegans.github.com \
            user-theme@gnome-shell-extensions.gcampax.github.com; do
            echo "$enabled" | grep -q "^${uuid}$" && _ok "$uuid" || _warn "$uuid not enabled"
        done
    else
        _warn "gnome-extensions command not found — cannot verify extension state"
    fi

    echo ""
    echo "══════════════════════════════════════════════════════════════"
    if [[ $errors -eq 0 ]]; then
        echo "  ✅  PASSED — ${warnings} warning(s), 0 errors"
    else
        echo "  ❌  FAILED — ${errors} error(s), ${warnings} warning(s)"
    fi
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    return "$errors"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    banner "Material You GNOME Rice v${SCRIPT_VERSION} — GNOME Shell 50"

    preflight

    install_theme_packages
    generate_wallpaper
    run_matugen
    apply_gnome_theme
    configure_gtk_settings
    configure_extensions
    configure_kitty
    configure_fastfetch

    validate_installation || true

    banner "Setup Complete!"
    cat <<ENDMSG
  Installed:
     Orchis-Dark (GTK + Shell) · Tela-circle-purple-dark icons
     Vimix-white-cursors · matugen Material You color pipeline
     JetBrainsMono Nerd Font 14pt (system-wide monospace + kitty + fastfetch)
     Retuned: rounded corners, blur-my-shell (shell surfaces + kitty
              per-app blur), dash-to-dock, tilingshell,
              burn-my-windows (aura-glow, violet hue)
     Kitty: 82% background opacity + background blur (real blur comes
            from blur-my-shell's kitty whitelist under GNOME/mutter)
     Fastfetch: Material You violet theme

  Config files:
     ${WALLPAPER_OUT}
     ${HOME}/.config/matugen/config.toml
     ${HOME}/.config/kitty/kitty.conf (+ material-colors.conf)
     ${HOME}/.config/gtk-4.0/colors.css
     ${HOME}/.config/fastfetch/config.jsonc

  Log: ${LOGFILE}

  Note: log out/in (or Alt+F2 → 'r' on X11) for the shell theme and
  accent color to fully apply everywhere.
ENDMSG
    echo ""
    cleanup_sudo_keepalive
}

# ── CLI ───────────────────────────────────────────────────────────────────────
ARGS=("$@")
for arg in "${ARGS[@]}"; do
    case "$arg" in
        --force-wallpaper) FORCE_WALLPAPER=true ;;
    esac
done

case "${1:-}" in
    --dry-run)         DRY_RUN=true; main ;;
    --validate)        mkdir -p "$(dirname "$LOGFILE")"; touch "$LOGFILE"; validate_installation ;;
    --force-wallpaper) main ;;
    --help|-h)
        echo "Usage: ./material-you-gnome-rice.sh [--dry-run|--validate|--force-wallpaper|--help]"
        exit 0
        ;;
    "")                 main ;;
    *)                  echo "Unknown: $1 (try --help)" >&2; exit 1 ;;
esac
