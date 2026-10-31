#!/usr/bin/env bash
# Quick health check for the home focus server.
# Usage: ./verify.sh [test-domain]
# Run on the server itself.

set -u
TEST_DOMAIN="${1:-youtube.com}"
WIFI_IF="$(ls /sys/class/net | grep '^wl' | head -n1)"

ok()   { printf "  [OK]   %s\n" "$1"; }
bad()  { printf "  [FAIL] %s\n" "$1"; }
info() { printf "  [i]    %s\n" "$1"; }

echo "Home focus switch: health check"
echo

info "LAN IP: $(hostname -I | awk '{print $1}')"
command -v tailscale >/dev/null && info "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'not connected')"

systemctl is-active --quiet pihole-FTL && ok "pihole-FTL is running" || bad "pihole-FTL is not running"
systemctl is-enabled --quiet pihole-FTL && ok "pihole-FTL starts on boot" || bad "pihole-FTL is not enabled at boot"
systemctl is-active --quiet ssh || systemctl is-active --quiet ssh.socket && ok "SSH is available" || bad "SSH is not running"
systemctl is-active --quiet tailscaled && ok "tailscaled is running" || bad "tailscaled is not running"

if [ -n "$WIFI_IF" ] && command -v iw >/dev/null; then
  ps_state="$(iw dev "$WIFI_IF" get power_save 2>/dev/null | awk '{print $NF}')"
  [ "$ps_state" = "off" ] && ok "Wi-Fi power saving is off on $WIFI_IF" || bad "Wi-Fi power saving is '$ps_state' on $WIFI_IF"
  signal="$(iw dev "$WIFI_IF" link 2>/dev/null | awk '/signal/ {print $2}')"
  [ -n "$signal" ] && info "Wi-Fi signal: ${signal} dBm"
fi

[ -f /etc/systemd/logind.conf.d/lid.conf ] && ok "Lid-close sleep is disabled" || bad "lid.conf missing (laptop may sleep)"

if command -v dig >/dev/null; then
  ans="$(dig @127.0.0.1 "$TEST_DOMAIN" +short | head -n1)"
  info "Pi-hole answer for $TEST_DOMAIN from localhost: ${ans:-<none>}"
  info "(localhost isn't in the Social group, so a real IP here is expected)"
fi
