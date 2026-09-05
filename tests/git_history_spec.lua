local git_history = require("git_history")
local config = require("git_history.config")
local parser = require("git_history.parser")
local repository = require("git_history.repository")
local ui = require("git_history.ui")

local function assert_equal(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error((message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
  end
end

local function git(root, ...)
  local command = { "git", "-C", root }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    error(table.concat(command, " ") .. " failed: " .. (result.stderr or ""))
  end
  return vim.trim(result.stdout or "")
end

local function wait_for(predicate, message)
  assert(vim.wait(5000, predicate, 10), message)
end

for _, command in ipairs({
  "GitHistory",
  "GitHistoryFile",
  "GitBranches",
  "GitHistoryRefresh",
  "GitHistoryClose",
  "GitHistoryBack",
  "GitCheckout",
  "GitSwitch",
  "GitNewBranch",
}) do
  assert_equal(2, vim.fn.exists(":" .. command), command .. " must exist")
end

local commit_output = table.concat({
  "aaaaaaaa" .. string.char(31) .. "aaaaaaa" .. string.char(31) .. "A U Thor" .. string.char(31)
    .. "2026-09-05T00:00:00+09:00"
    .. string.char(31)
    .. "Subject with | separator"
    .. string.char(30),
})
local parsed = parser.commits(commit_output)
assert_equal(1, #parsed)
assert_equal("A U Thor", parsed[1].author)
assert_equal("Subject with | separator", parsed[1].subject)

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
git(root, "init", "-b", "main")
git(root, "config", "user.name", "Test User")
git(root, "config", "user.email", "test@example.com")

local file = root .. "/example.txt"
vim.fn.writefile({ "first" }, file)
git(root, "add", "example.txt")
git(root, "commit", "-m", "First commit")
local first_hash = git(root, "rev-parse", "HEAD")
git(root, "branch", "feature")

vim.fn.writefile({ "first", "second" }, file)
git(root, "add", "example.txt")
git(root, "commit", "-m", "Second commit")
local main_hash = git(root, "rev-parse", "HEAD")

local root_files = nil
repository.preview(root, first_hash, "files", function(ok, content)
  assert(ok)
  root_files = content
end)
wait_for(function()
  return root_files ~= nil
end, "root commit files preview did not load")
assert(root_files:find("example.txt", 1, true), "root commit files preview omitted the added file")

git_history.setup({
  checkout = {
    confirm = false,
    allow_dirty = false,
  },
  branch = {
    show_remote = false,
    allow_dirty = false,
  },
})

local original_lines = vim.o.lines
vim.o.lines = 3
local compact_opened = ui.open(config.values, {}, { view = "commits" })
assert_equal(false, compact_opened, "minimum-height editor must be rejected without opening invalid windows")
vim.o.lines = original_lines

git_history.open({ cwd = root, view = "commits" })
wait_for(function()
  local current = git_history.get_state()
  return ui.is_open()
    and #current.commits == 2
    and current.preview:find("Second commit", 1, true) ~= nil
end, "commit history did not load")
local state = git_history.get_state()
assert_equal(root, state.repository)
assert_equal("main", state.current_branch)
assert_equal(main_hash, state.head)
assert_equal("Second commit", state.commits[1].subject)
assert(
  state.preview:find("Second commit", 1, true),
  "selected commit details must be loaded into the preview"
)
assert(
  state.preview:find("+second", 1, true),
  "selected commit details must include its patch without requiring the diff mapping"
)
local preview_marks = 0
local namespace = vim.api.nvim_create_namespace("git-history-ui")
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buffer].filetype == "git-history-preview" then
    preview_marks = #vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {})
  end
end
assert(preview_marks > 0, "commit details must include color highlights")

local checkout_done = false
git_history.checkout_commit(first_hash, function(ok)
  assert(ok)
  checkout_done = true
end)
wait_for(function()
  return checkout_done
end, "commit checkout did not complete")
assert_equal("", git(root, "branch", "--show-current"))
assert_equal(first_hash, git(root, "rev-parse", "HEAD"))

local back_done = false
git_history.back(function(ok)
  assert(ok)
  back_done = true
end)
wait_for(function()
  return back_done
end, "return to original branch did not complete")
assert_equal("main", git(root, "branch", "--show-current"))

git_history.set_view("branches")
wait_for(function()
  return #git_history.get_state().branches == 2
end, "branch list did not load")
local feature = nil
for _, branch in ipairs(git_history.get_state().branches) do
  if branch.name == "feature" then
    feature = branch
  end
end
assert(feature, "feature branch was not listed")

local switch_done = false
git_history.switch_branch(feature, function(ok)
  assert(ok)
  switch_done = true
end)
wait_for(function()
  return switch_done
end, "branch switch did not complete")
assert_equal("feature", git(root, "branch", "--show-current"))

local create_done = false
git_history.create_branch("topic", first_hash, function(ok)
  assert(ok)
  create_done = true
end)
wait_for(function()
  return create_done
end, "branch creation did not complete")
assert_equal("topic", git(root, "branch", "--show-current"))

vim.fn.writefile({ "dirty" }, file)
local rejected = false
git_history.checkout_commit(main_hash, function(ok)
  assert_equal(false, ok)
  rejected = true
end)
wait_for(function()
  return rejected
end, "dirty checkout was not rejected")
assert_equal("topic", git(root, "branch", "--show-current"))
git(root, "restore", "example.txt")

vim.fn.writefile({ "ignored.txt" }, root .. "/.gitignore")
git(root, "add", ".gitignore")
git(root, "commit", "-m", "Ignore generated file")
vim.fn.writefile({ "local generated content" }, root .. "/ignored.txt")
local ignored_rejected = false
git_history.checkout_commit(first_hash, function(ok)
  assert_equal(false, ok)
  ignored_rejected = true
end)
wait_for(function()
  return ignored_rejected
end, "ignored untracked file did not block checkout")
assert_equal("local generated content", vim.fn.readfile(root .. "/ignored.txt")[1])
vim.fn.delete(root .. "/ignored.txt")

local unrelated_remote_rejected = false
git_history.switch_branch({
  type = "remote",
  name = "origin/feature",
  hash = first_hash,
}, function(ok)
  assert_equal(false, ok)
  unrelated_remote_rejected = true
end)
wait_for(function()
  return unrelated_remote_rejected
end, "unrelated local branch was used for a remote branch")
assert_equal("topic", git(root, "branch", "--show-current"))

local file_commits = nil
repository.commits(root, 100, 0, file, function(ok, commits)
  assert(ok)
  file_commits = commits
end)
wait_for(function()
  return file_commits ~= nil
end, "file history did not load")
assert_equal(1, #file_commits, "file history must only include commits reachable from HEAD that changed the file")

git(root, "switch", "--detach", first_hash)
git_history.close()
git_history.open({ cwd = root, view = "commits" })
wait_for(function()
  return ui.is_open() and git_history.get_state().current_branch == nil
end, "detached repository did not load")
local detached_checkout_done = false
git_history.checkout_commit(main_hash, function(ok)
  assert(ok)
  detached_checkout_done = true
end)
wait_for(function()
  return detached_checkout_done
end, "detached-to-detached checkout did not complete")
local detached_back_done = false
git_history.back(function(ok)
  assert(ok)
  detached_back_done = true
end)
wait_for(function()
  return detached_back_done
end, "return to original detached commit did not complete")
assert_equal("", git(root, "branch", "--show-current"))
assert_equal(first_hash, git(root, "rev-parse", "HEAD"))

git_history.close()
assert_equal(false, ui.is_open())
vim.fn.delete(root, "rf")

print("git.nvim tests passed")
