# win31-runtime — play *Colonization for Windows* (1995) on a modern computer

*Sid Meier's Colonization* shipped for Windows 3.1 as a 16-bit program, and no
current macOS, Linux or 64-bit Windows runs 16-bit programs out of the box. This
repository is the glue that does: a script that builds a small runtime, installs
your game into it, and starts it.

It does **not** contain the game. Bring your own copy: Steam still sells it.

## Pick your platform

Each platform has its own script, in its own folder:

| Folder | Platform | State |
| --- | --- | --- |
| [macos/](macos/) | macOS | **works**; see below for which Wine has been tried |
| `linux/` | Linux | planned |
| `windows/` | Windows 10/11 (64-bit) | planned: otvdm runs natively there, with no Wine |

On macOS, in detail:

| Setup | State |
| --- | --- |
| Apple Silicon, CrossOver 26 | **works**: the game starts and draws; a full turn, sound and save/load not yet checked |
| Apple Silicon, the Wine in Apple's Game Porting Toolkit 1.1 | **works**: the game starts and its window appears |
| Homebrew's free Wine (`wine-stable`) | expected to work, not yet tried |
| Intel | expected to work, not yet tried |

## Quick start (macOS)

```sh
git clone https://github.com/colonization-re/win31-runtime
cd win31-runtime
./macos/colonization.sh setup ~/games/colonization     # your game: a folder, or an .iso
./macos/colonization.sh
```

You also need a Wine; [macos/README.md](macos/README.md) says which ones work and
how to install one. It is the whole manual for macOS: every command, where your
saves are, choosing between Wines, and what to do when something goes wrong.

## Your game

`setup` takes the game in any of these forms, and reads it without changing it:

| The game from | State |
| --- | --- |
| **Steam**: the folder holding `COLONIZE.ISO`, or the ISO itself | installs, starts, and loads every module; on-screen drawing not yet confirmed |
| an **installed copy**: the folder holding `COLONIZE.EXE` and `COLDATA0.DLL` … | works, patched or not |
| the **Windows CD**, mounted or copied, or an `.iso` of it | the same path as Steam's ISO |
| GOG | planned |

### The Steam release

Windows 3.1 is no longer sold, but *Colonization* is. Steam's release has
`COLONIZE.ISO` in its folder: an image of the CD that carried both the DOS and the
Windows versions. `setup` installs the Windows version from the image. It copies
the same files the CD's own installer would, without running the installer.
[docs/cd-image.md](docs/cd-image.md) explains how, and what the image holds.

Two things differ from a boxed copy of the time:

- **It is the original, unpatched 1995 build.** MicroProse's later patch, which
  fixes "some of the recurring lock-ups", is not on the CD. `setup` and `info` say
  which build you have.
- **There is no music.** The game played its music as audio tracks from the CD,
  and the ISO holds only the data track. Sound effects work as normal.

## How it works

Three layers, top to bottom:

```
COLONIZE.EXE   16-bit Windows 3.1 program
otvdm          emulates the 16-bit x86 CPU in software; turns Win16 calls into Win32 calls
Wine           runs otvdm, which is an ordinary 32-bit Windows program (not needed on Windows)
macOS
```

Wine has Win16 support of its own, but on macOS it cannot work: it has to write
16-bit segment descriptors into the processor's LDT, and 64-bit macOS does not
allow that. otvdm sidesteps the LDT entirely, and it also supplies WinG, the 1994
graphics library the game draws with, which is not part of the game's files.
[docs/how-it-works.md](docs/how-it-works.md) has the details and the evidence.

## What is where

| | |
| --- | --- |
| [macos/](macos/) | the macOS script, and its manual |
| [runtime.lock](runtime.lock) | what setup downloads (otvdm), pinned by SHA-256; shared by every platform |
| [known-builds.txt](known-builds.txt) | the `COLONIZE.EXE` builds setup can name; shared by every platform |
| [lib/](lib/) | helpers the Unix scripts share: the unpacker for the CD's compressed `COLONIZE.EXE` |
| [docs/](docs/) | how the runtime works, and how it installs from a CD image |

## Credits and licence

- **otvdm / winevdm**, by otya128 and contributors, GPL-2.0. It is downloaded
  from its GitHub release when you run setup and is not redistributed here.
- **Wine**, LGPL, which you install yourself.

This repository's scripts and documentation are MIT-licensed; see
[LICENSE](LICENSE). The game belongs to its rights holder; see
[NOTICE.md](NOTICE.md).
