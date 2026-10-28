# 7thDroid

Installs the [7th Heaven](https://github.com/tsunamods-codes/7th-Heaven) mod manager for FINAL FANTASY VII on
[DroidDeck](https://github.com/Droid-Deck/DroidDeck), the Android app that runs Steam and Windows games with
Valve's ARM64 Proton and FEX.

7thDroid grew out of [7thDeck](https://github.com/dotaxis/7thDeck), which is now deprecated in favour of
[MateriaForge](https://github.com/dotaxis/MateriaForge-rs). It is a new project, written only for DroidDeck.

## What it does

1. **Finds your copy of FINAL FANTASY VII.** It looks in these places:
   - Steam: the 2013 release (app 39140) and the 2026 release (app 3837340), in any Steam library.
   - The GOG release (1698970154), installed with DroidDeck's own GOG store, with Heroic (AppImage, Flatpak or Nix), or with Lutris (native or Flatpak).

   If none is found, you give it a path to one of these:
   - an installed game folder;
   - a GOG installer (`setup_final_fantasy_vii_*.exe`);
   - the 1998 CD-ROM release, as disc images (`.iso`) or folders copied from the discs.
2. **Prepares a Proton prefix.**
   - Steam games use the prefix Steam made for FF7. Any other copy gets a prefix of its own, and the game files stay where they are.
   - It installs the .NET Desktop Runtime that 7th Heaven needs, both x64 and x86.
   - It turns off WinForms/WPF hardware acceleration, because 7th Heaven's controls vanish without that.
   - It makes Wine prefer 7th Heaven's `dinput.dll`. Without that, mods silently don't load.
3. **Installs 7th Heaven** silently into `C:\7th Heaven` in that prefix, then points it at your game.
   - You choose the build: the pinned version, the latest stable release, or the canary build.
4. **Adds shortcuts, if you want them:**
   - the DroidDeck app's Desktop page;
   - Steam, as a non-Steam game;
   - the KDE desktop's menu.

Installers run with the FEX settings DroidDeck uses for .NET programs, including full x87 precision.
Without that, the GOG installer stops with "File not fpund". 7thDroid passes these settings through `droiddeck-proton-run --verb run`, so your FEX preset in the DroidDeck app doesn't override them. Your preset is left unchanged, and it still applies when you play.

## Requirements

- DroidDeck with Steam set up. Proton has to be downloaded first: open Steam once and let it finish (sometimes this takes a couple of starts).
- For the Steam releases: the game installed and started once from Steam, so that Steam creates its prefix.

## Usage

Shared Android storage is mounted `noexec`, so run the script with `bash`:

1. Download this repository and unpack it, for example into `/root/Storage/Download/7thDroid`. That folder is Android's Downloads folder.
2. Open Konsole on the DroidDeck desktop. You can also add `install.sh` as a Script app on the Desktop page.
3. Run:

```bash
bash /root/Storage/Download/7thDroid/install.sh
```

Then start 7th Heaven from the shortcuts you added, or with `bash ~/.local/share/7thdroid/"7th Heaven.sh"`.

### Options

| Option | |
|---|---|
| `--version pinned\|latest\|canary` | The 7th Heaven build. If you leave it out, the script asks. |
| `--source PATH` | Use this game instead of searching. Repeat it once per disc. |
| `--game-dir DIR` | Where a GOG installer puts the game (default `~/Games/FINAL FANTASY VII`). |
| `--app-entry`, `--steam`, `--desktop` (and `--no-…`) | Add or skip each shortcut without asking. |
| `--shortcuts-only` | Only recreate the launcher and shortcuts, for example after closing Steam. |
| `--winetricks-dinput` | Also run winetricks' `dinput` verb, if a Proton build that ships protonfixes is installed (e.g. DroidDeck-Proton). |
| `--reinstall` | Run every step again. |
| `--yes` | Accept every default without asking. |
| `--dry-run` | Show what would run without changing anything. |

The log is written to `~/.local/state/7thdroid/install.log`.

## Troubleshooting

- **The Steam shortcut won't start.** The shortcut is a Linux script. If Steam tries to run it with Proton, open its Properties → Compatibility and turn off the forced compatibility tool.
- **The Steam shortcut wasn't added.** Steam has to be closed while shortcuts are written. Close Steam, then run `bash install.sh --shortcuts-only`.
- **Mods don't load.** Re-run with `--winetricks-dinput` if a Proton with protonfixes is installed, and please report it.
- **Paths to DroidDeck's helpers changed.** Each one can be overridden: `DROIDDECK_PROTON_RUN`, `DROIDDECK_INNOEXTRACT`, `DROIDDECK_MSITOOLS`, `DROIDDECK_STEAM_SHORTCUTS`, `DROIDDECK_APPS_DIR` and `STEAM_ROOT`.

## Development

The tests run on any Linux machine. A stub replaces `droiddeck-proton-run`, and a DroidDeck checkout (`DROIDDECK_SRC`) enables the checks against DroidDeck's own shortcut code:

```bash
DROIDDECK_SRC=../DroidDeck bash tests/test_install.sh
```

```bash
DROIDDECK_SRC=../DroidDeck python3 -m unittest discover -s tests
```

```bash
shellcheck -x install.sh
```

## License

GPL-3.0. See [LICENSE](LICENSE).
