#!/bin/bash
# Regenerate the login banners (/etc/issue, /etc/issue.net) with the machine IP.
# Invoked at boot by vendorledger-banner.service and by provision.sh.
set -u

IFACE="${BANNER_IFACE:-enp0s3}"
TMPL="${BANNER_TMPL:-/etc/vendorledger/banner.tmpl}"

IP=$(ip -4 -o addr show "$IFACE" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$IP" ] || IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$IP" ] || IP="unknown"

for out in /etc/issue /etc/issue.net; do
  awk -v ip="$IP" \
    '{ if ($0 ~ /\[ IP MACHINE \]/) sub(/\[ IP MACHINE \].*/, "[ IP MACHINE ] " ip); print }' \
    "$TMPL" > "$out"
  chmod 644 "$out"
done
