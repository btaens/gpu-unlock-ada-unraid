#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
printf '\n=== Kernel ===\n'
uname -r
printf '\n=== Boot parameters ===\n'
cat /proc/cmdline
printf '\n=== Unlock and NVIDIA initialization ===\n'
dmesg | grep -Ei 'gpu.unlock|NVRM: loading' || true
printf '\n=== NVIDIA ===\n'
nvidia-smi
