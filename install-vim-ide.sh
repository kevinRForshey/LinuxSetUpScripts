#!/usr/bin/env bash
# Kevin's Vim IDE bootstrap — Node/Express, .NET (C#/Blazor), Python, Next.js.
# Run from the directory containing this script and its sibling `vimrc`.
set -euo pipefail

VIM_DIR="$HOME/.vim"
BUNDLE_DIR="$VIM_DIR/bundle"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing system packages"
if command -v pacman >/dev/null; then
  sudo pacman -S --needed --noconfirm \
    vim git curl nodejs npm python python-pip dotnet-sdk \
    universal-ctags ripgrep fd pandoc
elif command -v apt-get >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y \
    vim git curl nodejs npm python3 python3-pip dotnet-sdk-8.0 \
    universal-ctags ripgrep fd-find pandoc
else
  echo "!! Unrecognized package manager — install manually: vim git curl nodejs npm python python-pip dotnet-sdk universal-ctags ripgrep fd pandoc" >&2
fi

echo "==> Installing global npm tools (typescript-language-server, eslint, prettier)"
npm list -g typescript typescript-language-server eslint prettier >/dev/null 2>&1 || \
  sudo npm install -g typescript typescript-language-server eslint prettier

echo "==> Installing Python LSP (pylsp) + plugins"
pip3 install --user --break-system-packages \
  "python-lsp-server[all]" pylsp-mypy python-lsp-black python-lsp-isort

echo "==> Bootstrapping pathogen"
mkdir -p "$VIM_DIR/autoload" "$BUNDLE_DIR" "$VIM_DIR/undodir"
curl -LSso "$VIM_DIR/autoload/pathogen.vim" https://tpo.pe/pathogen.vim

echo "==> Cloning plugins into $BUNDLE_DIR"
declare -A PLUGINS=(
  [ale]=https://github.com/dense-analysis/ale
  [asyncrun-vim]=https://github.com/skywind3000/asyncrun.vim
  [catppuccin-vim]=https://github.com/catppuccin/vim
  [emmet-vim]=https://github.com/mattn/emmet-vim
  [fzf-vim]=https://github.com/junegunn/fzf.vim
  [indentLine]=https://github.com/Yggdroot/indentLine
  [nerdtree]=https://github.com/preservim/nerdtree
  [nerdtree-git-plugin]=https://github.com/Xuyuanp/nerdtree-git-plugin
  [vim-nerdtree-syntax-highlight]=https://github.com/tiagofumo/vim-nerdtree-syntax-highlight
  [omnisharp-vim]=https://github.com/OmniSharp/omnisharp-vim
  [supertab]=https://github.com/ervandew/supertab
  [tagbar]=https://github.com/preservim/tagbar.git
  [vim-airline]=https://github.com/vim-airline/vim-airline
  [vim-airline-themes]=https://github.com/vim-airline/vim-airline-themes
  [vim-auto-save]=https://github.com/907th/vim-auto-save
  [vim-commentary]=https://github.com/tpope/vim-commentary
  [vim-devicons]=https://github.com/ryanoasis/vim-devicons
  [vim-fugitive]=https://github.com/tpope/vim-fugitive
  [vim-gitgutter]=https://github.com/airblade/vim-gitgutter
  [vim-illuminate]=https://github.com/RRethy/vim-illuminate
  [vim-polyglot]=https://github.com/sheerun/vim-polyglot
  [vim-razor]=https://github.com/jlcrochet/vim-razor
  [vim-startify]=https://github.com/mhinz/vim-startify
  [vim-surround]=https://github.com/tpope/vim-surround
  [vim-tmux-navigator]=https://github.com/christoomey/vim-tmux-navigator
  [vim-visual-multi]=https://github.com/mg979/vim-visual-multi
)
for name in "${!PLUGINS[@]}"; do
  dest="$BUNDLE_DIR/$name"
  if [ -d "$dest/.git" ]; then
    echo "  - $name (updating)"
    git -C "$dest" pull --ff-only --quiet
  else
    echo "  - $name (cloning)"
    git clone --depth=1 --quiet "${PLUGINS[$name]}" "$dest"
  fi
done

echo "==> Deploying .vimrc"
cp -f "$SCRIPT_DIR/vimrc" "$HOME/.vimrc"

echo "==> Installing OmniSharp Roslyn server (C#/Blazor completion)"
vim -Nu "$HOME/.vimrc" -c 'OmniSharpInstall' -c 'sleep 60' -c 'qa!' >/dev/null 2>&1 || \
  echo "    (skipped/failed — run :OmniSharpInstall manually inside vim)"

if ! fc-list 2>/dev/null | grep -qi "nerd font"; then
  echo "!! No Nerd Font detected — airline/devicons/nerdtree glyphs need one," \
       "e.g. https://www.nerdfonts.com (JetBrainsMono Nerd Font recommended)."
fi

echo "==> Done. Open vim and start coding."
