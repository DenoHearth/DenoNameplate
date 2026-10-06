# Deno Nameplate

Clean, compact nameplates for WoW: Forever with health text, cast bars, level and quest icons, and full size and font options.

[![Latest release](https://img.shields.io/github/v/release/DenoHearth/DenoNameplate?label=download&style=for-the-badge)](https://github.com/DenoHearth/DenoNameplate/releases/latest)

A World of Warcraft: Forever addon (interface 16001).

## What it does

Replaces the default nameplates with clean, compact ones: a slim health bar, the unit's
name above it, a cast bar below, and small level, elite, raid marker and quest icons
around it. Written from scratch for World of Warcraft: Forever and its addon rules.

- **Friendly and enemy settings are separate**, each with its own page.
- **Health bar:** width, height, bar texture, background color.
- **Health text** in five formats: current, current / max, percent, current / max - percent,
  or missing health.
- **Cast bar** with spell icon, and a shield for casts that cannot be interrupted.
- **Level indicator** colored by difficulty, a skull for bosses, gold and silver icons for
  elite and rare-elite units.
- **Raid target icon** and **quest objective icon** (left, right or above the name).
- **Colors:** class colors for players, the game's reaction colors for everything else,
  grey for units tapped by someone else, red plus a highlight on enemies you have threat on.
- **Your debuffs** above enemy nameplates.
- **Target:** a larger plate (adjustable scale) with a highlight and a bright border.
- **Classic style:** an optional bordered look with a fixed size.
- **Clickable area:** width and height of the click box, with a toggle that draws the box
  so you can see it.
- **View distance:** how far away nameplates show, up to the game's maximum of 60 yards.
- **Fonts and textures:** a built-in set; LibSharedMedia entries are added when another
  addon provides that library. No library is required.
- **Minimap button** that opens the options; it can be hidden.

## Install

- **CurseForge:** [Deno Nameplate](https://www.curseforge.com/wow/addons/deno-nameplate),
  or search for it in the CurseForge app under WoW: Forever.
- **By hand:** download the zip from the
  [latest release](https://github.com/DenoHearth/DenoNameplate/releases/latest) and extract
  the `DenoNameplate` folder into `World of Warcraft\<Forever folder>\Interface\AddOns\`.
  Restart the game.

## Options

Open them with `/dnp`, `/denonameplate`, or the minimap button.

| Page | Settings |
|---|---|
| General | Classic Style, Show My Debuffs, View Distance, Show Minimap Button, Clickable Height and Width, Show Clickable Box, Target Scale |
| Friendly | Name (show, font, size, outline); Health (Name Only, width, height, text format, show text, font, bar texture, class color, background color); Cast Bar (enabled, font, texture, height); Level Indicator (players, NPCs); Objective Icons (show, scale, anchor) |
| Enemy | The same groups as Friendly, without Name Only |

Defaults: enemy health bar 112 x 10 with percent text in a monochrome outline, target
scale 1.2, cast bars on enemies only, view distance 60.

## How it works

Forever hides combat numbers from addons: health, cast times and auras come back as
opaque "secret" values that code may pass on but not read. This addon never reads them.
Health goes straight into the bar and the text formatter, cast bars run on the game's own
duration objects, and the debuff row is drawn by Blizzard's aura container.

The game's own nameplate is kept, invisible, underneath: the click area belongs to it.

## Files

- `Core.lua` - defaults, saved settings, fonts and textures, client settings
- `Plate.lua` - one nameplate: layout and every element's update
- `Driver.lua` - attaches a plate to each nameplate the game shows
- `Minimap.lua` - the minimap button
- `Options.lua` - the options pages

## Limits

- Nameplates the game does not let addons change keep the default look. That includes
  friendly players inside instances and plates that only carry a quest widget.
- Your own personal resource display is not a nameplate on Forever and is not styled.
- Health numbers are shortened (12.3K). The "missing" format shows `-0` at full health,
  because the value cannot be compared with zero.
- Changes to the clickable area and view distance wait until you are out of combat.
- The debuff row is built out of combat; a plate first seen mid-fight gets it afterwards.


## Compatibility

- World of Warcraft: Forever, interface version **16001**.
- Forever only. It uses that client's API and will not load on retail or the Classic clients.

## Changelog

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).  Current version: 1.0.0.
