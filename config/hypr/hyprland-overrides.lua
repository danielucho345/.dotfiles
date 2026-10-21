-- Personal Hyprland overrides for current Omarchy releases.

hl.unbind("SUPER + CTRL + SHIFT + code:65")
-- Replace Omarchy's Theme menu shortcut with the per-monitor picker.
o.rebind(
  "SUPER + SHIFT + CTRL + SPACE",
  "Monitor wallpaper picker",
  "wallpaper-monitor select"
)

hl.unbind("SUPER + E")
o.bind("SUPER + E", "Find open window", "hypr-window-switcher")

-- Use Omarchy's saved monitor blocks so reconnecting a monitor keeps its key.
local function focus_registered_monitor(index)
  local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
  local file = io.open(state_home .. "/omarchy/monitor-workspaces", "r")
  if not file then return end

  local output
  for line in file:lines() do
    local block, connector = line:match("^(%d+)\t([^\t]*)\t")
    if tonumber(block) == index - 1 then
      output = connector
      break
    end
  end
  file:close()

  if output and output ~= "" and hl.get_monitor(output) then
    hl.dispatch(hl.dsp.focus({ monitor = output }))
  end
end

for index = 1, 10 do
  -- Omarchy uses keycodes for its group-window shortcuts.
  hl.unbind("SUPER + ALT + code:" .. tostring(index + 9))
  o.rebind(
    "SUPER + ALT + " .. tostring(index % 10),
    "Focus registered monitor " .. index,
    function() focus_registered_monitor(index) end
  )
end

-- Replace Omarchy's default SUPER + SHIFT + S binding.
hl.unbind("SUPER + SHIFT + S")
o.bind(
  "SUPER + SHIFT + S",
  "Screenshot to clipboard",
  [[sh -c 'grim -g "$(slurp)" - | wl-copy']]
)
-- -- Workspace-to-monitor assignments migrated from hyprland-overrides.conf.

--
-- -- DP-2
-- hl.workspace_rule({ workspace = "2", monitor = "DP-2", default = true })
-- hl.workspace_rule({ workspace = "3", monitor = "DP-2" })
-- hl.workspace_rule({ workspace = "4", monitor = "DP-2" })
-- hl.workspace_rule({ workspace = "5", monitor = "DP-2" })
--
-- -- DP-1
-- hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true })
-- hl.workspace_rule({ workspace = "6", monitor = "DP-1" })
-- hl.workspace_rule({ workspace = "7", monitor = "DP-1" })
-- hl.workspace_rule({ workspace = "8", monitor = "DP-1" })
-- hl.workspace_rule({ workspace = "9", monitor = "DP-1" })
-- hl.workspace_rule({ workspace = "0", monitor = "DP-1" })
