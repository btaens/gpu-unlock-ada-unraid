#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Invoked by modprobe before nvidia; never unload or unbind a running driver.
BASE=/boot/config/gpu-unlock-unraid
log() { printf '<6>gpu-unlock-unraid: %s\n' "$*" > /dev/kmsg; }

if [ "${1:-}" != --locked ]; then
    ERR=/run/gpu-unlock-unraid.err
    /usr/bin/flock -x /run/gpu-unlock-unraid.lock \
        /bin/sh "$BASE/pre-nvidia.sh" --locked 2>"$ERR"
    RESULT=$?
    if [ -s "$ERR" ]; then
        while IFS= read -r LINE; do log "$LINE"; done < "$ERR"
    fi
    [ "$RESULT" -eq 0 ] || log "Hook exited $RESULT; continuing NVIDIA startup."
    exit 0
fi

[ ! -e "$BASE/disabled" ] || { log 'Skipped: disabled.'; exit 0; }
[ ! -e /boot/config/gpu-unlock.disable ] || { log 'Skipped: legacy disable file.'; exit 0; }
if [ -f /boot/unraidsafemode ] || grep -qw unraidsafemode /proc/cmdline; then
    log 'Skipped: Safe Mode.'; exit 0
fi
KREL=$(uname -r)
PAYLOAD="$BASE/kernels/$KREL"
if [ ! -r "$PAYLOAD/gpu_unlock.ko" ]; then
    log "Skipped: no module built for $KREL."; exit 0
fi
TARGET=$(cat "$BASE/target" 2>/dev/null)
if ! printf '%s\n' "$TARGET" | grep -Eq '^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$'; then
    log 'Skipped: invalid PCI target.'; exit 0
fi
# Check complete tokens rather than accepting a partial PCI address match.
OPT_IN=no
for ARG in $(cat /proc/cmdline); do
    [ "$ARG" != "gpu_unlock.targets=$TARGET" ] || OPT_IN=yes
done
[ "$OPT_IN" = yes ] || { log 'Skipped: boot opt-in absent.'; exit 0; }
[ ! -d /sys/module/gpu_unlock ] || exit 0
if [ -L "/sys/bus/pci/devices/$TARGET/driver" ]; then
    log "Skipped: a driver already owns $TARGET."; exit 0
fi
if ! (cd "$PAYLOAD" && sha256sum -c SHA256SUMS >/dev/null); then
    log 'Skipped: payload checksum verification failed.'; exit 0
fi
if ! mkdir -p /lib/firmware/gpu-unlock ||
   ! cp -R "$PAYLOAD/firmware/gpu-unlock/." /lib/firmware/gpu-unlock/; then
    log 'Skipped: firmware staging failed.'; exit 0
fi
log "Running unlock for $TARGET before NVIDIA loads ($KREL)."
if /sbin/insmod "$PAYLOAD/gpu_unlock.ko" "targets=$TARGET"; then
    log 'Module executed; check gpu_unlock: unlocked in kernel log.'
else
    log 'Module load failed; continuing NVIDIA startup.'
fi
exit 0
