local actions = require("git_history.actions")
local config = require("git_history.config")
local repository = require("git_history.repository")
local state = require("git_history.state")
local ui = require("git_history.ui")

local M = {}

local configured = false
local preview_generation = 0
local load_generation = 0
local session_generation = 0

local function is_current(token, root)
  return token == session_generation and (not root or state.get().repository == root)
end

local function notify_error(message, token, root)
  if token and not is_current(token, root) then
    return
  end
  local values = state.get()
  values.loading = false
  values.error = message
  values.preview = "Error: " .. message
  ui.render(values)
  vim.notify("Git History: " .. message, vim.log.levels.ERROR)
end

local function ensure_setup()
  if not configured then
    M.setup()
  end
end

local function selected_hash()
  local item = state.selected()
  return item and item.hash or nil
end

local function confirm(prompt, callback)
  if not config.values.checkout.confirm then
    callback(true)
    return
  end
  vim.ui.select({ "Continue", "Cancel" }, {
    prompt = prompt,
  }, function(choice)
    callback(choice == "Continue")
  end)
end

local function refresh_status(callback, token, root)
  local values = state.get()
  token = token or session_generation
  root = root or values.repository
  repository.status(root, function(ok, status, err)
    if not is_current(token, root) then
      return
    end
    if not ok then
      notify_error(err, token, root)
      return
    end
    values.current_branch = status.branch
    values.head = status.head
    values.dirty = status.dirty
    callback()
  end)
end

local function render_preview(mode)
  local values = state.get()
  local token = session_generation
  local root = values.repository
  local hash = selected_hash()
  if not hash then
    values.preview = "No item selected."
    ui.render(values)
    return
  end

  preview_generation = preview_generation + 1
  local generation = preview_generation
  values.preview_mode = mode or values.preview_mode
  values.preview = "Loading..."
  ui.render(values)
  repository.preview(root, hash, values.preview_mode, function(ok, content, err)
    if generation ~= preview_generation or not is_current(token, root) then
      return
    end
    if not ok then
      notify_error(err, token, root)
      return
    end
    values.preview = content
    ui.render(values)
  end)
end

local function load_view(callback, token)
  local values = state.get()
  token = token or session_generation
  local root = values.repository
  local view = values.view
  local file = values.file
  load_generation = load_generation + 1
  local generation = load_generation
  values.loading = true
  values.error = nil
  values.preview = "Loading..."
  ui.render(values)

  if view == "branches" then
    repository.branches(root, config.values.branch.show_remote, function(ok, branches, err)
      if generation ~= load_generation or not is_current(token, root) or state.get().view ~= view then
        return
      end
      values.loading = false
      if not ok then
        notify_error(err, token, root)
        return
      end
      values.branches = branches
      values.selected_branch = math.min(math.max(1, values.selected_branch), math.max(1, #branches))
      ui.render(values)
      render_preview("details")
      if callback then
        callback(true)
      end
    end)
    return
  end

  repository.commits(
    root,
    config.values.log.max_count,
    0,
    file,
    function(ok, commits, err)
      if generation ~= load_generation or not is_current(token, root) or state.get().view ~= view then
        return
      end
      values.loading = false
      if not ok then
        notify_error(err, token, root)
        return
      end
      values.commits = commits
      values.selected_commit = math.min(math.max(1, values.selected_commit), math.max(1, #commits))
      ui.render(values)
      render_preview("details")
      if callback then
        callback(true)
      end
    end
  )
end

local function refresh_after_action(callback, token, root)
  refresh_status(function()
    load_view(callback, token)
  end, token, root)
end

local function remember_original()
  local values = state.get()
  if not values.original_ref then
    values.original_ref = values.current_branch or values.head
    values.original_ref_type = values.current_branch and "branch" or "commit"
  end
end

local function complete_action(ok, _, callback, token, root)
  if not is_current(token, root) then
    return
  end
  if not ok then
    if callback then
      callback(false)
    end
    return
  end
  refresh_after_action(function()
    if callback then
      callback(true)
    end
  end, token, root)
end

local function ui_handlers()
  return {
    commits = function()
      M.set_view("commits")
    end,
    branches = function()
      M.set_view("branches")
    end,
    toggle_view = function()
      M.set_view(state.get().view == "commits" and "branches" or "commits")
    end,
    details = function()
      if state.get().view == "branches" then
        M.switch_branch()
      else
        render_preview("details")
      end
    end,
    diff = function()
      render_preview("diff")
    end,
    files = function()
      render_preview("files")
    end,
    checkout = function()
      M.checkout_commit()
    end,
    new_branch = function()
      M.create_branch()
    end,
    delete_branch = function()
      M.delete_branch()
    end,
    fetch = M.fetch,
    refresh = M.refresh,
    back = M.back,
    close = M.close,
    select = function(index)
      local values = state.get()
      if values.view == "branches" then
        values.selected_branch = index
      else
        values.selected_commit = index
      end
      render_preview("details")
    end,
  }
end

local function detect_and_load(opts, token)
  local values = state.get()
  local start = opts.cwd or vim.fn.getcwd()
  repository.detect(start, function(ok, root, err)
    if token ~= session_generation then
      return
    end
    if not ok then
      notify_error(err, token)
      vim.schedule(function()
        vim.notify(
          "Git History: open a file inside a Git repository or pass a repository directory to :GitBranches",
          vim.log.levels.INFO
        )
      end)
      return
    end
    values.repository = root
    values.file = opts.file
    refresh_status(function()
      if not ui.is_open() then
        local opened, open_err = ui.open(config.values, ui_handlers(), values)
        if not opened then
          notify_error(open_err, token, root)
          return
        end
      end
      load_view(opts.on_loaded, token)
    end, token, root)
  end)
end

function M.setup(opts)
  config.setup(opts)
  vim.api.nvim_set_hl(0, "GitHistoryCurrent", { default = true, link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "GitHistoryTitle", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "GitHistoryMeta", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "GitHistorySubject", { default = true, link = "String" })
  vim.api.nvim_set_hl(0, "GitHistoryAdd", { default = true, link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "GitHistoryDelete", { default = true, link = "DiffDelete" })
  vim.api.nvim_set_hl(0, "GitHistoryChange", { default = true, link = "DiffChange" })
  vim.api.nvim_set_hl(0, "GitHistoryHunk", { default = true, link = "DiagnosticInfo" })
  configured = true
  return M
end

function M.open(opts)
  ensure_setup()
  opts = opts or {}
  session_generation = session_generation + 1
  load_generation = load_generation + 1
  preview_generation = preview_generation + 1
  local token = session_generation
  state.reset(opts.view or config.values.default_view)
  detect_and_load(opts, token)
end

function M.open_file()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    notify_error("the current buffer has no file")
    return
  end
  M.open({
    cwd = vim.fn.fnamemodify(file, ":h"),
    file = file,
    view = "commits",
  })
end

function M.close()
  session_generation = session_generation + 1
  load_generation = load_generation + 1
  preview_generation = preview_generation + 1
  ui.close()
end

function M.set_view(view)
  local values = state.get()
  if view ~= "commits" and view ~= "branches" then
    return
  end
  values.view = view
  values.preview_mode = "details"
  load_view()
end

function M.refresh()
  if not state.get().repository then
    return
  end
  refresh_after_action()
end

function M.checkout_commit(hash, callback)
  local values = state.get()
  local token = session_generation
  local root = values.repository
  hash = hash or (values.view == "commits" and selected_hash())
  if not hash then
    notify_error("no commit selected")
    return
  end
  confirm("Switch to detached HEAD at " .. hash:sub(1, 7) .. "?", function(accepted)
    if not accepted or not is_current(token, root) then
      return
    end
    remember_original()
    actions.checkout_commit(root, hash, config.values.checkout.allow_dirty, function(ok, message)
      complete_action(ok, message, callback, token, root)
    end)
  end)
end

function M.switch_branch(branch, callback)
  local values = state.get()
  local token = session_generation
  local root = values.repository
  if type(branch) == "string" then
    local requested = branch
    branch = nil
    for _, item in ipairs(values.branches) do
      if item.name == requested then
        branch = item
        break
      end
    end
    if not branch then
      notify_error("branch not found: " .. requested)
      return
    end
  end
  branch = type(branch) == "table" and branch or (values.view == "branches" and state.selected())
  if not branch then
    notify_error("no branch selected")
    return
  end
  if branch.type == "local" and branch.name == values.current_branch then
    return
  end
  confirm("Switch to branch " .. branch.name .. "?", function(accepted)
    if not accepted or not is_current(token, root) then
      return
    end
    remember_original()
    actions.switch_branch(root, branch, config.values.branch.allow_dirty, function(ok, message)
      complete_action(ok, message, callback, token, root)
    end)
  end)
end

function M.create_branch(name, start_point, callback)
  local values = state.get()
  local token = session_generation
  local root = values.repository
  local function create(value)
    if not value or vim.trim(value) == "" or not is_current(token, root) then
      return
    end
    local start = start_point
    if not start then
      start = values.view == "commits" and selected_hash() or values.head
    end
    remember_original()
    actions.create_branch(root, value, start, config.values.branch.allow_dirty, function(ok, message)
      complete_action(ok, message, callback, token, root)
    end)
  end
  if name then
    create(name)
  else
    vim.ui.input({ prompt = "New branch name: " }, create)
  end
end

function M.delete_branch(branch, callback)
  local values = state.get()
  local token = session_generation
  local root = values.repository
  branch = branch or (values.view == "branches" and state.selected())
  if not branch then
    notify_error("no branch selected")
    return
  end
  if not config.values.branch.allow_delete then
    notify_error("branch deletion is disabled")
    return
  end
  confirm("Delete branch " .. branch.name .. "?", function(accepted)
    if accepted and is_current(token, root) then
      actions.delete_branch(root, branch, values.current_branch, function(ok, message)
        complete_action(ok, message, callback, token, root)
      end)
    end
  end)
end

function M.back(callback)
  local values = state.get()
  local token = session_generation
  local root = values.repository
  actions.back(
    root,
    values.original_ref,
    values.original_ref_type,
    config.values.branch.allow_dirty,
    function(ok, message)
      complete_action(ok, message, callback, token, root)
    end
  )
end

function M.fetch()
  local values = state.get()
  local token = session_generation
  local root = values.repository
  if root then
    actions.fetch(root, function(ok, message)
      complete_action(ok, message, nil, token, root)
    end)
  end
end

function M.get_state()
  return vim.deepcopy(state.get())
end

function M.resize()
  ui.resize(state.get())
end

return M
