" Declare our public API in case we exit early
" (often configured to be called automatically, so don't throw errors on call)
function! CodeStatsXp()
endfunction

" Check for MacVim
if has('gui_macvim')
    echomsg 'code-stats-vim does not support MacVim with Python 2.'
    echomsg 'See https://gitlab.com/code-stats/code-stats-vim/issues/10'
    finish
endif

" Check InsertCharPre support (Vim >= 7.3.186 in practice)
if !exists('##InsertCharPre')
    echomsg 'code-stats-vim requires InsertCharPre support (Vim >= 7.3.186)!'
    finish
endif

" API key: required
if !exists('g:codestats_api_key')
    echomsg 'code-stats-vim requires g:codestats_api_key to be set!'
    finish
endif

" API endpoint
if !exists('g:codestats_api_url')
    let g:codestats_api_url = 'https://codestats.net'
endif

" this script may be run many times; stop timer before reloading Python code
if exists('s:timer')
    call timer_stop(s:timer)
endif

" check Python 2 or 3 support
let s:codestats_path = fnamemodify(resolve(expand('<sfile>:p')), ':h')
if has('python3')
    execute 'py3file ' . s:codestats_path . '/codestats.py'
    let s:python = 'python3'
elseif has('python')
    execute 'pyfile ' . s:codestats_path . '/codestats.py'
    let s:python = 'python'
else
    echomsg 'code-stats-vim requires Python support!'
    finish
endif


" Two XP counters:
"   - global g:codestats_pending_xp
"   - buffer-local b:codestats_xp (initialized when it's used)
" On :PlugUpdate, we intentionally clear pending XP because the worker
" process that was supposed to send it is already gone.
" Buffer-local XP is kept and sent in the future.
let g:codestats_pending_xp = 0      " global total of unsaved XP


function! s:add_xp()
    " plugins trigger TextChanged (eg. vim-plug) for unmodifiable buffers
    if &modifiable
        let g:codestats_pending_xp += 1
        if exists('b:codestats_xp')
            let b:codestats_xp += 1
        else
            let b:codestats_xp = 1
        endif
    endif
endfunction

function! s:log_xp()
    if exists('b:codestats_xp')
        execute s:python . ' codestats.log_xp("' .
                \ &filetype . '", ' .
                \ b:codestats_xp . ')'

        if !exists('s:timer')
            " Vim compiled without timer support; need to make this call here
            call codestats#check_xp(0)
        endif
    endif
    let b:codestats_xp = 0
endfunction

function! s:exit()
    if exists('s:timer')
        call timer_stop(s:timer)
    endif
    execute s:python . ' del codestats'
endfunction

" the Python code calls this function when xp has been sent successfully
function! s:xp_was_sent(xp)
    let g:codestats_pending_xp -= a:xp
    if exists('g:codestats_error')
        " clear error on success
        unlet g:codestats_error
    endif
endfunction

" NOTE: this function cannot be script-local (s:check_xp or such) because
" the timer could not access it
function! codestats#check_xp(timer_id)
    execute s:python . ' codestats.check_xp()'
endfunction


" Handle Vim events
augroup codestats
    autocmd!

    " ADDING XP: Insert mode
    " Does not fire for newlines or backspaces,
    " TextChangedI could be used instead but some
    " plugins are doing something weird with it that
    " messes up the results.
    autocmd InsertCharPre * call s:add_xp()

    " ADDING XP: Normal mode changes
    autocmd TextChanged * call s:add_xp()

    " LOGGING XP
    autocmd InsertEnter,InsertLeave,BufEnter,BufLeave * call s:log_xp()

    " STOPPING
    autocmd VimLeavePre * call s:exit()
augroup END


" check xp periodically if possible
if has('timers')
    " run every 500ms, repeat infinitely
    let s:timer = timer_start(500, 'codestats#check_xp', {'repeat': -1})
endif


" export function that returns pending xp like "C::S 13"
function! CodeStatsXp()
    if exists('g:codestats_error')
        return 'C::S ERR'
    endif
    return 'C::S ' . g:codestats_pending_xp
endfunction
