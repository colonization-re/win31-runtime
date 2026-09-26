# win31-runtime — play *Colonization for Windows* (1995) on a modern computer

*Sid Meier's Colonization* shipped for Windows 3.1 as a 16-bit program, and no
current macOS, Linux or 64-bit Windows runs 16-bit programs out of the box. This
repository is the glue that does: one script that builds a small runtime, copies
your game into it, and starts it.

It does **not** contain the game. Bring your own copy.

## Where it runs

| Host | State |
| --- | --- |
| macOS on Apple Silicon, with CrossOver 26 | **works**: the game starts and draws; a full turn, sound and save/load not yet checked |
| macOS on Apple Silicon, with the Wine in Apple's Game Porting Toolkit 1.1 | **starts**: the game and all its data modules load and it runs; on-screen drawing not yet confirmed |
| macOS, with Homebrew's free Wine (`wine-stable`) | expected to work, not yet tried |
| macOS on Intel | expected to work, not yet tried |
| Linux | the same script, with any Wine that runs 32-bit programs; not yet tried |
| Windows 10/11 (64-bit) | planned: `colonization.ps1`, running otvdm natively with no Wine |

## Quick start (macOS)

**1. A Wine.** Any one of these:

- the free one: `brew install --cask wine-stable`
- [CrossOver](https://www.codeweavers.com/crossover), if you have it
- Apple's Game Porting Toolkit, if you already have it installed

On Apple Silicon, Wine also needs Rosetta 2:
`softwareupdate --install-rosetta --agree-to-license`.

**2. Your game.** An *installed* copy: the directory holding `COLONIZE.EXE`,
`COLTEXT0.DLL` and `COLDATA0.DLL` … `COLDATA9.DLL`. The name of the directory does
not matter.

**3. Set up once, then play:**

```sh
git clone https://github.com/colonization-re/win31-runtime
cd win31-runtime
./colonization.sh setup ~/games/colonization
./colonization.sh
```

Setup takes under a minute. It downloads one thing,
[otvdm](https://github.com/otya128/winevdm) (1.5 MB), and checks it against
the checksum pinned in [runtime.lock](runtime.lock).

## Commands

| | |
| --- | --- |
| `./colonization.sh setup GAME_DIR` | build the runtime and copy the game into it. Safe to run again: files already in the runtime, your saves among them, are left alone |
| `./colonization.sh` | play (`play` is the default command) |
| `./colonization.sh info` | what was found and where everything lives |
| `./colonization.sh wine CMD` | run a Windows command inside the runtime, e.g. `winecfg` |

## Where things are

Everything lives in one directory, the **runtime**:

- macOS: `~/Library/Application Support/win31-runtime`
- Linux: `~/.local/share/win31-runtime` (or `$XDG_DATA_HOME/win31-runtime`)
- anywhere else you like: set `COLWIN_HOME=/some/dir`

The game runs from a copy at `prefix/drive_c/COLONIZE` inside the runtime, and
**that is where your saved games are** (`*.SAV`). The directory you gave `setup`
is only ever read: a copy from a CD or a read-only folder works just as well.

To uninstall, delete the runtime directory and this checkout. Back up your saves
first, because deleting the runtime deletes them.

## Choosing a Wine

With no instructions, `setup` takes the first Wine it finds: `wine` or `wine64` on
your `PATH`, then the Wine apps in `/Applications`, then CrossOver. CrossOver
comes last on purpose, so that owning it is never required. To pick one yourself:

```sh
./colonization.sh setup --wine=crossover ~/games/colonization
./colonization.sh setup --wine=/path/to/bin/wine ~/games/colonization
```

A runtime keeps the Wine it was built with, because a CrossOver bottle and a
plain Wine prefix are not interchangeable. To try a different Wine, build a second
runtime beside the first one:
`COLWIN_HOME=~/colonization-crossover ./colonization.sh setup --wine=crossover …`.

## When something goes wrong

- Wine's output from the last run is in `last-run.log` in the runtime. When the
  game exits with an error, the end of that log is printed for you.
- `WINEDEBUG=+loaddll,+module ./colonization.sh` logs every module as it loads
  (`+loaddll` alone leaves out the game's own 16-bit modules). A healthy start
  loads `krnl386.exe16` from `C:\otvdm\dll` as `native`, then
  `C:\COLONIZE\COLONIZE.EXE`, then `coldata0.dll` and the rest.
- otvdm has its own settings, in `prefix/drive_c/otvdm/otvdm.ini`. They are left
  at their defaults. Your edits there survive running `setup` again.

## How it works

Three layers, top to bottom:

```
COLONIZE.EXE   16-bit Windows 3.1 program
otvdm          emulates the 16-bit x86 CPU in software; turns Win16 calls into Win32 calls
Wine           runs otvdm, which is an ordinary 32-bit Windows program
macOS / Linux
```

Wine has Win16 support of its own, but on macOS it cannot work: it has to write
16-bit segment descriptors into the processor's LDT, and 64-bit macOS does not
allow that. otvdm sidesteps the LDT entirely, and it also supplies WinG, the 1994
graphics library the game draws with, which is not part of the game's files.
[docs/how-it-works.md](docs/how-it-works.md) has the details and the evidence.

## Credits and licence

- **otvdm / winevdm**, by otya128 and contributors, GPL-2.0. It is downloaded
  from its GitHub release when you run setup and is not redistributed here.
- **Wine**, LGPL, which you install yourself.

This repository's scripts and documentation are MIT-licensed; see
[LICENSE](LICENSE). The game belongs to its rights holder; see
[NOTICE.md](NOTICE.md).
