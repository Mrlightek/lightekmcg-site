#!/usr/bin/env bash
# A fixed diagnostic protocol. Never print BASH_COMMAND or environment values.
lightek_installer_diagnostics() {
  case "$1" in native|bootstrap|starter) ;; *) return 2 ;; esac
  LIGHTEK_INSTALLER_SCOPE=$1
  set -E
  trap 'lightek_installer_failure "$?" "$LINENO"' ERR
}
lightek_installer_failure() {
  local failure_status=$1 failure_line=$2
  printf 'LIGHTEK_INSTALLER_FAILURE scope=%s line=%s exit=%s\n' "$LIGHTEK_INSTALLER_SCOPE" "$failure_line" "$failure_status" >&2
  return "$failure_status"
}
