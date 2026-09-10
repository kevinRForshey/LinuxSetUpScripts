# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  .zshrc — Kevin's CachyOS Dev Shell · Catppuccin Mocha · Bible Verses        ║
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
zstyle ':completion:*'              menu no            # fzf-tab owns the menu (see end of file)
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
alias hyprconf='vim ~/.config/hypr/hyprland.conf'
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

# Daily Bible wisdom — random verse (World English Bible, public domain)
VERSE=$(curl -s --max-time 4 https://bible-api.com/data/web/random \
        | jq -r '.random_verse |
                 "\(.text | gsub("[\n\r]+"; " ") | gsub("^ +| +$"; "")) — \(.book) \(.chapter):\(.verse)"' \
                 2>/dev/null)
[ -n "$VERSE" ] && echo "$VERSE" | cowsay

# ── Starship prompt ───────────────────────────────────────────────────────────
eval "$(starship init zsh)"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  HISTORY-DRIVEN AUTOCOMPLETE — loaded LAST so its keybindings win            ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  Install once:                                                               ║
# ║    sudo pacman -S --needed zsh-autosuggestions zsh-syntax-highlighting \      ║
# ║                            zsh-history-substring-search fzf atuin            ║
# ║    paru -S --needed zsh-fzf-tab-git                                           ║
# ║    atuin import auto                                                          ║
# ║                                                                              ║
# ║  compinit already ran in the Completion section above — not re-run here.    ║
# ║  Every source is guarded; a wrong path = that feature silently off, not a   ║
# ║  broken prompt. Missing a feature? Check: ls /usr/share/zsh/plugins/        ║
# ║  These intentionally override the ↑/↓ and ^R bindings set earlier.          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# fzf-tab — fuzzy Tab menu (must load AFTER compinit, BEFORE syntax-highlighting)
if [[ -f /usr/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh ]]; then
    source /usr/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh
    zstyle ':fzf-tab:*' fzf-flags \
        --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
        --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
        --color=marker:#a6e3a1,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
    zstyle ':fzf-tab:*' switch-group ',' '.'
fi

# zsh-autosuggestions — inline ghost text (→ accepts, Ctrl+Space also accepts)
if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#7f849c'      # Overlay1 (muted)
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    bindkey '^ ' autosuggest-accept
fi

# zsh-syntax-highlighting — colour as you type (load near the end)
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# zsh-history-substring-search — ↑/↓ prefix search (load AFTER syntax-highlighting)
if [[ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
    HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=#cba6f7,fg=#1e1e2e,bold'   # Mauve
    HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=#f38ba8,fg=#1e1e2e'    # Red
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
    bindkey -M vicmd 'k' history-substring-search-up
    bindkey -M vicmd 'j' history-substring-search-down
fi

# atuin — SQLite fuzzy Ctrl+R. --disable-up-arrow leaves ↑ to substring-search above.
if command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init zsh --disable-up-arrow)"
fi
