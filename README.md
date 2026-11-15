# Gloamreach

An original dark-fantasy action RPG built for phones, made with **Godot 4** (GL Compatibility renderer).

Descend through procedurally generated depths beneath a drowned, lamplit city as **the Warden**, the last keeper of the Vigil flame. The world, characters, names, art and sound in this repository are all original. Every sprite is drawn in code and every sound is synthesised at runtime, so the project has no third-party assets.

## Design pillars

- **Grim, gothic tone:** a dark ambient palette, flickering braziers, and a lantern light around the hero.
- **Mobile-first, simplified systems:** one-thumb combat (hold STRIKE and the Warden picks a target and closes in on it), three gear slots, gear that equips itself when it's an upgrade, and leftovers salvaged for gold.
- **Juicy feedback:** hit-pause, trauma-based screen shake, squash and stretch, crit numbers, blood and ember particles, shockwave rings, telegraphed slams, light pillars on good loot, and a pulsing low-health vignette.

## Content (first playable slice)

| Area | What's in |
| --- | --- |
| Hero | The Warden: basic strike, **Cleave** (wide fire arc, 12 mana), **Nova** (radial knockback, 20 mana), Crimson Draughts (healing potions) |
| Foes | Hollowed (melee), Cinder Wisps (ranged, kite and strafe), Gravebound Brutes (telegraphed area slam; a critical hit interrupts it), elite variants |
| Bosses | Every 3rd depth; they seal the stairs until defeated |
| Loot | Worn, Tempered, Gilded and Ashborn rarities; weapon, armor and charm slots; damage, armor, life, crit, leech and speed stats |
| Depths | Three rotating themes: Sunken Ossuary, Cinder Halls, Drowned Choir |

## Controls

| Touch | Keyboard (desktop testing) |
| --- | --- |
| Drag on the left half of the screen to move (floating stick) | WASD or arrow keys |
| Hold **STRIKE** (or anywhere on the right half) | Space |
| **CLEAVE** / **NOVA** buttons | Q / E |
| Potion button | R |

## Running

1. Install Godot 4.7 or later (standard build, not .NET). Cloud sessions on the `billiard-roguelike-chatgpt` environment install it automatically.
2. Open `project.godot` in the editor and press Play, or run `godot --path .` from this folder.
3. For phones, add Android or iOS export presets in **Project → Export** (export templates required).

## Bot playtest

`tests/autoplay.tscn` plays the game through the same HUD inputs a thumb would use. It pathfinds to foes, holds STRIKE, uses skills and potions, clears each floor and takes the stairs, then prints a summary. It also reports any enemy that ends up inside a wall, and stalls.

```bash
# fast, headless (4 minutes of game time in about 15 s)
godot --headless --path . --fixed-fps 60 tests/autoplay.tscn -- 240

# with screenshots every 10 s (needs a display, e.g. xvfb-run)
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
  --fixed-fps 60 tests/autoplay.tscn -- 75 /tmp/shots
```

## Layout

```
project.godot        engine config (landscape, touch emulation, GL Compatibility)
scenes/main.tscn     entry scene
scripts/main.gd      floor lifecycle, spawning, loot, death/restart
scripts/dungeon.gd   rooms-and-corridors generator + code-drawn tiles
scripts/actor.gd     shared health/knockback/hit feedback
scripts/player.gd    the Warden, skills, stats, equipment
scripts/enemy.gd     foe AI (melee / ranged / brute), elites, bosses
scripts/items.gd     loot tables and rarity rolls
scripts/loot.gd      drops on the floor, pickup
scripts/projectile.gd
scripts/stairs.gd
scripts/hud.gd       multi-touch controls, orbs, toasts, compass
scripts/fx.gd        autoload: shake, hit-pause, particles, floating text
scripts/sfx.gd       autoload: procedural sound synthesis
tests/autoplay.*     bot playtest
```
