#!/bin/bash
# 合盖模式守护：接外接屏时禁止睡眠，合盖时熄灭内屏背光，开盖恢复
BRIGHT_STATE=/var/run/clamshell_brightness
DB=/Users/macos/bin/dbright
DISP=/Users/macos/bin/displays

restore() {
    if [ -f "$BRIGHT_STATE" ]; then
        v=$(cat "$BRIGHT_STATE" 2>/dev/null)
        [ -n "$v" ] && "$DB" "$v" >/dev/null 2>&1
        rm -f "$BRIGHT_STATE"
    fi
}
trap restore EXIT INT TERM
restore

while true; do
    ext=$("$DISP" 2>/dev/null | grep -c 'builtin=0')
    clam=$(ioreg -c IOPMrootDomain -r -l -w0 2>/dev/null \
           | grep -o '"AppleClamshellState" = [A-Za-z]*' | awk '{print $3}')

    if [ "${ext:-0}" -gt 0 ]; then
        pmset -a disablesleep 1 2>/dev/null
        if [ "$clam" = "Yes" ]; then
            if [ ! -f "$BRIGHT_STATE" ]; then
                "$DB" 2>/dev/null | head -1 | sed 's/.*brightness=//' > "$BRIGHT_STATE"
            fi
            "$DB" 0 >/dev/null 2>&1
        else
            restore
        fi
    else
        pmset -a disablesleep 0 2>/dev/null
        restore
    fi
    sleep 2
done
