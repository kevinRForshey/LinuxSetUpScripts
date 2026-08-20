#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  KevinsCachyPlasmaAndCatppuccinV1.sh                                     ║
# ║  CachyOS · install KDE Plasma (X11) + Catppuccin Mocha/Mauve theme      ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# A scoped-down extract of KevinsCachyPlasmaConfigurationV1.sh: JUST Plasma
# and the Catppuccin theme, none of the dev-tools/Rambox/Claude steps. Same
# two-phase, checkpointed design as that script, for the same reason — do not
# collapse this back into one unattended pass.
#
# PHASE 1 (runs once, then the script stops on purpose):
#   1. Base prerequisites (git, curl, wget, unzip)
#   2. A Btrfs/snapper snapshot, if available, before touching anything
#      display-related — a real rollback option, not just a warning
#   3. KDE Plasma (X11 session) installed as an ADDITIONAL session in your
#      existing GDM login screen — GDM/GNOME itself is left completely alone
#
# >>> STOPS HERE. Log out, pick "Plasma (X11)" from the GDM session menu,
#     confirm you get a working desktop, THEN re-run this exact script. <<<
#
# PHASE 2 (only runs once Phase 1 is confirmed working):
#   4. Catppuccin Mocha (Mauve accent) Plasma theme — global theme, cursors,
#      splash screen, Aurorae window decoration
#
# Why the split: applying a global theme is itself a Plasma-shell-affecting
# change. Doing it before you've confirmed Plasma even renders stacks two
# unverified changes on top of each other — exactly the situation that led
# to a blank screen and a reinstall last time. Confirm Plasma works first,
# THEN theme it, from inside a session you already know is fine.
#
# NVIDIA driver setup is intentionally NOT in this script — see
# KevinsCachyPlasmaConfigurationV1.sh if you need that too. Phase 1 here
# defaults to the Plasma X11 session specifically so you don't need it just
# to verify Plasma renders (X11 doesn't need nvidia_drm.modeset=1 the way
# Wayland does).
#
# Safe to re-run: every step checks for existing installs/files first.
# Designed for CachyOS/Arch, currently running GNOME.
#
# Error handling: `set -e` stays on as a backstop, but every step that can
# fail for a reason that ISN'T "the script itself is broken" (network hiccup,
# renamed/missing AUR package, an already-installed conflict, no write
# permission on one file) is caught explicitly, logged as a warning, and
# collected. The script keeps going past those. Only the two preflight checks
# right below (running as root, no pacman) are treated as fatal, because
# nothing past that point can work without them. Every collected warning is
# printed as a numbered list at the end — see print_summary/main.

set -euo pipefail

WARNINGS=()
PHASE1_MARKER="$HOME/.cache/kevins-cachy-plasma-catppuccin-setup.phase1-done"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
ok()   { printf '  \033[1;32m+\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$1" >&2; WARNINGS+=("$1"); }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$1" >&2; }

if [[ $EUID -eq 0 ]]; then
    err "Run this as your normal user, not root — it calls sudo itself where needed."
    exit 1
fi

if ! command -v pacman &>/dev/null; then
    err "pacman not found — this script targets CachyOS/Arch only."
    exit 1
fi

# ── 0. Base prerequisites ───────────────────────────────────────────────────
ensure_base_deps() {
    log "Installing base prerequisites"
    sudo pacman -S --needed --noconfirm git curl wget unzip \
        || { warn "Base prerequisite install failed — later steps that need git/curl/wget/unzip may fail too. Retry: sudo pacman -S git curl wget unzip"; return 1; }
    ok "base prerequisites present"
}

# ── Snapshot checkpoint ──────────────────────────────────────────────────────
# CachyOS ships snap-pac by default, which already snapshots around every
# pacman transaction — so recovery from this exact class of problem (a
# misconfiguration that leaves you at a blank screen) is normally a Limine
# boot-menu "Snapshots" -> restore away, not a reinstall. This adds one more,
# clearly-labeled manual snapshot right before the display-stack changes so
# there's an obvious single point to roll back to if anything looks wrong
# after picking the new Plasma session.
snapshot_checkpoint() {
    if ! command -v snapper &>/dev/null; then
        warn "snapper not found — no automatic rollback snapshot was taken before installing Plasma. If this is a Btrfs install, consider 'sudo pacman -S snapper snap-pac' first; if not, just proceed carefully."
        return 0
    fi
    if ! snapper list-configs 2>/dev/null | grep -q '^root'; then
        warn "snapper is installed but has no 'root' config — no snapshot was taken. Check 'snapper list-configs'."
        return 0
    fi
    log "Creating a snapshot checkpoint before touching the display stack"
    if sudo snapper create --type single --description "before install_plasma (KevinsCachyPlasmaAndCatppuccinV1.sh)" &>/dev/null; then
        ok "Snapshot created. If Plasma doesn't render after you log out: reboot, pick the 'Snapshots' entry in the Limine boot menu, find the one described above (or just 'sudo snapper list'), and restore it — no reinstall needed."
    else
        warn "snapper create failed — proceeding without a fresh checkpoint snapshot (snap-pac's automatic pre/post-pacman snapshots still apply, see 'sudo snapper list')."
    fi
}

# ── 1. KDE Plasma (added alongside your existing GNOME/GDM, not replacing it) ──
install_plasma() {
    log "Installing KDE Plasma (X11 session)"
    # plasma-x11-session + kwin-x11 are called out separately because Arch's
    # base Plasma packaging dropped the X11 session as a default a while back
    # (KDE split it into its own package) — without these you'd only get a
    # Wayland session offered, and Wayland is the pairing most associated with
    # NVIDIA blank-screen reports, which is exactly what we're trying to avoid
    # verifying for the first time.
    #
    # Deliberately NOT installing cachyos-kde-settings: it hard-conflicts with
    # cachyos-gnome-settings (CachyOS's own desktop-settings packages are
    # mutually exclusive, one per DE, by design) — installing it would mean
    # either removing something from your live GNOME session or aborting.
    # It's also just CachyOS's skel/wallpaper opinions for KDE, not required
    # for a working Plasma session, and Catppuccin is about to override the
    # visual defaults anyway.
    #
    # `yes '' |` guards against pacman's "multiple providers available"
    # prompt (e.g. for tessdata, pulled in transitively by something in
    # plasma-meta) — that prompt isn't governed by --noconfirm, so without
    # this it can sit waiting for input in a context where nothing's there
    # to answer it. An empty line picks the shown default every time.
    if ! yes '' | sudo pacman -S --needed --noconfirm \
        plasma-meta plasma-x11-session kwin-x11 konsole dolphin
    then
        warn "Plasma package install failed — GNOME is untouched either way. Retry: sudo pacman -S plasma-meta plasma-x11-session kwin-x11 konsole dolphin"
        return 1
    fi
    ok "Plasma installed"

    # Defensive check, not an action: we deliberately never install or enable
    # sddm here, specifically so there's only ever one display manager running
    # — GDM. Two enabled display managers fighting over :0 is itself a classic
    # cause of a blank screen at boot, so if some dependency enabled sddm
    # anyway, undo that rather than leave two active.
    if systemctl is-enabled sddm.service &>/dev/null; then
        warn "sddm.service got enabled as a side effect of installing Plasma — disabling it so gdm.service stays the only active display manager."
        sudo systemctl disable sddm.service &>/dev/null \
            || warn "Could not disable sddm.service — run 'systemctl status sddm gdm' before logging out to confirm only gdm is enabled."
    fi
    if systemctl is-enabled gdm.service &>/dev/null; then
        ok "gdm.service confirmed as the only enabled display manager"
    else
        warn "gdm.service isn't showing as enabled — that would leave you without a login screen. Run 'sudo systemctl enable gdm.service' before rebooting."
    fi

    ok "Plasma (X11) is now selectable from the session menu on your existing GDM login screen (the gear/settings icon next to the password field) — GDM itself was not touched."
}

# ── 2. Catppuccin Plasma theme ──────────────────────────────────────────────
install_catppuccin_plasma() {
    log "Installing Catppuccin Mocha (Mauve accent) Plasma theme"
    sudo pacman -S --needed --noconfirm kde-cli-tools kpackage plasma-workspace \
        || warn "kde-cli-tools/kpackage/plasma-workspace install failed — lookandfeeltool/plasma-apply-lookandfeel/kpackagetool6 (all needed by the theme installer below) may already be present from your Plasma install, so trying anyway."

    local tmp; tmp=$(mktemp -d)
    if ! git clone --depth=1 --quiet https://github.com/catppuccin/kde.git "$tmp/catppuccin-kde"; then
        warn "Could not clone catppuccin/kde (network issue?) — skipping Plasma theming entirely. Retry: git clone https://github.com/catppuccin/kde.git"
        rm -rf "$tmp"
        return 1
    fi
    (
        cd "$tmp/catppuccin-kde"
        # Flavour 1 = Mocha, Accent 4 = Mauve, WindowDec 1 = Modern — matches
        # your existing Catppuccin Mocha/Mauve rice. Change these three
        # numbers for a different combo (see the repo README for the full
        # 1-14 accent list).
        #
        # The upstream README documents a trailing "auto" arg to skip prompts,
        # but reading install.sh's actual control flow, an unrecognized 4th
        # arg falls through without setting confirmation and exits without
        # installing anything. Piping "y\ny" answers the two real y/N prompts
        # (confirm install, then confirm apply) instead — verified against
        # the script's source, so this is the version that's actually known
        # to install and apply the theme non-interactively.
        printf 'y\ny\n' | ./install.sh 1 4 1
    ) || { warn "catppuccin/kde's install.sh failed partway through — Plasma theme may be partially applied. Re-run this script (it's the git-clone-and-run step, safe to retry) or run it by hand from a fresh clone of https://github.com/catppuccin/kde"; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"

    ok "Catppuccin Plasma theme applied. Log out/in (or restart plasmashell) if anything looks half-applied."
}

print_phase1_summary() {
    cat <<'SUMMARY'

==============================================================================
 Phase 1 done: Plasma (X11) is installed as an EXTRA session option. GDM and
 your current GNOME session were not touched or disabled.

 >>> NEXT STEPS — do these before re-running this script <<<
   1. Log out of GNOME.
   2. At the GDM login screen, click the gear/settings icon near the
      password field and choose "Plasma (X11)".
   3. Log in and confirm you get a working desktop.
   4. If it's blank or broken: reboot, choose "Snapshots" in the Limine boot
      menu, pick the checkpoint snapshot from just before this run (see the
      snapshot message above, or 'sudo snapper list'), and restore it — GDM
      and GNOME come back exactly as they are right now. No reinstall needed.
   5. Once Plasma (X11) is confirmed working, log into it and re-run this
      exact script from a terminal there to apply the Catppuccin theme.
==============================================================================
SUMMARY

    if [ "${#WARNINGS[@]}" -gt 0 ]; then
        echo ""
        echo "Phase 1 completed with ${#WARNINGS[@]} non-fatal warning(s):"
        local i=1 w
        for w in "${WARNINGS[@]}"; do
            printf '  %2d. %s\n' "$i" "$w"
            i=$((i + 1))
        done
    else
        echo ""
        echo "Phase 1 completed with no warnings."
    fi
}

print_phase2_summary() {
    cat <<'SUMMARY'

==============================================================================
 All done. Log out/in (or run `plasmashell --replace`) to see the Catppuccin
 theme applied everywhere.
==============================================================================
SUMMARY

    if [ "${#WARNINGS[@]}" -gt 0 ]; then
        echo ""
        echo "Phase 2 completed with ${#WARNINGS[@]} non-fatal warning(s):"
        local i=1 w
        for w in "${WARNINGS[@]}"; do
            printf '  %2d. %s\n' "$i" "$w"
            i=$((i + 1))
        done
    else
        echo ""
        echo "Phase 2 completed with no warnings."
    fi
}

# Runs one step, and — only if that step failed without already logging its
# own specific warning — adds a generic fallback warning so nothing fails
# silently. This is what keeps `set -e` from taking down the whole script:
# the step's exit status is being tested here (as the left side of an if),
# which exempts it from -e's abort-on-error behavior.
run_step() {
    local name="$1"; shift
    local before=${#WARNINGS[@]}
    if ! "$@"; then
        if [ "${#WARNINGS[@]}" -eq "$before" ]; then
            warn "$name failed with no specific error captured — check the output above it. Re-run the script to retry (every step is idempotent)."
        fi
    fi
}

main() {
    sudo -v

    if [ ! -f "$PHASE1_MARKER" ]; then
        log "PHASE 1: install Plasma + safety checkpoint"
        run_step "ensure_base_deps"    ensure_base_deps
        run_step "snapshot_checkpoint" snapshot_checkpoint

        # install_plasma is called directly, not via run_step: run_step
        # deliberately swallows failures so the script can keep going past
        # non-critical steps, but this IS the critical step for Phase 1 —
        # if it fails, there's nothing installed yet to log into, and the
        # checkpoint marker below must not get written.
        if install_plasma; then
            mkdir -p "$(dirname "$PHASE1_MARKER")"
            touch "$PHASE1_MARKER"
            print_phase1_summary
        else
            echo ""
            err "Phase 1 did NOT complete — Plasma wasn't actually installed (see the error above). There's nothing to log into yet."
            echo "Fix the issue above, then re-run this script — it'll retry Phase 1 from scratch (no checkpoint was written)."
            if [ "${#WARNINGS[@]}" -gt 0 ]; then
                echo ""
                echo "Warnings so far:"
                local i=1 w
                for w in "${WARNINGS[@]}"; do
                    printf '  %2d. %s\n' "$i" "$w"
                    i=$((i + 1))
                done
            fi
        fi
        exit 0
    fi

    log "PHASE 2: apply the Catppuccin theme (Phase 1 already confirmed done)"
    run_step "ensure_base_deps"          ensure_base_deps
    run_step "install_catppuccin_plasma" install_catppuccin_plasma
    print_phase2_summary
}

main "$@"