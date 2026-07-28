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

" ── Tabs ──────────────────────────────────────────────
nnoremap <silent> ]t :tabnext<CR>
nnoremap <silent> [t :tabprevious<CR>

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

" nerdtree-git-plugin: inline git status flags per file/folder
let g:NERDTreeGitStatusIndicatorMapCustom = {
\ 'Modified'  : '✹',
\ 'Staged'    : '✚',
\ 'Untracked' : '✭',
\ 'Renamed'   : '➜',
\ 'Unmerged'  : '═',
\ 'Deleted'   : '✖',
\ 'Dirty'     : '✗',
\ 'Ignored'   : '☒',
\ 'Clean'     : '✔',
\ 'Unknown'   : '?',
\ }
let g:NERDTreeGitStatusWithFlags = 1
let g:NERDTreeGitStatusUseNerdFonts = 1

" vim-nerdtree-syntax-highlight: color file names/icons by filetype
let g:NERDTreeFileExtensionHighlightFullName = 1
let g:NERDTreeExactMatchHighlightFullName = 1
let g:NERDTreeHighlightFolders = 1
let g:NERDTreeHighlightFoldersFullName = 1

" ── Airline ───────────────────────────────────────────
let g:airline_theme='catppuccin'
let g:airline_powerline_fonts=1
let g:airline#extensions#tabline#enabled=1
let g:airline#extensions#tabline#formatter='unique_tail'

" ── ALE ───────────────────────────────────────────────
let g:ale_linters = {
\   'python':     ['pylsp'],
\   'javascript': ['eslint', 'typescript-language-server'],
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
" Same gap as typescript above, applies to plain .js too — Express is
" almost entirely plain JS, so without this there's no completion/hover/
" goto-def on .js files at all (only eslint diagnostics).
call ale#linter#Define('javascript', {
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
autocmd FileType python,javascript,javascriptreact,typescript,typescriptreact,cs
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

" ── Node.js / Express ─────────────────────────────────
" F9 runs the current file directly via node (quick scripts); F10 runs
" `npm start` (expects an Express "start" script in package.json); F7 runs
" `npm test`. All execute from the project root (nearest package.json/.git)
" via AsyncRun, output lands in the quickfix window.
command! -nargs=1 NpmRun AsyncRun -cwd=<root> npm run <args>
autocmd FileType javascript,javascriptreact,typescript,typescriptreact
      \ nnoremap <buffer> <F9>       :AsyncRun -cwd=<root> node %<CR>
autocmd FileType javascript,javascriptreact,typescript,typescriptreact
      \ nnoremap <buffer> <F10>      :AsyncRun -cwd=<root> npm start<CR>
autocmd FileType javascript,javascriptreact,typescript,typescriptreact
      \ nnoremap <buffer> <F7>       :AsyncRun -cwd=<root> npm test<CR>
autocmd FileType javascript,javascriptreact,typescript,typescriptreact
      \ nnoremap <buffer> <leader>ni :AsyncRun -cwd=<root> npm install<CR>
autocmd FileType javascript,javascriptreact,typescript,typescriptreact
      \ nnoremap <buffer> <leader>nr :NpmRun<Space>

" :NodeExpressSetup — one-shot scaffold for real Express/Node autocomplete.
" typescript-language-server only knows req/res/app methods and node
" builtins (fs, http, process, ...) if @types/node + @types/express are in
" node_modules — plain eslint-only JS has no type info to complete from.
" Writes a jsconfig.json (checkJs + node module resolution) at the nearest
" package.json and npm-installs the type packages as devDependencies.
function! s:NodeExpressSetup() abort
  let l:pkg = findfile('package.json', expand('%:p:h') . ';')
  if empty(l:pkg)
    echoerr 'NodeExpressSetup: no package.json found upward from this file.'
    return
  endif
  let l:root = fnamemodify(l:pkg, ':h')
  let l:jsconfig = l:root . '/jsconfig.json'
  if !filereadable(l:jsconfig)
    call writefile([
    \ '{',
    \ '  "compilerOptions": {',
    \ '    "target": "ES2022",',
    \ '    "module": "commonjs",',
    \ '    "moduleResolution": "node",',
    \ '    "checkJs": true,',
    \ '    "allowJs": true',
    \ '  },',
    \ '  "exclude": ["node_modules"]',
    \ '}',
    \ ], l:jsconfig)
    echo 'NodeExpressSetup: wrote ' . l:jsconfig
  endif
  execute 'AsyncRun -cwd=' . fnameescape(l:root) . ' npm install --save-dev @types/node @types/express'
endfunction
command! NodeExpressSetup call s:NodeExpressSetup()
autocmd FileType javascript,javascriptreact,typescript,typescriptreact
      \ nnoremap <buffer> <leader>ns :NodeExpressSetup<CR>

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
