-- Personal Hyprland overrides for current Omarchy releases.

o.bind(
  "SUPER + CTRL + SHIFT + code:65",
  "Monitor wallpaper picker",
  "wallpaper-monitor select"
)

-- Replace Omarchy's default SUPER + SHIFT + S binding.
hl.unbind("SUPER + SHIFT + S")
o.bind(
  "SUPER + SHIFT + S",
  "Screenshot to clipboard",
  [[sh -c 'grim -g "$(slurp)" - | wl-copy']]
)

-- Workspace-to-monitor assignments migrated from hyprland-overrides.conf.

-- DP-2
hl.workspace_rule({ workspace = "2", monitor = "DP-2", default = true })
hl.workspace_rule({ workspace = "3", monitor = "DP-2" })
hl.workspace_rule({ workspace = "4", monitor = "DP-2" })
hl.workspace_rule({ workspace = "5", monitor = "DP-2" })

-- DP-1
hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true })
hl.workspace_rule({ workspace = "6", monitor = "DP-1" })
hl.workspace_rule({ workspace = "7", monitor = "DP-1" })
hl.workspace_rule({ workspace = "8", monitor = "DP-1" })
hl.workspace_rule({ workspace = "9", monitor = "DP-1" })
hl.workspace_rule({ workspace = "0", monitor = "DP-1" })
