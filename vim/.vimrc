set nocompatible

set laststatus=2
set t_Co=256
set encoding=utf-8
set autoindent
set magic
set scrolloff=3
set sidescroll=3
set ruler
set cc=80
set nowrap
set ignorecase
set smartcase
set splitbelow
set hidden
set notimeout
set incsearch
set showmatch
set hlsearch
set mouse=a
set noswapfile
set nofoldenable
set lazyredraw
set spc=

let g:fzf_layout = { 'window': { 'width': 1.0, 'height': 0.5, 'relative': v:true, 'yoffset': 1.0, 'border': 'none' }}

let mapleader = "\<space>"
nnoremap <silent> <F5> :let _s=@/<Bar>:%s/\s\+$//e<Bar>:let @/=_s<Bar>:nohl<CR> " Trim trailing spaces
nnoremap Y y$
nnoremap cc :center<cr>
inoremap <C-c> <ESC>
set listchars=tab:▸\ ,eol:¬,space:.
nnoremap <leader>l :set list!<CR>

function! GitFZF()
    let path = trim(system('cd '.shellescape(expand('%:p:h')).' && git rev-parse --show-toplevel'))
    exe 'FZF ' . path
endfunction
command! GitFZF call GitFZF()
nnoremap <C-p> :GitFZF<CR>

syntax on
highlight Normal ctermfg=none ctermbg=none
highlight NonText ctermfg=none ctermbg=none
highlight EndOfBuffer ctermfg=none ctermbg=none
highlight TabLineFill ctermfg=none ctermbg=none
highlight Search ctermbg=12
highlight NonText ctermfg=darkgrey
highlight SpecialKey ctermfg=darkgrey
highlight clear SignColumn
highlight Comment cterm=bold ctermfg=none
highlight StatusLine cterm=none ctermbg=none ctermfg=darkgrey
highlight StatusLineNC cterm=none ctermbg=none ctermfg=darkgrey
highlight Title cterm=none ctermfg=darkgrey
highlight TabLineFill cterm=none
highlight TabLine cterm=none ctermfg=darkgrey ctermbg=none
highlight ColorColumn ctermbg=darkgrey guibg=lightgrey
highlight Todo ctermbg=NONE ctermfg=red cterm=bold
highlight PreProc ctermfg=grey
highlight String ctermfg=darkblue cterm=italic
highlight Type ctermfg=darkblue
highlight lineNr ctermfg=grey cterm=italic
highlight cIncluded ctermfg=NONE cterm=bold
highlight pythonInclude ctermfg=blue
highlight pythonConditional ctermfg=darkcyan
highlight pythonBuiltin ctermfg=darkcyan
highlight Pmenu ctermbg=white ctermfg=black
highlight PmenuSel ctermbg=darkcyan ctermfg=black
highlight hareKeyword ctermbg=NONE ctermfg=darkcyan
highlight hareLabel ctermbg=NONE cterm=bold

autocmd FileType markdown setlocal tw=80 et ts=2 sw=2
autocmd FileType text setlocal tw=80
autocmd BufNewFile,BufRead * if expand('%:t') == 'APKBUILD' | set ft=sh | endif
autocmd BufNewFile,BufRead * if expand('%:t') == 'PKGBUILD' | set ft=sh | endif

filetype plugin on

" VimWiki
let g:vimwiki_list = [{'syntax': 'markdown',
                     \ 'ext': 'md',
		     \ 'path': '~/iCloud'}]

let g:vimwiki_global_ext = 0
