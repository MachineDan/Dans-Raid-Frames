# Changelog

## 1.1.0 (2026-11-12)

See at a glance who's missing your buffs, and icon sizes that finally do what the slider says.

### New: missing class buff marker
Blizzard's raid frames never show long class buffs like Power Word: Fortitude, so there was no easy way to tell who still needs one. Now anyone missing **your** buff gets its icon with a red border in the top-right corner of their frame, and it disappears as soon as they're buffed.

- **Priest:** Power Word: Fortitude, and Divine Spirit on mana users if you have it.
- **Mage:** Arcane Intellect, on mana users.
- **Druid:** Mark of the Wild.
- **Paladin:** any of your Blessings. Someone who only has another paladin's blessing still gets marked, and the icon shows the blessing you cast last.

Group versions (Prayer of Fortitude, Arcane Brilliance, Gift of the Wild, Greater Blessings) count too. If someone is missing several of your buffs, the icons line up side by side. Dead and offline players are skipped. Short or range-based buffs like Battle Shout, totems and auras are left out on purpose, so the marker doesn't flicker.

Markers hide in combat, when the game doesn't let addons read buffs, and come back afterwards. Turn them off with **Show Missing Class Buff** in `/drf`.

### Icon sizes now follow your frames
- **Buff and Icon Size grow with the frame**, like Blizzard's Big Defensive already does. 100% keeps the default icon-to-frame ratio at any size, so bigger frames mean bigger icons.
- **The sliders stop at Blizzard's limit** for your frame size (it caps icons at 200%): 25–100% on 144 x 72 frames, 50–200% on default-size frames. Every step now changes something.
- **The preview** draws icons at the same size as the real frames.

### Fixes
- **Big Defensive, Buff and Icon Size now change the real frames**, not just the preview. 1.0.0 saved these sizes into Edit Mode in the wrong format, so anything above 50% showed up at the maximum.

### Updating from 1.0.0
- **Restart the game** after installing: 1.1.0 adds a new file, and `/reload` doesn't load new files.
- Open `/drf` and click **Apply** once, to rewrite the icon sizes 1.0.0 saved incorrectly.
- Buff and Icon Size are now relative to the frame, so on frames bigger than default the same percentage gives bigger icons than before. Adjust them if they look too big.

## 1.0.0 (2026-10-22)

First release of **Dan's Raid Frames**: quick controls for Blizzard's party and raid frames.

### Features
- **One options panel** (`/drf`) for both party and raid frames, each with its own settings: orientation, sort order, aura layout, border, width, height, opacity, and big defensive, buff and icon sizes. Frames resize live while you drag a slider.
- **Move and resize from the frames:** right-click a party or raid frame and choose **Unlock Frames**. Drag the outline to move, drag its corner to resize, right-click it to lock. The outline shows the full group (5 party slots, or a full 40-player raid). Frames lock automatically in combat.
- **Party alignment:** the party frame always has room for 5, and members sit left, centered or right, so a small group stays centered.
- **Works with Edit Mode:** settings and positions are saved into your active Edit Mode layout.
- **Pixel-perfect sizes:** every frame is drawn the same size at any UI scale.
- A button to Blizzard's own Raid Frame options, a minimap addon-menu entry, and `/drf help` for all commands.
