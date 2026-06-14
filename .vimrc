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
\   'cs':         ['OmniSharp'],
\   'python':     ['pylsp', 'flake8'],
\   'javascript': ['eslint'],
\   'typescript': ['eslint', 'tsserver'],
\}
let g:ale_fixers = {
\   '*':          ['remove_trailing_lines', 'trim_whitespace'],
\   'python':     ['black'],
\   'javascript': ['prettier'],
\   'typescript': ['prettier'],
\   'css':        ['prettier'],
\}
" Optional SQL linting/formatting (needs: pip install sqlfluff).
" Off by default — sqlfluff is noisy without a dialect config. Uncomment to use.
" let g:ale_linters['sql'] = ['sqlfluff']
" let g:ale_fixers['sql']  = ['sqlfluff']
let g:ale_fix_on_save=1
let g:ale_sign_error='✗'
let g:ale_sign_warning='⚠'
nmap <silent> [e <Plug>(ale_previous_wrap)
nmap <silent> ]e <Plug>(ale_next_wrap)

" ── OmniSharp ─────────────────────────────────────────
let g:OmniSharp_server_stdio=1
let g:OmniSharp_highlight_types=3
autocmd FileType cs nmap <silent> gd :OmniSharpGotoDefinition<CR>
autocmd FileType cs nmap <silent> K  :OmniSharpDocumentation<CR>

" ── IndentLine ────────────────────────────────────────
let g:indentLine_char='│'
let g:indentLine_color_term=239

" ── Language Bindings ─────────────────────────────────
autocmd FileType cs         setlocal tabstop=4 shiftwidth=4 expandtab colorcolumn=120
autocmd FileType cs         nnoremap <buffer> <F9>  :!dotnet run<CR>
autocmd FileType cs         nnoremap <buffer> <F10> :!dotnet build<CR>
autocmd FileType javascript,typescript,typescriptreact,javascriptreact
                          \ setlocal tabstop=2 shiftwidth=2 expandtab
autocmd FileType python     setlocal tabstop=4 shiftwidth=4 expandtab colorcolumn=88
autocmd FileType python     nnoremap <buffer> <F9> :!python %<CR>
autocmd FileType html,css,scss,json,yaml
                          \ setlocal tabstop=2 shiftwidth=2 expandtab

autocmd BufNewFile,BufRead *.razor  set filetype=html
autocmd BufNewFile,BufRead *.cshtml set filetype=html
autocmd BufNewFile,BufRead *.tsx    set filetype=typescriptreact
autocmd BufNewFile,BufRead *.jsx    set filetype=javascriptreact

" ── SQL · dadbod ──────────────────────────────────────
" Register named connections for DBUI. Edit/extend as needed.
let g:dbs = {
\   'sample':    'sqlite:' . expand('~/sample.db'),
\   'bibletest': 'sqlite:' . expand('~/DevProjects/PlatformInterviewPrep/bibletest.db'),
\ }
let g:db_ui_use_nerd_fonts   = 1
let g:db_ui_save_location    = '~/.local/share/db_ui'
let g:db_ui_show_help        = 0
let g:db_ui_win_position     = 'left'
let g:db_ui_winwidth         = 35

" Schema-aware completion. SuperTab (context mode) already routes <Tab>
" through omnifunc, so this gives you Tab-completion of tables/columns
" once a buffer is bound to a connection (via DBUI or :DB).
autocmd FileType sql,mysql,plsql setlocal omnifunc=vim_dadbod_completion#omni
" Keep <Tab> on the LSP omnifunc elsewhere, but in SQL it's now dadbod's.

" Mappings (<leader>d* is otherwise unused)
nnoremap <leader>du :DBUIToggle<CR>
nnoremap <leader>df :DBUIFindBuffer<CR>
nnoremap <leader>dr :DBUIRenameBuffer<CR>
nnoremap <leader>dl :DBUILastQueryInfo<CR>

" ── Custom Commands ───────────────────────────────────
command! StripTrailing :%s/\s\+$//e
command! ReloadVimrc   :source $MYVIMRC | echo "vimrc reloaded"
command! FullPath      :echo expand('%:p')
command! VTerm         :vsplit | terminal

"--------  Typescript Additions ------------------------
let g:lsp_diagnostics_echo_cursor    = 1
let g:lsp_document_highlight_enabled = 1
let g:asyncomplete_auto_popup        = 1

if executable('typescript-language-server')
  augroup nextjs_lsp_register
    autocmd!
    autocmd User lsp_setup call lsp#register_server({
      \ 'name': 'typescript-language-server',
      \ 'cmd': {server_info->['typescript-language-server', '--stdio']},
      \ 'allowlist': ['javascript','javascriptreact','typescript','typescriptreact'],
      \ })
  augroup END
endif

function! s:nextjs_lsp_buffer() abort
  setlocal omnifunc=lsp#complete
  nmap <buffer> gd         <plug>(lsp-definition)
  nmap <buffer> gr         <plug>(lsp-references)
  nmap <buffer> gi         <plug>(lsp-implementation)
  nmap <buffer> gt         <plug>(lsp-type-definition)
  nmap <buffer> K          <plug>(lsp-hover)
  nmap <buffer> <leader>rn <plug>(lsp-rename)
  nmap <buffer> <leader>a  <plug>(lsp-code-action)
  nmap <buffer> [g         <plug>(lsp-previous-diagnostic)
  nmap <buffer> ]g         <plug>(lsp-next-diagnostic)
endfunction
augroup nextjs_lsp_buffer
  autocmd!
  autocmd User lsp_buffer_enabled call s:nextjs_lsp_buffer()
augroup END

" SuperTab drives <Tab> completion through the LSP omnifunc
let g:SuperTabDefaultCompletionType        = 'context'
let g:SuperTabContextDefaultCompletionType = "\<c-x>\<c-o>"
let g:SuperTabClosePreviewOnPopupClose     = 1

"---------------  End Typescript Functionality here ---------------

" ----------  NERDTree vertical and horizontal split open shortcuts
let g:NERDTreeMapOpenVSplit = 'v'   " was 's'
let g:NERDTreeMapOpenSplit  = 'h'   " was 'i'
let g:NERDTreeQuitOnOpen = 0

"  Nxt and previous tab ctrl + right arrow for next tab.  ctrol + left arrow
"  for previous tab.
nnoremap <C-Right> <C-w>l
nnoremap <C-Left>  <C-w>h
nnoremap <C-Up>    <C-w>k
nnoremap <C-Down>  <C-w>j
