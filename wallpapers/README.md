# Wallpapers

These wallpapers are stored with descriptive names containing their native
dimensions and aspect class. They are landscape images intended for desktop
monitors.

| File | Native size | Aspect ratio | Best fit |
| --- | ---: | ---: | --- |
| `wallpaper-station-4096x2304-16x9.png` | 4096 × 2304 | 16:9 | Standard 16:9 monitor or laptop |
| `night-clouds-city-4096x2660-1.54x1.jpg` | 4096 × 2660 | 1.54:1 | Wide monitor; may crop on 16:9 |
| `sailboat-beach-2358x1310-16x9.jpg` | 2358 × 1310 | 16:9 | Standard 16:9 monitor or laptop |
| `street-shop-atmosphere-4096x2304-16x9.png` | 4096 × 2304 | 16:9 | Standard 16:9 monitor or laptop |

The 16:9 images are the safest choices for most laptop and external monitor
layouts. The 1.54:1 image has more vertical content than 16:9, so Omarchy's
`fill` behavior may crop some of its top and bottom when displayed on a 16:9
screen.

## Omarchy installation

These files are repository assets and can be exposed through the dedicated
Stow package with:

```bash
./install-all.sh wallpapers
```

This links them into the custom-theme scaffold at
`~/.config/omarchy/themes/tokyo-night-wallpapers/`, installs the
`daniel.background` monitor-aware background plugin, and links the
`wallpaper-monitor` helper into `~/.local/bin`. The installer does not select a
wallpaper.

Choose wallpapers per connected monitor with:

```bash
wallpaper-monitor select
wallpaper-monitor select DP-1
wallpaper-monitor clear DP-1
wallpaper-monitor apply
```

The graphical picker combines the current theme's backgrounds, its user
background directory, and this repository's curated collection. Selections
persist in `~/.local/state/omarchy/monitor-backgrounds.json` and survive theme
changes without modifying the repository.

For manual setup without Stow, the current theme's user-background directory
can be created with:

```bash
mkdir -p ~/.config/omarchy/backgrounds/$(cat ~/.local/state/omarchy/current/theme.name)
```

Then select one with `omarchy theme bg set <path-to-image>` or cycle through
the current theme's available backgrounds with `omarchy theme bg next`.

Preview and selection commands:

```bash
omarchy theme bg install
omarchy theme bg-switcher
omarchy theme bg set <path-to-image>
omarchy theme bg next
```
