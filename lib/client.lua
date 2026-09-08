local M = {}
local class = "org.omarchy.cliamp.quake"
local workspace = "special:cliamp"
local state = _G.cliamp_control

local function managed(window)
  return window and (window.class == class or window.initial_class == class)
end

local function report(status, ...)
  hl.dispatch(hl.dsp.event(table.concat({
    "cliamp", state.epoch, state.revision, status, ...,
  }, ",")))
end

function M.rectangle(monitor, alignment, width, height)
  local mw, mh = monitor.width, monitor.height
  if monitor.transform % 2 == 1 then mw, mh = mh, mw end
  local reserved = monitor.reserved
  local usable_width = math.max(1,
    math.floor(mw / monitor.scale - reserved.left - reserved.right))
  local usable_height = math.max(1,
    math.floor(mh / monitor.scale - reserved.top - reserved.bottom))
  width, height = math.min(width, usable_width), math.min(height, usable_height)
  local free = usable_width - width
  local offset = alignment == "Right" and free
    or alignment == "Center" and math.floor(free / 2) or 0
  return monitor.x + reserved.left + offset, monitor.y + reserved.top,
    width, height
end

local function fit()
  hl.exec_scheduled_prop_refresh_immediately()
  local count = 0
  for _, window in ipairs(hl.get_windows()) do
    if managed(window) and window.mapped and window.monitor then
      count = count + 1
      local x, y, width, height = M.rectangle(window.monitor,
        state.alignment, state.width, state.height)
      local target = "address:" .. window.address
      local floated = not window.floating
      if floated then
        hl.dispatch(hl.dsp.window.float({window = target, action = "on"}))
      end
      if floated or window.size.x ~= width or window.size.y ~= height then
        hl.dispatch(hl.dsp.window.resize({window = target,
          x = width, y = height, relative = false}))
      end
      if floated or window.at.x ~= x or window.at.y ~= y then
        hl.dispatch(hl.dsp.window.move({window = target,
          x = x, y = y, relative = false}))
      end
      hl.exec_scheduled_prop_refresh_immediately()
      report("geometry", x, y, width, height,
        window.at.x, window.at.y, window.size.x, window.size.y)
    end
  end
  if count == 0 then report("absent") end
end

function M.apply()
  if not state or state ~= _G.cliamp_control or state.applying then return end
  state.applying = true
  local ok, error = pcall(fit)
  state.applying = false
  if not ok then report("error", tostring(error)) end
end

function M.configure(epoch, revision, alignment, width, height)
  assert(state and state.epoch == epoch, "CLIamp controller is not installed")
  assert(alignment == "Left" or alignment == "Center" or alignment == "Right")
  assert(width >= 1 and width <= 100000 and width % 1 == 0)
  assert(height >= 1 and height <= 100000 and height % 1 == 0)
  state.revision, state.alignment, state.width, state.height =
    revision, alignment, width, height
  M.apply()
end

function M.stop(epoch)
  if not state or state.epoch ~= epoch then return end
  for _, listener in ipairs(state.listeners) do listener:remove() end
  if state.launch_timer then state.launch_timer:set_enabled(false) end
  state.rule:set_enabled(false)
  state.window_rule:set_enabled(false)
  _G.cliamp_control = nil
end

function M.install(epoch, launcher, revision, alignment, width, height)
  if state then M.stop(state.epoch) end
  state = {epoch = epoch, launcher = launcher, listeners = {}}
  _G.cliamp_control = state
  state.rule = hl.workspace_rule({workspace = workspace, gaps_in = 0,
    gaps_out = 0, no_border = true, on_created_empty = ""})
  state.window_rule = hl.window_rule({name = "cliamp-control",
    match = {initial_class = "^org[.]omarchy[.]cliamp[.]quake$"},
    workspace = workspace .. " silent", float = true, no_initial_focus = true})
  state.listeners[1] = hl.on("window.open", function(window)
    if not managed(window) then return end
    state.launching = false
    if state.launch_timer then state.launch_timer:set_enabled(false) end
    M.apply()
    if window.workspace and window.workspace.visible then
      hl.dispatch(hl.dsp.focus({window = "address:" .. window.address}))
    end
  end)
  for _, event in ipairs({"monitor.layout_changed", "workspace.special_active",
      "workspace.move_to_monitor", "window.move_to_workspace"}) do
    state.listeners[#state.listeners + 1] = hl.on(event, M.apply)
  end
  M.configure(epoch, revision, alignment, width, height)
end

function M.toggle(monitor_name, origin_workspace)
  assert(state, "CLIamp controller is not installed")
  local monitor = hl.get_active_monitor()
  if not monitor then return end
  if monitor_name and (monitor.name ~= monitor_name
      or not monitor.active_workspace
      or monitor.active_workspace.id ~= origin_workspace) then return end
  hl.dispatch(hl.dsp.workspace.toggle_special("cliamp"))
  hl.exec_scheduled_prop_refresh_immediately()
  local visible = monitor.active_special_workspace
  if visible and visible.name == workspace and not state.launching then
    local exists = false
    for _, window in ipairs(hl.get_windows()) do
      if managed(window) then exists = true; break end
    end
    if not exists then
      state.launching = true
      state.launch_timer = hl.timer(function()
        state.launching = false
        report("error", "CLIamp window did not appear")
      end, {timeout = 5000, type = "oneshot"})
      hl.exec_cmd("bash '" .. state.launcher:gsub("'", "'\\''") .. "'", {
        workspace = workspace .. " silent", float = true, no_initial_focus = true,
      })
    end
  end
  M.apply()
end

return M
