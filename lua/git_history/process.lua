local M = {}

local function command(root, args)
  local result = { "git" }
  if root and root ~= "" then
    vim.list_extend(result, { "-C", root })
  end
  vim.list_extend(result, args)
  return result
end

function M.run(root, args, callback)
  return vim.system(command(root, args), {
    text = true,
  }, function(result)
    vim.schedule(function()
      callback(result.code == 0, result.stdout or "", vim.trim(result.stderr or ""), result.code)
    end)
  end)
end

function M.run_sync(root, args)
  local result = vim.system(command(root, args), { text = true }):wait()
  return result.code == 0, result.stdout or "", vim.trim(result.stderr or ""), result.code
end

return M
