local M = {}

local namespace = vim.api.nvim_create_namespace("git-history-ui")
local list_buffer = nil
local preview_buffer = nil
local list_window = nil
local preview_window = nil
local origin_window = nil
local config = nil
local handlers = nil
local line_items = {}
local selected_index = nil

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function valid_buffer(buffer)
  return buffer and vim.api.nvim_buf_is_valid(buffer)
end

local function buffer(filetype)
  local value = vim.api.nvim_create_buf(false, true)
  vim.bo[value].buftype = "nofile"
  vim.bo[value].bufhidden = "wipe"
  vim.bo[value].swapfile = false
  vim.bo[value].filetype = filetype
  return value
end

local function dimensions()
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  if columns < 6 or lines < 3 then
    return nil, "editor is too small for the two-pane Git History window"
  end
  local total_width = math.min(columns, math.max(6, math.floor(columns * config.window.width)))
  local total_height = math.min(lines, math.max(3, math.floor(lines * config.window.height)))
  local content_width = total_width - 4
  local list_width = math.max(1, math.min(content_width - 1, math.floor(content_width * config.window.list_width)))
  local preview_width = math.max(1, content_width - list_width)
  local row = math.max(0, math.floor((lines - total_height) / 2))
  local col = math.max(0, math.floor((columns - total_width) / 2))
  return {
    row = row,
    col = col,
    height = total_height - 2,
    list_width = list_width,
    preview_width = preview_width,
  }
end

local function window_configs(view)
  local size, err = dimensions()
  if not size then
    return nil, nil, err
  end
  local title = view == "branches" and " Branches " or " Commits "
  return {
    relative = "editor",
    row = size.row,
    col = size.col,
    width = size.list_width,
    height = size.height,
    style = "minimal",
    border = config.window.border,
    title = title,
    title_pos = "center",
  }, {
    relative = "editor",
    row = size.row,
    col = size.col + size.list_width + 2,
    width = size.preview_width,
    height = size.height,
    style = "minimal",
    border = config.window.border,
    title = " Details ",
    title_pos = "center",
  }
end

local function set_lines(target, lines)
  if not valid_buffer(target) then
    return
  end
  vim.bo[target].modifiable = true
  vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
  vim.bo[target].modifiable = false
end

local function short_date(date)
  return (date or ""):sub(1, 16):gsub("T", " ")
end

local function render_commits(state)
  local lines = {
    string.format(
      "Repository: %s  Branch: %s%s",
      vim.fn.fnamemodify(state.repository, ":t"),
      state.current_branch or "(detached)",
      state.dirty and "  [dirty]" or ""
    ),
    "",
  }
  line_items = {}
  for index, commit in ipairs(state.commits) do
    local marker = commit.hash == state.head and "*" or " "
    table.insert(
      lines,
      string.format("%s %s  %-16s  %-14s  %s", marker, commit.short_hash, short_date(commit.date), commit.author, commit.subject)
    )
    line_items[#lines] = index
  end
  if #state.commits == 0 then
    table.insert(lines, "(No commits)")
  end
  return lines
end

local function render_branches(state)
  local lines = {
    string.format(
      "Repository: %s  Current: %s%s",
      vim.fn.fnamemodify(state.repository, ":t"),
      state.current_branch or ("detached at " .. (state.head or ""):sub(1, 7)),
      state.dirty and "  [dirty]" or ""
    ),
    "",
  }
  line_items = {}
  for index, branch in ipairs(state.branches) do
    local marker = branch.type == "local" and branch.name == state.current_branch and "*" or " "
    local kind = branch.type == "local" and "L" or "R"
    table.insert(
      lines,
      string.format("%s [%s] %-30s  %-16s  %s", marker, kind, branch.name, short_date(branch.date), branch.subject)
    )
    line_items[#lines] = index
  end
  if #state.branches == 0 then
    table.insert(lines, "(No branches)")
  end
  return lines
end

local function preview_highlight(line, mode)
  if mode == "diff" or mode == "details" then
    if line:match("^diff %-%-git") then
      return "GitHistoryTitle"
    elseif line:match("^@@") then
      return "GitHistoryHunk"
    elseif line:match("^%+%+%+") or line:match("^%-%-%-") then
      return "GitHistoryMeta"
    elseif line:match("^%+") then
      return "GitHistoryAdd"
    elseif line:match("^%-") then
      return "GitHistoryDelete"
    end
  end
  if mode == "files" then
    local status = line:match("^([A-Z])")
    if status == "A" then
      return "GitHistoryAdd"
    elseif status == "D" then
      return "GitHistoryDelete"
    elseif status == "M" or status == "T" then
      return "GitHistoryChange"
    elseif status == "R" or status == "C" then
      return "GitHistoryHunk"
    end
  elseif mode == "details" then
    if line:match("^commit ") then
      return "GitHistoryTitle"
    elseif line:match("^Author") or line:match("^Commit") or line:match("^%w+Date:") then
      return "GitHistoryMeta"
    elseif line:match("^    %S") then
      return "GitHistorySubject"
    elseif line:find(" | ", 1, true) then
      return "GitHistoryChange"
    elseif line:match("^%s*%d+ files? changed") then
      return "GitHistoryMeta"
    end
  end
  return nil
end

function M.render(state)
  if not M.is_open() then
    return
  end
  local cursor = state.view == "branches" and state.selected_branch or state.selected_commit
  selected_index = cursor
  local lines = state.view == "branches" and render_branches(state) or render_commits(state)
  set_lines(list_buffer, lines)
  vim.api.nvim_buf_clear_namespace(list_buffer, namespace, 0, -1)
  for line, _ in pairs(line_items) do
    vim.api.nvim_buf_set_extmark(list_buffer, namespace, line - 1, 0, {
      end_col = #lines[line],
      hl_group = lines[line]:sub(1, 1) == "*" and "GitHistoryCurrent" or nil,
    })
  end
  for line, index in pairs(line_items) do
    if index == cursor then
      if vim.api.nvim_win_get_cursor(list_window)[1] ~= line then
        vim.api.nvim_win_set_cursor(list_window, { line, 0 })
      end
      break
    end
  end
  M.set_preview(state.preview ~= "" and state.preview or "Select an item to display details.", state.preview_mode)
  local list_config, preview_config, err = window_configs(state.view)
  if not list_config then
    M.close()
    vim.notify("Git History: " .. err, vim.log.levels.WARN)
    return
  end
  vim.api.nvim_win_set_config(list_window, list_config)
  vim.api.nvim_win_set_config(preview_window, preview_config)
end

function M.set_preview(content, mode)
  local lines = vim.split(content or "", "\n", { plain = true })
  set_lines(preview_buffer, #lines > 0 and lines or { "" })
  vim.api.nvim_buf_clear_namespace(preview_buffer, namespace, 0, -1)
  for index, line in ipairs(lines) do
    local highlight = preview_highlight(line, mode)
    if highlight then
      vim.api.nvim_buf_add_highlight(preview_buffer, namespace, highlight, index - 1, 0, -1)
    end
  end
  if valid_window(preview_window) then
    vim.api.nvim_win_set_cursor(preview_window, { 1, 0 })
  end
end

local function selected_line()
  if not valid_window(list_window) then
    return nil
  end
  return line_items[vim.api.nvim_win_get_cursor(list_window)[1]]
end

local function map(key, callback)
  vim.keymap.set("n", key, callback, {
    buffer = list_buffer,
    silent = true,
    nowait = true,
  })
end

local function mappings()
  local keys = config.keymaps
  map(keys.commits_view, handlers.commits)
  map(keys.branches_view, handlers.branches)
  map(keys.switch_view, handlers.toggle_view)
  map(keys.details, handlers.details)
  map(keys.diff, handlers.diff)
  map(keys.files, handlers.files)
  map(keys.checkout, handlers.checkout)
  map(keys.new_branch, handlers.new_branch)
  map(keys.delete_branch, handlers.delete_branch)
  map(keys.fetch, handlers.fetch)
  map(keys.refresh, handlers.refresh)
  map(keys.back, handlers.back)
  map(keys.close, handlers.close)
  map("<Esc>", handlers.close)
  map("<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= list_window or not line_items[mouse.line] then
      return
    end
    vim.api.nvim_set_current_win(list_window)
    vim.api.nvim_win_set_cursor(list_window, { mouse.line, math.max(0, mouse.column - 1) })
    selected_index = line_items[mouse.line]
    handlers.select(selected_index)
  end)
  map("l", function()
    if valid_window(preview_window) then
      vim.api.nvim_set_current_win(preview_window)
    end
  end)

  local preview_opts = {
    buffer = preview_buffer,
    silent = true,
    nowait = true,
  }
  vim.keymap.set("n", "h", function()
    if valid_window(list_window) then
      vim.api.nvim_set_current_win(list_window)
    end
  end, preview_opts)
  vim.keymap.set("n", keys.close, handlers.close, preview_opts)
  vim.keymap.set("n", "<Esc>", handlers.close, preview_opts)
end

function M.open(options, callbacks, state)
  if M.is_open() then
    vim.api.nvim_set_current_win(list_window)
    return
  end
  if valid_window(list_window) or valid_window(preview_window) then
    M.close()
  end

  config = options
  handlers = callbacks
  local list_config, preview_config, err = window_configs(state.view)
  if not list_config then
    return false, err
  end
  origin_window = vim.api.nvim_get_current_win()
  list_buffer = buffer("git-history-list")
  preview_buffer = buffer("git-history-preview")
  list_window = vim.api.nvim_open_win(list_buffer, true, list_config)
  preview_window = vim.api.nvim_open_win(preview_buffer, false, preview_config)
  vim.wo[list_window].cursorline = true
  vim.wo[list_window].wrap = false
  vim.wo[preview_window].wrap = false
  vim.wo[preview_window].foldenable = false
  vim.wo[preview_window].conceallevel = 0
  mappings()

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = list_buffer,
    callback = function()
      local index = selected_line()
      if index and index ~= selected_index then
        selected_index = index
        handlers.select(index)
      end
    end,
  })
  M.render(state)
  return true
end

function M.close()
  if valid_window(preview_window) then
    vim.api.nvim_win_close(preview_window, true)
  end
  if valid_window(list_window) then
    vim.api.nvim_win_close(list_window, true)
  end
  list_window = nil
  preview_window = nil
  list_buffer = nil
  preview_buffer = nil
  line_items = {}
  selected_index = nil
  if valid_window(origin_window) then
    vim.api.nvim_set_current_win(origin_window)
  end
  origin_window = nil
end

function M.is_open()
  return valid_window(list_window) == true and valid_window(preview_window) == true
end

function M.resize(state)
  if M.is_open() then
    M.render(state)
  end
end

return M
