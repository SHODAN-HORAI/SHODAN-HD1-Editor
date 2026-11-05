# SHODAN HD1 Editor

Change the stats of weapons, grenades, backpacks, stratagems, sentries, mines, strikes, vehicles,
enemies, status effects and your Helldiver in **Helldivers** (the first one).
Press **F7** in game, pick an item, change its numbers, and the change applies at once. Your changes
stay for the next launch.

**[Download the latest release](../../releases/latest)**· Nothing else needed

![SHODAN HD1 Editor](images/window.jpg)

## What you can do

- **Edit stats live**: every value, per item.
- **Attachments**: turn each weapon's armory upgrades on and off, bought or not. Your save is left as it is.
- **Presets**: 5 per item, and up to 50 named presets in the Presets tab for everything you have changed.
- **Settings**: turn all your changes off and on again, pick how see-through the window is, hide the key hints, and hide tabs you don't use.

## Install

There are two versions of the same editor. Pick one, not both.

### Standalone (nothing else needed)

1. Download `SHODAN-HD1-Editor-<version>.zip` from the [latest release](../../releases/latest) and unzip it.
2. Close the game, then double-click `Install.bat`.
3. Start Helldivers and press **F7**.

To take it out, double-click `Uninstall.bat`. Verifying the game files in Steam also takes it out, and a
game update may too. Run `Install.bat` again after one.

If you also use a mod manager, deploy your mods there first, then run `Install.bat`. The editor keeps those
mods running. Every time you deploy again, the editor stops opening until you run `Install.bat` again.

### Mod Manager (Obsidian Mod Manager)

1. Download `shodan.hd1editor-obsidian-<version>.zip` from the [latest release](../../releases/latest).
2. In Obsidian Mod Manager, press the green **+** on the Mods tab, or drop the zip on the list.
3. Turn it on, press Deploy, then start Helldivers and press **F7**.

Obsidian Mod Manager updates it for you. Change the open key in its keybinds. If the standalone version is
installed too, this one stays off.

## Unlock everything

`Unlock Everything.bat` is a separate tool in the standalone zip. It works without the editor installed. Close the game and
double-click it: every weapon, stratagem, perk, armor and upgrade you can earn is unlocked in your save. Your rank
and XP stay as they are. Paid DLC stays locked unless you own it, and the DLC you own gets its upgrades too. Your
old save is backed up first.

## Keys

| Key | What it does |
|---|---|
| F7 | Open or close the window (pick another key in Settings, or in Obsidian Mod Manager's keybinds) |
| Up / Down | Choose a stat |
| Left / Right | Change it (hold Shift for bigger steps) |
| Enter | Type a value |
| Del | Put the stat back to the game's value |
| PgUp / PgDn | Previous / next item |
| Tab | Next tab (Shift: previous) |
| Esc | Close |

## Notes

- Leaderboard scores aren't sent while the editor is installed. The standalone version still sends Galactic War progress. Obsidian Mod Manager holds that back too while a mod like this one is on.
- Some values apply at once, others on the next call-in, spawn or mission. The line under the stats says which.
- An item whose data the game hasn't loaded on the current screen says so. Open it on the ship or in a mission.
- The standalone version keeps your edits and presets in `%LOCALAPPDATA%\SHODAN\SHD1Editor`. The Mod Manager version keeps its own.
- Works with other mods (see Install for mod managers).
- Made for solo play.

## License

GPL-3.0. See [LICENSE](LICENSE). Third-party notices: [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).
