<p align="center">
  <img src="media/logo.webp" alt="Dan's Raid Frames logo" width="320">
</p>

# Dan's Raid Frames

Quick controls for Blizzard's party and raid frames: resize, rearrange and move them without opening Edit Mode.

Dan's Raid Frames doesn't replace the default frames. It gives you one place to set up Blizzard's own party and raid frames, and lets you move and resize them straight from the frames.

## Features

- **One options panel** for both party and raid frames, each with its own settings:
  orientation, sort order, aura layout, border, width, height, opacity, and big defensive, buff and icon sizes.
- **Live preview:** frames resize on screen while you drag a slider, and a 1:1 preview shows the result.
- **Move and resize from the frames:** right-click a party or raid frame and choose **Unlock Frames**.
  An outline shows the full group (5 party slots, or a full 40-player raid). Drag it to move, drag its corner to resize.
- **Party alignment:** the party frame always has room for 5, and you choose whether members sit
  left, centered or right (top, center or bottom when vertical). A 2-player group stays centered.
- **Works with Edit Mode:** settings and positions are saved into your active Edit Mode layout,
  so Edit Mode and Dan's Raid Frames always agree.
- **Shortcut to Blizzard's Raid Frame options** (power bars, class colors, debuffs, health text…),
  so those aren't duplicated.

## Installation

1. Download the latest version: **Code → Download ZIP** on this page.
2. Extract it into your AddOns folder, for example
   `World of Warcraft\_retail_\Interface\AddOns\`.
3. **Rename the folder to `DansRaidFrames`**. GitHub names it after the repository plus `-main`,
   and WoW only loads the addon if the folder matches its name.
4. Restart the game or type `/reload`.

## Usage

Open the options with `/drf`, from **Esc → Options → AddOns → Dan's Raid Frames**,
or by left-clicking the addon in the minimap's addon menu.

### Moving and resizing frames

1. Right-click any party or raid frame and choose **Unlock Frames**.
2. Drag the outline to move the frames, or drag its bottom-right corner to resize them.
3. Right-click the outline to lock them again.

Frames lock automatically when you enter combat.
While solo, use `/drf unlock` or right-click the addon in the minimap's addon menu.

### Slash commands

| Command | What it does |
| --- | --- |
| `/drf` | Open the options |
| `/drf unlock [party\|raid]` | Unlock frames to move them (same as the right-click menu) |
| `/drf lock` | Lock the frames again |
| `/drf on` / `off` / `toggle` | Show raid-style frames in groups |
| `/drf width <n>` / `height <n>` / `size <w> <h>` | Frame size, for the Party or Raid page you used last |
| `/drf reset` | Reset that page's settings to defaults |
| `/drf resetpos` | Put the frames back in their default spot (with Edit Mode, use its **Reset Position**) |
| `/drf help` | List all commands in chat |

## Good to know

- **Edit Mode layouts:** changes are saved into the Edit Mode layout you have selected.
  Blizzard's preset layouts (Modern, Classic) can't be edited, so if one of them is active,
  the addon creates its own layout, `DansRaidFrames`, and switches to it.
- **Display options** like power bars, class colors and debuffs stay in Blizzard's
  **Options → Gameplay → Interface → Raid Frames**. The addon's options page has a button that opens it.
- **Taint-safe by design:** the addon only uses plain frame methods (size, position, visibility)
  on Blizzard's frames and saves through the game's Edit Mode API instead of Edit Mode's own code,
  to avoid "action blocked" errors in combat.

## Compatibility

Developed and tested on the WoW **1.60** client.
The `.toc` also lists Classic Era (1.15), Mists of Pandaria Classic (5.5) and Retail (12.1),
which haven't been tested yet.

## License

[MIT](LICENSE)
