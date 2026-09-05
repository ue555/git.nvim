local process = require("git_history.process")

local M = {}

local function fail(message, callback)
  vim.notify("Git History: " .. message, vim.log.levels.ERROR)
  callback(false, message)
end

local function ensure_clean(root, allow_dirty, callback)
  local pending = 3
  local failure = nil
  local tracked_dirty = false
  local untracked = false

  local function done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    if failure then
      fail(failure, callback)
    elseif untracked then
      fail("untracked or ignored files must be moved before changing the worktree", callback)
    elseif tracked_dirty and not allow_dirty then
      fail("working tree has uncommitted changes", callback)
    else
      callback(true)
    end
  end

  process.run(root, { "status", "--porcelain", "--untracked-files=no" }, function(ok, stdout, stderr)
    if not ok then
      failure = stderr
    else
      tracked_dirty = vim.trim(stdout) ~= ""
    end
    done()
  end)
  process.run(root, { "ls-files", "--others", "--exclude-standard" }, function(ok, stdout, stderr)
    if not ok then
      failure = stderr
    else
      untracked = untracked or vim.trim(stdout) ~= ""
    end
    done()
  end)
  process.run(root, { "ls-files", "--others", "--ignored", "--exclude-standard" }, function(ok, stdout, stderr)
    if not ok then
      failure = stderr
    else
      untracked = untracked or vim.trim(stdout) ~= ""
    end
    done()
  end)
end

local function run(root, args, callback)
  process.run(root, args, function(ok, stdout, stderr)
    if not ok then
      fail(stderr ~= "" and stderr or "Git command failed", callback)
      return
    end
    callback(true, vim.trim(stdout))
  end)
end

function M.checkout_commit(root, hash, allow_dirty, callback)
  ensure_clean(root, allow_dirty, function(ok, message)
    if not ok then
      callback(false, message)
      return
    end
    run(root, { "switch", "--detach", hash }, callback)
  end)
end

function M.switch_branch(root, branch, allow_dirty, callback)
  ensure_clean(root, allow_dirty, function(ok, message)
    if not ok then
      callback(false, message)
      return
    end
    if branch.type == "local" then
      run(root, { "switch", branch.name }, callback)
      return
    end

    local local_name = branch.name:match("^[^/]+/(.+)$") or branch.name
    process.run(root, { "show-ref", "--verify", "--quiet", "refs/heads/" .. local_name }, function(exists)
      if not exists then
        run(root, { "switch", "--track", branch.name }, callback)
        return
      end

      process.run(
        root,
        { "for-each-ref", "--format=%(upstream:short)", "refs/heads/" .. local_name },
        function(upstream_ok, stdout, stderr)
          if not upstream_ok then
            fail(stderr, callback)
          elseif vim.trim(stdout) ~= branch.name then
            fail(
              "local branch "
                .. local_name
                .. " does not track "
                .. branch.name
                .. "; switch to the local branch explicitly or choose another name",
              callback
            )
          else
            run(root, { "switch", local_name }, callback)
          end
        end
      )
    end)
  end)
end

function M.create_branch(root, name, start_point, allow_dirty, callback)
  name = vim.trim(name or "")
  if name == "" then
    fail("branch name cannot be empty", callback)
    return
  end
  ensure_clean(root, allow_dirty, function(ok, message)
    if not ok then
      callback(false, message)
      return
    end
    local args = { "switch", "-c", name }
    if start_point and start_point ~= "" then
      table.insert(args, start_point)
    end
    run(root, args, callback)
  end)
end

function M.delete_branch(root, branch, current_branch, callback)
  if branch.type ~= "local" then
    fail("remote branch deletion is not supported", callback)
    return
  end
  if branch.name == current_branch then
    fail("the current branch cannot be deleted", callback)
    return
  end
  run(root, { "branch", "-d", branch.name }, callback)
end

function M.back(root, original_ref, original_ref_type, allow_dirty, callback)
  if not original_ref or original_ref == "" then
    fail("no original branch or commit was recorded", callback)
    return
  end
  ensure_clean(root, allow_dirty, function(ok, message)
    if not ok then
      callback(false, message)
      return
    end
    local args = original_ref_type == "commit" and { "switch", "--detach", original_ref }
      or { "switch", original_ref }
    run(root, args, callback)
  end)
end

function M.fetch(root, callback)
  run(root, { "fetch", "--all", "--prune" }, callback)
end

return M
