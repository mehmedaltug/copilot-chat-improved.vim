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

export def Http(method: string, url: string, headers: list<string>, body: any): string
  var response = ''
  var json_body = (method !=# 'GET' && !empty(body)) ? json_encode(body) : ''

  if has('win32')
    var ps_cmd = 'powershell -NoProfile -Command "'
    ps_cmd ..= '$headers = @{'
    for header in headers
      var idx = stridx(header, ':')
      if idx != -1
        var key = trim(header[0 : idx - 1])
        var val = trim(header[idx + 1 :])
        key = substitute(key, "'", "''", 'g')
        val = substitute(val, "'", "''", 'g')
        ps_cmd ..= "'" .. key .. "'='" .. val .. "';"
      endif
    endfor
    ps_cmd ..= '};'

    var esc_url = substitute(url, "'", "''", 'g')
    var iwr_args = "-UseBasicParsing -Uri '" .. esc_url .. "' -Method " .. method .. " -Headers $headers"

    if !empty(json_body)
      var ps_body = substitute(json_body, "'", "''", 'g')
      ps_cmd ..= "$body = '" .. ps_body .. "';"
      iwr_args ..= " -Body $body -ContentType 'application/json'"
    endif

    ps_cmd ..= "Invoke-WebRequest " .. iwr_args .. " | Select-Object -ExpandProperty Content"
    ps_cmd ..= '"'

    response = system(ps_cmd)
    if v:shell_error != 0
      echom 'PowerShell Error: ' .. v:shell_error
      return ''
    endif
  else
    var esc_url = substitute(url, "'", "'\\''", 'g')
    var curl_cmd = 'curl -s -X ' .. method .. ' --compressed '

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
      echom 'Curl Error: ' .. v:shell_error
      return ''
    endif
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

export def AgentRequest(messages: list<any>): void
  var chat_token: string = auth.VerifySignin()
  curl_output = []
  buffer_messages = messages
  var url: string = 'https://api.individual.githubcopilot.com/responses'
  var data: string = json_encode({
    'model': models.Current(),
    'stream': true,
    'tools': tools.List(),
    'input': messages
  })
  debugger.Write('making agent request')
  debugger.Write(data)

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
     'out_cb': HandleAgentJobOutput,
     'exit_cb': HandleAgentJobClose,
     'err_cb': HandleAgentJobError
  })
  _buffer.WaitingForResponse()
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
    'messages': messages
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

def HandleAgentJobClose(j: job, exit_status: number): void
  if filereadable(current_tmpfile)
    delete(current_tmpfile)
  endif

  deletebufline(g:copilot_chat_active_buffer, '$')
  for line in curl_output
    if line =~? '^data: {'
      try
        var json_completion = json_decode(strcharpart(line, 6))
        if has_key(json_completion, 'response') && json_completion['response']['output'] != v:null
          if len(json_completion['response']['output']) > 0
            var outcome = json_completion['response']['output'][-1]
            if outcome['type'] == 'function_call' && index(function_calls, outcome['call_id']) == -1
              tools.InvokeTool(outcome, buffer_messages)
              add(function_calls, outcome['call_id'])
            elseif outcome['type'] == 'message'
              for m in outcome['content']
                _buffer.AppendResponse(m['text'])
              endfor
            endif
          endif
        endif
      catch
      endtry
    endif
  endfor
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
      # Handle SSE streams gracefully (skip 'data: [DONE]')
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

  # Iterate line-by-line to pass string items instead of list<string>
  for resp_line in response
    _buffer.AppendResponse(resp_line)
  endfor

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
