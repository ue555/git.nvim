local ok, err = xpcall(function()
  dofile("tests/git_history_spec.lua")
end, debug.traceback)

if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end

vim.cmd("qa!")
