#!/bin/bash
fail=0
chk(){ if ! eval "$2" >/dev/null 2>&1; then echo "FAIL: $1"; fail=$((fail+1)); fi; }
chk "results line" 'pmars -b -r 50 -f /app/flashpaper.red /app/rave.red | tail -n 1 | grep -Eq "^Results: [0-9]+ [0-9]+ [0-9]+$"'
chk "no X11" '[ -x /usr/local/bin/pmars ] && ! ldd /usr/local/bin/pmars | grep -qi x11'
chk "debian source" 'ls /app/pmars_*.dsc && ls -d /app/pmars-*/debian'
chk "debugger" 'echo q | pmars -e /app/flashpaper.red /app/rave.red 2>&1 | grep -qi cdb'
[ $fail -eq 0 ] && echo "All checks passed." || echo "FAILED: $fail"
