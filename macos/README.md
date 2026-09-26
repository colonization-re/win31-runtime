# Colonization for Windows on macOS

`colonization.sh` builds a runtime for the game, installs your copy into it, and
starts it. It is for macOS only; other platforms get their own folder.

## What you need

**A Wine.** Any one of these:

- the free one: `brew install --cask wine-stable`
- [CrossOver](https://www.codeweavers.com/crossover), if you have it
- Apple's Game Porting Toolkit, if you already have it installed

On Apple Silicon, Wine also needs Rosetta 2:
`softwareupdate --install-rosetta --agree-to-license`.

**Your game**: Steam's `COLONIZE.ISO` (or the folder holding it), an installed
copy, or the Windows CD. The [top-level README](../README.md#your-game) lists
what each gives you.

Nothing else. Setup downloads one thing, [otvdm](https://github.com/otya128/winevdm)
(1.5 MB), and checks it against the SHA-256 pinned in
[runtime.lock](../runtime.lock). Everything else it uses (`tar`, `perl`, `curl`,
`unzip`, `shasum`) comes with macOS.

## Set up once, then play

```sh
./macos/colonization.sh setup ~/games/colonization     # the folder, or the .iso file
./macos/colonization.sh
```

`setup` with no argument uses the current directory, so running it from inside the
game's folder (Steam's, for instance) works too. It takes under a minute.

## Commands

| | |
| --- | --- |
| `colonization.sh setup [SOURCE]` | build the runtime and install the game into it, from an installed copy, the CD, or an ISO (default: the current directory). Safe to run again: files already in the runtime, your saves among them, are left alone |
| `colonization.sh` | play (`play` is the default command) |
| `colonization.sh info` | what was found, which build is installed, and where everything lives |
| `colonization.sh wine CMD` | run a Windows command inside the runtime, e.g. `winecfg` |

## Where things are

Everything lives in one directory, the **runtime**:
`~/Library/Application Support/win31-runtime`, or wherever `COLWIN_HOME` points.

The game runs from a copy at `prefix/drive_c/COLONIZE` inside the runtime, and
**that is where your saved games are** (`*.SAV`). Whatever you gave `setup` is
only ever read, so a read-only folder, a CD or Steam's own files work as they are.

To uninstall, delete the runtime directory and this checkout. Back up your saves
first, because deleting the runtime deletes them.

## Choosing a Wine

With no instructions, `setup` takes the first Wine it finds: `wine` or `wine64` on
your `PATH`, then the Wine apps in `/Applications`, then CrossOver. CrossOver
comes last on purpose, so that owning it is never required. To pick one yourself:

```sh
./macos/colonization.sh setup --wine=crossover ~/games/colonization
./macos/colonization.sh setup --wine=/path/to/bin/wine ~/games/colonization
```

A runtime keeps the Wine it was built with, because a CrossOver bottle and a
plain Wine prefix are not interchangeable. To try a different Wine, or a different
copy of the game, build a second runtime beside the first one:
`COLWIN_HOME=~/colonization-crossover ./macos/colonization.sh setup --wine=crossover …`.

## When something goes wrong

- Wine's output from the last run is in `last-run.log` in the runtime. When the
  game exits with an error, the end of that log is printed for you.
- `WINEDEBUG=+loaddll,+module ./macos/colonization.sh` logs every module as it
  loads (`+loaddll` alone leaves out the game's own 16-bit modules). A healthy
  start loads `krnl386.exe16` from `C:\otvdm\dll` as `native`, then
  `C:\COLONIZE\COLONIZE.EXE`, then `coldata0.dll` and the rest.
- otvdm has its own settings, in `prefix/drive_c/otvdm/otvdm.ini`. They are left
  at their defaults. Your edits there survive running `setup` again.
