# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A launcher that runs the original *Colonization for Windows* (1995, a 16-bit
Win16 NE program) on modern hosts. The stack is otvdm (a software 16-bit x86
emulator plus Win16 modules) under Wine. The repository never contains the game:
the player supplies an installed copy, and `setup` copies it into a runtime
directory outside the checkout. [docs/how-it-works.md](docs/how-it-works.md)
explains each layer and quotes the evidence for it.

## Layout

| | |
| --- | --- |
| [colonization.sh](colonization.sh) | the macOS/Linux entry point: `setup`, `play`, `info`, `wine` |
| [runtime.lock](runtime.lock) | pinned downloads (otvdm version, URL, SHA-256), shared by every host script |
| [docs/how-it-works.md](docs/how-it-works.md) | why otvdm, why registry overrides, why a copy of the game |
| [.github/workflows/lint.yml](.github/workflows/lint.yml) | shellcheck, plus a syntax check and smoke run under macOS's bash 3.2 |

## Constraints that are easy to break

- **bash 3.2.** macOS ships bash 3.2, so `colonization.sh` must run on it: no
  associative arrays, no `mapfile`, no `${var,,}`, and no `"${arr[@]}"` on an
  array that may be empty (under `set -u`, 3.2 treats that as unbound). Check
  with `/bin/bash -n colonization.sh`, not the Homebrew bash.
- **`runtime.lock` is data, not shell.** It is parsed with `kv`, never
  `source`d, so that the planned `colonization.ps1` can read it with
  `ConvertFrom-StringData`. Keep it `KEY=VALUE`, with no quotes and no expansion.
- **The source game directory is read-only.** `setup` reads it and copies
  missing files into the runtime. It never writes to the source and never
  overwrites a file already in the runtime, because that file may be a save.
- **DLL overrides go in the registry**
  (`HKCU\Software\Wine\AppDefaults\otvdm.exe\DllOverrides`), not in
  `WINEDLLOVERRIDES`: CrossOver's wrapper deletes that variable. Wine strips a
  `.dll` suffix before its lookup, so `vm86.dll` is written as `vm86`, while
  `krnl386.exe16` keeps its full name.
- **CrossOver is one Wine among several.** Its wrapper accepts an absolute path
  as `--bottle`, so a CrossOver runtime lives in `COLWIN_HOME` like any other.
  Only prefix creation (`cxbottle`) and the launch flags differ.

## Testing a change

There is no unit-test suite; the test is running the game. Build a throwaway
runtime so the real one is not touched:

```sh
export COLWIN_HOME=/tmp/colwin-test
./colonization.sh setup /path/to/game                  # or: setup --wine=crossover ...
WINEDEBUG=+loaddll,+module ./colonization.sh           # close the window, or kill it
grep -E "got app defaults|Loaded module 'C:|coldata0" "$COLWIN_HOME/last-run.log"
```

A healthy run shows `got app defaults n for L"krnl386.exe16"`, `COLONIZE.EXE`
loaded, then `coldata0.dll` through `coldata9.dll`. Whether the game *draws*
needs a person looking at the screen: say which of the two was checked.

If a test run is killed from outside, killing `colonization.sh` does not stop
Wine. Stop that prefix's processes too: `WINEPREFIX=$COLWIN_HOME/prefix
wineserver -k` for a plain Wine; under CrossOver, kill the `otvdm.exe` and
`winewrapper.exe` processes.

Before committing, run `shellcheck colonization.sh` (CI does) and
`/bin/bash -n colonization.sh`.

## Planned

- **Windows:** `colonization.ps1` (plus a `.cmd` shim to double-click), which
  runs otvdm natively with no Wine and no overrides, reads `runtime.lock`, and
  uses `%LOCALAPPDATA%\win31-runtime` as its runtime.
- **Linux:** `colonization.sh` already runs there but has never been tried; the
  README's status table says so until someone has.
