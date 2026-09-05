local M = {}

local field_separator = string.char(31)
local record_separator = string.char(30)

local function records(output)
  local result = {}
  for record in output:gmatch("([^" .. record_separator .. "]+)") do
    record = record:gsub("^[\r\n]+", ""):gsub("[\r\n]+$", "")
    if record ~= "" then
      table.insert(result, record)
    end
  end
  return result
end

local function fields(record)
  local result = {}
  local start = 1
  while true do
    local index = record:find(field_separator, start, true)
    if not index then
      table.insert(result, record:sub(start))
      break
    end
    table.insert(result, record:sub(start, index - 1))
    start = index + 1
  end
  return result
end

function M.commits(output)
  local result = {}
  for _, record in ipairs(records(output)) do
    local item = fields(record)
    if #item >= 5 then
      table.insert(result, {
        hash = item[1],
        short_hash = item[2],
        author = item[3],
        date = item[4],
        subject = table.concat(item, field_separator, 5),
      })
    end
  end
  return result
end

function M.branches(output)
  local result = {}
  for _, record in ipairs(records(output)) do
    local item = fields(record)
    if #item >= 6 and not item[2]:match("/HEAD$") then
      table.insert(result, {
        type = item[1]:match("^refs/heads/") and "local" or "remote",
        full_name = item[1],
        name = item[2],
        hash = item[3],
        upstream = item[4],
        date = item[5],
        subject = table.concat(item, field_separator, 6),
      })
    end
  end
  return result
end

return M
