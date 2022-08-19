if exists('g:bm_has_any') || !has('signs') || &cp
  finish
endif
scriptencoding utf-8

let g:bm_has_any = 0
let g:bm_sign_index = 9500
let g:bm_current_file = ''

let g:bookmark_sign = '⚑'
let g:bookmark_annotation_sign = '☰'
let g:bookmark_auto_save_file = $HOME . '/.vim-bookmarks'

" Configuration {{{

function! s:init()
  augroup bm_vim_enter
    autocmd!
    autocmd BufEnter * call s:set_up_auto_save(expand('<afile>:p'))
  augroup END

  autocmd CursorMoved * call s:display_annotation()

  call BookmarkLoad(s:bookmark_save_file())
endfunction

" }}}


" Commands {{{

function! BookmarkToggle()
  call s:refresh_line_numbers()

  let file = expand("%:p")
  if file ==# ""
    return
  endif

  let current_line = line('.')
  if bm#has_bookmark_at_line(file, current_line)
    call s:bookmark_remove(file, current_line)
    echo "Bookmark removed"
  else
    call s:bookmark_add(file, current_line)
    echo "Bookmark added"
  endif
endfunction

function! BookmarkAnnotate(...)
  call s:refresh_line_numbers()

  let file = expand("%:p")
  if file ==# ""
    return
  endif

  let current_line = line('.')
  let has_bm = bm#has_bookmark_at_line(file, current_line)
  let bm = has_bm ? bm#get_bookmark_by_line(file, current_line) : 0
  let old_annotation = has_bm ? bm['annotation'] : ""
  let new_annotation = a:0 ># 0 ? a:1 : ""

  " Get annotation from user input if not passed in
  if new_annotation ==# ""
    let input_msg = old_annotation !=# "" ? "Edit" : "Enter"
    let cancelled_input = '@I@DINT@RITE@NUTHIN@MATE@'
    let new_annotation = inputdialog(input_msg ." annotation: ", old_annotation, cancelled_input)
    if new_annotation ==# cancelled_input
      let new_annotation = old_annotation
    endif
    execute ":redraw!"
  endif

  " Nothing changed, bail out
  if old_annotation ==# new_annotation
    return

  " Update annotation
  elseif has_bm
    call bm#update_annotation(file, bm['sign_idx'], new_annotation)
    let result_msg = (new_annotation ==# "")
          \ ? "removed"
          \ : old_annotation !=# ""
          \   ? "updated: ". new_annotation
          \   : "added: ". new_annotation
    call bm_sign#update_at(file, bm['sign_idx'], bm['line_nr'], bm['annotation'] !=# "")
    echo "Annotation ". result_msg

  " Create bookmark with annotation
  elseif new_annotation !=# ""
    call s:bookmark_add(file, current_line, new_annotation)
    echo "Bookmark added with annotation: ". new_annotation
  endif
endfunction

function! BookmarkNext()
  call s:refresh_line_numbers()
  call s:jump_to_bookmark('next')
endfunction

function! BookmarkPrev()
  call s:refresh_line_numbers()
  call s:jump_to_bookmark('prev')
endfunction

function! BookmarkSave(target_file)
  call s:refresh_line_numbers()
  let serialized_bookmarks = bm#serialize()
  call writefile(serialized_bookmarks, a:target_file)
endfunction

function! BookmarkLoad(target_file)
  call s:remove_all_bookmarks()
  try
    let data = readfile(a:target_file)
    let new_entries = bm#deserialize(data)
  catch
  endtry
endfunction

" }}}


" Private {{{

function! s:lazy_init()
  if g:bm_has_any ==# 0
    let g:bm_has_any = 1
    augroup bm_refresh
      autocmd!
      autocmd ColorScheme * call bm_sign#define_highlights()
      autocmd BufLeave * call s:refresh_line_numbers()
    augroup END
  endif
endfunction

function! s:refresh_line_numbers()
  call s:lazy_init()

  let file = expand("%:p")
  if file ==# "" || !bm#has_bookmarks_in_file(file)
    return
  endif

  let bufnr = bufnr(file)
  let sign_line_map = bm_sign#lines_for_signs(file)
  for sign_idx in keys(sign_line_map)
    let line_nr = sign_line_map[sign_idx]
    let line_content = getbufline(bufnr, line_nr)
    let content = len(line_content) > 0 ? line_content[0] : ' '
    call bm#update_bookmark_for_sign(file, sign_idx, line_nr, content)
  endfor
endfunction

function! s:bookmark_add(file, line_nr, ...)
  let annotation = (a:0 ==# 1) ? a:1 : ""
  let sign_idx = bm_sign#add(a:file, a:line_nr, annotation !=# "")
  call bm#add_bookmark(a:file, sign_idx, a:line_nr, getline(a:line_nr), annotation)
endfunction

function! s:bookmark_remove(file, line_nr)
  let bookmark = bm#get_bookmark_by_line(a:file, a:line_nr)
  call bm_sign#del(a:file, bookmark['sign_idx'])
  call bm#del_bookmark_at_line(a:file, a:line_nr)
endfunction

function! s:jump_to_bookmark(type)
  let file = expand("%:p")
  let line_nr = bm#{a:type}(file, line("."))
  if line_nr ==# 0
    echo "No bookmarks found"
  else
    call cursor(line_nr, 1)
    normal! ^
    normal! zz
    let bm = bm#get_bookmark_by_line(file, line_nr)
    let annotation = bm['annotation'] !=# "" ? " (". bm['annotation'] . ")" : ""
    execute ":redraw!"
    echo "Jumped to bookmark". annotation
  endif
endfunction

function! s:remove_all_bookmarks()
  let files = bm#all_files()
  for file in files
    let lines = bm#all_lines(file)
    for line_nr in lines
      call s:bookmark_remove(file, line_nr)
    endfor
  endfor
endfunction

function! s:bookmark_save_file()
  return g:bookmark_auto_save_file
endfunction

" should only be called from autocmd!
function! s:add_missing_signs(file)
  let bookmarks = values(bm#all_bookmarks_by_line(a:file))
  for bookmark in bookmarks
    call bm_sign#add_at(a:file, bookmark['sign_idx'], bookmark['line_nr'], bookmark['annotation'] !=# "")
  endfor
endfunction

function! s:auto_save()
  if g:bm_current_file !=# ''
    call BookmarkSave(s:bookmark_save_file())
  endif
  augroup bm_auto_save
    autocmd!
  augroup END
endfunction

function! s:set_up_auto_save(file)
  let g:bm_current_file = a:file
  augroup bm_auto_save
    autocmd!
    autocmd BufWinEnter * call s:add_missing_signs(expand('<afile>:p'))
    autocmd BufLeave,VimLeave,BufReadPre * call s:auto_save()
  augroup END
endfunction

function! s:display_annotation()
  let file = expand("%:p")
  if file ==# ""
    return
  endif

  let current_line = line('.')
  let has_bm = bm#has_bookmark_at_line(file, current_line)
  let bm = has_bm ? bm#get_bookmark_by_line(file, current_line) : 0
  let annotation = has_bm ? bm['annotation'] : ""
  if annotation !=# ""
      echo "Bookmark annotation: ". annotation
  else
      echo
  endif
endfunction

" }}}


" Maps {{{

command! BookmarkToggle call BookmarkToggle()
command! -nargs=* BookmarkAnnotate call BookmarkAnnotate(<q-args>, 0)
command! BookmarkNext call BookmarkNext()
command! BookmarkPrev call BookmarkPrev()

function! s:register_mapping(command, shortcut)
  execute "nnoremap <silent> <Plug>". a:command ." :". a:command ."<CR>"
endfunction

call s:register_mapping('BookmarkToggle',   'mm')
call s:register_mapping('BookmarkAnnotate', 'mi')
call s:register_mapping('BookmarkNext',     'mn')
call s:register_mapping('BookmarkPrev',     'mp')

" }}}

if has('vim_starting')
  autocmd VimEnter * call s:init()
else
  call s:init()
endif
