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

These files are repository assets for now; they are not activated
automatically yet. In a later phase, they can be copied or linked into the
current theme's user-background directory:

```bash
mkdir -p ~/.config/omarchy/backgrounds/$(cat ~/.local/state/omarchy/current/theme.name)
```

Then select one with `omarchy theme bg set <path-to-image>` or cycle through
the current theme's available backgrounds with `omarchy theme bg next`.
