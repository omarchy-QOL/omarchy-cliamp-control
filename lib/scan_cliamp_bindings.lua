-- Discover effective CLIamp binds without depending on Hyprland's opaque
-- __lua dispatcher IDs.

local config = arg[1]
  or (os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
local bindings = {}
local order = {}
local boolean_options = {
  "mouse",
  "repeating",
  "locked",
  "release",
  "non_consuming",
  "transparent",
  "ignore_mods",
  "dont_inhibit",
  "long_press",
  "submap_universal",
  "click",
  "drag",
  "allow_input_capture",
}

local function dispatcher(kind, value)
  return {
    __cliamp_dispatcher = true,
    kind = kind or "",
    value = value or "",
  }
end

local function lua_literal(value)
  local value_type = type(value)

  if value_type == "string" then
    return string.format("%q", value)
  elseif value_type == "number" or value_type == "boolean" then
    return tostring(value)
  elseif value_type == "nil" then
    return "nil"
  end

  return "nil"
end

local function call_expression(path, ...)
  local values = {}
  for index = 1, select("#", ...) do
    values[index] = lua_literal(select(index, ...))
  end
  return path .. "(" .. table.concat(values, ", ") .. ")"
end

local function dsp_proxy(path)
  return setmetatable({ path = path }, {
    __index = function(self, key)
      return dsp_proxy(self.path .. "." .. tostring(key))
    end,
    __call = function(self, ...)
      local value = ...
      if self.path == "hl.dsp.exec_cmd" and type(value) == "string" then
        return dispatcher("exec", value)
      end
      return dispatcher("lua", call_expression(self.path, ...))
    end,
  })
end

local noop
noop = setmetatable({}, {
  __index = function()
    return noop
  end,
  __call = function()
    return noop
  end,
})

local function copy_bind_options(opts)
  local source = type(opts) == "table" and opts or {}
  local copied = {}

  for _, name in ipairs(boolean_options) do
    if type(source[name]) == "boolean" then
      copied[name] = source[name]
    end
  end

  if type(source.device) == "table" then
    local device = {}
    if type(source.device.inclusive) == "boolean" then
      device.inclusive = source.device.inclusive
    end
    if type(source.device.list) == "table" then
      device.list = {}
      for _, value in ipairs(source.device.list) do
        if type(value) == "string" then
          device.list[#device.list + 1] = value
        end
      end
    end
    if next(device) ~= nil then
      copied.device = device
    end
  end

  return copied
end

local function remember(keys, bind_dispatcher, opts)
  keys = tostring(keys or "")
  if keys == "" then
    return noop
  end

  local value = ""
  if type(bind_dispatcher) == "string" then
    value = bind_dispatcher
  elseif type(bind_dispatcher) == "table"
      and bind_dispatcher.__cliamp_dispatcher then
    value = bind_dispatcher.value
  end

  opts = type(opts) == "table" and opts or {}
  if bindings[keys] == nil then
    order[#order + 1] = keys
  end
  bindings[keys] = {
    keys = keys,
    description = tostring(opts.description or opts.desc or ""),
    command = value,
    options = copy_bind_options(opts),
  }
  return noop
end

hl = setmetatable({
  dsp = dsp_proxy("hl.dsp"),
  bind = remember,
  unbind = function(keys)
    bindings[tostring(keys or "")] = nil
    return noop
  end,
  get_active_window = function()
    return nil
  end,
  get_active_monitor = function()
    return nil
  end,
  get_config = function()
    return nil
  end,
  get_monitors = function()
    return {}
  end,
}, {
  __index = function()
    return noop
  end,
})

local omarchy_path = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
local bootstrap = omarchy_path .. "/default/hypr/bootstrap.lua"
local bootstrapped, bootstrap_error = pcall(dofile, bootstrap)
if not bootstrapped then
  io.stderr:write(
    "CLIamp binding bootstrap failed: " .. tostring(bootstrap_error) .. "\n"
  )
  os.exit(1)
end

local loaded, load_error = pcall(dofile, config)
if not loaded then
  io.stderr:write("CLIamp binding scan failed: " .. tostring(load_error) .. "\n")
  os.exit(1)
end

local function is_cliamp_binding(binding)
  local command = string.lower(binding.command)
    :gsub("['\"]", "")
    :gsub("%s+", " ")

  return string.find(
      command, "omarchy-launch-or-focus-tui cliamp", 1, true) ~= nil
    or string.find(command, "omarchy-launch-tui cliamp", 1, true) ~= nil
    or string.find(command, "toggle_cliamp.sh", 1, true) ~= nil
    or string.find(command, "quake_toggle.sh music", 1, true) ~= nil
end

local function json_string(value)
  return "\"" .. tostring(value or "")
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\b", "\\b")
    :gsub("\f", "\\f")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t") .. "\""
end

local function json_options(options)
  local fields = {}

  for _, name in ipairs(boolean_options) do
    if type(options[name]) == "boolean" then
      fields[#fields + 1] = json_string(name) .. ":"
        .. tostring(options[name])
    end
  end

  if type(options.device) == "table" then
    local device_fields = {}
    if type(options.device.inclusive) == "boolean" then
      device_fields[#device_fields + 1] = '"inclusive":'
        .. tostring(options.device.inclusive)
    end
    if type(options.device.list) == "table" then
      local values = {}
      for _, value in ipairs(options.device.list) do
        values[#values + 1] = json_string(value)
      end
      device_fields[#device_fields + 1] = '"list":['
        .. table.concat(values, ",") .. "]"
    end
    fields[#fields + 1] = '"device":{'
      .. table.concat(device_fields, ",") .. "}"
  end

  return "{" .. table.concat(fields, ",") .. "}"
end

local matches = {}
for _, keys in ipairs(order) do
  local binding = bindings[keys]
  if binding and is_cliamp_binding(binding) then
    matches[#matches + 1] = binding
  end
end

table.sort(matches, function(left, right)
  local function priority(binding)
    local description = string.lower(binding.description)
    local command = string.lower(binding.command)
    if description == "cliamp drop-down"
        or string.find(command, "toggle_cliamp.sh", 1, true) then
      return 0
    elseif string.find(command, "quake_toggle.sh", 1, true) then
      return 1
    end
    return 2
  end

  local left_priority = priority(left)
  local right_priority = priority(right)
  if left_priority ~= right_priority then
    return left_priority < right_priority
  end
  return left.keys < right.keys
end)

io.write("[")
for index, binding in ipairs(matches) do
  if index > 1 then
    io.write(",")
  end
  io.write("{\"keys\":", json_string(binding.keys))
  io.write(",\"description\":", json_string(binding.description))
  io.write(",\"command\":", json_string(binding.command))
  io.write(",\"options\":", json_options(binding.options), "}")
end
io.write("]\n")
