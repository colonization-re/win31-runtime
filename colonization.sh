#!/usr/bin/env bash
# Run Sid Meier's Colonization for Windows 3.1 (1995) on a modern computer.
#
#   ./colonization.sh setup /path/to/game   once: build a runtime, copy the game into it
#   ./colonization.sh                       play (the same as ./colonization.sh play)
#   ./colonization.sh info                  what was found, and where everything lives
#   ./colonization.sh wine winecfg          run any Windows command inside the runtime
#
# The game is a 16-bit Windows 3.1 program, which nothing modern runs directly. It
# runs on two layers:
#
#   COLONIZE.EXE  a 16-bit Win16 program
#   otvdm         emulates the 16-bit CPU in software, turns Win16 calls into Win32 ones
#   Wine          runs otvdm, which is an ordinary 32-bit Windows program
#
# Wine's own Win16 support is not used: it has to write 16-bit segment descriptors
# into the LDT, and 64-bit macOS does not allow that. docs/how-it-works.md has the
# evidence.
#
# This script is for macOS and Linux. On Windows otvdm runs without Wine; that will be
# colonization.ps1, reading the same runtime.lock.
#
# The game directory given to setup is only ever read. The game runs from a writable
# copy inside the runtime, and that copy is where its saves go.
#
# Environment:
#   COLWIN_HOME  where the runtime lives (default: per-user application data; see info)
#   COLWIN_GAME  the game directory, when setup is not given one
#   COLWIN_WINE  which Wine setup uses: auto, crossover, or a path to a wine binary
#   WINEDEBUG    passed through to Wine (default -all); the output goes to last-run.log
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LOCK=$HERE/runtime.lock

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }
say()  { printf '   %s\n' "$*"; }

usage() {
    cat <<'EOF'
usage: colonization.sh [--wine=WINE] [COMMAND [ARGS...]]

commands:
  setup [GAME_DIR]   build the runtime and copy the game into it (GAME_DIR or $COLWIN_GAME)
  play [ARGS...]     start the game (the default); ARGS go to COLONIZE.EXE
  info               platform, Wine, runtime location, installed state, saves
  wine CMD...        run a Windows command in the runtime, e.g. winecfg or regedit

options:
  --wine=WINE        for setup: auto (default), crossover, or a path to a wine binary

The runtime lives in $COLWIN_HOME if set, else in the per-user application data
directory. Deleting it removes everything, including saved games.
EOF
}

# kv FILE KEY: the value of KEY in a KEY=VALUE file (the last one wins), or nothing.
kv() {
    [ -f "$1" ] || return 0
    sed -n "s/^$2=//p" "$1" | tr -d '\r' | tail -n 1
}

# find_file DIR NAME: the entry of DIR whose name is NAME in any case, or nothing.
find_file() {
    local hit
    hit=$(find "$1" -mindepth 1 -maxdepth 1 -iname "$2" 2>/dev/null | head -n 1 || true)
    if [ -n "$hit" ]; then basename "$hit"; fi
}

# count ARGS...: how many arguments; with a glob, how many files it matched.
count() { echo $#; }

case "$(uname -s)" in
    Darwin) PLATFORM=macos ;;
    Linux)  PLATFORM=linux ;;
    MINGW*|MSYS*|CYGWIN*)
        die "on Windows otvdm runs without Wine; colonization.ps1 is planned but not written yet" ;;
    *)  die "unsupported system: $(uname -s)" ;;
esac
ARCH=$(uname -m)

if [ -n "${COLWIN_HOME:-}" ]; then
    RUNTIME=$COLWIN_HOME
elif [ "$PLATFORM" = macos ]; then
    RUNTIME="$HOME/Library/Application Support/win31-runtime"
else
    RUNTIME="${XDG_DATA_HOME:-$HOME/.local/share}/win31-runtime"
fi
PREFIX=$RUNTIME/prefix          # the Wine prefix (a CrossOver bottle, under CrossOver)
CACHE=$RUNTIME/cache            # downloads, kept so a re-setup needs no network
CONFIG=$RUNTIME/config          # which Wine built the prefix, and where the game came from
LOG=$RUNTIME/last-run.log
OTVDM_DIR=$PREFIX/drive_c/otvdm
GAME_DIR=$PREFIX/drive_c/COLONIZE
OTVDM_WIN='C:\otvdm'
GAME_WIN='C:\COLONIZE'

OTVDM_VERSION=$(kv "$LOCK" OTVDM_VERSION)
OTVDM_URL=$(kv "$LOCK" OTVDM_URL)
OTVDM_SHA256=$(kv "$LOCK" OTVDM_SHA256)
{ [ -n "$OTVDM_VERSION" ] && [ -n "$OTVDM_URL" ] && [ -n "$OTVDM_SHA256" ]; } \
    || die "runtime.lock is missing or incomplete: $LOCK"

export WINEDEBUG=${WINEDEBUG:--all}

# ---------------------------------------------------------------------------- Wine

# wine_kind PATH: "crossover" when PATH is CrossOver's wine wrapper, else "wine".
# The difference: CrossOver names its prefix with --bottle (a path is accepted) and
# replaces WINEPREFIX, WINEDLLOVERRIDES and WINEDEBUG with values of its own.
wine_kind() {
    if [ -x "$(dirname "$1")/cxbottle" ]; then echo crossover; else echo wine; fi
}

# wine_version PATH: one line naming the Wine, e.g. "wine-9.0" or "CrossOver 26.3.0".
wine_version() {
    if [ "$(wine_kind "$1")" = crossover ]; then
        "$1" --version 2>/dev/null | sed -n 's/^Public Version: /CrossOver /p' || true
    else
        "$1" --version 2>/dev/null | head -n 1 || true
    fi
}

crossover_wine() {
    local c
    for c in ${CX_ROOT:+"$CX_ROOT/bin/wine"} \
             "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
             "$HOME/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"; do
        if [ -x "$c" ]; then echo "$c"; return 0; fi
    done
    return 0
}

# find_wine: the first Wine found, as a path, or nothing. A free Wine on PATH comes
# first; CrossOver last, so that owning it is never required.
find_wine() {
    local c
    for c in wine wine64; do
        if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
    done
    [ "$PLATFORM" = macos ] || return 0
    for c in "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine" \
             "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine" \
             "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine" \
             "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"; do
        if [ -x "$c" ]; then echo "$c"; return 0; fi
    done
    crossover_wine
}

# resolve_wine auto|crossover|PATH: a wine binary, or nothing.
resolve_wine() {
    case $1 in
        auto)      find_wine ;;
        crossover) crossover_wine ;;
        *)         if [ -x "$1" ]; then echo "$1"; fi ;;
    esac
}

no_wine_help() {
    if [ "$PLATFORM" = macos ]; then
        echo "no Wine found. Install one (brew install --cask wine-stable), or CrossOver, or pass --wine=/path/to/wine"
    else
        echo "no Wine found. Install your distribution's wine package (with 32-bit support), or pass --wine=/path/to/wine"
    fi
}

use_wine() {
    WINE_BIN=$1
    WINE_KIND=$(wine_kind "$WINE_BIN")
    if [ "$WINE_KIND" = crossover ]; then export CX_DEBUGMSG=$WINEDEBUG; fi
}

# w ARGS...: run a Windows command in the runtime's prefix.
w() {
    if [ "$WINE_KIND" = crossover ]; then
        "$WINE_BIN" --bottle "$PREFIX" "$@"
    else
        WINEPREFIX=$PREFIX "$WINE_BIN" "$@"
    fi
}

# Wait for the prefix's wineserver to exit, which is when the registry reaches disk.
# CrossOver's wrapper manages its own wineserver, so there is nothing to wait for.
wait_wineserver() {
    local ws
    ws="$(dirname "$WINE_BIN")/wineserver"
    if [ "$WINE_KIND" = wine ] && [ -x "$ws" ]; then WINEPREFIX=$PREFIX "$ws" -w || true; fi
}

load_config() {
    [ -f "$CONFIG" ] || die "not set up yet: run ./colonization.sh setup /path/to/game"
    local bin; bin=$(kv "$CONFIG" WINE)
    [ -x "$bin" ] || die "the Wine this runtime was built with is gone: $bin (run setup again)"
    use_wine "$bin"
}

# ------------------------------------------------------------------------- helpers

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi \
        | cut -d' ' -f1
}

download() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
    else die "neither curl nor wget is installed"
    fi
}

# fetch URL DEST SHA256: DEST, downloaded if absent, and always checked against SHA256.
fetch() {
    if [ ! -f "$2" ]; then
        mkdir -p "$(dirname "$2")"
        download "$1" "$2.part" || die "download failed: $1"
        mv "$2.part" "$2"
    fi
    local got; got=$(sha256 "$2")
    if [ "$got" != "$3" ]; then
        rm -f "$2"
        die "checksum mismatch for $1 (got $got, runtime.lock pins $3); the file was deleted"
    fi
}

# Every module otvdm ships must load as otvdm's copy. Wine has builtins under the same
# names (krnl386.exe16, user.exe16, wow32.dll, ...) and prefers them, and its builtin
# krnl386 is the one that needs the LDT. Scoped to otvdm.exe, so nothing else in the
# prefix is affected. Wine drops a ".dll" suffix before it looks a name up; ".dll16"
# and the rest are looked up whole.
write_overrides() {
    local f
    printf 'REGEDIT4\n\n[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\otvdm.exe\\DllOverrides]\n'
    for f in "$OTVDM_DIR"/dll/*; do
        f=$(basename "$f")
        printf '"%s"="native"\n' "${f%.dll}"
    done
}

# ------------------------------------------------------------------------ commands

cmd_setup() {
    local src=
    while [ $# -gt 0 ]; do
        case $1 in
            --wine=*) WINE_OPT=${1#--wine=} ;;
            -*)       die "unknown setup option: $1" ;;
            *)        [ -z "$src" ] || die "setup takes one game directory"; src=$1 ;;
        esac
        shift
    done
    src=${src:-${COLWIN_GAME:-}}
    [ -n "$src" ] || die "usage: ./colonization.sh setup /path/to/game"
    [ -d "$src" ] || die "not a directory: $src"
    src=$(cd "$src" && pwd)
    local exe; exe=$(find_file "$src" COLONIZE.EXE)
    [ -n "$exe" ] || die "no COLONIZE.EXE in $src: point setup at an installed copy of the game"
    [ -n "$(find_file "$src" COLDATA0.DLL)" ] \
        || die "$src has COLONIZE.EXE but no COLDATA0.DLL: is the install complete?"

    if [ "$PLATFORM" = macos ] && [ "$ARCH" = arm64 ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
        die "Wine on Apple Silicon needs Rosetta 2: softwareupdate --install-rosetta --agree-to-license"
    fi

    # A prefix belongs to the Wine that made it; a CrossOver bottle and a plain prefix
    # are not interchangeable. So an existing runtime keeps its Wine.
    local want=${WINE_OPT:-${COLWIN_WINE:-auto}} bin
    if [ -f "$PREFIX/system.reg" ] && [ -f "$CONFIG" ]; then
        bin=$(kv "$CONFIG" WINE)
        if [ "$want" != auto ] && [ "$(resolve_wine "$want")" != "$bin" ]; then
            die "this runtime was built with $bin. To switch Wine, move $RUNTIME away (your saves are in $GAME_DIR) or set COLWIN_HOME to build a second one"
        fi
        [ -x "$bin" ] || die "this runtime was built with $bin, which is gone. Move $RUNTIME away (saves: $GAME_DIR) and run setup again"
    else
        bin=$(resolve_wine "$want")
        [ -n "$bin" ] || die "$(no_wine_help)"
    fi
    use_wine "$bin"
    say "Wine: $WINE_BIN ($(wine_version "$WINE_BIN"))"
    say "runtime: $RUNTIME"

    step "1/4 Wine prefix"
    if [ -f "$PREFIX/system.reg" ]; then
        say "already exists"
    else
        mkdir -p "$RUNTIME"
        if [ "$WINE_KIND" = crossover ]; then
            # win98: the oldest 32-bit template CrossOver offers, and the one verified.
            "$(dirname "$WINE_BIN")/cxbottle" --bottle "$PREFIX" --create --template win98 \
                --description "Colonization for Windows 3.1" >/dev/null 2>&1 || true
        else
            # mscoree/mshtml disabled: a fresh prefix otherwise offers to download Mono
            # and Gecko, neither of which a 1995 game uses.
            WINEPREFIX=$PREFIX WINEDLLOVERRIDES='mscoree=;mshtml=' \
                "$WINE_BIN" wineboot --init >/dev/null 2>&1 || true
            wait_wineserver
        fi
        [ -f "$PREFIX/system.reg" ] || die "Wine did not create a prefix at $PREFIX"
        say "created"
    fi

    step "2/4 otvdm $OTVDM_VERSION"
    if [ "$(cat "$OTVDM_DIR/.version" 2>/dev/null || true)" = "$OTVDM_VERSION" ]; then
        say "already installed"
    else
        local zip=$CACHE/otvdm-$OTVDM_VERSION.zip tmp top
        command -v unzip >/dev/null 2>&1 || die "unzip is required to unpack otvdm"
        fetch "$OTVDM_URL" "$zip" "$OTVDM_SHA256"
        tmp=$(mktemp -d "$RUNTIME/.unpack.XXXXXX")
        unzip -q "$zip" -d "$tmp"
        top=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)
        { [ -n "$top" ] && [ -f "$top/otvdm.exe" ]; } || die "unexpected layout in $zip"
        # An otvdm.ini the player has edited survives an upgrade.
        if [ -f "$OTVDM_DIR/otvdm.ini" ]; then cp -p "$OTVDM_DIR/otvdm.ini" "$top/otvdm.ini"; fi
        rm -rf "$OTVDM_DIR"
        mv "$top" "$OTVDM_DIR"
        rm -rf "$tmp"
        echo "$OTVDM_VERSION" > "$OTVDM_DIR/.version"
        say "installed to $OTVDM_WIN (checksum verified)"
    fi

    step "3/4 Wine loads otvdm's Win16 modules, not its own"
    write_overrides > "$OTVDM_DIR/colonization-overrides.reg"
    w reg import "$OTVDM_WIN\\colonization-overrides.reg" >/dev/null 2>&1 \
        || die "could not import $OTVDM_DIR/colonization-overrides.reg into the prefix"
    say "$(count "$OTVDM_DIR"/dll/*) modules set to native for otvdm.exe"

    step "4/4 the game, copied to $GAME_WIN"
    local f copied=0 kept=0
    mkdir -p "$GAME_DIR"
    while IFS= read -r f; do
        if [ -e "$GAME_DIR/$f" ]; then kept=$((kept + 1)); continue; fi
        mkdir -p "$GAME_DIR/$(dirname "$f")"
        cp -p "$src/$f" "$GAME_DIR/$f"
        chmod u+w "$GAME_DIR/$f"
        copied=$((copied + 1))
    done < <(cd "$src" && find . -type f ! -name '.*' | sed 's|^\./||' | sort)
    say "$copied copied from $src"
    if [ "$kept" -gt 0 ]; then say "$kept already there and left alone (saves, settings, edits)"; fi

    {
        echo "# Written by colonization.sh setup. The Wine that built this prefix."
        echo "WINE=$WINE_BIN"
        echo "GAME_SOURCE=$src"
    } > "$CONFIG"
    wait_wineserver

    printf '\nReady. Play with:  %s/colonization.sh\n' "$HERE"
}

cmd_play() {
    load_config
    local exe; exe=$(find_file "$GAME_DIR" COLONIZE.EXE)
    [ -n "$exe" ] || die "no COLONIZE.EXE in $GAME_DIR: run setup again"
    [ -f "$OTVDM_DIR/otvdm.exe" ] || die "otvdm is missing from $OTVDM_DIR: run setup again"
    cd "$GAME_DIR" || die "cannot enter $GAME_DIR"
    say "starting $exe (Wine output goes to $LOG)"
    local rc=0
    if [ "$WINE_KIND" = crossover ]; then
        "$WINE_BIN" --bottle "$PREFIX" --workdir "$GAME_WIN" \
            "$OTVDM_WIN\\otvdm.exe" "$GAME_WIN\\$exe" "$@" >"$LOG" 2>&1 || rc=$?
    else
        WINEPREFIX=$PREFIX "$WINE_BIN" \
            "$OTVDM_WIN\\otvdm.exe" "$GAME_WIN\\$exe" "$@" >"$LOG" 2>&1 || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        printf 'The game exited with status %s. The end of %s:\n\n' "$rc" "$LOG" >&2
        tail -n 20 "$LOG" >&2
    fi
    return "$rc"
}

cmd_info() {
    echo "platform    $PLATFORM $ARCH"
    if [ "$PLATFORM" = macos ] && [ "$ARCH" = arm64 ]; then
        if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then echo "rosetta     installed"
        else echo "rosetta     MISSING (softwareupdate --install-rosetta --agree-to-license)"; fi
    fi
    local found; found=$(find_wine)
    echo "wine found  ${found:-none}${found:+ ($(wine_version "$found"))}"
    echo "runtime     $RUNTIME$([ -d "$RUNTIME" ] || echo ' (not set up)')"
    [ -f "$CONFIG" ] || return 0
    echo "built with  $(kv "$CONFIG" WINE) ($(wine_version "$(kv "$CONFIG" WINE)"))"
    echo "otvdm       $(cat "$OTVDM_DIR/.version" 2>/dev/null || echo missing) (runtime.lock pins $OTVDM_VERSION)"
    echo "game        $GAME_DIR$([ -n "$(find_file "$GAME_DIR" COLONIZE.EXE)" ] || echo ' (COLONIZE.EXE missing)')"
    echo "copied from $(kv "$CONFIG" GAME_SOURCE)"
    echo "saves       $(find "$GAME_DIR" -maxdepth 1 -iname '*.sav' 2>/dev/null | wc -l | tr -d ' ') .SAV file(s), in the game directory above"
    if [ -f "$LOG" ]; then echo "last log    $LOG"; fi
}

cmd_wine() {
    [ $# -gt 0 ] || die "usage: ./colonization.sh wine CMD [ARGS...]"
    load_config
    cd "$GAME_DIR" || die "cannot enter $GAME_DIR"
    w "$@"
}

# -------------------------------------------------------------------------- main

WINE_OPT=
while [ $# -gt 0 ]; do
    case $1 in
        --wine=*)       WINE_OPT=${1#--wine=}; shift ;;
        -h|--help|help) usage; exit 0 ;;
        --)             shift; break ;;
        -*)             die "unknown option: $1 (see --help)" ;;
        *)              break ;;
    esac
done
cmd=${1:-play}
if [ $# -gt 0 ]; then shift; fi
case $cmd in
    setup) cmd_setup "$@" ;;
    play)  cmd_play "$@" ;;
    info)  cmd_info ;;
    wine)  cmd_wine "$@" ;;
    *)     die "unknown command: $cmd (see --help)" ;;
esac
