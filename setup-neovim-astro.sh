#!/usr/bin/env bash
# ==============================================================
#  Neovim + AstroNvim Developer Setup
#  Catppuccin Mocha · Git branch · Nerd Fonts · Oh My Posh
#  Languages: .NET 10 / C# / Blazor · Next.js / TypeScript · Python
#
#  Supports: Ubuntu/Debian · Arch/CachyOS · Fedora/RHEL · macOS
#
#  Usage:
#    chmod +x setup-neovim-astro.sh
#    ./setup-neovim-astro.sh
# ==============================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────
MAUVE='\033[38;2;203;166;247m'
BLUE='\033[38;2;137;180;250m'
GREEN='\033[38;2;166;227;161m'
PEACH='\033[38;2;250;179;135m'
RED='\033[38;2;243;139;168m'
BOLD='\033[1m'
RESET='\033[0m'

section() {
    echo -e "\n${MAUVE}${BOLD}══════════════════════════════════════════${RESET}"
    echo -e "${MAUVE}${BOLD}  $*${RESET}"
    echo -e "${MAUVE}${BOLD}══════════════════════════════════════════${RESET}\n"
}
info()    { echo -e "${BLUE}${BOLD}  ->  $*${RESET}"; }
success() { echo -e "${GREEN}${BOLD}  OK  $*${RESET}"; }
warn()    { echo -e "${PEACH}${BOLD}  !!  $*${RESET}"; }
error()   { echo -e "${RED}${BOLD}  XX  $*${RESET}"; exit 1; }

# ── Detect OS ─────────────────────────────────────────────────
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        case "${ID:-}" in
            ubuntu|debian|linuxmint|pop)    OS="debian" ;;
            arch|cachyos|manjaro|endeavour) OS="arch"   ;;
            fedora|rhel|centos|rocky)       OS="fedora" ;;
            *)
                if   command -v apt-get &>/dev/null; then OS="debian"
                elif command -v pacman  &>/dev/null; then OS="arch"
                elif command -v dnf     &>/dev/null; then OS="fedora"
                else error "Unsupported OS: ${ID:-unknown}"
                fi ;;
        esac
    else
        error "Cannot detect OS — /etc/os-release not found"
    fi
    info "Detected OS: $OS"
}

# ── Package installer ─────────────────────────────────────────
install_pkg() {
    case "$OS" in
        debian) sudo apt-get install -y --no-install-recommends "$@" ;;
        arch)   sudo pacman -S --noconfirm --needed "$@" ;;
        fedora) sudo dnf install -y "$@" ;;
        macos)  brew install "$@" ;;
    esac
}

# ── Detect OS immediately ─────────────────────────────────────
detect_os

# ── Paths ─────────────────────────────────────────────────────
NVIM_CONFIG="$HOME/.config/nvim"
PLUGINS_DIR="$NVIM_CONFIG/lua/plugins"
OMP_DIR="$HOME/.config/ohmyposh"
OMP_THEME="$OMP_DIR/catppuccin-dev.omp.json"
LOCAL_BIN="$HOME/.local/bin"

# Detect shell config file
SHELL_RC="$HOME/.bashrc"
[[ "${SHELL:-}" == *"zsh"*  ]] && SHELL_RC="$HOME/.zshrc"
[[ "${SHELL:-}" == *"fish"* ]] && SHELL_RC="$HOME/.config/fish/config.fish"

# ==============================================================
#  STEP 1 — System dependencies
# ==============================================================
section "Step 1 — Installing system dependencies"

case "$OS" in
    debian)
        sudo apt-get update -qq
        install_pkg git curl wget unzip tar gcc g++ make \
            python3 python3-pip python3-venv \
            nodejs npm ripgrep fd-find xclip fontconfig
        # Debian/Ubuntu name fd as fdfind — symlink it
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
        fi
        ;;
    arch)
        sudo pacman -Sy --noconfirm
        install_pkg git curl wget unzip tar gcc make \
            python python-pip nodejs npm ripgrep fd xclip fontconfig
        ;;
    fedora)
        install_pkg git curl wget unzip tar gcc gcc-c++ make \
            python3 python3-pip nodejs npm ripgrep fd-find xclip fontconfig
        ;;
    macos)
        if ! command -v brew &>/dev/null; then
            info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        install_pkg git curl wget unzip node ripgrep fd python3
        ;;
esac

success "System dependencies installed"

# ==============================================================
#  STEP 2 — Neovim (latest stable)
# ==============================================================
section "Step 2 — Installing Neovim"

install_neovim() {
    case "$OS" in
        arch)  install_pkg neovim ;;
        macos) brew install neovim ;;
        debian|fedora)
            info "Downloading Neovim latest stable from GitHub..."
            local NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
            local NVIM_TAR="/tmp/nvim-linux-x86_64.tar.gz"
            curl -Lo "$NVIM_TAR" "$NVIM_URL"
            sudo rm -rf /opt/nvim-linux-x86_64
            sudo tar -C /opt -xzf "$NVIM_TAR"
            sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
            rm -f "$NVIM_TAR"
            ;;
    esac
}

if command -v nvim &>/dev/null; then
    NVIM_VER=$(nvim --version | head -1)
    # Require at least 0.9
    NVIM_MINOR=$(nvim --version | head -1 | grep -oP '\.\K[0-9]+' | head -1 || echo "0")
    if [[ "${NVIM_MINOR:-0}" -lt 9 ]]; then
        warn "Neovim too old ($NVIM_VER) — upgrading..."
        install_neovim
    else
        warn "Neovim already installed: $NVIM_VER"
    fi
else
    install_neovim
fi

success "$(nvim --version | head -1) ready"

# ==============================================================
#  STEP 3 — .NET 10 SDK
# ==============================================================
section "Step 3 — Installing .NET 10 SDK"

if command -v dotnet &>/dev/null && dotnet --version 2>/dev/null | grep -q "^10\."; then
    warn ".NET 10 already installed: $(dotnet --version)"
else
    info "Installing .NET 10 SDK via dotnet-install script..."
    mkdir -p "$HOME/.dotnet"
    curl -sSL https://dot.net/v1/dotnet-install.sh | \
        bash /dev/stdin --channel 10.0 --install-dir "$HOME/.dotnet"
    export DOTNET_ROOT="$HOME/.dotnet"
    export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
    success ".NET $(dotnet --version 2>/dev/null || echo 'installed') ready"
fi

# ==============================================================
#  STEP 4 — Node.js LTS
# ==============================================================
section "Step 4 — Ensuring Node.js LTS"

if command -v node &>/dev/null; then
    success "Node.js $(node --version) already installed"
else
    info "Installing nvm + Node.js LTS..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    success "Node.js $(node --version) installed"
fi

# ==============================================================
#  STEP 5 — JetBrainsMono Nerd Font
# ==============================================================
section "Step 5 — Installing JetBrainsMono Nerd Font"

FONT_DIR="$HOME/.local/share/fonts"
FONT_CHECK="$FONT_DIR/JetBrainsMonoNerdFontMono-Regular.ttf"

if [[ -f "$FONT_CHECK" ]]; then
    warn "JetBrainsMono Nerd Font already installed -- skipping"
elif [[ "$OS" == "macos" ]]; then
    brew tap homebrew/cask-fonts 2>/dev/null || true
    brew install --cask font-jetbrains-mono-nerd-font
else
    info "Downloading JetBrainsMono Nerd Font..."
    mkdir -p "$FONT_DIR"
    curl -Lo /tmp/JetBrainsMono.zip \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip"
    unzip -o /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono/ '*.ttf' 2>/dev/null || true
    find /tmp/JetBrainsMono -name "*Mono*Regular*" -o -name "*Mono*Bold*" 2>/dev/null | \
        xargs -I{} cp {} "$FONT_DIR/" 2>/dev/null || true
    fc-cache -fv "$FONT_DIR" &>/dev/null || true
    rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
    success "JetBrainsMono Nerd Font installed"
    info "  -> Set your terminal font to: JetBrainsMono Nerd Font Mono"
fi

# ==============================================================
#  STEP 6 — fastfetch
# ==============================================================
section "Step 6 — Installing fastfetch"

if command -v fastfetch &>/dev/null; then
    warn "fastfetch already installed -- skipping"
else
    case "$OS" in
        arch)   install_pkg fastfetch ;;
        fedora) install_pkg fastfetch ;;
        macos)  brew install fastfetch ;;
        debian)
            info "Downloading fastfetch .deb..."
            curl -Lo /tmp/fastfetch.deb \
                "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
            sudo dpkg -i /tmp/fastfetch.deb
            rm -f /tmp/fastfetch.deb
            ;;
    esac
    success "fastfetch installed"
fi

# ==============================================================
#  STEP 7 — Oh My Posh
# ==============================================================
section "Step 7 — Installing Oh My Posh"

if command -v oh-my-posh &>/dev/null; then
    warn "Oh My Posh already installed ($(oh-my-posh --version 2>/dev/null || echo 'unknown version')) -- skipping"
else
    info "Installing Oh My Posh..."
    mkdir -p "$LOCAL_BIN"
    curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$LOCAL_BIN"
    export PATH="$LOCAL_BIN:$PATH"
    success "Oh My Posh installed"
fi

# ==============================================================
#  STEP 8 — Backup old Neovim config and start fresh
# ==============================================================
section "Step 8 — Preparing Neovim config directory"

if [[ -d "$NVIM_CONFIG" ]]; then
    BACKUP="$HOME/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"
    warn "Existing config found -- backing up to $BACKUP"
    mv "$NVIM_CONFIG" "$BACKUP"
fi

for dir in "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"; do
    if [[ -d "$dir" ]]; then
        warn "Removing $dir for clean install..."
        rm -rf "$dir"
    fi
done

success "Config directory ready"

# ==============================================================
#  STEP 9 — Clone AstroNvim template
# ==============================================================
section "Step 9 — Installing AstroNvim"

info "Cloning AstroNvim template..."
git clone --depth 1 https://github.com/AstroNvim/template "$NVIM_CONFIG"
rm -rf "$NVIM_CONFIG/.git"
success "AstroNvim template cloned"

# ==============================================================
#  STEP 10 — Write all plugin config files
# ==============================================================
section "Step 10 — Writing AstroNvim configuration"

mkdir -p "$PLUGINS_DIR"

# ── catppuccin.lua ────────────────────────────────────────────
info "Writing catppuccin.lua..."
cat > "$PLUGINS_DIR/catppuccin.lua" << 'LUAEOF'
return {
  {
    "catppuccin/nvim",
    name     = "catppuccin",
    priority = 1000,
    opts = {
      flavour    = "mocha",
      background = { light = "latte", dark = "mocha" },
      transparent_background = false,
      term_colors            = true,
      dim_inactive           = { enabled = false },
      integrations = {
        aerial           = true,
        alpha            = true,
        cmp              = true,
        gitsigns         = true,
        illuminate        = true,
        indent_blankline = { enabled = true },
        mason            = true,
        mini             = true,
        native_lsp = {
          enabled    = true,
          underlines = {
            errors      = { "underline" },
            hints       = { "underline" },
            warnings    = { "underline" },
            information = { "underline" },
          },
        },
        neotree         = true,
        notify          = true,
        semantic_tokens = true,
        telescope       = { enabled = true },
        treesitter      = true,
        which_key       = true,
      },
    },
  },
}
LUAEOF

# ── colorscheme.lua ───────────────────────────────────────────
info "Writing colorscheme.lua..."
cat > "$PLUGINS_DIR/colorscheme.lua" << 'LUAEOF'
return {
  {
    "AstroNvim/astroui",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
}
LUAEOF

# ── options.lua ───────────────────────────────────────────────
info "Writing options.lua..."
cat > "$PLUGINS_DIR/options.lua" << 'LUAEOF'
return {
  {
    "AstroNvim/astrocore",
    opts = {
      options = {
        opt = {
          number         = true,
          relativenumber = false,   -- absolute line numbers only
          tabstop        = 4,
          shiftwidth     = 4,
          softtabstop    = 4,
          expandtab      = true,
          autoindent     = true,
          smartindent    = true,
          wrap           = false,
          scrolloff      = 8,
          sidescrolloff  = 8,
          ignorecase     = true,
          smartcase      = true,
          hlsearch       = true,
          incsearch      = true,
          termguicolors  = true,
          cursorline     = true,
          signcolumn     = "yes",
          colorcolumn    = "100",
          showmatch      = true,
          pumheight      = 10,
          conceallevel   = 0,
          showmode       = false,
          encoding       = "utf-8",
          fileencoding   = "utf-8",
          undofile       = true,
          swapfile       = false,
          backup         = false,
          updatetime     = 100,
          timeoutlen     = 500,
          clipboard      = "unnamedplus",
          splitbelow     = true,
          splitright     = true,
        },
      },
    },
  },
}
LUAEOF

# ── lsp.lua ───────────────────────────────────────────────────
info "Writing lsp.lua..."
cat > "$PLUGINS_DIR/lsp.lua" << 'LUAEOF'
return {
  {
    "AstroNvim/astrolsp",
    opts = {
      servers = {
        "omnisharp",
        "ts_ls",
        "eslint",
        "cssls",
        "html",
        "jsonls",
        "tailwindcss",
        "pyright",
        "ruff",
      },
      config = {
        omnisharp = {
          cmd      = { "omnisharp" },
          filetypes = { "cs", "vb", "razor", "cshtml" },
          settings = {
            omnisharp = {
              enableRoslynAnalyzers     = true,
              enableEditorConfigSupport = true,
              organizeImportsOnFormat   = true,
              enableImportCompletion    = true,
              useModernNet              = true,
            },
          },
        },
        ts_ls = {
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints             = "all",
                includeInlayFunctionParameterTypeHints     = true,
                includeInlayVariableTypeHints              = true,
                includeInlayPropertyDeclarationTypeHints   = true,
                includeInlayFunctionLikeReturnTypeHints    = true,
              },
            },
            javascript = {
              inlayHints = {
                includeInlayParameterNameHints         = "all",
                includeInlayFunctionParameterTypeHints = true,
              },
            },
          },
        },
        pyright = {
          settings = {
            python = {
              analysis = {
                typeCheckingMode      = "basic",
                autoSearchPaths       = true,
                useLibraryCodeForTypes = true,
              },
            },
          },
        },
        ruff = {
          on_attach = function(client)
            client.server_capabilities.hoverProvider = false
          end,
        },
      },
      formatting = {
        format_on_save = {
          enabled = true,
          allow_filetypes = {
            "lua", "python",
            "javascript", "typescript", "typescriptreact", "javascriptreact",
            "json", "css", "scss", "html",
          },
        },
      },
    },
  },
}
LUAEOF

# ── mason.lua ─────────────────────────────────────────────────
info "Writing mason.lua..."
cat > "$PLUGINS_DIR/mason.lua" << 'LUAEOF'
return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "omnisharp",
        "csharpier",
        "netcoredbg",
        "typescript-language-server",
        "eslint-lsp",
        "prettier",
        "css-lsp",
        "html-lsp",
        "json-lsp",
        "tailwindcss-language-server",
        "pyright",
        "ruff",
        "black",
        "debugpy",
        "stylua",
        "lua-language-server",
      },
    },
  },
}
LUAEOF

# ── treesitter.lua ────────────────────────────────────────────
info "Writing treesitter.lua..."
cat > "$PLUGINS_DIR/treesitter.lua" << 'LUAEOF'
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua", "vim", "vimdoc", "query",
        "c_sharp",
        "javascript", "typescript", "tsx",
        "html", "css", "json", "json5", "jsonc",
        "python",
        "markdown", "markdown_inline",
        "yaml", "toml", "bash",
        "regex", "comment",
      },
      highlight    = { enable = true },
      indent       = { enable = true },
      auto_install = true,
    },
  },
}
LUAEOF

# ── mappings.lua ──────────────────────────────────────────────
info "Writing mappings.lua..."
cat > "$PLUGINS_DIR/mappings.lua" << 'LUAEOF'
return {
  {
    "AstroNvim/astrocore",
    opts = {
      mappings = {
        n = {
          -- File explorer
          ["<C-b>"]      = { "<cmd>Neotree toggle<cr>",              desc = "Toggle file explorer" },
          ["<leader>e"]  = { "<cmd>Neotree toggle<cr>",              desc = "Toggle file explorer" },
          ["<leader>nf"] = { "<cmd>Neotree reveal<cr>",              desc = "Reveal file in explorer" },

          -- Buffer navigation
          ["<S-l>"]      = { "<cmd>bnext<cr>",                       desc = "Next buffer" },
          ["<S-h>"]      = { "<cmd>bprevious<cr>",                   desc = "Previous buffer" },
          ["<leader>d"]  = { "<cmd>bdelete<cr>",                     desc = "Close buffer" },

          -- Split navigation
          ["<C-h>"]      = { "<C-w>h",                               desc = "Move to left split" },
          ["<C-j>"]      = { "<C-w>j",                               desc = "Move to below split" },
          ["<C-k>"]      = { "<C-w>k",                               desc = "Move to above split" },
          ["<C-l>"]      = { "<C-w>l",                               desc = "Move to right split" },

          -- Save / quit
          ["<leader>w"]  = { "<cmd>w<cr>",                           desc = "Save file" },
          ["<leader>q"]  = { "<cmd>q<cr>",                           desc = "Quit" },
          ["<leader>x"]  = { "<cmd>x<cr>",                           desc = "Save and quit" },

          -- Clear search highlight
          ["<Esc>"]      = { "<cmd>nohlsearch<cr>",                  desc = "Clear search highlight" },

          -- LSP
          ["gd"]         = { function() vim.lsp.buf.definition()     end, desc = "Go to definition" },
          ["gr"]         = { function() vim.lsp.buf.references()     end, desc = "Find references" },
          ["gi"]         = { function() vim.lsp.buf.implementation() end, desc = "Go to implementation" },
          ["gy"]         = { function() vim.lsp.buf.type_definition() end, desc = "Go to type definition" },
          ["K"]          = { function() vim.lsp.buf.hover()          end, desc = "Hover docs" },
          ["<leader>rn"] = { function() vim.lsp.buf.rename()         end, desc = "Rename symbol" },
          ["<leader>ca"] = { function() vim.lsp.buf.code_action()    end, desc = "Code action" },
          ["<leader>f"]  = { function() vim.lsp.buf.format()         end, desc = "Format file" },

          -- Diagnostics
          ["[g"]         = { function() vim.diagnostic.goto_prev()   end, desc = "Previous diagnostic" },
          ["]g"]         = { function() vim.diagnostic.goto_next()   end, desc = "Next diagnostic" },

          -- Terminal
          ["<leader>t"]  = { "<cmd>ToggleTerm direction=horizontal<cr>", desc = "Toggle terminal" },

          -- Telescope
          ["<C-p>"]      = { "<cmd>Telescope find_files<cr>",        desc = "Find files" },
          ["<leader>fg"] = { "<cmd>Telescope live_grep<cr>",         desc = "Live grep" },
          ["<leader>fb"] = { "<cmd>Telescope buffers<cr>",           desc = "Find buffers" },
          ["<leader>fh"] = { "<cmd>Telescope help_tags<cr>",         desc = "Help tags" },
          ["<leader>fo"] = { "<cmd>Telescope oldfiles<cr>",          desc = "Recent files" },
        },
        v = {
          ["<leader>ca"] = { function() vim.lsp.buf.code_action() end, desc = "Code action" },
        },
        i = {
          ["jk"] = { "<Esc>", desc = "Escape insert mode" },
        },
      },
    },
  },
}
LUAEOF

# ── extras.lua ────────────────────────────────────────────────
info "Writing extras.lua..."
cat > "$PLUGINS_DIR/extras.lua" << 'LUAEOF'
return {
  -- Auto-close brackets/quotes
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts  = { check_ts = true },
  },

  -- Comment/uncomment with gc
  {
    "numToStr/Comment.nvim",
    event = "BufReadPost",
    opts  = {},
  },

  -- Surround text (like vim-surround)
  {
    "kylechui/nvim-surround",
    event   = "BufReadPost",
    version = "*",
    opts    = {},
  },

  -- Git signs in gutter
  {
    "lewis6991/gitsigns.nvim",
    event = "BufReadPre",
    opts  = {
      signs = {
        add          = { text = "+" },
        change       = { text = "~" },
        delete       = { text = "-" },
        topdelete    = { text = "-" },
        changedelete = { text = "~" },
      },
      current_line_blame      = true,
      current_line_blame_opts = { delay = 500 },
    },
  },

  -- Indent guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main  = "ibl",
    event = "BufReadPost",
    opts  = {
      indent = { char = "|" },
      scope  = { char = "|" },
    },
  },

  -- Toggleable terminal
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd     = "ToggleTerm",
    opts    = {
      size      = 15,
      direction = "horizontal",
    },
  },

  -- Better diagnostics list
  {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd          = { "Trouble", "TroubleToggle" },
    keys         = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",              desc = "Diagnostics" },
      { "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
    },
    opts = { use_diagnostic_signs = true },
  },

  -- Which-key: keybinding hints
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts  = {
      preset = "modern",
      icons  = { mappings = false },
    },
  },

  -- Emmet for HTML / JSX / Blazor
  {
    "mattn/emmet-vim",
    ft   = { "html", "css", "typescriptreact", "javascriptreact", "razor", "cshtml" },
    init = function()
      vim.g.user_emmet_settings = {
        typescriptreact = { extends = "jsx" },
        javascriptreact = { extends = "jsx" },
      }
    end,
  },

  -- Fix: disable Neo-tree's internal <C-b> so our global toggle works
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      window = {
        mappings = {
          ["<C-b>"] = "none",
        },
      },
      filesystem = {
        window = {
          mappings = {
            ["<C-b>"] = "none",
          },
        },
      },
    },
  },
}
LUAEOF

# ── filetypes.lua ─────────────────────────────────────────────
info "Writing filetypes.lua..."
cat > "$PLUGINS_DIR/filetypes.lua" << 'LUAEOF'
return {
  {
    "AstroNvim/astrocore",
    opts = {
      autocmds = {
        CSharpSettings = {
          {
            event    = "FileType",
            pattern  = { "cs", "razor", "cshtml" },
            callback = function()
              vim.opt_local.tabstop    = 4
              vim.opt_local.shiftwidth = 4
              vim.opt_local.expandtab  = true
            end,
          },
        },
        WebSettings = {
          {
            event    = "FileType",
            pattern  = {
              "javascript", "typescript",
              "typescriptreact", "javascriptreact",
              "json", "html", "css", "scss",
            },
            callback = function()
              vim.opt_local.tabstop    = 2
              vim.opt_local.shiftwidth = 2
              vim.opt_local.expandtab  = true
            end,
          },
        },
        PythonSettings = {
          {
            event    = "FileType",
            pattern  = "python",
            callback = function()
              vim.opt_local.tabstop     = 4
              vim.opt_local.shiftwidth  = 4
              vim.opt_local.expandtab   = true
              vim.opt_local.textwidth   = 88
              vim.opt_local.colorcolumn = "88"
            end,
          },
        },
        YankHighlight = {
          {
            event    = "TextYankPost",
            callback = function()
              vim.highlight.on_yank({ timeout = 200 })
            end,
          },
        },
      },
    },
  },
}
LUAEOF

success "All plugin config files written"

# ==============================================================
#  STEP 11 — Oh My Posh Catppuccin theme
# ==============================================================
section "Step 11 — Writing Oh My Posh theme"

mkdir -p "$OMP_DIR"

cat > "$OMP_THEME" << 'OMPEOF'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "console_title_template": "{{ .Shell }} -- {{ .Folder }}",
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "os",
          "style": "diamond",
          "leading_diamond": "\ue0b6",
          "trailing_diamond": "\ue0b0",
          "foreground": "#1e1e2e",
          "background": "#cba6f7",
          "template": "  "
        },
        {
          "type": "path",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#1e1e2e",
          "background": "#89b4fa",
          "properties": {
            "style": "agnoster_short",
            "max_depth": 4,
            "folder_separator": " / ",
            "home_icon": "~"
          },
          "template": "  {{ .Path }} "
        },
        {
          "type": "git",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#1e1e2e",
          "background": "#a6e3a1",
          "foreground_templates": [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}#1e1e2e{{ end }}",
            "{{ if and (gt .Ahead 0) (gt .Behind 0) }}#1e1e2e{{ end }}",
            "{{ if gt .Ahead 0 }}#1e1e2e{{ end }}"
          ],
          "background_templates": [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}#fab387{{ end }}",
            "{{ if and (gt .Ahead 0) (gt .Behind 0) }}#f38ba8{{ end }}",
            "{{ if gt .Ahead 0 }}#89dceb{{ end }}"
          ],
          "properties": {
            "branch_icon": " branch:",
            "fetch_status": true
          },
          "template": " {{ .HEAD }}{{ if .Working.Changed }} ~ {{ .Working.String }}{{ end }}{{ if .Staging.Changed }} + {{ .Staging.String }}{{ end }}{{ if gt .Ahead 0 }} ^ {{ .Ahead }}{{ end }}{{ if gt .Behind 0 }} v {{ .Behind }}{{ end }} "
        },
        {
          "type": "dotnet",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#1e1e2e",
          "background": "#cba6f7",
          "template": "  dotnet:{{ .Full }} ",
          "properties": { "display_mode": "files" }
        },
        {
          "type": "node",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#1e1e2e",
          "background": "#a6e3a1",
          "template": "  node:{{ .Full }} ",
          "properties": { "display_mode": "files" }
        },
        {
          "type": "python",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#1e1e2e",
          "background": "#f9e2af",
          "template": "  py:{{ .Full }}{{ if .Venv }} ({{ .Venv }}){{ end }} ",
          "properties": { "display_mode": "files", "fetch_virtual_env": true }
        },
        {
          "type": "executiontime",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#1e1e2e",
          "background": "#f38ba8",
          "template": "  took {{ .FormattedMs }} ",
          "properties": { "threshold": 3000, "always_enabled": false }
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "right",
      "segments": [
        {
          "type": "time",
          "style": "plain",
          "foreground": "#cba6f7",
          "template": "{{ .CurrentDate | date \"15:04:05\" }} "
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground_templates": [ "{{ if gt .Code 0 }}#f38ba8{{ end }}" ],
          "foreground": "#a6e3a1",
          "template": "{{ if gt .Code 0 }}[err:{{ .Code }}] >{{ else }}>{{ end }} "
        }
      ]
    }
  ]
}
OMPEOF

success "Oh My Posh theme written"

# ==============================================================
#  STEP 12 — Shell profile
# ==============================================================
section "Step 12 — Configuring shell profile ($SHELL_RC)"

# Back up existing profile
if [[ -f "$SHELL_RC" ]]; then
    cp "$SHELL_RC" "${SHELL_RC}.bak.$(date +%Y%m%d_%H%M%S)"
    warn "Backed up existing shell config"
fi

# Remove any previous block from this script
sed -i '/# -- Neovim Dev Setup --/,/# -- END Neovim Dev Setup --/d' "$SHELL_RC" 2>/dev/null || true

cat >> "$SHELL_RC" << 'SHELLEOF'

# -- Neovim Dev Setup --

# Local bin (oh-my-posh etc.)
export PATH="$HOME/.local/bin:$PATH"

# .NET
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"

# nvm
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

# Oh My Posh
if command -v oh-my-posh &>/dev/null; then
    _OMP_THEME="$HOME/.config/ohmyposh/catppuccin-dev.omp.json"
    if [[ -f "$_OMP_THEME" ]]; then
        eval "$(oh-my-posh init bash --config "$_OMP_THEME")"
    fi
fi

# fastfetch on new terminal
if command -v fastfetch &>/dev/null; then
    fastfetch
fi

# cowsay: random nerdy joke / dad joke on startup
_jokes=(
    "Why do Java developers wear glasses? Because they don't C#."
    "A SQL query walks into a bar and asks two tables: Can I join you?"
    "There are 10 types of people: those who understand binary and those who don't."
    "Why do programmers prefer dark mode? Because light attracts bugs."
    "Debugging: being the detective in a crime movie where you are also the murderer."
    "99 bugs in the code... take one down, patch it around... 127 bugs in the code."
    "It's not a bug, it's an undocumented feature."
    "Why did the programmer quit? Because he didn't get arrays."
    "To understand recursion, you must first understand recursion."
    "I tried to write clean code once. The compiler laughed."
    "Knock knock. Race condition. Who's there?"
    "git commit -m 'fix bug' -- the lie we tell ourselves."
    "Why don't bachelors like Git? They are afraid of commitment."
    "How do you comfort a JavaScript bug? You console it."
    "I would tell you a UDP joke but you might not get it."
    "TODO: fix this -- found 3 years later."
    "Why did the developer go broke? He used up all his cache."
    "Real programmers count from 0. Off-by-one errors are someone else's problem."
    "My code doesn't have bugs. It has unexpected features."
    "The cloud is just someone else's computer... and it's always raining."
    "Why was the JavaScript developer sad? He didn't Node how to Express himself."
    "A byte walks into a bar looking pale. Bartender asks what's wrong. Bit flip."
    "What's a programmer's favourite hangout? Foo Bar."
    "rm -rf / -- just kidding. Or am I?"
    "Why did Wi-Fi and the programmer get married? They had a connection."
)
_j="${_jokes[$RANDOM % ${#_jokes[@]}]}"
_w=${#_j}
(( _w > 72 )) && _w=72
printf '\n'
printf ' +%s+\n' "$(printf '%0.s-' $(seq 1 $((_w + 2))))"
printf ' | %-*s |\n' "$_w" "$_j"
printf ' +%s+\n' "$(printf '%0.s-' $(seq 1 $((_w + 2))))"
printf '        \   ^__^\n'
printf '         \  (oo)\_______\n'
printf '            (__)\       )\/\\\n'
printf '                ||----w |\n'
printf '                ||     ||\n\n'

# Aliases
alias vi='nvim'
alias vim='nvim'
alias v='nvim'
alias g='git'
alias ll='ls -lAh --color=auto'
alias la='ls -A --color=auto'

# Git
gs()  { git status; }
ga()  { git add "$@"; }
gc()  { git commit -m "$@"; }
gp()  { git push "$@"; }
gpl() { git pull "$@"; }
gl()  { git log --oneline --graph --decorate --all; }
gco() { git checkout "$@"; }
gb()  { git branch "$@"; }
gd()  { git diff "$@"; }

# .NET
dr()  { dotnet run "$@"; }
db()  { dotnet build "$@"; }
dt()  { dotnet test "$@"; }
dw()  { dotnet watch "$@"; }
da()  { dotnet add "$@"; }

# Node / Next.js
dev() { npm run dev "$@"; }
nb()  { npm run build "$@"; }
ni()  { npm install "$@"; }
nid() { npm install --save-dev "$@"; }

# Python
venv() {
    [[ ! -d .venv ]] && python3 -m venv .venv && echo "Created .venv"
    source .venv/bin/activate
    echo "Virtual environment activated"
}
pipi() { pip install "$@"; }
pir()  { pip install -r requirements.txt; }
pif()  { pip freeze > requirements.txt && echo "requirements.txt updated"; }

# Utility
serve() { python3 -m http.server "${1:-8000}"; }
ff()    { find . -name "$1" 2>/dev/null; }
mkcd()  { mkdir -p "$1" && cd "$1" || return; }
reload() { source "$HOME/.bashrc" && echo "Profile reloaded"; }

# -- END Neovim Dev Setup --
SHELLEOF

success "Shell profile updated"

# ==============================================================
#  STEP 13 — Bootstrap AstroNvim headlessly
# ==============================================================
section "Step 13 — Bootstrapping AstroNvim plugins (2-5 min)"

info "Running Neovim headlessly to install plugins..."

# Try lazy sync — suppress errors since headless output is noisy
nvim --headless "+Lazy! sync" +qa 2>/dev/null && \
    success "Plugin bootstrap complete" || \
    warn "Headless bootstrap may have had warnings -- open nvim to finish"

# ==============================================================
#  STEP 14 — update-neovim helper
# ==============================================================
section "Step 14 — Creating update-neovim helper"

mkdir -p "$LOCAL_BIN"
cat > "$LOCAL_BIN/update-neovim" << 'UPDATEEOF'
#!/usr/bin/env bash
echo "Updating Oh My Posh..."
curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"

echo "Updating Neovim plugins..."
nvim --headless "+Lazy! sync" +qa 2>/dev/null

echo "Updating Mason LSP servers..."
nvim --headless "+MasonUpdateAll" +qa 2>/dev/null

echo "Updating Treesitter parsers..."
nvim --headless "+TSUpdateSync" +qa 2>/dev/null

echo ""
echo "All done!"
UPDATEEOF
chmod +x "$LOCAL_BIN/update-neovim"
success "update-neovim installed to $LOCAL_BIN/update-neovim"

# ==============================================================
#  DONE
# ==============================================================
section "Setup Complete!"

echo -e "${MAUVE}${BOLD}"
echo "  Config files written to: ~/.config/nvim/lua/plugins/"
echo "    catppuccin.lua   colorscheme.lua  options.lua"
echo "    lsp.lua          mason.lua        treesitter.lua"
echo "    mappings.lua     extras.lua       filetypes.lua"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Restart your terminal to activate Oh My Posh + aliases"
echo ""
echo "  2. Set terminal font to: JetBrainsMono Nerd Font Mono"
echo ""
echo "  3. Open Neovim -- lazy.nvim finishes installing on first launch:"
echo "     nvim"
echo ""
echo "  4. Inside Neovim verify everything loaded:"
echo "     :Lazy          plugin manager status"
echo "     :Mason         LSP / tool installer"
echo "     :LspInfo       active language servers"
echo "     :checkhealth   full health report"
echo ""
echo "  5. Update everything later:"
echo "     update-neovim"
echo ""
echo "  Key mappings:"
echo "    Ctrl+b / Space+e   toggle Neo-tree file explorer"
echo "    Ctrl+p             fuzzy file finder (Telescope)"
echo "    gd / gr / K        go to def / references / hover"
echo "    Space+rn           rename symbol"
echo "    Space+ca           code action"
echo "    Space+f            format file"
echo "    Space+t            toggle terminal"
echo "    [g / ]g            prev / next diagnostic"
echo "    jk                 exit insert mode"
echo -e "${RESET}"
