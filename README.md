# Human Haste - Configurable

Use Coen's human haste running animation in vampire form, with adjustable haste speed.

Vampire locomotion normally has walk, run and sprint samples but no human haste sample. Redirecting the ability alone can therefore leave vampire haste using the sprint gait. This mod adds the missing human haste gait and calibrates its speed against vanilla wolf haste.

## Features

- Human haste running in vampire form.
- Vampire haste speed from **25% to 300%**, default **100%**.
- The default targets vanilla wolf haste's forward-speed baseline and retains the vampire enhanced-haste bonus.
- Ordinary sprint samples and daytime haste speed are preserved.

## Requirements

- The Blood of Dawnwalker.
- UE4SS for Dawnwalker by Vercadi, 1.3 (RC6) or newer, with native pre-hooks and delayed game-thread actions.
- Mod Setting Menu 1.0.6 or newer, with `HookProcessConsoleExec=1` in the loader configuration.

## Installation

- **Vortex:** Install **Human Haste - Configurable.zip** through Vortex, enable it and deploy.
- **Manual:** Copy the archive's **Dawnwalker** folder into **The Blood of Dawnwalker** game directory, preserving the folder structure.

## Settings

Open **Mod Setting Menu → Human Haste - Configurable**, adjust **Vampire haste speed**, then Apply. At 150%, the target is one and a half times the vanilla wolf forward-speed baseline. Stop and restart haste after applying a change.

The normal wolf animation's mean forward root-speed curve is approximately **9.28 m/s**. The human haste animation's corresponding value is approximately **7.81 m/s**, so the mod uses a calibration ratio of **1.1892839243706543**, multiplied by the vampire ability's selected normal/enhanced movement-profile scale and your percentage. These are nominal animation values; slopes, acceleration, collisions and other game effects affect actual travel.

Personal settings are created in `Dawnwalker/Binaries/Win64/ue4ss/Mods/HumanHasteAtNight/settings.ini`. They are not included in the archive.

**Logging** is the final setting: Off, Error, Warning, Info or Debug. The default is Warning. To report a problem, select Debug, Apply, reproduce it and attach `Dawnwalker/Binaries/Win64/ue4ss/UE4SS.log` to a GitHub issue. Include your mod version and the speed setting used.

## Source and asset build

The Lua sources are in `Scripts/`. The runtime folder remains `HumanHasteAtNight`, and the menu ID is `HumanHasteConfigurable`.

The replacement vampire locomotion blendspace is in `assets/legacy/`. It retains the twelve ordinary locomotion samples and adds `Coen_SprintFastTravel02_F` at gait coordinate Y=3, using the human blendspace's matching interpolation data. The referenced animations remain in the game.

Rebuild the cooked container with [retoc](https://github.com/trumank/retoc) 0.1.5 or newer:

```text
retoc to-zen assets/legacy package/Dawnwalker/Content/Paks/~mods/zzz_HumanHasteConfigurable_P.utoc --version UE5_5
```

For a game-root archive, include `package/Dawnwalker/`; place `Scripts/`, `enabled.txt` and `mod_settings.ini` under `Dawnwalker/Binaries/Win64/ue4ss/Mods/HumanHasteAtNight/`. Add the package's root metadata, `README.md` as `README.txt`, `LICENSE` as `LICENSE.txt`, `CHANGELOG.md`, `RELEASE-NOTES.md`, `SOURCE.json` and `ASSET-NOTICE.txt`. Do not include `assets/legacy/` or generated personal settings in the install archive.

## Credits

Based on [HumanHasteAtNight 1.0.0 by SkrappyNPC](https://www.nexusmods.com/thebloodofdawnwalker/mods/753), distributed under the MIT license. Its license is preserved verbatim, including the original copyright placeholder. This derivative retains its ability redirect and removal of the animal-sprint unlock requirement.

Mod Setting Menu's integration helper is included unchanged. See `SOURCE.json` for provenance. The new Lua changes are MIT licensed; game-derived blendspace data remains subject to its original owners' rights, as described in `ASSET-NOTICE.txt`.
