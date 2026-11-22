# pMARS build from Debian source — implementation plan

**Goal:** `/usr/local/bin/pmars` built without X11 from the Debian trixie `pmars` source package, with the source extracted into `/app`.
**Spec:** /tmp/pasadena/specs/2026-11-22-pmars-build.md
**Verification:** `bash /tmp/pasadena/accept.sh` ends with `All checks passed.`
(Also: `pmars -b -r 50 -f /app/flashpaper.red /app/rave.red | tail -n 1` prints `Results: X Y Z`.)
Codex budget: not applicable (explore mode). No git: the plan and spec live under /tmp/pasadena and no commits are made.

## Global constraints
- Source comes from Debian (`apt-get source pmars`, trixie, 0.9.4-1), never koth.org.
- No X11: the build removes `-DXWINGRAPHX` and `-lX11`. The debugger (CDB) stays enabled.
- Install path: `/usr/local/bin/pmars`.
- Do not modify `/app/flashpaper.red` or `/app/rave.red`.
- Untrusted downloads: fetch into a new empty directory (`/tmp/pasadena/dl`), and do not run build tools from inside it. Pass paths as arguments (`make -C`).

## Review Focus
- Debian patches fail to apply, or the Makefile has no X flags where expected: read the real Makefile before editing.
- The `deb-src` entry is rejected because the mirror is unreachable: report it, and do not fall back to koth.org.
- The binary links against X11 indirectly, so check with `ldd`.
- The debugger prompt is missing: it must be tested, not assumed.

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone, acceptance tests, red until the last wave |
| 1 | 1 | alone, fetches the source that everything else reads |
| 2 | 2 | alone, builds in the tree from Task 1 |
| 3 | 3 | alone, installs the binary from Task 2 |

All tasks are serialized because each consumes the previous task's output.

### Task 0: acceptance tests
**Writes:** `/tmp/pasadena/accept.sh`
**Executor:** claude
**Covers:** "prints `Results: X Y Z` with integer values"; "`ldd` ... no X11"; "source tree under /app contains Debian patches and .dsc"; "debugger reaches `cdb>`".

- [ ] **Step 1: write the script.** It checks, with `fail` incrementing a counter:
  1. `pmars -b -r 50 -f /app/flashpaper.red /app/rave.red | tail -n 1` matches `^Results: [0-9]+ [0-9]+ [0-9]+$`.
  2. `ldd /usr/local/bin/pmars` contains no `X11`.
  3. `ls /app/pmars_*.dsc` exists and `/app/pmars-*/debian` exists.
  4. `echo q | pmars -e /app/flashpaper.red /app/rave.red` output contains `cdb`.
  It prints `All checks passed.` when the counter is 0, otherwise `FAILED: N`.
- [ ] **Step 2: run it, watch it fail.** `bash /tmp/pasadena/accept.sh`, expect `FAILED: 4` or similar.

### Task 1: fetch the Debian source
**Writes:** `/etc/apt/sources.list.d/debian-src.sources`, `/app/pmars-0.9.4/`, `/app/pmars_*.dsc`, `/app/pmars_*.tar.*`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** acceptance check 3.
**Interfaces:** Produces the patched source tree `/app/pmars-0.9.4/` with `src/Makefile`.

- [ ] **Step 1:** write `debian-src.sources` with `Types: deb-src`, `URIs: http://deb.debian.org/debian`, `Suites: trixie`, `Components: main`, `Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg`.
- [ ] **Step 2:** `apt-get update`.
- [ ] **Step 3:** `mkdir /tmp/pasadena/dl && cd /tmp/pasadena/dl && apt-get source --download-only pmars`. Then `dpkg-source -x pmars_*.dsc /app/pmars-0.9.4`, and `cp pmars_* /app/`.
- [ ] **Step 4:** run `bash /tmp/pasadena/accept.sh`. Check 3 passes.

### Task 2: build without X11
**Writes:** `/app/pmars-0.9.4/src/Makefile`, `/app/pmars-0.9.4/src/pmars`
**Depends on:** Task 1
**Executor:** claude
**Complexity:** routine
**Interfaces:** Consumes `src/Makefile` from Task 1. Produces the executable `/app/pmars-0.9.4/src/pmars`.

- [ ] **Step 1:** `apt-get install -y build-essential` (the package needs only gcc and make).
- [ ] **Step 2:** read the Makefile, then remove `-DXWINGRAPHX` from `CFLAGS` and `-lX11` (with any `-L` for X) from `LFLAGS`. Keep the text-mode graphics flags unchanged.
- [ ] **Step 3:** `make -C /app/pmars-0.9.4/src`.
- [ ] **Step 4:** run `ldd /app/pmars-0.9.4/src/pmars | grep -i x11`, expect no output.

### Task 3: install and verify
**Writes:** `/usr/local/bin/pmars`
**Depends on:** Task 2
**Executor:** claude
**Complexity:** routine
**Satisfies:** acceptance checks 1, 2 and 4.

- [ ] **Step 1:** `install -m755 /app/pmars-0.9.4/src/pmars /usr/local/bin/pmars`.
- [ ] **Step 2:** `bash /tmp/pasadena/accept.sh`, expect `All checks passed.`
