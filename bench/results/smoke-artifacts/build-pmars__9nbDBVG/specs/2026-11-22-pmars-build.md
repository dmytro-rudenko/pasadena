# pMARS build from Debian source — design

**Date:** 2026-11-22
**Status:** proposed (awaiting approval)

## 1. Problem
`/app` holds only `flashpaper.red` and `rave.red`. No `pmars` binary exists. koth.org is unreliable, so the upstream tarball is not a usable source.

## 2. Constraint that shapes the solution
The source must come from Debian (`pmars` 0.9.4-1, trixie), not koth.org. The binary must have no X11 linkage, and the debugger must still work. The Debian sources are not enabled (`Types: deb` only), so a `deb-src` entry is needed to fetch the source package.

## 3. Solution
1. Add a `deb-src` stanza for trixie to `/etc/apt/sources.list.d/` (a new file, so `debian.sources` is untouched). Run `apt-get update`.
2. Install build deps: `apt-get build-dep -y pmars`, or at minimum `build-essential` and `dpkg-dev`.
3. In a new empty directory, run `apt-get source pmars`. Then place the unpacked source tree in `/app/pmars-0.9.4/`. The `.dsc`, orig tarball and debian tarball sit alongside it as evidence of Debian provenance. The `.red` files stay untouched.
4. Build with the Debian patches applied, and with X11 off: edit the `CFLAGS` and `LFLAGS` in `src/Makefile`, removing `-DXWINGRAPHX` and `-lX11`. Keep the debugger enabled (it is the default text-mode CDB). Build from the `src` directory with `make`, passing paths as arguments.
5. Install with `install -m755 pmars /usr/local/bin/pmars`.

## 4. Out of scope
The graphical display, the Debian `.deb` packaging, man pages and docs installation, and any changes to the `.red` files.

## 5. Trade-offs accepted
We build with the Makefile directly rather than via `dpkg-buildpackage`. This is simpler and does not need to produce a `.deb`. It also adds an apt source to the system.

## 6. Verification
- `pmars -b -r 50 -f /app/flashpaper.red /app/rave.red | tail -n 1` prints `Results: X Y Z` with integer values.
- `ldd /usr/local/bin/pmars | grep -i x11` returns nothing.
- The source tree under `/app` contains the Debian patches (`debian/` directory or an applied `.pc`), and the `.dsc` is present.
- The debugger starts: `echo q | pmars -e flashpaper.red rave.red` reaches the `cdb>` prompt.
