#!/usr/bin/env bash
#
# Reproduces Kevin's "Vim as a Python IDE" setup (Catppuccin Mocha, CachyOS)
# on a fresh machine/account: system packages, pathogen, all bundled
# plugins, and an identical ~/.vimrc.
#
# Safe to re-run: existing plugin clones are updated in place, and an
# existing ~/.vimrc is backed up (never silently overwritten).

set -euo pipefail

VIM_DIR="$HOME/.vim"
BUNDLE_DIR="$VIM_DIR/bundle"
AUTOLOAD_DIR="$VIM_DIR/autoload"
VIMRC="$HOME/.vimrc"

log() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }

# ── 1. System packages (pacman / Arch-based) ──────────────────────────
if command -v pacman >/dev/null 2>&1; then
    log "Installing system packages via pacman"
    sudo pacman -S --needed --noconfirm \
        vim git ctags fzf nodejs npm ttf-jetbrains-mono-nerd
else
    log "pacman not found — skipping system package install."
    log "Make sure vim, git, ctags, fzf, nodejs/npm, and a Nerd Font are installed manually."
fi

# ── 2. Node-based linters/formatters (ALE: eslint, prettier, typescript-language-server) ─
# typescript-language-server wraps tsserver over LSP; TypeScript 7.x removed
# the standalone tsserver binary that ALE's built-in 'tsserver' linter needs,
# and ALE has no built-in linter for typescript-language-server (checked
# against upstream master), so a custom linter is registered in .vimrc.
if command -v npm >/dev/null 2>&1; then
    log "Installing global npm packages: eslint, prettier, typescript, typescript-language-server"
    sudo npm install -g eslint prettier typescript typescript-language-server
fi

# ── 3. Python LSP stack (ALE: pylsp, black, isort, mypy) ──────────────
if command -v pipx >/dev/null 2>&1; then
    log "Installing python-lsp-server + plugins via pipx"
    pipx install "python-lsp-server[all]" --force
    pipx inject python-lsp-server pylsp-mypy black isort mypy
else
    log "pipx not found — skipping global Python LSP install."
    log "Install manually: pip install 'python-lsp-server[all]' pylsp-mypy black isort mypy"
    log "(or into a project venv — pylsp auto-detects venvs named .venv/venv/env/etc.)"
fi

# ── 4. dotnet SDK check (optional, for C# builds via <F9>/<F10>) ───────
if ! command -v dotnet >/dev/null 2>&1; then
    log "dotnet SDK not found — install it manually if you need C# support."
fi

# ── 5. Vim directory layout ────────────────────────────────────────────
log "Creating ~/.vim directory layout"
mkdir -p "$AUTOLOAD_DIR" "$BUNDLE_DIR" "$VIM_DIR/undodir"

# ── 6. Pathogen ─────────────────────────────────────────────────────────
if [ ! -f "$AUTOLOAD_DIR/pathogen.vim" ]; then
    log "Installing pathogen.vim"
    curl -LSso "$AUTOLOAD_DIR/pathogen.vim" https://tpo.pe/pathogen.vim
else
    log "pathogen.vim already present, skipping"
fi

# ── 7. Plugins (cloned into ~/.vim/bundle) ─────────────────────────────
declare -A PLUGINS=(
    [ale]="https://github.com/dense-analysis/ale"
    [asyncrun-vim]="https://github.com/skywind3000/asyncrun.vim"
    [catppuccin-vim]="https://github.com/catppuccin/vim"
    [emmet-vim]="https://github.com/mattn/emmet-vim"
    [fzf-vim]="https://github.com/junegunn/fzf.vim"
    [indentLine]="https://github.com/Yggdroot/indentLine"
    [nerdtree]="https://github.com/preservim/nerdtree"
    [omnisharp-vim]="https://github.com/OmniSharp/omnisharp-vim"
    [supertab]="https://github.com/ervandew/supertab"
    [tagbar]="https://github.com/preservim/tagbar.git"
    [vim-airline]="https://github.com/vim-airline/vim-airline"
    [vim-airline-themes]="https://github.com/vim-airline/vim-airline-themes"
    [vim-auto-save]="https://github.com/907th/vim-auto-save"
    [vim-commentary]="https://github.com/tpope/vim-commentary"
    [vim-devicons]="https://github.com/ryanoasis/vim-devicons"
    [vim-fugitive]="https://github.com/tpope/vim-fugitive"
    [vim-gitgutter]="https://github.com/airblade/vim-gitgutter"
    [vim-illuminate]="https://github.com/RRethy/vim-illuminate"
    [vim-polyglot]="https://github.com/sheerun/vim-polyglot"
    [vim-razor]="https://github.com/jlcrochet/vim-razor"
    [vim-startify]="https://github.com/mhinz/vim-startify"
    [vim-surround]="https://github.com/tpope/vim-surround"
    [vim-tmux-navigator]="https://github.com/christoomey/vim-tmux-navigator"
    [vim-visual-multi]="https://github.com/mg979/vim-visual-multi"
)

for name in "${!PLUGINS[@]}"; do
    url="${PLUGINS[$name]}"
    dest="$BUNDLE_DIR/$name"
    if [ -d "$dest/.git" ]; then
        log "Updating $name"
        git -C "$dest" pull --ff-only --quiet || log "  (skipped: local changes or diverged history)"
    else
        log "Cloning $name"
        git clone --depth=1 --quiet "$url" "$dest"
    fi
done

# vim-devicons must load after nerdtree/airline; pathogen loads bundle/
# dirs alphabetically so this is just informational, no action needed.

# ── 7b. OmniSharp/Roslyn server (for C# completion via omnisharp-vim) ──
# omnisharp-vim's own installer, run directly rather than via :OmniSharpInstall
# so this script stays non-interactive. Its default -l path (~/.omnisharp/,
# trailing slash) has a bug: it extracts into a dir nested inside itself, then
# rm -rf's the parent before the final mv, deleting its own output. Passing
# -l explicitly without a trailing slash (matching omnisharp-vim's own default
# search path, OmniSharp#util#ServerDir()) avoids it.
OMNISHARP_DIR="$HOME/.omnisharp/omnisharp-roslyn"
if [ -d "$BUNDLE_DIR/omnisharp-vim" ]; then
    if [ ! -x "$OMNISHARP_DIR/run" ]; then
        log "Installing OmniSharp/Roslyn server to $OMNISHARP_DIR"
        "$BUNDLE_DIR/omnisharp-vim/installer/omnisharp-manager.sh" -l "$OMNISHARP_DIR"
    else
        log "OmniSharp/Roslyn server already installed, skipping"
    fi
fi

# ── 8. ~/.vimrc ─────────────────────────────────────────────────────────
if [ -f "$VIMRC" ]; then
    backup="$VIMRC.backup.$(date +%Y%m%d%H%M%S)"
    log "Existing ~/.vimrc found — backing up to $backup"
    cp "$VIMRC" "$backup"
fi

log "Writing ~/.vimrc"
cat > "$VIMRC" <<'VIMRC_EOF'
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
colorscheme catppuccin_mocha

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
\   'python':     ['pylsp'],
\   'javascript': ['eslint'],
\   'typescript': ['eslint', 'typescript-language-server'],
\}

" ALE ships no built-in linter for 'OmniSharp' (checked: not present in
" ale_linters/cs/) so C# diagnostics/completion come from omnisharp-vim
" itself, not ALE. See the ── OmniSharp ── section below.

" ALE's bundled 'tsserver' linter needs the standalone tsserver binary that
" the typescript npm package used to ship in bin/ — TypeScript 7.x removed
" it, and this ALE version (checked against upstream master, no update
" available) has no built-in linter for the replacement,
" typescript-language-server. Register it manually instead.
call ale#linter#Define('typescript', {
\   'name': 'typescript-language-server',
\   'lsp': 'stdio',
\   'executable': 'typescript-language-server',
\   'command': '%e --stdio',
\   'project_root': function('ale#handlers#tsserver#GetProjectRoot'),
\})
let g:ale_fixers = {
\   '*':          ['remove_trailing_lines', 'trim_whitespace'],
\   'python':     ['isort', 'black'],
\   'javascript': ['prettier'],
\   'typescript': ['prettier'],
\   'css':        ['prettier'],
\}
let g:ale_fix_on_save=1
let g:ale_sign_error='✗'
let g:ale_sign_warning='⚠'
let g:airline#extensions#ale#enabled = 1
nmap <silent> [e <Plug>(ale_previous_wrap)
nmap <silent> ]e <Plug>(ale_next_wrap)

" pylsp auto-detects a venv by walking up from the current file looking for
" one of these dir names containing bin/activate (falls back to $VIRTUAL_ENV
" if you activated a venv with a different name before launching vim).
let g:ale_virtualenv_dir_names = ['313venv', '.venv', 'venv', 'env', '.env', 've', 'virtualenv']

let g:ale_python_pylsp_config = {
\   'pylsp': {
\       'plugins': {
\           'jedi_completion': {'enabled': v:true, 'fuzzy': v:true, 'include_params': v:true},
\           'jedi_definition': {'enabled': v:true, 'follow_imports': v:true, 'follow_builtin_imports': v:true},
\           'jedi_hover':      {'enabled': v:true},
\           'jedi_references': {'enabled': v:true},
\           'jedi_symbols':    {'enabled': v:true, 'all_scopes': v:true},
\           'rope_completion': {'enabled': v:true},
\           'rope_rename':     {'enabled': v:true},
\           'pycodestyle':     {'enabled': v:true, 'maxLineLength': 88},
\           'pyflakes':        {'enabled': v:true},
\           'mccabe':          {'enabled': v:false},
\           'pylsp_mypy':      {'enabled': v:true, 'live_mode': v:false, 'strict': v:false},
\           'black':           {'enabled': v:false},
\           'yapf':            {'enabled': v:false},
\           'autopep8':        {'enabled': v:false},
\       },
\   },
\}

" ── LSP completion / navigation (powered by ALE + pylsp/tsserver, OmniSharp for cs) ──
" Completion is triggered manually (<Tab> or '.') rather than as-you-type.
let g:ale_completion_enabled = 0
let g:ale_completion_autoimport = 1
let g:ale_completion_max_suggestions = 50
set omnifunc=ale#completion#OmniFunc
set completeopt=menuone,popup,noinsert,noselect

" Vim's bundled ftplugin/python.vim and ftplugin/javascript.vim call
" setlocal omnifunc=... to their own basic completers, which silently
" overrides the 'set omnifunc' above every time such a buffer loads
" (ftplugins run on FileType, after this vimrc has already been sourced).
" Re-assert ALE's LSP-backed omnifunc afterwards. cs is deliberately
" excluded — omnisharp-vim's own ftplugin already sets omnifunc correctly.
autocmd FileType python,javascript,javascriptreact,typescript,typescriptreact
      \ setlocal omnifunc=ale#completion#OmniFunc

" SuperTab: <Tab> falls through to the omnifunc above (context-aware) instead
" of its undocumented default of buffer-only keyword completion.
let g:SuperTabDefaultCompletionType = "context"
let g:SuperTabContextDefaultCompletionType = "<c-x><c-o>"
let g:SuperTabClosePreviewOnPopupClose = 1

" Also trigger omni-completion automatically after typing '.' (member access).
" (Also fires on numeric literals like 1.5 and on '...' — harmless, since
" completeopt=noselect means nothing auto-inserts; just keep typing or <Esc>.)
function! s:DotComplete() abort
  return pumvisible() ? '' : "\<C-x>\<C-o>"
endfunction
autocmd FileType python,typescript,typescriptreact,cs
      \ inoremap <buffer><silent><expr> . '.' . <SID>DotComplete()

let g:ale_floating_preview = 1
let g:ale_hover_to_floating_preview = 1
let g:ale_detail_to_floating_preview = 1
let g:ale_close_preview_on_insert = 1

nnoremap <silent> <F12>      :ALEGoToDefinition<CR>
nnoremap <silent> <S-F12>    :ALEGoToDefinition -vsplit<CR>
nnoremap <silent> <F11>      :ALEGoToImplementation<CR>
nnoremap <silent> gd         :ALEGoToDefinition<CR>
nnoremap <silent> gD         :ALEGoToDefinition -vsplit<CR>
nnoremap <silent> gr         :ALEFindReferences<CR>
nnoremap <silent> K          :ALEHover<CR>
nnoremap <silent> <leader>rn :ALERename<CR>
nnoremap <silent> <leader>ca :ALECodeAction<CR>
nnoremap <silent> <F8>       :TagbarToggle<CR>

" ── OmniSharp ─────────────────────────────────────────
" omnisharp-vim's own ftplugin (ftplugin/cs/OmniSharp.vim) sets
" omnifunc=OmniSharp#Complete automatically once the server is installed
" (:OmniSharpInstall / installer/omnisharp-manager.sh) — no manual wiring
" needed here, SuperTab and the '.' trigger above call it via <C-x><C-o>.
let g:OmniSharp_server_stdio=1
let g:OmniSharp_highlight_types=3
autocmd FileType cs nmap <silent> gd :OmniSharpGotoDefinition<CR>
autocmd FileType cs nmap <silent> K  :OmniSharpDocumentation<CR>

" ── AsyncRun (background `dotnet` build/run/test → quickfix) ──
" Note on scope: OmniSharp/Roslyn has no Razor/Blazor *markup* LSP for Vim
" (that only exists in Neovim, via roslyn.nvim + rzls.nvim) — so the OmniSharp
" wiring above is the real completion/nav layer for Blazor projects, since
" .razor.cs code-behind files are plain .cs. vim-razor (bundle/vim-razor)
" only adds syntax highlighting + indent for the .razor/.cshtml markup
" itself, not diagnostics or completion inside it.
let g:asyncrun_open = 8

" ── IndentLine ────────────────────────────────────────
let g:indentLine_char='│'
let g:indentLine_color_term=239

" ── Tagbar (code outline, <F8>) ───────────────────────
let g:tagbar_ctags_bin = 'ctags'
let g:tagbar_width = 36
let g:tagbar_autofocus = 1
let g:tagbar_sort = 0

" ── Language Bindings ─────────────────────────────────
autocmd FileType cs         setlocal tabstop=4 shiftwidth=4 expandtab colorcolumn=120
autocmd FileType cs         nnoremap <buffer> <F9>  :AsyncRun -cwd=<root> dotnet run<CR>
autocmd FileType cs         nnoremap <buffer> <F10> :AsyncRun -cwd=<root> dotnet build<CR>
autocmd FileType cs         nnoremap <buffer> <F7>  :AsyncRun -cwd=<root> dotnet test<CR>
autocmd FileType razor      setlocal tabstop=4 shiftwidth=4 expandtab
autocmd FileType javascript,typescript,typescriptreact,javascriptreact
                          \ setlocal tabstop=2 shiftwidth=2 expandtab
autocmd FileType python     setlocal tabstop=4 shiftwidth=4 expandtab colorcolumn=88
autocmd FileType python     nnoremap <buffer> <F9> :!python %<CR>
autocmd FileType html,css,scss,json,yaml
                          \ setlocal tabstop=2 shiftwidth=2 expandtab

" *.razor / *.cshtml filetype detection is handled by vim-razor's own
" ftdetect (sets filetype=razor) — do not override it here.
autocmd BufNewFile,BufRead *.tsx    set filetype=typescriptreact
autocmd BufNewFile,BufRead *.jsx    set filetype=javascriptreact

" ── Custom Commands ───────────────────────────────────
command! StripTrailing :%s/\s\+$//e
command! ReloadVimrc   :source $MYVIMRC | echo "vimrc reloaded"
command! FullPath      :echo expand('%:p')
command! VTerm         :vsplit | terminal
VIMRC_EOF

# ── 9. Generate helptags for every plugin ──────────────────────────────
# Root cause of the old hang: those were interactive `-c` commands run under
# a normal (non-batch) Vim. With 20+ plugins, Helptags' one-line-per-plugin
# output overflows the terminal height and trips Vim's "-- More --" /
# "Press ENTER" pager prompt, which then blocks on stdin forever — invisible
# here since stdout/stderr were sent to /dev/null. `-es` (Ex mode, batch)
# is built for scripting and never pauses for a pager or "hit enter"
# prompt. stdin is also redirected from /dev/null as a second line of
# defense, and output goes to a log file instead of /dev/null so real
# failures are visible instead of silently swallowed.
log "Generating helptags"
HELPTAGS_LOG="$(mktemp)"
if vim -u NONE -es \
       -c 'execute pathogen#infect()' \
       -c 'silent! Helptags' \
       -c 'qa!' \
       < /dev/null > "$HELPTAGS_LOG" 2>&1; then
    rm -f "$HELPTAGS_LOG"
else
    log "Warning: helptag generation reported errors — see $HELPTAGS_LOG"
fi

log "Done. Open vim to verify (:scriptnames to confirm plugins loaded)."
log "Note: python-lsp-server/black/isort/mypy were installed globally via pipx;"
log "project venvs named 313venv/.venv/venv/env/etc. still take priority automatically."
