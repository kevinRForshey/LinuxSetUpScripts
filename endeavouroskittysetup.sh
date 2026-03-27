#!/usr/bin/env bash
# ============================================================
#   EndeavourOS Terminal Rice Setup
#   Zsh + Kitty + Starship + Catppuccin Mocha
#   Fastfetch + Chuck Norris cowsay + Linus Cow
#
#   EndeavourOS is Arch-based so everything installs via
#   pacman — no PPAs, no manual .deb files, no git clones.
#   yay is pre-installed on EndeavourOS for AUR access.
# ============================================================

set -euo pipefail

# ── Colors for script output ─────────────────────────────────
MAUVE='\033[38;2;203;166;247m'
GREEN='\033[38;2;166;227;161m'
RED='\033[38;2;243;139;168m'
YELLOW='\033[38;2;249;226;175m'
RESET='\033[0m'

info()    { echo -e "${MAUVE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

# ── Must not run as root ──────────────────────────────────────
if [[ "$EUID" -eq 0 ]]; then
  error "Do not run this script as root. Run as your normal user."
fi

echo ""
echo -e "${MAUVE}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${MAUVE}║   EndeavourOS Terminal Rice — Catppuccin Mocha Setup  ║${RESET}"
echo -e "${MAUVE}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# ════════════════════════════════════════════════════════════
# STEP 1 — System update
# ════════════════════════════════════════════════════════════
info "Updating system packages..."
sudo pacman -Syu --noconfirm --quiet
success "System updated"

# ════════════════════════════════════════════════════════════
# STEP 2 — Install all packages via pacman
#
# EndeavourOS / Arch differences vs Ubuntu:
#   - bat       → just 'bat' (no batcat symlink needed)
#   - lsd       → in official repos
#   - fastfetch → in official repos (no PPA needed)
#   - starship  → in official repos (no curl script needed)
#   - zsh plugins → all three in official repos
#   - nerd font → ttf-jetbrains-mono-nerd in official repos
#   - yay       → pre-installed on EndeavourOS
# ════════════════════════════════════════════════════════════
info "Installing packages via pacman..."

sudo pacman -S --noconfirm --needed \
  zsh \
  kitty \
  curl \
  wget \
  git \
  unzip \
  jq \
  cowsay \
  tree \
  bat \
  btop \
  fzf \
  lolcat \
  lsd \
  fastfetch \
  zsh-autosuggestions \
  zsh-syntax-highlighting \
  zsh-history-substring-search \
  ttf-jetbrains-mono-nerd \
  starship \
  neovim

success "All packages installed"

# ════════════════════════════════════════════════════════════
# STEP 3 — Set zsh as default shell
# ════════════════════════════════════════════════════════════
ZSH_PATH="$(which zsh)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"

if [[ "$CURRENT_SHELL" == "$ZSH_PATH" ]]; then
  warn "zsh is already your default shell"
else
  info "Setting zsh as your default shell..."
  chsh -s "$ZSH_PATH"
  success "Default shell set to $ZSH_PATH (takes effect on next login)"
fi

# ════════════════════════════════════════════════════════════
# STEP 4 — Kitty config
# Full Catppuccin Mocha theme, JetBrainsMono Nerd Font size 14
# Ctrl+C = copy_or_interrupt, Ctrl+V = paste, Ctrl+Q = close tab
# ════════════════════════════════════════════════════════════
info "Writing Kitty config..."
mkdir -p "$HOME/.config/kitty"

if [[ -f "$HOME/.config/kitty/kitty.conf" ]]; then
  cp "$HOME/.config/kitty/kitty.conf" \
     "$HOME/.config/kitty/kitty.conf.bak.$(date +%Y%m%d_%H%M%S)"
  warn "Existing kitty.conf backed up"
fi

cat > "$HOME/.config/kitty/kitty.conf" << 'KITTY'
# ============================================================
#   Kitty — Catppuccin Mocha Rice
#   JetBrainsMono Nerd Font 14 | Ctrl+C copy | Ctrl+V paste
# ============================================================

# --- Font ---
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        14.0

# --- Transparency & Background ---
background_opacity 0.88
dynamic_background_opacity yes
background_blur 32

# --- Catppuccin Mocha Palette ---
foreground              #CDD6F4
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #F5C2E7

cursor                  #F5E0DC
cursor_text_color       #1E1E2E

url_color               #F5C2E7

# Black
color0  #45475A
color8  #585B70

# Red
color1  #F38BA8
color9  #F38BA8

# Green
color2  #A6E3A1
color10 #A6E3A1

# Yellow
color3  #F9E2AF
color11 #F9E2AF

# Blue
color4  #89B4FA
color12 #89B4FA

# Magenta
color5  #F5C2E7
color13 #F5C2E7

# Cyan
color6  #94E2D5
color14 #94E2D5

# White
color7  #BAC2DE
color15 #A6ADC8

# --- Tab bar ---
active_tab_foreground   #1E1E2E
active_tab_background   #CBA6F7
inactive_tab_foreground #CDD6F4
inactive_tab_background #313244
tab_bar_style           powerline
tab_powerline_style     slanted
tab_bar_edge            bottom
tab_title_template      " {index}: {title} "

# --- Window ---
window_padding_width    10
hide_window_decorations no
remember_window_size    yes
initial_window_width    1200
initial_window_height   700

active_border_color   #CBA6F7
inactive_border_color #45475A

# --- Scrollback ---
scrollback_lines 10000

# --- Bell ---
enable_audio_bell    no
visual_bell_duration 0

# ============================================================
#   Keybindings
# ============================================================

clear_all_shortcuts yes

# --- Font size ---
map ctrl+shift+equal     change_font_size all +1.0
map ctrl+shift+minus     change_font_size all -1.0
map ctrl+shift+backspace change_font_size all 0

# --- Copy / Paste ---
# copy_or_interrupt: copies when text selected, sends SIGINT when nothing selected
map ctrl+c copy_or_interrupt
map ctrl+v paste_from_clipboard

# --- Tabs ---
map ctrl+t          new_tab_with_cwd
map ctrl+q          close_tab
map ctrl+shift+,    set_tab_title
map ctrl+tab        next_tab
map ctrl+shift+tab  previous_tab

# Switch tabs with Ctrl+Number
map ctrl+1  goto_tab 1
map ctrl+2  goto_tab 2
map ctrl+3  goto_tab 3
map ctrl+4  goto_tab 4
map ctrl+5  goto_tab 5
map ctrl+6  goto_tab 6
map ctrl+7  goto_tab 7
map ctrl+8  goto_tab 8
map ctrl+9  goto_tab 9

# --- Windows (splits) ---
map ctrl+p        new_window_with_cwd
map ctrl+shift+w  close_window

# Switch windows with Ctrl+Shift+Number
map ctrl+shift+1  first_window
map ctrl+shift+2  second_window
map ctrl+shift+3  third_window
map ctrl+shift+4  fourth_window
map ctrl+shift+5  fifth_window
map ctrl+shift+6  sixth_window
map ctrl+shift+7  seventh_window
map ctrl+shift+8  eighth_window
map ctrl+shift+9  ninth_window

# Navigate panes with Alt+Arrow
map alt+left  neighboring_window left
map alt+right neighboring_window right
map alt+up    neighboring_window up
map alt+down  neighboring_window down

# Resize panes
map alt+shift+left  resize_window narrower
map alt+shift+right resize_window wider
map alt+shift+up    resize_window taller
map alt+shift+down  resize_window shorter

# Scrollback
map ctrl+shift+k  scroll_line_up
map ctrl+shift+j  scroll_line_down
map ctrl+shift+u  scroll_page_up
map ctrl+shift+d  scroll_page_down
map ctrl+shift+g  scroll_end

# Reload config
map ctrl+shift+r  load_config_file
KITTY

success "Kitty config written to ~/.config/kitty/kitty.conf"

# ════════════════════════════════════════════════════════════
# STEP 5 — Starship config
# Catppuccin Mocha powerline prompt showing: OS, user, dir,
# git branch/status, language runtimes, cmd duration, exit code
# ════════════════════════════════════════════════════════════
info "Writing Starship config..."
mkdir -p "$HOME/.config"

cat > "$HOME/.config/starship.toml" << 'STARSHIP'
# ============================================================
#   Starship — Catppuccin Mocha
# ============================================================

format = """
[░▒▓](surface0)\
$os\
$username\
[](bg:mauve fg:surface0)\
$directory\
[](bg:blue fg:mauve)\
$git_branch\
$git_status\
[](bg:teal fg:blue)\
$nodejs\
$python\
$rust\
$golang\
$java\
$php\
$ruby\
[](fg:teal)\
$fill\
$cmd_duration\
$status\
$line_break\
$character"""

palette = 'catppuccin_mocha'

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
style = "bg:surface0 fg:text"

[os.symbols]
EndeavourOS = " "
Arch        = " "
Linux       = " "

[username]
show_always = true
style_user  = "bg:surface0 fg:text"
style_root  = "bg:surface0 fg:red"
format      = '[ $user ]($style)'

[directory]
style             = "bg:mauve fg:base"
format            = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music"     = " "
"Pictures"  = " "
"Videos"    = " "
"Projects"  = " "

[git_branch]
symbol = " "
style  = "bg:blue fg:base"
format = '[ $symbol$branch ]($style)'

[git_status]
style            = "bg:blue fg:base"
format           = '[$all_status$ahead_behind ]($style)'
conflicted       = "⚡"
ahead            = "⇡${count}"
behind           = "⇣${count}"
diverged         = "⇕⇡${ahead_count}⇣${behind_count}"
untracked        = "?"
stashed          = "$"
modified         = "!"
staged           = "+"
renamed          = "»"
deleted          = "✘"

[nodejs]
symbol = " "
style  = "bg:teal fg:base"
format = '[ $symbol$version ]($style)'

[python]
symbol = " "
style  = "bg:teal fg:base"
format = '[ $symbol$version ]($style)'

[rust]
symbol = " "
style  = "bg:teal fg:base"
format = '[ $symbol$version ]($style)'

[golang]
symbol = " "
style  = "bg:teal fg:base"
format = '[ $symbol$version ]($style)'

[java]
symbol = " "
style  = "bg:teal fg:base"
format = '[ $symbol$version ]($style)'

[php]
symbol = " "
style  = "bg:teal fg:base"
format = '[ $symbol$version ]($style)'

[ruby]
symbol = " "
style  = "bg:teal fg:base"
format = '[ $symbol$version ]($style)'

[fill]
symbol = " "

[cmd_duration]
min_time = 2_000
style    = "fg:yellow"
format   = "[󱦟 $duration ]($style)"

[status]
disabled       = false
symbol         = " "
success_symbol = ""
style          = "fg:red"
format         = "[$symbol$status ]($style)"

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"
vimcmd_symbol  = "[❮](bold mauve)"
STARSHIP

success "Starship config written to ~/.config/starship.toml"

# ════════════════════════════════════════════════════════════
# STEP 6 — Fastfetch config
# ════════════════════════════════════════════════════════════
info "Writing Fastfetch config..."
mkdir -p "$HOME/.config/fastfetch"

cat > "$HOME/.config/fastfetch/config.jsonc" << 'FASTFETCH'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "source": "endeavouros",
    "color": {
      "1": "magenta",
      "2": "blue"
    },
    "padding": {
      "top": 1,
      "left": 2,
      "right": 2
    }
  },
  "display": {
    "separator": "  󰁔  ",
    "color": {
      "keys": "blue",
      "title": "magenta"
    }
  },
  "modules": [
    {
      "type": "title",
      "format": "{user-name}@{host-name}"
    },
    "separator",
    { "type": "os",           "key": " OS"          },
    { "type": "kernel",       "key": " Kernel"      },
    { "type": "host",         "key": "󰌢 Host"        },
    { "type": "bios",         "key": "󰖳 BIOS"        },
    { "type": "uptime",       "key": "󱫐 Uptime"      },
    { "type": "packages",     "key": "󰏗 Packages"    },
    { "type": "shell",        "key": " Shell"       },
    { "type": "terminal",     "key": " Terminal"    },
    { "type": "terminalfont", "key": " Font"        },
    { "type": "de",           "key": " Desktop"     },
    { "type": "wm",           "key": " WM"          },
    { "type": "wmtheme",      "key": " WM Theme"    },
    { "type": "theme",        "key": "󰉼 GTK Theme"   },
    { "type": "icons",        "key": " Icons"       },
    { "type": "cursor",       "key": " Cursor"      },
    { "type": "wallpaper",    "key": "󰸉 Wallpaper"   },
    "separator",
    { "type": "cpu",          "key": " CPU",        "showPeCoreCount": true },
    { "type": "cpuusage",     "key": " CPU Usage"   },
    { "type": "gpu",          "key": "󰍛 GPU"         },
    { "type": "memory",       "key": "󰘚 RAM"         },
    { "type": "swap",         "key": "󰓡 Swap"        },
    { "type": "disk",         "key": "󰋊 Disk",       "folders": "/" },
    { "type": "battery",      "key": " Battery"    },
    { "type": "locale",       "key": " Locale"     },
    { "type": "localip",      "key": "󰩟 Local IP",   "showIpv4": true, "showIpv6": false },
    { "type": "publicip",     "key": "󰖟 Public IP"   },
    { "type": "datetime",     "key": "󰃰 Date/Time",  "format": "%A %d %B %Y — %H:%M" },
    "break",
    { "type": "colors",       "paddingLeft": 2,     "symbol": "circle" }
  ]
}
FASTFETCH

success "Fastfetch config written to ~/.config/fastfetch/config.jsonc"

# ════════════════════════════════════════════════════════════
# STEP 7 — Write .zshrc
# ════════════════════════════════════════════════════════════
info "Writing ~/.zshrc..."

if [[ -f "$HOME/.zshrc" ]]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d_%H%M%S)"
  warn "Existing .zshrc backed up"
fi

cat > "$HOME/.zshrc" << 'ZSHRC'
# ============================================================
#   .zshrc — EndeavourOS Catppuccin Rice
# ============================================================

# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# --- Options ---
setopt AUTO_CD
setopt CORRECT
setopt GLOB_DOTS
setopt NO_BEEP
setopt EXTENDED_GLOB

# --- Completion ---
autoload -Uz compinit
compinit -d ~/.zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{purple}── %d%f'
zstyle ':completion:*:warnings' format '%F{red}No matches%f'

# --- Plugins ---
# EndeavourOS/Arch installs zsh plugins to /usr/share/zsh/plugins/
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh

# History substring search bindings
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# --- Autosuggestion style ---
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#585B70'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# --- Syntax highlighting colors (Catppuccin) ---
ZSH_HIGHLIGHT_STYLES[command]='fg=#89B4FA,bold'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#CBA6F7,bold'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#A6E3A1,bold'
ZSH_HIGHLIGHT_STYLES[function]='fg=#94E2D5,bold'
ZSH_HIGHLIGHT_STYLES[string]='fg=#A6E3A1'
ZSH_HIGHLIGHT_STYLES[path]='fg=#CDD6F4,underline'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#F38BA8,bold'

# ============================================================
#   LSD Aliases — drop-in ls replacement
# ============================================================

alias ls='lsd --group-dirs first'
alias ll='lsd -lah --group-dirs first'
alias la='lsd -a --group-dirs first'
alias l='lsd -l --group-dirs first'
alias lt='lsd --tree --group-dirs first'
alias ltd='lsd --tree --depth 2 --group-dirs first'
alias l3='lsd --tree --depth 3 --group-dirs first'

alias lss='lsd -l --group-dirs first --sizesort'
alias lsm='lsd -l --group-dirs first --timesort'
alias lse='lsd -l --group-dirs first --extensionsort'

alias ld='lsd -l --group-dirs first -d */'
alias lla='lsd -la --group-dirs first'
alias llg='lsd -l --group-dirs first | grep'

alias t2='lsd --tree --depth 2 --group-dirs first'
alias t3='lsd --tree --depth 3 --group-dirs first'
alias t4='lsd --tree --depth 4 --group-dirs first'

# --- Other Aliases ---
alias tree='tree -C'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias cat='bat --style=plain'
alias top='btop'
alias vim='nvim'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# EndeavourOS / Arch package management
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias remove='sudo pacman -Rns'
alias search='pacman -Ss'
alias cleanup='sudo pacman -Sc'
alias orphans='sudo pacman -Rns $(pacman -Qtdq)'

# yay AUR helper (pre-installed on EndeavourOS)
alias yi='yay -S'
alias yu='yay -Syu'
alias ys='yay -Ss'

# --- Keybindings ---
bindkey -e
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line
bindkey '^[[3~'   delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# --- Starship Prompt ---
eval "$(starship init zsh)"

# --- FZF ---
# EndeavourOS/Arch installs fzf keybindings to /usr/share/fzf/
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ]   && source /usr/share/fzf/completion.zsh

export FZF_DEFAULT_OPTS="
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
  --border rounded --prompt '  ' --pointer '' --marker ''
"

# ============================================================
#   chuck_cow_nerdy — Chuck Norris jokes via cowsay + API
#   Catppuccin Mocha themed — no rainbow
# ============================================================
chuck_cow_nerdy() {
  # Try to fetch a nerdy Chuck Norris joke from the API
  local categories=("dev" "science" "money" "food")
  local category="${categories[$(( RANDOM % ${#categories[@]} + 1 ))]}"

  local joke
  joke=$(curl -sf --max-time 3 \
    "https://api.chucknorris.io/jokes/random?category=${category}" \
    | jq -r '.value' 2>/dev/null)

  # Offline fallback jokes — pure nerd
  if [[ -z "$joke" || "$joke" == "null" ]]; then
    local fallbacks=(
      "Chuck Norris doesn't use version control. Files are too afraid to change."
      "Chuck Norris can divide by zero."
      "Chuck Norris compiled Hello World and it said 'Hello, Chuck.'"
      "Chuck Norris's keyboard has no Escape key. Nothing escapes Chuck Norris."
      "Chuck Norris solved the halting problem... by roundhouse kicking the machine."
      "Chuck Norris doesn't push to main. Main pulls from Chuck."
      "Chuck Norris's git log has one commit: 'fixed everything.'"
      "Chuck Norris can do infinite loops in 4 seconds."
      "Chuck Norris doesn't need a debugger. Bugs fix themselves in his presence."
      "Chuck Norris's code never has bugs. It has surprise features."
    )
    joke="${fallbacks[$(( RANDOM % ${#fallbacks[@]} + 1 ))]}"
  fi

  # Cowfiles available on Arch/EndeavourOS cowsay package
  local cows=("vader" "stimpy" "skeleton" "dragon" "mech-and-cow" "vader-koala" "tux" "moose" "stegosaurus" "turtle" "duck" "three-eyes" "ghostbusters" "flaming-sheep" "dragon-and-cow")
  local cow="${cows[$(( RANDOM % ${#cows[@]} + 1 ))]}"

  # Catppuccin Mocha ANSI colors — no lolcat rainbow
  local mauve=$'\033[38;2;203;166;247m'
  local blue=$'\033[38;2;137;180;250m'
  local teal=$'\033[38;2;148;226;213m'
  local green=$'\033[38;2;166;227;161m'
  local subtext=$'\033[38;2;166;173;200m'
  local reset=$'\033[0m'

  local accents=("$mauve" "$blue" "$teal" "$green")
  local accent="${accents[$(( RANDOM % ${#accents[@]} + 1 ))]}"

  echo ""
  cat <(echo "$joke") <(echo "— Chuck Norris") \
    | cowsay -f "$cow" -W 70 \
    | while IFS= read -r line; do
        if [[ "$line" == *"Chuck Norris"* ]]; then
          printf "%s%s%s\n" "$subtext" "$line" "$reset"
        else
          printf "%s%s%s\n" "$accent" "$line" "$reset"
        fi
      done
  echo ""
}

# ============================================================
#   Startup Display — fires in any interactive shell
# ============================================================
if [[ -o interactive ]]; then
  fastfetch
  echo ""
  chuck_cow_nerdy
fi
ZSHRC

success "~/.zshrc written"

# ════════════════════════════════════════════════════════════
# DONE
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║                  Setup Complete!                    ║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${MAUVE}Next steps:${RESET}"
echo -e "  1. ${YELLOW}Log out and back in${RESET} for zsh to become your default shell"
echo -e "  2. Open ${YELLOW}Kitty${RESET} — font, theme and keybindings are all set"
echo -e "  3. Enjoy your rice! 🎉"
echo ""
