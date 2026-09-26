# Installing from the CD, or from Steam's COLONIZE.ISO

Windows 3.1 is no longer sold, but *Colonization* is: the Steam release ships
`COLONIZE.ISO`, an image of the game's CD, and the Windows version is on it. So
`setup` accepts that image, or the CD itself, and installs the Windows version from
it. It does not run the CD's installer; this page explains what it does instead,
and why the result is the same.

## What is on the CD

Steam's `COLONIZE.ISO` is a 36,896,768-byte UDF image. It also has an ISO 9660
directory (`CD001` at offset 0x8001), which is what `bsdtar` reads. Its top level:

| Directory | What it holds |
| --- | --- |
| `INSTALL/` | the Windows version and its installer |
| `WING/` | Microsoft's WinG installer, compressed (`WING.DL_`, `WINGDE.DL_`, …) |
| `COL_DOS/` | the DOS version's installer (`INSTALL.EXE`, `MPSLABS.00x`) |
| `MANUAL/` | the manual as a PDF, and Acrobat Reader installers from the time |
| `EXTRAS/` | a DOS boot-disk maker |

`INSTALL/` holds almost everything uncompressed: the ten data modules
`COLDATA0.DLL` … `COLDATA8.DLL` and `COLTEXT0.DLL`, the map `AMER2.MP`, 43 sound
effects and a `README.TXT`. Only the executable is packed, as `COLONIZE._00`. The
installer is InstallWrap (© 1994 Robert Salesas): `SETUP.EXE`, its compressed
script `SETUP.INF`, and `INSTALL.BIN`, another ARCV archive, which holds a
124,928-byte `install.exe`.

## What setup does instead of running the installer

The installer records what it copies in `INSTALL.LOG`. On an install made from
this CD, that is every file in `INSTALL/` except three (`COLONIZE._00`,
`INSTALL.BIN`, `MPLOGO.BMP`), plus `colonize.exe`, unpacked from `COLONIZE._00`.
It also creates a Program Manager group, which does not matter here.
`setup` does exactly that and no more:

1. extract the image with `bsdtar` (macOS's `tar`; on Linux `bsdtar`, or 7-Zip);
2. copy `INSTALL/` except those three files;
3. unpack `COLONIZE._00` to `COLONIZE.EXE` with [lib/arcv_extract.pl](../lib/arcv_extract.pl);
4. name the build by its SHA-256 from [known-builds.txt](../known-builds.txt).

Why not run `SETUP.EXE` itself inside the runtime? It is interactive, so setup
could not finish unattended. The CD also carries the real WinG in `WING/`, which
a Windows 3.1 install put into `WINDOWS\SYSTEM`; under this runtime otvdm supplies
WinG instead, and a second copy could only get in its way. Doing the steps above
directly gives the same game files the installer would have produced, in seconds.

## `COLONIZE._00`: an ARCV archive

ARCV is InstallWrap's container, and this one holds one member:

```
0x00  "ARCV"
0x04  WORD   version, 0x0110
0x06  WORD   offset of the CHNK header (59 here)
0x0c  BYTE   length of the member name; the name follows ("colonize.exe")
      DWORD  uncompressed size (1,175,040)
      DWORD  compressed size (448,408)
0x3b  "CHNK", a 16-byte header, then the payload to the end of the file
```

The sizes are placed right after the name, so their offsets depend on the name's
length. `INSTALL.BIN`, whose member is the 11-character `install.exe`, has them
one byte earlier, and the extractor reads them from there.

The payload is LZHUF (adaptive Huffman coding over a 4,096-byte LZSS window) in
InstallWrap's variant. It has 287 symbols: 256 literals, an end marker, and 30
match lengths. Its ring buffer is prefilled with spaces, and writing starts at
0xdc3. The position tables are LZHUF's standard ones, so the extractor generates
them rather than reading them out of `SETUP.EXE`. The constants were read out of
`SETUP.EXE`'s decompressor by the
[win-decomp](https://github.com/colonization-re/win-decomp) project.

It checks out exactly. The header's two sizes add up to the file size, and the
unpacked output is exactly the size the header states. It is also byte-identical
to the pre-patch executable that win-decomp recovered independently:
SHA-256 `ae7d9149…4833b650`, 1,175,040 bytes, a valid NE executable.

## Which build this gives you

The CD's `COLONIZE.EXE` is the **original 1995 release**. MicroProse later
released a patch. Its README says it "fixes some of the recurring lock-ups in the
game", and that the original "would not run under Windows '95. This has also been
corrected." A patched install has a different `COLONIZE.EXE` (1,227,264 bytes in
place of 1,175,040), plus `COLDATA9.DLL` and `COCKGUN.WAV`. The CD's installer
writes neither file, and only the patched build references them. The original
build names `COLDATA0.DLL` … `COLDATA8.DLL` and nothing more, so the CD's files
are complete for it.

Steam's image does not include the patch. Under otvdm the original build loads
exactly as the patched one does (`COLONIZE.EXE`, WinG, every data module, no
error dialogs). How it plays, lock-ups included, has not been compared yet.

## Music

The game's music is CD audio: tracks 2 to 27 of the original CD, played through
Windows' `[MCI] CD Audio` driver. The game does try (Wine loads `mcicda.dll`
during start-up). Steam's `COLONIZE.ISO` is data only, with no audio tracks, so
the game runs without music. Sound effects are WAV files and are unaffected.
