vim9script
scriptencoding utf-8

import autoload 'copilot_chat/auth.vim' as auth
import autoload 'copilot_chat/buffer.vim' as _buffer
import autoload 'copilot_chat/models.vim' as models
import autoload 'copilot_chat/tools.vim' as tools
import autoload 'copilot_chat/debug.vim' as debugger

var curl_output: list<string> = []
var buffer_messages: list<any> = []
var function_calls: list<string> = []
var current_tmpfile: string = ''

def GetSystemPrompt(): string
  # assume dir containing .github, fallback to cwd
  var project_root: string = finddir('.github', ';')
  if project_root == ''
    project_root = getcwd() .. '/.github'
  endif

  var instructions: string = project_root .. '/copilot-instructions.md'
  
  # try to read .github/copilot-instructions.md, fallback to basic prompt
  if filereadable(instructions)
    var lines: list<string> = readfile(instructions)
    instructions = join(lines, '\n')
  else
    instructions = $'You are an assistive AI working for this codebase in: {getcwd()}.'
    if g:copilot_chat_mode = 'Agent'
      instructions ..= ' Use the tools to explore the project first.'
    endif
  endif
  
  return instructions
enddef

export def Http(method: string, url: string, headers: list<string>, body: any): string
  var response = ''
  var json_body = (method !=# 'GET' && !empty(body)) ? json_encode(body) : ''

  var esc_url = substitute(url, "'", "'\\''", 'g')
  var curl_cmd = 'curl -s -N -X ' .. method .. ' --compressed '

  for header in headers
    var esc_header = substitute(header, '"', '\"', 'g')
    curl_cmd ..= '-H "' .. esc_header .. '" '
  endfor

  if !empty(json_body)
    var esc_body = substitute(json_body, "'", "'\\''", 'g')
    curl_cmd ..= "-d '" .. esc_body .. "' "
  endif

  curl_cmd ..= "'" .. esc_url .. "'"

  response = system(curl_cmd)
  if v:shell_error != 0
    return ''
  endif

  return response
enddef

export def FetchModels(chat_token: string): list<string>
  if exists('g:copilot_chat_test_mode')
    return ['gpt-o4']
  endif

  var chat_headers = [
    'Content-Type: application/json',
    $'Authorization: Bearer {chat_token}',
    'Editor-Version: vscode/1.80.1'
  ]

  var response = Http('GET', 'https://api.githubcopilot.com/models', chat_headers, {})
  var model_list: list<string> = []
  if empty(response)
    return model_list
  endif

  try
    var json_response = json_decode(response)
    if has_key(json_response, 'data') && type(json_response.data) == v:t_list
      for item in json_response.data
        if has_key(item, 'id')
          add(model_list, item.id)
        endif
      endfor
    endif
  catch
    echom 'Failed to parse models JSON response'
  endtry

  return model_list
enddef

export def AgentRequest(messages: list<any>): job
  var chat_token: string = auth.VerifySignin()
  curl_output = []
  buffer_messages = messages
  var url: string = 'https://api.githubcopilot.com/chat/completions'

  var payload: dict<any> = {
    'model': models.Current(),
    'stream': true,
    'temperature': 0,
    'messages': [{'role': 'system', 'content': GetSystemPrompt()}] + messages
  }

  var tool_list = tools.List()
  if !empty(tool_list)
    payload['tools'] = tool_list
  endif

  var data: string = json_encode(payload)
  current_tmpfile = tempname()
  writefile([data], current_tmpfile)

  var curl_cmd: list<string> = [
    'curl', '-s', '-N',
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', 'Authorization: Bearer ' .. chat_token,
    '-H', 'Editor-Version: vscode/1.80.1',
    '-H', 'Copilot-Integration-Id: vscode-chat',
    '-d', $'@{current_tmpfile}',
    url
  ]

  var job: job = job_start(curl_cmd, {
     'out_cb': HandleAgentJobOutput,
     'exit_cb': HandleAgentJobClose,
     'err_cb': HandleAgentJobError
  })
  _buffer.WaitingForResponse()

  return job
enddef

export def AsyncRequest(messages: list<any>, file_list: list<any>): job
  var chat_token: string = auth.VerifySignin()
  curl_output = []
  var url: string = 'https://api.githubcopilot.com/chat/completions'

  for file in file_list
    if filereadable(file)
      var file_content: list<string> = readfile(file)
      var full_path: string = fnamemodify(file, ':p')
      var attachment_content: string = '<attachment id="' .. file .. '">\n````markdown\n<!-- filepath: ' .. full_path .. ' -->\n' .. join(file_content, "\n") .. '\n```</attachment>'
      add(messages, {'content': attachment_content, 'role': 'user'})
    endif
  endfor

  var data: string = json_encode({
    'intent': false,
    'model': models.Current(),
    'temperature': 0,
    'top_p': 1,
    'n': 1,
    'stream': true,
    'messages': [{'role': 'system', 'content': GetSystemPrompt()}] + messages
  })

  current_tmpfile = tempname()
  writefile([data], current_tmpfile)

  var curl_cmd: list<string> = [
    'curl',
    '-s',
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    '-H', 'Authorization: Bearer ' .. chat_token,
    '-H', 'Editor-Version: vscode/1.80.1',
    '-d',
    $'@{current_tmpfile}',
    url
  ]

  var job: job = job_start(curl_cmd, {
     'out_cb': HandleJobOutput,
     'exit_cb': HandleJobClose,
     'err_cb': HandleJobError
  })

  _buffer.WaitingForResponse()

  return job
enddef

def HandleAgentJobOutput(channel: channel, msg: any): void
  if type(msg) == v:t_list
    for data in msg
      add(curl_output, data)
    endfor
  else
    add(curl_output, msg)
  endif
enddef

def HandleAgentJobClose(j: job, exit_status: number): void
  if filereadable(current_tmpfile)
    delete(current_tmpfile)
  endif

  deletebufline(g:copilot_chat_active_buffer, '$')

  var full_text = ''
  var error_lines = []
  var pending_tool_calls: dict<dict<string>> = {}

  for raw_line in curl_output
    var line = substitute(raw_line, '[\r\n]', '', 'g')
    if empty(line)
      continue
    endif

    if line =~? '^data:\s*'
      var payload = substitute(line, '^data:\s*', '', '')
      if payload ==# '[DONE]'
        continue
      endif

      try
        var json_completion = json_decode(payload)

        if has_key(json_completion, 'choices') && !empty(json_completion.choices)
          var choice = json_completion.choices[0]
          if has_key(choice, 'delta')
            var delta = choice.delta

            if has_key(delta, 'content') && type(delta.content) == v:t_string
              full_text ..= delta.content
            endif

            if has_key(delta, 'tool_calls') && type(delta.tool_calls) == v:t_list
              for tc in delta.tool_calls
                var idx = string(get(tc, 'index', 0))
                if !has_key(pending_tool_calls, idx)
                  pending_tool_calls[idx] = {'id': '', 'name': '', 'arguments': ''}
                endif

                if has_key(tc, 'id') && !empty(tc.id)
                  pending_tool_calls[idx]['id'] = tc.id
                endif

                if has_key(tc, 'function')
                  var fn = tc.function
                  if has_key(fn, 'name') && !empty(fn.name)
                    pending_tool_calls[idx]['name'] = fn.name
                  endif
                  if has_key(fn, 'arguments') && !empty(fn.arguments)
                    pending_tool_calls[idx]['arguments'] ..= fn.arguments
                  endif
                endif
              endfor
            endif
          endif
        endif
      catch
      endtry
    elseif line =~? 'error' || line =~? '^{\s*"message"'
      add(error_lines, line)
    endif
  endfor

  if !empty(pending_tool_calls)
    for [idx, tc] in items(pending_tool_calls)
      if !empty(tc.id) && index(function_calls, tc.id) == -1
        add(function_calls, tc.id)
        tools.InvokeTool(tc, buffer_messages)
      endif
    endfor
    return
  endif

  if !empty(full_text)
    _buffer.AppendResponse(full_text)
  elseif !empty(error_lines)
    _buffer.AppendResponse("API Error:\n" .. join(error_lines, "\n"))
  endif
enddef

def HandleAgentJobError(channel: channel, msg: any): void
  echom msg
enddef

def HandleJobOutput(channel: channel, msg: any): void
  if type(msg) == v:t_list
    for data in msg
      if data =~? '^data: {'
        add(curl_output, data)
      endif
    endfor
  else
    if msg =~? '^data: {'
      add(curl_output, msg)
    endif
  endif
enddef

def HandleJobClose(j: job, exit_status: number): void
  if filereadable(current_tmpfile)
    delete(current_tmpfile)
  endif

  deletebufline(g:copilot_chat_active_buffer, '$')
  var result = ''
  for line in curl_output
    if line =~? '^data: {'
      var payload = strcharpart(line, 6)
      if payload ==# '[DONE]'
        continue
      endif
      try
        var json_completion = json_decode(payload)
        var content = json_completion.choices[0].delta.content
        if type(content) != type(v:null)
          result ..= content
        endif
      catch
        result ..= "\n"
      endtry
    elseif line =~? 'error'
      result ..= line
    endif
  endfor

  var response = split(result, "\n")
  var width = winwidth(0) - 2 - getwininfo(win_getid())[0].textoff
  var response_start = line('$') + 1

  _buffer.AppendResponse(result)

  var wrap_width = width + 2
  var softwrap_lines = 0
  for line in response
    if strwidth(line) > wrap_width
      softwrap_lines += float2nr(ceil(strwidth(line) * 1.0 / wrap_width))
    else
      softwrap_lines += 1
    endif
  endfor

  var total_response_length = softwrap_lines + 2
  var height = winheight(0)
  if total_response_length >= height
    execute 'normal! ' .. response_start .. 'Gzt'
  else
    execute 'normal! G'
  endif
  setcursorcharpos(line('$'), 3)
enddef

def HandleJobError(channel: channel, msg: any): void
  if type(msg) == v:t_list
    var filtered_errors = filter(copy(msg), '!empty(v:val)')
    if len(filtered_errors) > 0
      echom filtered_errors
    endif
  else
    echom msg
  endif
enddef
