#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
mkdir -p /boot/config/gpu-unlock-unraid
touch /boot/config/gpu-unlock-unraid/disabled
echo 'Disabled for the next boot. Current GPU state is unchanged.'
