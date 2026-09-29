<div align="center">

# Copilot Chat Improved for Vim

An enhanced fork of [DanBradbury/copilot-chat.vim](https://github.com/DanBradbury/copilot-chat.vim) providing GitHub Copilot Chat functionality with full **Agent Mode** and tool-calling capabilities directly inside Vim.

Nvim users can check [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) for a Neovim-native experience.

![copilotChat](https://github.com/user-attachments/assets/0cd1119d-89c8-4633-972e-641718e6b24b)
</div>

## Requirements

- [Vim > 9.0](https://github.com/vim/vim)
- [Curl](https://curl.se) (Mandatory for both Unix and Windows)
- [NerdFonts](https://www.nerdfonts.com) (Optional for pretty icons)

## Installation

Using [Vundle](https://github.com/VundleVim/Vundle.vim), [Pathogen](https://github.com/tpope/vim-pathogen), [vim-plug](https://github.com/junegunn/vim-plug), Vim 8+ packages, or any other plugin manager.

### Vundle

Add to your `.vimrc`:
```vim
call vundle#begin()
Plugin 'mehmedaltug/copilot-chat-improved.vim'
call vundle#end()

filetype plugin indent on

```

### Pathogen

Clone repository:

```bash
git clone https://github.com/mehmedaltug/copilot-chat-improved.vim.git ~/.vim/bundle

```

Add to your `.vimrc`:

```vim
call pathogen#infect()
syntax on
filetype plugin indent on

```

### vim-plug

Add to your `.vimrc`:

```vim
call plug#begin()
Plug 'mehmedaltug/copilot-chat-improved.vim'
call plug#end()

filetype plugin indent on

```

### Vim 8+ packages

Clone repository:

```bash
git clone [https://github.com/mehmedaltug/copilot-chat-improved.vim.git](https://github.com/mehmedaltug/copilot-chat-improved.vim.git) ~/.vim/pack/plugins/start

```

Add to your `.vimrc`:

```vim
filetype plugin indent on

```

## Setup

1. Run `:CopilotChatOpen` to open a chat window. You will be prompted to setup your device on first use.
2. Write your prompt under the line separator and press `<Enter>` in normal mode.
3. You should see a `Waiting for response..` indicator in the buffer while Copilot is working in the background.

---

## What's New & Key Features

### Agent Mode (`@agent` & `@ask`)

Copilot can now act as an autonomous workspace agent!

* **`@agent`**: Enables agent mode with full tool execution capabilities. The agent can:
* Explore directory structures (`list_dir`)
* Read project files (`read_file`)
* Create new files and directories (`create_file`, `create_directory`)
* Apply diff patches directly to your workspace (`apply_patch`)


* **`@ask`**: Asks Copilot direct questions without triggering workspace modifications.
* **Silent Tool Execution**: Tools execute smoothly in the background without cluttering your chat buffer or printing intermediate curl outputs.
* **Cross-Platform Path Safety**: Automatic path normalization supporting Windows drive letters, file URIs, and Unix paths seamlessly.

---

### Autocomplete Macros & Context Tools

* **`#allfiles`**: Automatically injects context from all relevant project files into your prompt. auto excludes build, cache and framework library directories.
* **`#file:` Macro**: Autocompletes file paths based on Git-tracked files or current working directory contents.
* **`/tab all` Macro**: Expands into a list of all open tabs prefixed by `#file:` for easy multi-file reference.
* **`/buff all` Macro**: Expands into a list of all open buffers prefixed by `#file:` for easy multi-file reference.

---

### Roadmap & In Progress

* [x] **Agent mode**: Make copilot use tools and work like an agent.
* [x] **`/buff all` Macro**: Inject all currently open buffers into context automatically.
* [ ] **Copilot Instructions Support**: Automatic loading of custom repository guidelines from `.github/copilot-instructions.md`.
* [ ] **Model Selection Fixes**: Resolving model selection popup bugs in `:CopilotChatModels`.

---

## Commands

| Command | Description |
| --- | --- |
| `:CopilotChat <input>` | Launches a new Copilot chat with your input as the initial prompt |
| `:CopilotChatOpen` | Opens a new Copilot chat window (default vsplit right) |
| `:CopilotChatFocus` | Focuses the currently active chat window |
| `:CopilotChatReset` | Resets the current chat window |
| `:CopilotChatConfig` | Open `config.json` for default settings |
| `:CopilotChatModels` | View available models / select active model |
| `:CopilotChatSave <name>?` | Save chat history (uses timestamp if no name provided) |
| `:CopilotChatLoad <name>?` | Load chat history |
| `:CopilotChatList` | List all saved chat histories |
| `:CopilotChatSetActive <bufnr>?` | Sets active chat window to specified buffer number |
| `:CopilotChatLogin` | Login to github (if process doesnt auto open) |

## Plugin Keys

| Key | Description |
| --- | --- |
| `<Plug>CopilotChatAddSelection` | Copies selected text into active chat buffer |

## Key Mappings Example

```vim
" Open a new Copilot Chat window
nnoremap <leader>cc :CopilotChatOpen<CR>

" Add visual selection to Copilot window
vmap <leader>a <Plug>CopilotChatAddSelection

```

---

## Custom Configuration

```vim
let g:copilot_chat_window_position = 'bottom' " 'right' (default), 'left', 'top', 'bottom'
let g:copilot_chat_message_history_limit = 20
let g:copilot_chat_syntax_debounce_ms = 300
let g:copilot_chat_file_cache_timeout = 5

```

---

## Credits & Attributions

This project is a fork of [DanBradbury/copilot-chat.vim](https://github.com/DanBradbury/copilot-chat.vim).

| Contribution / Component | Original Author | Modifications / Enhancements in this Fork |
| --- | --- | --- |
| **Core Plugin Architecture** | [DanBradbury](https://github.com/DanBradbury) | Adapted, bug-fixed, and expanded for agent workflows. |
| **Agent Mode (Base Concept)** | Dan Bradbury (experimental branch) | Used as initial proof-of-concept for tool calling. |
| **Agent Mode (Refactor & Enhancements)** | [mehmedaltug](https://github.com/mehmedaltug) | **Heavily modified & rewritten**: Added Windows path normalization (`NormalizePath`), silent tool execution, directory listing (`list_dir`), safe JSON parameter decoding, and robust diff patching. |
| **Context Macros (`#allfiles`, `@agent`, `@ask`)** | [mehmedaltug](https://github.com/mehmedaltug) | New context handlers and macro integrations. |
| **Buffer Clutter & Curl Warning Removal** | [mehmedaltug](https://github.com/mehmedaltug) | Cleaned up streaming close handling and tool execution output logs. |
| **`/buff all` macro** | [Martin Askestad](https://github.com/MartinAskestad) & [mehmedaltug](https://github.com/mehmedaltug) (Same implementation) | Macro for including all active buffers as #file in chat |
