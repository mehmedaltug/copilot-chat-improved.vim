vim9script

import autoload 'copilot_chat/buffer.vim' as _buffer

# Safe parameter extraction helper
def GetParams(outcome: dict<any>): dict<any>
  var args = get(outcome, 'arguments', {})
  if type(args) == v:t_string
    try
      return json_decode(args)
    catch
      return {}
    endtry
  elseif type(args) == v:t_dict
    return args
  endif
  return {}
enddef

def NormalizePath(raw_path: string): string
  var path = raw_path
  path = substitute(path, '^file://', '', '')

  if path =~? '^/[a-zA-Z]:'
    path = path[1 :]
  endif

  if path =~? '^:\' || path =~? '^:/'
    var cwd_drive = matchstr(getcwd(), '^[a-zA-Z]:')
    if empty(cwd_drive)
      cwd_drive = 'C:'
    endif
    path = cwd_drive .. path
  endif

  return fnamemodify(path, ':p')
enddef

def ShowDiff(path: string, new_lines: list<string>): number
  var tmp_old = tempname()
  var tmp_new = tempname()
  if filereadable(path)
    writefile(readfile(path), tmp_old, 'b')
  else
    writefile([], tmp_old, 'b')
  endif

  writefile(new_lines, tmp_new, 'b')

  execute 'tabnew ' .. fnameescape(tmp_old)
  execute 'vert diffsplit ' .. fnameescape(tmp_new)

  setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
  wincmd l
  setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
  wincmd p
  redraw!

  var choice = confirm('Apply change to ' .. path .. '?', '&Yes\n&No\n&Apply to all\n&Abort', 1)
  execute 'tabclose'

  if choice == 1 || choice == 3
    return 1
  else
    return 0
  endif
enddef

export def ListDir(outcome: dict<any>): string
  var params = GetParams(outcome)
  var target = get(params, 'path', '.')
  if empty(target)
    target = '.'
  endif

  var full_path = NormalizePath(target)
  if !isdirectory(full_path)
    return $'Error: Directory not found: {full_path}'
  endif

  try
    var items = readdirex(full_path)
    var file_list = []

    for item in items
      if item.name =~? '^\.'
        continue
      endif
      var entry_type = item.type == 'dir' ? 'directory' : 'file'
      add(file_list, $'{item.name} ({entry_type})')
    endfor

    return json_encode({
      'directory': full_path,
      'contents': file_list
    })
  catch
    return $'Error listing directory {full_path}: {v:exception}'
  endtry
enddef

export def CreateDirectory(outcome: dict<any>): string
  var params = GetParams(outcome)
  var raw_path = get(params, 'dirPath', get(params, 'path', ''))

  if empty(raw_path)
    return 'Error: dirPath parameter missing.'
  endif

  var path = NormalizePath(raw_path)

  try
    if !isdirectory(path)
      mkdir(path, 'p')
    endif
    return $'Successfully created directory: {path}'
  catch
    return $'Error creating directory {path}: {v:exception}'
  endtry
enddef

export def CreateFile(outcome: dict<any>): string
  var params = GetParams(outcome)
  var raw_path = get(params, 'filePath', get(params, 'path', ''))
  var content = get(params, 'content', '')

  if empty(raw_path)
    return 'Error: filePath parameter missing.'
  endif

  var path = NormalizePath(raw_path)

  if filereadable(path) || isdirectory(path)
    return $'create_file Error - file already exists: {path}'
  endif

  var parent = fnamemodify(path, ':h')
  try
    if !empty(parent) && !isdirectory(parent)
      mkdir(parent, 'p')
    endif
    writefile(split(content, "\n", true), path)
    return $'Successfully created file: {path}'
  catch
    return $'Error creating file {path}: {v:exception}'
  endtry
enddef

export def ReadFile(outcome: dict<any>): string
  var params = GetParams(outcome)
  var raw_path = get(params, 'filePath', get(params, 'path', ''))

  if empty(raw_path)
    return 'Error: filePath parameter missing.'
  endif

  var path = NormalizePath(raw_path)

  if !filereadable(path)
    return $'Error: File not found or not readable: {path}'
  endif

  var start_line = get(params, 'startLine', 1) - 1
  var end_line = get(params, 'endLine', 0) - 1

  if start_line < 0
    start_line = 0
  endif

  try
    var all_lines = readfile(path)
    var total_lines = len(all_lines)

    if total_lines == 0
      return $'File {path} is empty.'
    endif

    if end_line < 0 || end_line >= total_lines
      end_line = total_lines - 1
    endif

    if start_line >= total_lines
      return $'Error: startLine ({start_line + 1}) exceeds total file lines ({total_lines}).'
    endif

    var slice_lines = all_lines[start_line : end_line]
    return join(slice_lines, "\n")
  catch
    return $'Error reading file {path}: {v:exception}'
  endtry
enddef

vim9script

def ShowDiffAndConfirm(path: string, new_lines: list<string>): number
  var tmp_old = tempname()
  var tmp_new = tempname()

  if filereadable(path)
    writefile(readfile(path), tmp_old, 'b')
  else
    writefile([], tmp_old, 'b')
  endif

  writefile(new_lines, tmp_new, 'b')

  # Open temp files in a diff view tab
  execute 'tabnew ' .. fnameescape(tmp_old)
  execute 'vert diffsplit ' .. fnameescape(tmp_new)

  setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
  wincmd l
  setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
  wincmd p
  redraw!

  # Prompt user for consent (1=Yes, 2=No, 3=Allow for session, 4=Abort)
  var choice = confirm($'Apply patch to {path}?', "&Yes\n&No\n&Allow for session\n&Abort", 1)

  execute 'tabclose!'

  # Cleanup
  if filereadable(tmp_old) | delete(tmp_old) | endif
  if filereadable(tmp_new) | delete(tmp_new) | endif

  return choice
enddef

def PromptConsent(path: string, new_lines: list<string>): dict<any>
  if get(g:, 'copilot_patch_autoapprove', false)
    return {'apply': true, 'abort': false}
  endif

  var choice = ShowDiffAndConfirm(path, new_lines)

  if choice == 3
    g:copilot_patch_autoapprove = true
    return {'apply': true, 'abort': false}
  elseif choice == 1 # Yes
    return {'apply': true, 'abort': false}
  elseif choice == 4 || choice == 0 # Abort or ESC
    return {'apply': false, 'abort': true}
  else
    return {'apply': false, 'abort': false}
  endif
enddef

export def ApplyPatch(outcome: dict<any>): string
  var params = GetParams(outcome)
  var patch_text = get(params, 'input', '')
  var updated_files = []

  if match(patch_text, '^\*\*\* Begin Patch') != 0
    return 'apply_patch error: patch must start with "*** Begin Patch"'
  endif

  var lines = split(patch_text, "\n", true)
  var n = len(lines)
  var i = 0

  try
    while i < n
      var ln = lines[i]

      if ln =~# '^\*\*\* Begin Patch' || ln =~# '^\s*$'
        i += 1
        continue
      endif
      if ln =~# '^\*\*\* End Patch'
        break
      endif

      # Update File Directive
      if ln =~# '^\*\*\* Update File:'
        var raw_path = trim(substitute(ln, '^\*\*\* Update File:\s*', '', ''))
        var path = NormalizePath(raw_path)
        i += 1

        var section = []
        while i < n && lines[i] !~# '^\*\*\* \(Update\|Delete\|Add\|End Patch\)'
          add(section, lines[i])
          i += 1
        endwhile

        if !filereadable(path)
          echom $'Update File Error - missing file: {path}'
          continue
        endif

        var new_lines = []
        for s in section
          if strlen(s) > 0 && s[0] == '+'
            add(new_lines, s[1 : ])
          endif
        endfor

        if len(new_lines) > 0
          var consent = PromptConsent(path, new_lines)
          if consent.abort
            echom 'Patch application aborted by user.'
            break
          endif

          if consent.apply
            try
              writefile(new_lines, path, 'b')
              add(updated_files, path)
            catch
              echom $'Failed to write updated file: {path}'
            endtry
          else
            echom $'Skipped update for: {path}'
          endif
        else
          echom $'Update for {path} contained no "+" lines; file left unchanged.'
        endif

        continue
      endif

      # Delete File Directive
      if ln =~# '^\*\*\* Delete File:'
        var raw_path = trim(substitute(ln, '^\*\*\* Delete File:\s*', '', ''))
        var path = NormalizePath(raw_path)
        i += 1

        if !filereadable(path)
          echom $'Delete File Error - missing file: {path}'
          continue
        endif

        var consent = PromptConsent(path, [])
        if consent.abort
          echom 'Patch application aborted by user.'
          break
        endif

        if consent.apply
          try
            delete(path)
            add(updated_files, $'Deleted: {path}')
            echom $'Deleted: {path}'
          catch
            echom $'Failed to delete: {path}'
          endtry
        else
          echom $'Skipped deletion for: {path}'
        endif

        continue
      endif

      # Add File Directive
      if ln =~# '^\*\*\* Add File:'
        var raw_path = trim(substitute(ln, '^\*\*\* Add File:\s*', '', ''))
        var path = NormalizePath(raw_path)
        i += 1

        if filereadable(path)
          echom $'Add File Error - file already exists: {path}'
          while i < n && lines[i] !~# '^\*\*\* \(Update\|Delete\|Add\|End Patch\)'
            i += 1
          endwhile
          continue
        endif

        var add_lines = []
        while i < n && lines[i] !~# '^\*\*\* \(Update\|Delete\|Add\|End Patch\)'
          var s = lines[i]
          if strlen(s) > 0 && s[0] == '+'
            add(add_lines, s[1 : ])
          endif
          i += 1
        endwhile

        var consent = PromptConsent(path, add_lines)
        if consent.abort
          echom 'Patch application aborted by user.'
          break
        endif

        if consent.apply
          try
            var parent = fnamemodify(path, ':h')
            if !empty(parent) && !isdirectory(parent)
              mkdir(parent, 'p')
            endif
            writefile(add_lines, path, 'b')
            add(updated_files, $'Added: {path}')
            echom $'Added: {path}'
          catch
            echom $'Failed to add file: {path}'
          endtry
        else
          echom $'Skipped adding file: {path}'
        endif

        continue
      endif

      i += 1
    endwhile
  catch
    return $'Exception while applying patch: {v:exception}'
  endtry

  return $'The following files were successfully edited:\n{join(updated_files, "\n")}\n'
enddef
