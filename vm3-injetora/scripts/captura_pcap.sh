#!/usr/bin/env bash
set -euo pipefail
IFACE="${1:-eth0}"
OUT="${2:-openarena_$(date +%Y%m%d_%H%M%S).pcap}"
echo "[INFO] Capturando UDP/27960 na interface $IFACE -> $OUT"
sudo tcpdump -i "$IFACE" udp port 27960 -w "$OUT"
