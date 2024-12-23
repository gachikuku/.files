" themprimeagen's set
set guicursor=
set number
set relativenumber
set tabstop=4
set softtabstop=4
set shiftwidth=4
set smartindent
set nowrap
set noswapfile
set nobackup
set undodir=$HOME/.vim/undodir
set undofile
set nohlsearch
set incsearch
set isfname+=@-@
set updatetime=50

" themprimeagen's remap
let mapleader = " "
nmap <Leader>pv :Ex<CR>
vmap J :m '>+1<CR>gv=gv
vmap K :m '<-2<CR>gv=gv
nmap J mzJ`z
nmap <C-d> <C-d>zz
nmap <C-u> <C-u>zz
nmap n nzzzv
nmap N Nzzzv
xmap <Leader>p "_dP
nmap <Leader>y "+y
vmap <Leader>y "+y
nmap <Leader>Y "+Y
nmap <Leader>d "_d
vmap <Leader>d "_d
nmap Q <nop>
nmap <C-k> :cnext<CR>zz
nmap <C-j> :cprev<CR>zz
nmap <Leader>k :lnext<CR>zz
nmap <Leader>j :lprev<CR>zz
nmap <Leader>s :%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>
nmap <Leader>x :!chmod +x %<CR>
nmap <Leader><Leader> :so<CR>

" theprimeagen netrw
let g:netrw_browse_split = 0
let g:netrw_banner = 0
let g:netrw_winsize = 25

" jcs
set encoding=utf-8
set signcolumn=no
set t_Co=256
syntax on
set showcmd
set showmatch
set showmode
set spelllang=en_us
set laststatus=2

" jcs colorscheme
hi clear
if exists("syntax_on")
	syntax reset
endif
hi Comment		cterm=NONE		ctermfg=242
" hi Constant		cterm=underline		ctermfg=NONE
hi CursorLineNr		cterm=bold		ctermfg=244
hi DiffAdd		cterm=bold		ctermfg=NONE
hi DiffChange		cterm=bold		ctermfg=NONE
hi DiffDelete		cterm=bold		ctermfg=NONE
hi DiffText		cterm=reverse		ctermfg=NONE
hi Directory		cterm=bold		ctermfg=NONE
hi Error		cterm=NONE		ctermfg=NONE	ctermbg=224
hi ErrorMsg		cterm=NONE		ctermfg=NONE	ctermbg=224
hi FoldColumn		cterm=standout		ctermfg=NONE
hi Folded		cterm=standout		ctermfg=NONE
" hi Identifier		cterm=underline		ctermfg=NONE
hi Ignore		cterm=bold		ctermfg=NONE
hi IncSearch		cterm=reverse		ctermfg=NONE
hi LineNr		cterm=NONE		ctermfg=248
hi MatchParen		cterm=bold		ctermfg=none	ctermbg=185
hi ModeMsg		cterm=bold		ctermfg=NONE
hi MoreMsg		cterm=bold		ctermfg=NONE
hi NonText		cterm=bold		ctermfg=NONE
" hi PreProc		cterm=underline		ctermfg=NONE
hi Pmenu		cterm=NONE		ctermfg=NONE	ctermbg=253
hi PmenuSel		cterm=bold		ctermfg=NONE	ctermbg=253
hi Question		cterm=standout		ctermfg=NONE
hi Search		cterm=reverse		ctermfg=NONE
hi SignColumn		cterm=NONE		ctermfg=NONE	ctermbg=NONE
hi SpellBad		cterm=NONE		ctermfg=NONE	ctermbg=224
hi SpellLocal		cterm=NONE		ctermfg=NONE	ctermbg=223
hi Special		cterm=bold		ctermfg=NONE
hi SpecialKey		cterm=bold		ctermfg=NONE
hi Statement		cterm=bold		ctermfg=NONE
hi StatusLine		cterm=bold,reverse	ctermfg=NONE
hi StatusLineNC		cterm=reverse		ctermfg=NONE
hi TabLine		cterm=reverse		ctermfg=NONE	ctermbg=NONE
hi Title		cterm=bold		ctermfg=NONE
hi Todo			cterm=bold,standout	ctermfg=185	ctermbg=0
hi Type			cterm=bold		ctermfg=NONE
" hi Underlined		cterm=underline		ctermfg=NONE
hi VertSplit		cterm=reverse		ctermfg=NONE
hi Visual		cterm=reverse		ctermfg=NONE	ctermbg=NONE
" hi VisualNOS		cterm=bold,underline	ctermfg=NONE
hi WarningMsg		cterm=standout		ctermfg=NONE
hi WildMenu		cterm=standout		ctermfg=NONE

hi ColorColumn		cterm=NONE		ctermfg=NONE	ctermbg=252
	" for highlighting stray spaces/tabs (requires match statements in vimrc)
hi ExtraWhitespace	cterm=reverse		ctermfg=185	ctermbg=NONE
	" mostly for nerdtree
hi VertSplit		cterm=bold		ctermfg=240	ctermbg=NONE

" ddvault
set listchars=tab:▸\ ,eol:¬,space:.

" me
	" Don't change background colour
autocmd ColorScheme * highlight Normal ctermbg=NONE guibg=NONE
	"suckless.org/rocks
set go+=c
