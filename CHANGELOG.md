# Changelog

## Unreleased

### Fixes
- **Big Defensive, Buff and Icon Size now change the real frames**, not just the preview. These sizes were saved into Edit Mode in the wrong format, so any size above 50% showed up at the maximum. Open `/drf` and click **Apply** once to rewrite sizes saved by 1.0.0.

### Changes
- **Missing class buff marker:** Blizzard's raid frames never show long class buffs like Power Word: Fortitude, so anyone missing yours now gets that buff's icon with a red border in the top-right corner of their frame. Works for Priest (Fortitude), Mage (Arcane Intellect, mana users only) and Druid (Mark of the Wild); the group versions count too. Hidden in combat, when the game doesn't let addons read buffs. Toggle: **Show Missing Class Buff** in `/drf`.
- **Buff and Icon Size now grow with the frame**, like Blizzard's Big Defensive already does: 100% keeps the default icon-to-frame ratio at any frame size, so making the frames bigger makes the icons bigger too. Blizzard caps icons at 200%, so the Buff and Icon Size sliders now stop where that limit is reached: 25%–100% on 144 x 72 frames, 50%–200% on default-size frames.
- The preview's icons now match the real frames' sizes.

## 1.0.0 (2026-10-22)

First release of **Dan's Raid Frames**: quick controls for Blizzard's party and raid frames.

### Features
- **One options panel** (`/drf`) for both party and raid frames, each with its own settings: orientation, sort order, aura layout, border, width, height, opacity, and big defensive, buff and icon sizes. Frames resize live while you drag a slider.
- **Move and resize from the frames:** right-click a party or raid frame and choose **Unlock Frames**. Drag the outline to move, drag its corner to resize, right-click it to lock. The outline shows the full group (5 party slots, or a full 40-player raid). Frames lock automatically in combat.
- **Party alignment:** the party frame always has room for 5, and members sit left, centered or right, so a small group stays centered.
- **Works with Edit Mode:** settings and positions are saved into your active Edit Mode layout.
- **Pixel-perfect sizes:** every frame is drawn the same size at any UI scale.
- A button to Blizzard's own Raid Frame options, a minimap addon-menu entry, and `/drf help` for all commands.
