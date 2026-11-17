-- Zenbook Duo UX8407AA: layout of the two internal panels for the current orientation.
--
-- Loaded by monitors.lua on every config (re)load, and re-run at runtime by
-- ~/.local/bin/zenbook-duo-rotate via `hyprctl eval` whenever the accelerometer
-- reports a new orientation. The orientation is kept in a state file so a config
-- reload (theme change, etc.) keeps the current rotation instead of snapping back.
--
-- Orientation names are iio-sensor-proxy's (no ACCEL_MOUNT_MATRIX, accel is in the lid):
--   normal   = laptop upright, top screen above the bottom one
--   left-up  = sideways, top screen on the RIGHT
--   right-up = sideways, top screen on the LEFT
--
-- eDP-1's panel is mounted upside down. The kernel param
-- video=eDP-1:panel_orientation=upside_down (boot-orientation step) makes the boot
-- console/Plymouth set the primary plane's KMS "rotation" to 180°, and Hyprland
-- (aquamarine 0.15) never resets that property. So eDP-1's picture is already
-- rotated in hardware and the transforms below are the same as for an upright
-- panel (no extra 180°). The cursor plane is NOT rotated, so the hardware cursor
-- would be drawn upside down and move the wrong way: use software cursors.
-- If a future aquamarine starts resetting the plane rotation, the top screen
-- flips: then go back to +180° on eDP-1 and drop no_hardware_cursors.
--
-- Scale: each panel uses the scale on its own hl.monitor line in monitors.lua
-- (where `omarchy hyprland monitor scaling` / Super+Alt+scale keys save it),
-- default 2. Positions are computed from it, so any clean scale works
-- (1.25 -> 2304x1440 logical, 2 -> 1440x900).

hl.config({ cursor = { no_hardware_cursors = 1 } })

-- Panel native mode (both panels are 2880x1800).
local PANEL_W, PANEL_H = 2880, 1800

-- Read `scale = N` from a one-line `hl.monitor({ output = "<name>", ... })` rule in
-- monitors.lua. This file runs after those rules and must set the scale itself
-- (it re-applies the whole monitor rule), so it re-uses the user's value.
local function configured_scale(output)
  local f = io.open(os.getenv("HOME") .. "/.config/hypr/monitors.lua", "r")
  if not f then
    return nil
  end
  local scale
  for line in f:lines() do
    local code = line:gsub("%-%-.*", "")
    if code:match('^%s*hl%.monitor%(%s*{%s*output%s*=%s*"' .. output:gsub("%-", "%%-") .. '"') then
      scale = tonumber(code:match("scale%s*=%s*([%d%.]+)")) or scale
    end
  end
  f:close()
  return scale
end

local scales = {}
local size = {} -- logical size per output: { w, h } in landscape
for _, output in ipairs({ "eDP-1", "eDP-2" }) do
  local s = configured_scale(output)
  if not s or s < 1 or s > 4 then
    s = 2
  end
  scales[output] = s
  size[output] = { math.ceil(PANEL_W / s), math.ceil(PANEL_H / s) }
end

local layouts = {
  ["normal"] = {
    { output = "eDP-1", position = "0x0", transform = 0 },
    { output = "eDP-2", position = "0x" .. size["eDP-1"][2], transform = 0 },
  },
  -- Positions verified by the user: in left-up the top screen (eDP-1) is
  -- physically on the RIGHT, in right-up on the LEFT. Rotated, a panel's
  -- logical width is its landscape height.
  ["left-up"] = {
    { output = "eDP-2", position = "0x0", transform = 1 },
    { output = "eDP-1", position = size["eDP-2"][2] .. "x0", transform = 1 },
  },
  ["right-up"] = {
    { output = "eDP-1", position = "0x0", transform = 3 },
    { output = "eDP-2", position = size["eDP-1"][2] .. "x0", transform = 3 },
  },
}

local state_dir = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
  .. "/zenbook-duo"
local runtime_dir = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/zenbook-duo"

local function read_word(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local value = (f:read("*l") or ""):gsub("%s+", "")
  f:close()
  return value
end

local function exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local orientation = read_word(state_dir .. "/orientation")
if not layouts[orientation] then
  orientation = "normal"
end

-- Bottom panel off when the keyboard rests on it (written by zenbook-duo-rotate
-- from the keyboard's USB presence), or for the rest of this boot when the kernel
-- failed to bring eDP-2 up: enabling it again then can hang the machine (xe #9196).
local docked = read_word(state_dir .. "/docked") == "1"
local edp2_unsafe = exists(runtime_dir .. "/edp2-unsafe")
local edp2_off = docked or edp2_unsafe
if edp2_off then
  orientation = "normal"
end

local touch_transform = 0
for _, m in ipairs(layouts[orientation]) do
  if m.output == "eDP-2" and edp2_off then
    hl.monitor({ output = "eDP-2", disabled = true })
  else
    hl.monitor({
      output = m.output,
      disabled = false,
      mode = "preferred",
      position = m.position,
      scale = scales[m.output],
      transform = m.transform,
      -- 10-bit framebuffer: with zenbook-duo-dsc-10bit.service (forces DSC) the
      -- panels then run at 10 bpc instead of xe's default 6 bpc + dithering.
      bitdepth = 10,
    })
  end
  if m.output == "eDP-2" then
    touch_transform = m.transform
  end
end

-- Digitizers: pin each to its own panel. Hyprland doesn't rotate touch with the
-- monitor, so each device needs its own transform. Both digitizers are aligned
-- with eDP-2's native orientation (upright works with transform 0 on both, even
-- though eDP-1's panel needs 180°), so both use eDP-2's transform.
-- RAYD0001 (2386:8C05) = top panel eDP-1, RAYD0002 (2386:8C06) = bottom panel eDP-2.
-- The bottom digitizer is switched off while its panel is off (keyboard on the glass).
local digitizers = {
  { name = "rayd0001:00-2386:8c05", output = "eDP-1", bottom = false },
  { name = "rayd0001:00-2386:8c05-stylus", output = "eDP-1", bottom = false },
  { name = "rayd0002:00-2386:8c06", output = "eDP-2", bottom = true },
  { name = "rayd0002:00-2386:8c06-stylus", output = "eDP-2", bottom = true },
}
for _, d in ipairs(digitizers) do
  hl.device({
    name = d.name,
    output = d.output,
    transform = touch_transform,
    enabled = not (d.bottom and edp2_off),
  })
end
