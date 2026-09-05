local parser = require("git_history.parser")
local process = require("git_history.process")

local M = {}

local log_format = "%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e"
local branch_format =
  "%(refname)%1f%(refname:short)%1f%(objectname)%1f%(upstream:short)%1f%(committerdate:iso-strict)%1f%(subject)%1e"

function M.detect(path, callback)
  process.run(path, { "rev-parse", "--show-toplevel" }, function(ok, stdout, stderr)
    if not ok then
      callback(false, nil, stderr ~= "" and stderr or "not inside a Git repository")
      return
    end
    callback(true, vim.trim(stdout))
  end)
end

function M.status(root, callback)
  local pending = 3
  local result = {}
  local failure = nil

  local function done()
    pending = pending - 1
    if pending == 0 then
      callback(failure == nil, result, failure)
    end
  end

  process.run(root, { "symbolic-ref", "--quiet", "--short", "HEAD" }, function(ok, stdout, stderr)
    if ok then
      result.branch = vim.trim(stdout)
    elseif stderr ~= "" then
      failure = stderr
    end
    done()
  end)
  process.run(root, { "rev-parse", "HEAD" }, function(ok, stdout, stderr)
    if ok then
      result.head = vim.trim(stdout)
    else
      failure = stderr
    end
    done()
  end)
  process.run(root, { "status", "--porcelain" }, function(ok, stdout, stderr)
    if ok then
      result.dirty = vim.trim(stdout) ~= ""
    else
      failure = stderr
    end
    done()
  end)
end

function M.commits(root, max_count, skip, file, callback)
  local args = {
    "log",
    "--date=iso-strict",
    "--no-color",
    "--max-count=" .. max_count,
    "--skip=" .. (skip or 0),
    "--pretty=format:" .. log_format,
  }
  if file and file ~= "" then
    table.insert(args, "--follow")
    vim.list_extend(args, { "--", file })
  end
  process.run(root, args, function(ok, stdout, stderr)
    callback(ok, ok and parser.commits(stdout) or nil, stderr)
  end)
end

function M.branches(root, show_remote, callback)
  local refs = { "refs/heads" }
  if show_remote then
    table.insert(refs, "refs/remotes")
  end
  local args = {
    "for-each-ref",
    "--sort=-committerdate",
    "--format=" .. branch_format,
  }
  vim.list_extend(args, refs)
  process.run(root, args, function(ok, stdout, stderr)
    callback(ok, ok and parser.branches(stdout) or nil, stderr)
  end)
end

function M.preview(root, hash, mode, callback)
  local commands = {
    details = { "show", "--stat", "--patch", "--format=fuller", "--no-ext-diff", "--color=never", hash },
    diff = { "show", "--format=", "--no-ext-diff", "--color=never", hash },
    files = { "diff-tree", "--root", "--no-commit-id", "--name-status", "-r", hash },
  }
  process.run(root, commands[mode] or commands.details, function(ok, stdout, stderr)
    callback(ok, ok and stdout or nil, stderr)
  end)
end

return M
