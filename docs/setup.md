# Setup guide

The full build, in the order I did it. Values in `<angle brackets>` are placeholders. Replace them with your own.

Example addresses used below:

| Thing | Example |
|---|---|
| Home router (gateway) | `192.168.1.254` |
| Home server LAN IP | `192.168.1.19` |
| Home server Tailscale IP | `100.x.y.z` |
| Wi-Fi interface | `wlo1` |

---

## 1. Install Ubuntu Server

1. Download **Ubuntu Server 26.04 LTS** for **Intel or AMD 64-bit** (`amd64`) from ubuntu.com.
2. Flash it to a USB stick with **balenaEtcher**. No need to format the stick first; Etcher overwrites it.
3. Boot the laptop from USB. On Asus, tap **Esc** at power-on for the boot menu. If Windows boots too fast, use *Shift + Restart → Use a device* from inside Windows.
4. Installer choices:
   - **Network:** connect to the **home** Wi-Fi, not a phone hotspot. Pi-hole must be on the same network as the devices it serves.
   - **Proxy / mirror:** leave as default.
   - **Storage:** *Use an entire disk*, **untick LVM** (otherwise Ubuntu often uses only part of the disk), no encryption (a headless server must boot unattended).
   - **Profile:** short lowercase hostname and username.
   - **SSH:** tick **Install OpenSSH server**. Allow password auth for now.
   - **Featured snaps:** none. Install Docker later from the official repo, not the snap.
5. Reboot, remove the USB, log in.

## 2. Reach it from your main machine

```bash
# on the server
hostname -I

# on the Mac
ssh <user>@192.168.1.19
```

If SSH times out, check both machines are on the same network (`ipconfig getifaddr en0` on the Mac).

To switch the server's Wi-Fi network, edit the netplan file (see [`configs/netplan`](../configs/netplan/)) and run:

```bash
sudo vi /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

Optional `~/.ssh/config` on the Mac, so `ssh homeserver` works and idle sessions stay alive:

```
Host homeserver
  HostName 192.168.1.19
  User <user>
  ServerAliveInterval 30
  ServerAliveCountMax 4
```

## 3. Prepare the server

```bash
# updates (run inside tmux so a dropped SSH session doesn't kill it)
tmux new -s setup
sudo apt update && sudo apt upgrade -y
```

### Stay awake with the lid closed

Copy [`configs/systemd/logind.conf.d/lid.conf`](../configs/systemd/logind.conf.d/lid.conf) into place:

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo vi /etc/systemd/logind.conf.d/lid.conf
sudo systemctl restart systemd-logind
```

Test: close the lid, then run `uptime` over SSH.

### Turn off Wi-Fi power saving (permanently)

Power saving made the Wi-Fi card drop SSH sessions every few seconds.

```bash
sudo apt install iw -y
ls /sys/class/net          # find the interface starting with "wl"
which iw                   # use this path in the service file
sudo vi /etc/systemd/system/wifi-powersave-off.service
sudo systemctl enable --now wifi-powersave-off.service
```

Service file: [`configs/systemd/system/wifi-powersave-off.service`](../configs/systemd/system/wifi-powersave-off.service). `enable` runs it at every boot, `--now` also runs it immediately.

### Free port 53 for Pi-hole

Ubuntu's `systemd-resolved` listens on port 53 by default. Turn off its stub listener ([`configs/systemd/resolved.conf.d/pihole.conf`](../configs/systemd/resolved.conf.d/pihole.conf)) and point `/etc/resolv.conf` at the real upstream list so the server keeps working DNS:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo vi /etc/systemd/resolved.conf.d/pihole.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
ping -c 3 google.com
```

## 4. Install Pi-hole

Download the installer first, then run it. **Don't pipe it into `sudo bash`.** See [troubleshooting](troubleshooting.md#1-pi-hole-installer-froze-on-a-blank-screen) for why.

```bash
curl -sSL https://install.pi-hole.net -o basic-install.sh
sudo bash basic-install.sh
```

In the setup screens:

- **Static IP warning:** press Left arrow to select **Continue**. Enter alone selects *Exit*.
- **Interface:** arrows to highlight the Wi-Fi interface, **Space** to select it, then Enter.
- **Upstream DNS:** Cloudflare or Google.
- **Blocklist, query logging:** Yes. **Privacy mode:** 0 (show everything).

Then:

```bash
sudo pihole setpassword
systemctl is-enabled pihole-FTL     # should say "enabled"
```

Dashboard: `http://192.168.1.19/admin`

Test from another machine:

```bash
dig @192.168.1.19 doubleclick.net +short   # 0.0.0.0  → blocked
dig @192.168.1.19 google.com +short        # real IPs → allowed
```

## 5. Build the "Social" group

1. **Group Management → Groups:** add a group called `Social`.
2. **Group Management → Domains:** add each domain from [`blocklists/social.txt`](../blocklists/social.txt) with **Add domain as wildcard** ticked, then **Add to denied domains**.
3. In the domains table, set each entry's **Group assignment** to **Social only** (untick Default).

A wildcard entry becomes a regex like `(\.|^)youtube\.com$`, which matches `youtube.com` and every subdomain (`m.youtube.com`, `www.youtube.com`) but not look-alikes such as `youtube.com.example.net`.

> Watch out: adding `www.instagram.com` instead of `instagram.com` only blocks the `www.` host. The app uses `i.instagram.com`, `graph.instagram.com` and others.

## 6. Tailscale as the switch

### On the server

```bash
curl -fsSL https://tailscale.com/install.sh -o tailscale-install.sh
sudo sh tailscale-install.sh
sudo tailscale up --accept-dns=false
tailscale ip -4                      # note the 100.x.y.z address
sudo pihole-FTL --config dns.listeningMode ALL
```

- `--accept-dns=false`: the server must not use Tailscale's DNS. Otherwise it would ask itself in a loop.
- `listeningMode ALL`: by default Pi-hole only answers the local subnet. Tailscale clients arrive from `100.x` addresses. This is safe as long as port 53 isn't forwarded from the internet.

### In the Tailscale admin console

1. **DNS → Nameservers → Add nameserver → Custom:** the server's `100.x.y.z`.
2. Turn on **Override DNS servers**. This is what stops devices from using the router's IPv6 DNS.
3. **Machines → server → Disable key expiry**, so the server doesn't silently log out after a few months.

### On each device

- Install Tailscale, sign in with the same account, and keep **Use Tailscale DNS** on.
- Remove any manual DNS settings you added earlier, so that **Tailscale off = normal internet**.
- **Android:** Private DNS → Off. Wi-Fi IP settings → DHCP.
- **Brave / Chrome:** turn off *Use secure DNS*, or the browser can skip system DNS.

### Put the devices in the switch

In Pi-hole, go to **Group Management → Clients**, add each device's **Tailscale IP** (`100.x`), and tick **Default + Social**.

## 7. Use it

- **Tailscale on** → focus mode. **Tailscale off** → free mode.
- Browsers cache DNS. After flipping, fully quit and reopen the browser (Cmd+Q on Mac) or force-stop the app.
- Master switch for everything: **Group Management → Groups → Social → Enabled/Disabled**.
- **On mobile data too:** with Tailscale on, the phone's DNS still tunnels home to Pi-hole. Inside the tunnel the phone always has the same `100.x` IP, so Pi-hole still recognises it as a Social member.

## 8. Encrypt upstream DNS (Unbound + DNS-over-TLS)

Without this, Pi-hole sends allowed lookups to Cloudflare/Google in plain text, and the ISP can read every site name.

> Many guides use `cloudflared proxy-dns` for DNS-over-HTTPS. Cloudflare removed that command from releases starting February 2026, so this uses **Unbound** forwarding over **DNS-over-TLS** instead.

```bash
sudo apt install unbound -y      # a "failed to start" error here is expected: port 53 is taken by Pi-hole
sudo vi /etc/unbound/unbound.conf.d/pi-hole.conf
sudo unbound-checkconf           # "no errors"
sudo systemctl enable --now unbound
dig @127.0.0.1 -p 5335 google.com +short
```

Config: [`configs/unbound/pi-hole.conf`](../configs/unbound/pi-hole.conf). Unbound listens only on `127.0.0.1:5335`, forwards to `1.1.1.1@853#cloudflare-dns.com` (the part after `#` is the name the TLS certificate must match), and validates DNSSEC.

If the package enabled `unbound-resolvconf.service`, disable it so Unbound doesn't take over the server's own DNS:

```bash
systemctl is-enabled unbound-resolvconf.service
sudo systemctl disable --now unbound-resolvconf.service
```

Point Pi-hole at it: **Settings → DNS**, untick the built-in upstreams, add custom `127.0.0.1#5335`, **Save & Apply**. Check:

```bash
sudo pihole-FTL --config dns.upstreams          # [ 127.0.0.1#5335 ]
dig @127.0.0.1 "test$RANDOM.cloudflare.com" +short; sudo ss -tnp | grep ':853'
```

The `ss` line should show `unbound` connected to `1.1.1.1:853`. A random name is needed because cached answers never leave the server, and Unbound closes idle TLS connections quickly.

## 9. SSH key login

On the **Mac** (the machine you connect *from*):

```bash
ls ~/.ssh/id_ed25519*                              # reuse an existing key if there is one
ssh-keygen -t ed25519 -C "<device-name>"           # otherwise create one, with a passphrase
ssh-copy-id -i ~/.ssh/id_ed25519.pub <user>@192.168.1.19
```

Add to `~/.ssh/config` **on the Mac**:

```
Host homeserver
  HostName 192.168.1.19
  User <user>
  IdentityFile ~/.ssh/id_ed25519
  AddKeysToAgent yes
  UseKeychain yes
  ServerAliveInterval 30
  ServerAliveCountMax 4
```

`ssh homeserver` should now log in without the server password. Each extra device gets its own key line in the server's `~/.ssh/authorized_keys`.

Later, once keys are proven on every device you use, turn off password login:

```bash
sudo vi /etc/ssh/sshd_config.d/no-passwords.conf   # PasswordAuthentication no
sudo systemctl restart ssh
ssh -o PubkeyAuthentication=no homeserver          # should fail: Permission denied (publickey)
```

Test from a second terminal while the first stays logged in. The laptop's own keyboard login is unaffected, so you can't lock yourself out completely.
