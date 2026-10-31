# Security and trade-offs

What this setup changes, what it costs, and why I'm fine with it.

## What changed

| Setting | Before | After |
|---|---|---|
| Device DNS (with Tailscale on) | Router's DNS | Pi-hole, through the Tailscale tunnel |
| Browser "Secure DNS" | On | Off |
| Android Private DNS | On / Automatic | Off |
| Pi-hole → internet | n/a | Plain DNS to Cloudflare/Google |
| Pi-hole listening mode | Local subnet only | All origins (for Tailscale clients) |

## What I give up

1. **The ISP can read the domain names Pi-hole looks up**, because upstream DNS is unencrypted. In practice this was mostly true before as well, and the ISP can infer sites from other signals. *Planned fix:* `cloudflared` (DNS-over-HTTPS) as Pi-hole's upstream.
2. **The server is a single point of failure.** If it's down while Tailscale is on, websites stop loading. *Escape hatch:* turn Tailscale off and you're instantly back on normal DNS.
3. **Pi-hole logs every lookup** from my devices. It's stored only on the server.

## What is *not* affected

- **Page content, passwords and messages** are still protected by HTTPS. DNS reveals site names, never what happens on them.
- **Spoofing risk:** a tampered DNS answer pointing at a fake site still fails the HTTPS certificate check, and the browser shows a warning. Rule: never click through certificate warnings.
- **Exposure:** Pi-hole and SSH are only reachable on the LAN and inside my tailnet. No ports are forwarded from the internet.
- **Between devices and Pi-hole,** DNS travels inside Tailscale's WireGuard tunnel, which is encrypted end to end.

## Why not just add a backup DNS like 8.8.8.8?

Devices don't use a secondary DNS only when the primary fails. They use whichever answers, often the faster one. A public backup would quietly bypass the block.

## Hardening still to do

- [ ] SSH keys, then `PasswordAuthentication no`
- [ ] `cloudflared` upstream
- [ ] Unattended security updates confirmed on
- [ ] Uptime monitoring with an alert
