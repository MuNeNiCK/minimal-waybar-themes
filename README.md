# Minimal V4 Bar for Omarchy 4

An Omarchy 4 Quickshell reconstruction of
[atif-1402/minimal-waybar-themes](https://github.com/atif-1402/minimal-waybar-themes),
based specifically on its Waybar V4 design.

The original V4 layout is mapped to native Omarchy widgets:

- Omarchy menu and active window on the left
- media, eight dot-style workspaces, clock, indicators, and updates in the center
- tray, audio, Bluetooth, network, and power on the right
- theme-aware rounded pill surfaces using the active Omarchy palette

## Requirements

- Omarchy 4.x
- A horizontal top bar

## Install

```bash
omarchy plugin add https://github.com/MuNeNiCK/minimal-waybar-themes.git --enable --yes
```

The plugin id is `munenick.minimal-v4-bar`. Select it explicitly with:

```bash
omarchy bar use munenick.minimal-v4-bar
```

## Update

```bash
omarchy plugin update munenick.minimal-v4-bar --yes
```

## Return to the stock bar

```bash
omarchy bar reset
```

Remove the plugin after switching back:

```bash
omarchy plugin remove munenick.minimal-v4-bar --yes
```

## Legacy Waybar themes

The original Waybar configurations remain archived under [`waybar/`](waybar/).
They are not loaded by Omarchy 4, which uses `omarchy-shell` and Quickshell for
the desktop bar.

## Credits

Original visual design and legacy configurations by
[atif-1402](https://github.com/atif-1402). Omarchy 4 port by MuNeNiCK.
