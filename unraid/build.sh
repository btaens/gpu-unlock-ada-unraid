#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build only: no GPU access, privileged container, host install, or driver changes.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
KREL=$(uname -r)
CONFIG="/usr/src/linux-$KREL/config"
WORK=${GPU_UNLOCK_WORK:-/mnt/user/appdata/gpu-unlock-unraid-build}
[[ "$KREL" =~ ^[0-9]+\.[0-9]+\.[0-9]+-Unraid$ ]] || { echo 'Unraid kernel required.' >&2; exit 1; }
test -r "$CONFIG"
grep -qx '# CONFIG_MODVERSIONS is not set' "$CONFIG" || { echo 'This recipe requires CONFIG_MODVERSIONS disabled.' >&2; exit 1; }
grep -qx 'CONFIG_RANDSTRUCT_NONE=y' "$CONFIG" || { echo 'This recipe requires CONFIG_RANDSTRUCT_NONE=y.' >&2; exit 1; }
GCC=$(sed -n 's/^CONFIG_CC_VERSION_TEXT=".*gcc (GCC) \([0-9][0-9.]*\).*"$/\1/p' "$CONFIG")
[[ "$GCC" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Could not determine GCC version; inspect kernel config.' >&2; exit 1; }
COMMIT=$(git -C "$ROOT" rev-parse HEAD)
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
exec 8>"$WORK/build.lock"
flock -n 8 || { echo 'Another build is running.' >&2; exit 1; }
SOURCE="$WORK/source-$COMMIT"
if [ ! -f "$SOURCE/Makefile" ]; then
    mkdir -p "$SOURCE"
    git -C "$ROOT" archive HEAD | tar -xf - -C "$SOURCE"
fi
docker run --rm -i \
    --mount "type=bind,src=$WORK,dst=/work" \
    --mount "type=bind,src=$CONFIG,dst=/input/unraid.config,readonly" \
    -e KREL="$KREL" -e GCC="$GCC" -e COMMIT="$COMMIT" \
    "gcc:$GCC" bash -s <<'BUILD'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends bc bison flex libelf-dev libssl-dev python3 zstd xz-utils kmod curl ca-certificates
test "$(gcc -dumpfullversion)" = "$GCC"
KSRC="/work/linux-$KREL"
ARCHIVE="/work/linux-$KREL.tar.xz"
if [ ! -s "$ARCHIVE" ]; then
    curl --fail --location --retry 3 \
        "https://github.com/ich777/unraid_kernel/releases/download/$KREL/linux-$KREL.tar.xz" \
        -o "$ARCHIVE.part"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
if [ ! -f "$KSRC/Makefile" ]; then
    mkdir -p "$KSRC"
    tar -xJf "$ARCHIVE" -C "$KSRC"
fi
test -s "$KSRC/Module.symvers"
cp /input/unraid.config "$KSRC/.config"
make -C "$KSRC" olddefconfig
make -C "$KSRC" -j4 modules_prepare
test "$(make --no-print-directory -s -C "$KSRC" kernelrelease)" = "$KREL"
cd "/work/source-$COMMIT"
make -C kernel/gpu_unlock KDIR="$KSRC" clean
make -C kernel/gpu_unlock KDIR="$KSRC" -j4
OUT=$(mktemp -d "/work/payload-$KREL.XXXXXX")
install -m644 kernel/gpu_unlock/gpu_unlock.ko "$OUT/gpu_unlock.ko"
test "$(modinfo -F vermagic "$OUT/gpu_unlock.ko" | cut -d ' ' -f1)" = "$KREL"
make assets INPUTS=/work/firmware-inputs ASSETS=/work/firmware-assets
make install-firmware ASSETS=/work/firmware-assets DESTDIR="$OUT" FWDIR=/firmware/gpu-unlock/610.43.03
cp /input/unraid.config "$OUT/kernel.config"
printf 'kernel=%s\ncompiler=%s\nsource_commit=%s\n' "$KREL" "$GCC" "$COMMIT" > "$OUT/manifest.txt"
modinfo -F vermagic "$OUT/gpu_unlock.ko" > "$OUT/vermagic.txt"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
modinfo "$OUT/gpu_unlock.ko"
printf '\nBUILD COMPLETE. Host payload directory: %s\n' "${OUT#/work/}"
BUILD
echo "Payload is inside $WORK. Build only; nothing installed or loaded."
