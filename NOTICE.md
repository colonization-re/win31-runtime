# NOTICE

## What this repository is, and is not

This is a launcher for **Sid Meier's Colonization for Windows** (1995),
**© 1994–1995 MicroProse Software, Inc.** The rights in that game are held by its
present owner, not by this project.

**This repository does not contain the game.** It ships no executable, art, text
or sound from it. You bring your own copy, installed or as the CD image Steam sells.
`setup` reads what you give it and installs it into a runtime on your own disk,
and nothing from it is ever uploaded or committed. The CD's compressed executable
is unpacked by this project's own code ([lib/arcv_extract.pl](lib/arcv_extract.pl)).
The format was established by reverse engineering, for interoperability, in the
sibling project [win-decomp](https://github.com/colonization-re/win-decomp).

## What it downloads

`setup` downloads **otvdm** (winevdm), © otya128 and contributors, licensed under
the GNU General Public License v2. It is fetched from the project's own GitHub
release at the version pinned in [runtime.lock](runtime.lock), and its SHA-256 is
checked before it is used. It is not redistributed in this repository. Its
source code and licence are at <https://github.com/otya128/winevdm>.

**Wine** (LGPL) and, optionally, CrossOver or Apple's Game Porting Toolkit are
installed by you, under their own terms.

## This repository's own licence

The scripts and documentation here are this project's own work and are MIT
licensed; see [LICENSE](LICENSE).
