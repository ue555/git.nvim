local M = {}

local values = {
  repository = nil,
  file = nil,
  current_branch = nil,
  head = nil,
  original_ref = nil,
  original_ref_type = nil,
  dirty = false,
  view = "commits",
  commits = {},
  branches = {},
  selected_commit = 1,
  selected_branch = 1,
  preview_mode = "details",
  preview = "",
  loading = false,
  error = nil,
}

function M.get()
  return values
end

function M.reset(view)
  values.repository = nil
  values.file = nil
  values.current_branch = nil
  values.head = nil
  values.original_ref = nil
  values.original_ref_type = nil
  values.dirty = false
  values.view = view or "commits"
  values.commits = {}
  values.branches = {}
  values.selected_commit = 1
  values.selected_branch = 1
  values.preview_mode = "details"
  values.preview = ""
  values.loading = false
  values.error = nil
end

function M.selected()
  if values.view == "branches" then
    return values.branches[values.selected_branch]
  end
  return values.commits[values.selected_commit]
end

return M
