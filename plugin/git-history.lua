if vim.g.loaded_git_history_nvim then
  return
end
vim.g.loaded_git_history_nvim = true

local git_history = require("git_history")

local function context_directory(argument)
  if argument ~= "" then
    return argument
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file ~= "" and vim.fn.isdirectory(file) == 0 then
    return vim.fn.fnamemodify(file, ":p:h")
  end
  return vim.fn.getcwd()
end

vim.api.nvim_create_user_command("GitHistory", function(args)
  git_history.open({
    cwd = context_directory(args.args),
    view = "commits",
  })
end, {
  nargs = "?",
  complete = "dir",
  desc = "Open repository commit history",
})
vim.api.nvim_create_user_command("GitHistoryFile", git_history.open_file, {
  desc = "Open history for the current file",
})
vim.api.nvim_create_user_command("GitBranches", function(args)
  git_history.open({
    cwd = context_directory(args.args),
    view = "branches",
  })
end, {
  nargs = "?",
  complete = "dir",
  desc = "Open repository branch navigator",
})
vim.api.nvim_create_user_command("GitHistoryRefresh", git_history.refresh, {
  desc = "Refresh Git history",
})
vim.api.nvim_create_user_command("GitHistoryClose", git_history.close, {
  desc = "Close Git history",
})
vim.api.nvim_create_user_command("GitHistoryBack", git_history.back, {
  desc = "Return to the branch active before navigation",
})
vim.api.nvim_create_user_command("GitCheckout", function(args)
  git_history.open({
    cwd = vim.fn.getcwd(),
    view = "commits",
    on_loaded = function()
      git_history.checkout_commit(args.args)
    end,
  })
end, {
  nargs = 1,
  desc = "Switch to a commit in detached HEAD mode",
})
vim.api.nvim_create_user_command("GitSwitch", function(args)
  git_history.open({
    cwd = vim.fn.getcwd(),
    view = "branches",
    on_loaded = function()
      git_history.switch_branch(args.args)
    end,
  })
end, {
  nargs = 1,
  desc = "Switch to a local or remote branch",
})
vim.api.nvim_create_user_command("GitNewBranch", function(args)
  git_history.open({
    cwd = vim.fn.getcwd(),
    view = "branches",
    on_loaded = function()
      git_history.create_branch(args.args)
    end,
  })
end, {
  nargs = 1,
  desc = "Create and switch to a new branch",
})

local group = vim.api.nvim_create_augroup("GitHistoryNvim", { clear = true })
vim.api.nvim_create_autocmd("VimResized", {
  group = group,
  callback = git_history.resize,
})
