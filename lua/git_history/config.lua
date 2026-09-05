local M = {}

local defaults = {
  default_view = "commits",
  window = {
    width = 0.9,
    height = 0.85,
    list_width = 0.42,
    border = "rounded",
  },
  log = {
    max_count = 100,
  },
  checkout = {
    confirm = true,
    allow_dirty = false,
  },
  branch = {
    show_remote = true,
    allow_dirty = false,
    allow_delete = true,
  },
  keymaps = {
    commits_view = "1",
    branches_view = "2",
    switch_view = "<Tab>",
    details = "<CR>",
    diff = "d",
    files = "f",
    checkout = "c",
    new_branch = "n",
    delete_branch = "D",
    fetch = "P",
    refresh = "r",
    back = "B",
    close = "q",
  },
}

M.values = vim.deepcopy(defaults)

local function ratio(name, value)
  assert(type(value) == "number" and value > 0 and value <= 1, name .. " must be greater than 0 and at most 1")
end

function M.setup(opts)
  opts = opts or {}
  assert(type(opts) == "table", "git_history setup options must be a table")
  local values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)

  assert(values.default_view == "commits" or values.default_view == "branches", "default_view must be commits or branches")
  ratio("window.width", values.window.width)
  ratio("window.height", values.window.height)
  assert(
    type(values.window.list_width) == "number"
      and values.window.list_width >= 0.2
      and values.window.list_width <= 0.8,
    "window.list_width must be between 0.2 and 0.8"
  )
  assert(
    type(values.log.max_count) == "number"
      and values.log.max_count >= 1
      and values.log.max_count % 1 == 0,
    "log.max_count must be a positive integer"
  )

  M.values = values
  return values
end

return M
