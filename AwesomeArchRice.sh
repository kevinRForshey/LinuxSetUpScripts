#!/usr/bin/env bash
set -euo pipefail

echo "🚀 === ARCH ELITE RICE (KITTY EDITION) ==="

log() { echo -e "\033[1;35m[ELITE]\033[0m $1"; }

# -------------------------
# System update
# -------------------------
log "Updating system..."
sudo pacman -Syu --noconfirm

# -------------------------
# Base packages
# -------------------------
log "Installing base packages..."

sudo pacman -S --needed --noconfirm \
  git curl wget unzip base-devel \
  neovim vim \
  python python-pip \
  nodejs npm \
  dotnet-sdk \
  fastfetch cowsay fortune-mod jq \
  lsd \
  zsh \
  kitty \
  ttf-jetbrains-mono-nerd \
  gnome gnome-tweaks gnome-shell-extensions \
  dconf-editor \
  papirus-icon-theme



# -------------------------
# AUR helper (yay)
# -------------------------
if ! command -v yay &>/dev/null; then
  log "Installing yay..."
  cd /tmp
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
fi

# -------------------------
# Catppuccin GTK Theme
# -------------------------
log "Installing Catppuccin GTK..."

mkdir -p ~/.themes
cd ~/.themes

if [ ! -d "catppuccin-gtk" ]; then
  git clone https://github.com/catppuccin/gtk.git catppuccin-gtk
else
  cd catppuccin-gtk && git pull
fi

# -------------------------
# Icons + folders
# -------------------------
log "Configuring icons..."

papirus-folders -C violet || true

# -------------------------
# Cursor
# -------------------------
log "Installing cursor..."

yay -S --noconfirm bibata-cursor-theme

# -------------------------
# ZSH + Starship
# -------------------------
log "Installing shell..."

chsh -s "$(which zsh)"

curl -sS https://starship.rs/install.sh | sh -s -- -y

# -------------------------
# KITTY CONFIG (CATPPUCCIN)
# -------------------------
log "Configuring Kitty..."

mkdir -p ~/.config/kitty

cat > ~/.config/kitty/kitty.conf <<'EOF'
font_family JetBrainsMono Nerd Font
bold_font auto
italic_font auto
font_size 11.0

background_opacity 0.90

# Catppuccin Mocha (Purple vibe)
foreground #CDD6F4
background #1E1E2E
selection_foreground #1E1E2E
selection_background #F5E0DC

color0  #45475A
color1  #F38BA8
color2  #A6E3A1
color3  #F9E2AF
color4  #89B4FA
color5  #CBA6F7
color6  #94E2D5
color7  #BAC2DE
color8  #585B70
color9  #F38BA8
color10 #A6E3A1
color11 #F9E2AF
color12 #89B4FA
color13 #CBA6F7
color14 #94E2D5
color15 #A6ADC8

cursor #F5E0DC
cursor_text_color #1E1E2E
EOF

# -------------------------
# Neovim setup
# -------------------------
log "Setting up Neovim..."

mkdir -p ~/.config/nvim

cat > ~/.config/nvim/init.lua <<'EOF'
vim.g.mapleader = " "

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({"git","clone","https://github.com/folke/lazy.nvim.git", lazypath})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
  { "nvim-tree/nvim-tree.lua" },
})

vim.cmd.colorscheme "catppuccin-mocha"
vim.opt.number = true
vim.opt.termguicolors = true

vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>")
vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>")
EOF

# -------------------------
# ZSH CONFIG
# -------------------------
log "Configuring ZSH..."

if ! grep -q "ELITE ARCH RICE" ~/.zshrc; then
cat <<'EOF' >> ~/.zshrc

# =========================
# ELITE ARCH RICE START
# =========================

eval "$(starship init zsh)"

alias ls='lsd'
alias ll='lsd -l'
alias la='lsd -la'
alias lt='lsd --tree'

# Fastfetch
fastfetch

# Chuck Norris API
JOKE=$(curl -s --max-time 2 https://api.chucknorris.io/jokes/random | jq -r '.value' 2>/dev/null)
[ -n "$JOKE" ] && echo "$JOKE" | cowsay

# =========================
# ELITE ARCH RICE END
# =========================

EOF
fi

# -------------------------
# Apply GNOME theme
# -------------------------
log "Applying GNOME theme..."

gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Mocha-Standard-Purple-Dark" || true
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" || true
gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic" || true

echo "==> Installing Hyprland Elite Mode..."

# -------------------------
# Core Hyprland packages
# -------------------------
sudo pacman -S --needed --noconfirm \
  hyprland \
  waybar \
  wofi \
  wl-clipboard \
  grim slurp \
  swappy \
  brightnessctl \
  network-manager-applet \
  pavucontrol \
  bluez bluez-utils \
  polkit-gnome

# -------------------------
# Enable Bluetooth
# -------------------------
sudo systemctl enable bluetooth --now

# -------------------------
# Hyprland config
# -------------------------
mkdir -p ~/.config/hypr

cat > ~/.config/hypr/hyprland.conf <<'EOF'
# =========================
# ELITE HYPRLAND CONFIG
# =========================

monitor=,preferred,auto,1

# Programs
$terminal = kitty
$menu = wofi --show drun

# Autostart
exec-once = waybar
exec-once = nm-applet
exec-once = blueman-applet

# Input
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
}

# Appearance (Catppuccin Purple)
general {
    gaps_in = 6
    gaps_out = 12
    border_size = 2
    col.active_border = rgba(cba6f7ee)
    col.inactive_border = rgba(585b70aa)
}

decoration {
    rounding = 10
    blur = yes
    blur_size = 6
    blur_passes = 2
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
}

animations {
    enabled = yes
    bezier = ease,0.25,0.1,0.25,1.0

    animation = windows,1,7,ease
    animation = fade,1,7,ease
    animation = workspaces,1,6,ease
}

# Keybinds
$mod = SUPER

bind = $mod, RETURN, exec, kitty
bind = $mod, Q, killactive
bind = $mod, D, exec, $menu
bind = $mod, F, fullscreen
bind = $mod, E, exec, thunar

bind = $mod SHIFT, E, exit

# Move focus
bind = $mod, h, movefocus, l
bind = $mod, l, movefocus, r
bind = $mod, k, movefocus, u
bind = $mod, j, movefocus, d
EOF

# -------------------------
# Waybar config
# -------------------------
mkdir -p ~/.config/waybar

cat > ~/.config/waybar/config <<'EOF'
{
  "layer": "top",
  "position": "top",
  "modules-left": ["hyprland/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["cpu", "memory", "pulseaudio", "network"]
}
EOF

cat > ~/.config/waybar/style.css <<'EOF'
* {
  font-family: JetBrainsMono Nerd Font;
  font-size: 12px;
  color: #cdd6f4;
}

window#waybar {
  background: rgba(30, 30, 46, 0.8);
  border-bottom: 2px solid #cba6f7;
}
EOF

# -------------------------
# Wofi (launcher)
# -------------------------
mkdir -p ~/.config/wofi

cat > ~/.config/wofi/config <<'EOF'
show=drun
prompt=Search...
EOF

cat > ~/.config/wofi/style.css <<'EOF'
window {
  background-color: #1e1e2e;
  border: 2px solid #cba6f7;
  border-radius: 10px;
}
EOF

echo "✅ Hyprland Elite Installed"
echo "👉 Select 'Hyprland' at login screen"

# -------------------------
# DONE
# -------------------------
log "✅ ELITE KITTY SETUP COMPLETE"
echo "👉 Log out and back in"