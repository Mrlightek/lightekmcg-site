#!/usr/bin/env bash
# Only invoked for the explicit remote starter-pool profile, before compilation.
set -euo pipefail
[[ "$EUID" = 0 ]] || { echo 'Starter-pool setup requires root.' >&2; exit 1; }
SWAP_FILE=/var/lib/lightek/member-pool.swap
SWAP_TARGET_KIB=2097152
current_kib=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
if (( current_kib < SWAP_TARGET_KIB ));then
 install -d -m 0700 /var/lib/lightek
 if [[ ! -f "$SWAP_FILE" ]];then
  available_kib=$(df -Pk /var/lib/lightek | awk 'NR==2 {print $4}')
  (( available_kib >= 3145728 )) || { echo 'Starter host needs 3 GB free before preparing swap.' >&2;exit 1; }
  (umask 077; fallocate -l 2G "$SWAP_FILE")
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
 fi
 if ! swapon --noheadings --raw --show=NAME | awk -v target="$SWAP_FILE" '$0==target {found=1} END {exit !found}';then
  swapon "$SWAP_FILE"
 fi
 grep -qF "$SWAP_FILE none swap sw 0 0" /etc/fstab || printf '%s none swap sw 0 0\n' "$SWAP_FILE" >> /etc/fstab
fi
