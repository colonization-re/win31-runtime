# How the runtime works

`COLONIZE.EXE` is a Windows 3.1 program: a 16-bit NE executable that imports
seven Win16 modules. Everything below explains how the runtime gets it running on
a 64-bit machine, and why each piece is there. Where a claim rests on an
observation, the observation is quoted.

## The stack

```
COLONIZE.EXE    16-bit, NE format, Borland C++ 4.52, 1995
  otvdm         software x86 emulator (vm86.dll) + Win16 modules thunked to Win32
    Wine        runs otvdm.exe, an ordinary 32-bit PE program
      macOS     (Linux: the same; Windows: otvdm runs natively, no Wine)
```

## Why Wine's own Win16 support is not used

Wine can run Win16 programs by itself, through `winevdm.exe` and its own
`krnl386.exe16`. On a 64-bit Mac that path is closed, for one of two reasons
depending on the Wine:

**CrossOver 26.3** ships the Win16 modules (`krnl386.exe16`, `user.exe16`,
`gdi.exe16`, even `wing.dll16`), but Wine builds real 16-bit code segments by
writing descriptors into the LDT, and CrossOver's 32-on-64 layer stubs out the
system call that does it:

```
err:wow:wow64_NtSetLdtEntries HACK: not calling NtSetLdtEntries()
warn:module:process_attach Initialization of L"krnl386.exe16" failed
err:module:loader_init "krnl386.exe16" failed to initialize, aborting
```

That is structural, not a setting: there is no 32-bit Unix-side loader on a
64-bit Mac to fall back to.

**Game Porting Toolkit 1.1 (wine-7.7)** has no Win16 layer at all: its 679
32-bit modules include neither `winevdm.exe` nor `krnl386.exe16`, and starting
the game directly fails before any of its code runs:

```
Application could not be started, or no application associated with the specified file.
ShellExecuteEx failed: File not found.
```

## Why otvdm works

[otvdm](https://github.com/otya128/winevdm) was written for 64-bit Windows,
which cannot run 16-bit programs either, and for the same underlying reason
(its README: *"64-bit Windows cannot modify LDT"*). It does not execute 16-bit
code on the CPU at all: `vm86.dll` **emulates** the x86 in software, and the
Win16 API is implemented by thunking up to Win32. To Wine, otvdm is just another
32-bit Windows program, which every current Mac Wine can run.

It also provides every module the game imports:

| The game imports | Provided by |
| --- | --- |
| `KERNEL` | `otvdm/dll/krnl386.exe16` |
| `USER` | `otvdm/dll/user.exe16` |
| `GDI` | `otvdm/dll/gdi.exe16` |
| `WING` | `otvdm/dll/wing.dll16` |
| `COMMDLG` | `otvdm/dll/commdlg.dll16` |
| `MMSYSTEM` | `otvdm/dll/mmsystem.dll16` |
| `WIN87EM` | `otvdm/dll/win87em.dll16` |

`WING` matters most. WinG was Microsoft's 1994 fast-graphics library for games;
the original installer copied it into `WINDOWS\SYSTEM`, so it is not among the
game's own files. Without otvdm's reimplementation the game would have no way to
draw.

## Making Wine use otvdm's modules

Wine ships builtins under the same names as otvdm's modules and prefers its own.
Left alone, it loads the builtin `krnl386.exe16`, which is exactly the one that
needs the LDT. So every module in `otvdm/dll` has to be set to `native`.

The runtime does that in the registry, not with the `WINEDLLOVERRIDES`
environment variable, for two reasons:

1. **CrossOver discards `WINEDLLOVERRIDES`.** Its `wine` wrapper deletes the
   variable and rebuilds it only from its own `--dll` option. Setting it looks
   right and silently does nothing. The registry is honoured by every Wine.
2. **It can be scoped.** The overrides go under
   `HKCU\Software\Wine\AppDefaults\otvdm.exe\DllOverrides`, so they apply only
   inside `otvdm.exe` and nothing else in the prefix changes.

One detail of Wine's lookup: it drops a `.dll` suffix before it consults the
registry, and keeps every other suffix. So otvdm's `vm86.dll` is registered as
`vm86`, while `krnl386.exe16` keeps its full name. A trace
(`WINEDEBUG=+module`) shows both taking effect:

```
trace:module:get_load_order_value got app defaults n for L"krnl386.exe16"
trace:loaddll:build_module Loaded L"C:\\otvdm\\dll\\krnl386.exe16" at 00B60000: native
trace:module:get_load_order_value got app defaults n for L"vm86"
trace:loaddll:build_module Loaded L"C:\\otvdm\\dll\\vm86.dll" at 02280000: native
```

After that the game loads the way it would on Windows 3.1:

```
trace:module:MODULE_LoadModule16 Loaded module 'C:\COLONIZE\COLONIZE.EXE'
trace:loaddll:build_module Loaded L"C:\\otvdm\\dll\\wing.dll16" at 034B0000: native
trace:module:MODULE_LoadModule16 Loaded module 'coldata0.dll' at 0x13d7.
...
trace:module:MODULE_LoadModule16 Loaded module 'coldata5.dll' at 0x1597.
```

## Why the game runs from a copy

The game writes into its own directory: its preferences (`COLWIN.PRF`) and its
saved games (`*.SAV`) go next to `COLONIZE.EXE`, and it opens its data files by
relative path, so it has to be started from that directory. The directory a
player has may be read-only (a CD, or files copied off one keep their read-only
bit), and some players will want their original copy left untouched. So `setup`
copies the game into the runtime, makes the copy writable, and never writes to
the source. Running `setup` again copies only files that are missing, so saves
and edits in the runtime survive it.

## The runtime directory

```
<runtime>/
  config                 which Wine built the prefix, where the game was copied from
  cache/otvdm-*.zip      the download, kept so that setup can run again offline
  last-run.log           Wine's output from the last run
  prefix/                a Wine prefix; under CrossOver, a bottle at this path
    drive_c/otvdm/       otvdm, plus the .reg file of overrides setup imported
    drive_c/COLONIZE/    the game, and its saves
```

A CrossOver bottle normally lives in CrossOver's own folder. CrossOver also
accepts an absolute path as a bottle name, so the runtime keeps the bottle here
and every Wine is handled the same way. The bottle does not appear in
CrossOver's window.

## Other hosts

- **Windows 10/11, 64-bit.** The same otvdm, run natively, with no Wine and no
  overrides, since there are no Wine builtins to shadow. The plan is a
  `colonization.ps1` beside `colonization.sh`, reading the same
  [runtime.lock](../runtime.lock). (32-bit Windows 10 still has NTVDM, which runs
  Win16 programs natively, but the game would also need WinG installed.)
- **Linux.** Wine on Linux can build LDT entries, so its own Win16 support may
  well work there. The runtime still uses otvdm, so that every host runs the
  game on the same emulator and bugs reproduce across hosts. The script already
  runs on Linux, but nobody has tried it yet.
