#!/usr/bin/env bash

set -e

echo "==> Updating system..."
sudo pacman -Syu --noconfirm

echo "==> Installing base development tools..."
sudo pacman -S --noconfirm \
  base-devel git curl wget unzip \
  vim neovim \
  nodejs npm \
  python python-pip python-virtualenv \
  dotnet-sdk \
  ripgrep fd \
  fzf \
  ttf-jetbrains-mono-nerd

echo "==> Installing global npm packages..."
sudo npm install -g \
  typescript \
  typescript-language-server \
  vscode-langservers-extracted

echo "==> Installing Python LSP tools..."
pip install --user \
  python-lsp-server \
  pylsp-mypy \
  black \
  flake8 \
  isort

echo "==> Setting up Vim with Pathogen..."
mkdir -p ~/.vim/autoload ~/.vim/bundle

if [ ! -f ~/.vim/autoload/pathogen.vim ]; then
  curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
fi

echo "==> Installing Vim plugins..."

cd ~/.vim/bundle

# NERDTree
if [ ! -d nerdtree ]; then
  git clone https://github.com/preservim/nerdtree.git
fi

# Vim Airline (status bar)
if [ ! -d vim-airline ]; then
  git clone https://github.com/vim-airline/vim-airline.git
fi

# LSP client
if [ ! -d vim-lsp ]; then
  git clone https://github.com/prabirshrestha/vim-lsp.git
fi

# Auto completion
if [ ! -d asyncomplete-vim ]; then
  git clone https://github.com/prabirshrestha/asyncomplete.vim.git asyncomplete-vim
fi

# LSP + completion bridge
if [ ! -d asyncomplete-lsp ]; then
  git clone https://github.com/prabirshrestha/asyncomplete-lsp.vim.git asyncomplete-lsp
fi

# Syntax for JS/TS
if [ ! -d vim-javascript ]; then
  git clone https://github.com/pangloss/vim-javascript.git
fi

if [ ! -d typescript-vim ]; then
  git clone https://github.com/leafgarland/typescript-vim.git
fi

# Python enhancements
if [ ! -d vim-python-pep8-indent ]; then
  git clone https://github.com/Vimjas/vim-python-pep8-indent.git
fi

echo "==> Creating .vimrc..."

cat > ~/.vimrc << 'EOF'
" ========================
" General Settings
" ========================
set nocompatible
filetype plugin indent on
syntax on

execute pathogen#infect()

set number
set norelativenumber

set tabstop=2
set shiftwidth=2
set expandtab
set smartindent

set clipboard=unnamedplus
set hidden
set nowrap

" ========================
" UI
" ========================
set termguicolors

" Airline
let g:airline_powerline_fonts = 1

" ========================
" NERDTree
" ========================
map <C-n> :NERDTreeToggle<CR>
let NERDTreeShowHidden=1

" ========================
" LSP Config
" ========================
if executable('typescript-language-server')
  au User lsp_setup call lsp#register_server({
    \ 'name': 'typescript-language-server',
    \ 'cmd': {server_info->['typescript-language-server', '--stdio']},
    \ 'allowlist': ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'],
    \ })
endif

if executable('pylsp')
  au User lsp_setup call lsp#register_server({
    \ 'name': 'pylsp',
    \ 'cmd': {server_info->['pylsp']},
    \ 'allowlist': ['python'],
    \ })
endif

" ========================
" Completion
" ========================
let g:asyncomplete_auto_popup = 1

" ========================
" Keybindings
" ========================
nnoremap gd :LspDefinition<CR>
nnoremap gr :LspReferences<CR>
nnoremap K :LspHover<CR>

EOF

echo "==> Setting JetBrains Nerd Font as default (may require manual terminal config)..."

echo "==> DONE!"
echo "Restart your terminal and set font to 'JetBrainsMono Nerd Font' in your terminal settings."