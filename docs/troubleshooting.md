# Troubleshooting log

Every real problem I hit while building this, written as **symptom → investigation → cause → fix**.

---

## 1. Pi-hole installer froze on a blank screen

**Symptom**
`curl -sSL https://install.pi-hole.net | sudo bash` printed the Pi-hole logo, installed dependencies, then sat for 15+ minutes. Arrow keys printed raw escape codes like `^[[B^[[A`.

**Investigation**
- Checked whether apt was stuck: `ps aux | grep -E "apt|dpkg|unattended"` showed nothing running, and `/var/log/apt/term.log` showed the dependencies had **finished**.
- Looked at the process tree: `ps -ef --forest`. Under the installer was a `dialog ... --title "Pi-hole Automated Installer"` process. The setup screen *was* open, just invisible.

**Cause**
In `curl ... | sudo bash`, the pipe makes **the downloaded script** bash's input, not the keyboard. Ubuntu 26.04's `sudo` also runs the command in its own pseudo-terminal, so the dialog was drawn somewhere I couldn't see or type into.

**Fix**
```bash
curl -sSL https://install.pi-hole.net -o basic-install.sh
sudo bash basic-install.sh
```
Now the script comes from a file and the terminal is the keyboard. This is also a good habit generally, since you can read a script before running it.

**Lesson:** on dialog screens, Enter confirms whatever is *already* highlighted. On the "Static IP Needed" screen the default is **Exit**, so press Left arrow first.

---

## 2. SSH dropped every few seconds

**Symptom**
`client_loop: send disconnect: Broken pipe` constantly. Not even a single command could finish.

**Investigation**
- Worked on the laptop's own keyboard to rule out the network path.
- `iw dev wlo1 link` showed signal **-57 dBm**, which is strong.
- `ping -c 30 <gateway>` showed **0% loss** once power saving was off.

**Cause**
The Wi-Fi card's **power-saving mode** was dozing between packets, so idle TCP connections died.

**Fix**
```bash
sudo iw dev wlo1 set power_save off
```
Made permanent with a oneshot systemd unit: [`configs/systemd/system/wifi-powersave-off.service`](../configs/systemd/system/wifi-powersave-off.service). On the Mac side, `ServerAliveInterval 30` in `~/.ssh/config` keeps sessions alive.

**Also:** long jobs go inside `tmux`. When SSH dies, the shell gets **SIGHUP** and kills child processes; `tmux attach` brings the session back intact.

---

## 3. First ping test showed 100% loss

**Symptom**
`ping 192.168.1.1` → `Destination Host Unreachable`.

**Cause**
The router wasn't at `.1`. I had guessed the address.

**Fix**
```bash
ip route
# default via 192.168.1.254 dev wlo1 ...
```
The address after `default via` is the real gateway.

---

## 4. SSH from the Mac timed out right after install

**Symptom**
`ssh: connect to host 10.x.x.x port 22: Operation timed out`

**Cause**
During install the laptop was on my **phone hotspot**. The Mac was on home Wi-Fi: two separate networks. A *timeout* (not *connection refused*) pointed at the network, not SSH.

**Fix**
Switched the laptop to home Wi-Fi in `/etc/netplan/*.yaml` and ran `sudo netplan apply`. This was required anyway, since Pi-hole has to live on the same network as its clients.

---

## 5. Keyboard typed `#` instead of `|`

**Cause**
The installer set **English (UK)** on a **US** keyboard. On UK layout that key is `#`/`~`, and `"` becomes `@`.

**Fix**
```bash
sudo dpkg-reconfigure keyboard-configuration   # Generic 105-key, English (US)
sudo setupcon
```
Workaround in the meantime: split piped commands into separate steps, or work over SSH from a correctly configured machine.

---

## 6. Installer picked the wrong network interface

**Symptom**
`[i] Using interface: eno2`, then the installer exited early.

**Cause**
On the interface screen I pressed Enter without selecting anything, which confirmed the first item: the unplugged Ethernet port.

**Fix**
Reran the installer. Arrows to highlight `wlo1`, **Space** to select, then Enter.

---

## 7. YouTube still loaded on the Mac after blocking

**Symptom**
The page opened, but every **thumbnail was blank**.

**Cause**
The browser had cached YouTube's address and kept its connections open. New lookups (thumbnails from `ytimg.com`) *were* blocked, which proved Pi-hole was working.

**Fix**
Fully quit the browser (Cmd+Q). In Brave/Chrome you can also clear `brave://net-internals/#dns` and flush `#sockets`, and turn off **Use secure DNS**.

---

## 8. Phone ignored Pi-hole completely  ← the interesting one

**Symptom**
Static IPv4 settings on Android with DNS = Pi-hole, Private DNS off. YouTube still worked.

**Investigation**
Filtered Pi-hole's **Query Log** by the phone's IP. The only entries were `www.google.com` every ~30 seconds, which is Android's connectivity check. **No YouTube queries at all.** The phone was asking someone else.

**Cause**
The ISP router advertises **IPv6** and includes its own **IPv6 DNS server** in those adverts. Android's static settings only cover IPv4, so most lookups went to the router over IPv6 and bypassed Pi-hole. (macOS's manual DNS list replaces everything, which is why the Mac worked.)

**Fix**
Without router access, I routed DNS through **Tailscale**:
- Server's Tailscale IP as the global nameserver
- **Override DNS servers** on
- Phone added to Pi-hole by its `100.x` Tailscale IP

Now every lookup, IPv4 or IPv6, goes through the tunnel to Pi-hole. Once I have the router login, the proper whole-house fix is to set the router's DNS to Pi-hole or disable IPv6 on the LAN.

---

## 9. Couldn't log into the router

The ISP technician kept the admin login. The Wi-Fi password isn't the admin password, and repeated failures can lock the login page. Still pending: request the admin login from the ISP.

---

## Handy commands

```bash
hostname -I                          # my IP
ip route                             # gateway
ls /sys/class/net                    # interface names
iw dev wlo1 link                     # Wi-Fi signal
sudo ss -tlnp | grep :22             # is SSH listening?
systemctl is-enabled pihole-FTL      # starts on boot?
pihole status                        # Pi-hole health
dig @<pihole-ip> example.com +short  # ask Pi-hole directly
tmux attach -t <name>                # get a dropped session back
```
