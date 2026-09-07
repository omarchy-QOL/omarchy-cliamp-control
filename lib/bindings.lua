-- Evaluate source bindings because Hyprland exposes opaque dispatcher IDs.
local config, toggle = assert(arg[1]), assert(arg[2])
local bindings = {}
local boolean_options = {
  "mouse", "repeating", "locked", "release", "non_consuming", "transparent",
  "ignore_mods", "dont_inhibit", "long_press", "submap_universal", "click",
  "drag", "allow_input_capture",
}

local noop
noop = setmetatable({}, {
  __index = function() return noop end,
  __call = function() return noop end,
})

local function options_lua(options)
  local fields = {
    "description = " .. string.format("%q", options.description or "CLIamp"),
  }
  for _, name in ipairs(boolean_options) do
    if type(options[name]) == "boolean" then
      fields[#fields + 1] = name .. " = " .. tostring(options[name])
    end
  end
  if type(options.device) == "table" then
    local device = {}
    if type(options.device.inclusive) == "boolean" then
      device[#device + 1] = "inclusive = " .. tostring(options.device.inclusive)
    end
    if type(options.device.list) == "table" then
      local names = {}
      for _, name in ipairs(options.device.list) do
        names[#names + 1] = string.format("%q", name)
      end
      device[#device + 1] = "list = { " .. table.concat(names, ", ") .. " }"
    end
    fields[#fields + 1] = "device = { " .. table.concat(device, ", ") .. " }"
  end
  return "{ " .. table.concat(fields, ", ") .. " }"
end

local function remember(keys, command, options)
  bindings[keys] = { command = command, options = options_lua(options or {}) }
  return noop
end

hl = setmetatable({
  dsp = setmetatable({ exec_cmd = function(command) return command end }, {
    __index = function() return noop end,
  }),
  bind = remember,
  unbind = function(keys) bindings[keys] = nil end,
  get_active_window = function() return nil end,
  get_active_monitor = function() return nil end,
  get_config = function() return nil end,
  get_monitors = function() return {} end,
}, { __index = function() return noop end })

local function load_config(path)
  local ok, error = pcall(dofile, path)
  if not ok then
    io.stderr:write("CLIamp binding scan failed: " .. tostring(error) .. "\n")
    os.exit(1)
  end
end

load_config(assert(os.getenv("OMARCHY_PATH"), "OMARCHY_PATH is required")
  .. "/default/hypr/bootstrap.lua")
load_config(config)

local function is_cliamp(command)
  if type(command) ~= "string" then return false end
  command = command:gsub("['\"]", "") .. " "
  return command:match("^omarchy%-launch%-or%-focus%-tui%s+cliamp%s")
    or command:match("^omarchy%-launch%-tui%s+cliamp%s")
end

local function json_string(value)
  return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
    return string.format("\\u%04x", char:byte())
  end) .. '"'
end

local keys = {}
for key, binding in pairs(bindings) do
  if is_cliamp(binding.command) then keys[#keys + 1] = key end
end
table.sort(keys)

local expressions, labels = {}, {}
local command = "bash '" .. toggle:gsub("'", "'\\''") .. "'"
for _, key in ipairs(keys) do
  expressions[#expressions + 1] = string.format(
    "hl.unbind(%q); hl.bind(%q, hl.dsp.exec_cmd(%q), %s)",
    key, key, command, bindings[key].options
  )
  labels[#labels + 1] = json_string(key:gsub("%s*%+%s*", "+"))
end
io.write('{"expression":', json_string(table.concat(expressions, "; ")),
  ',"labels":[', table.concat(labels, ","), "]}\n")
