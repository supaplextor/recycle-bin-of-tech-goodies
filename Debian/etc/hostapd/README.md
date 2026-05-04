# hostapd — Access Point Setup on Debian Trixie

This directory contains a minimal `hostapd.conf` for a 2.4 GHz WPA2-Personal
access point on Debian Trixie.

## Prerequisites

Install `hostapd`:

```bash
sudo apt install hostapd
```

> **Note:** On Debian, the `hostapd` service is **masked** by default after
> installation to prevent accidental activation. You must unmask it before it
> can be started or enabled.

## 1. Deploy the configuration file

Copy (or symlink) the config to the system location and edit it to match your
hardware and desired network settings:

```bash
sudo cp hostapd.conf /etc/hostapd/hostapd.conf
sudo nano /etc/hostapd/hostapd.conf   # adjust interface, ssid, wpa_passphrase, country_code, etc.
```

## 2. Unmask the service

```bash
sudo systemctl unmask hostapd
```

## 3. Enable and start hostapd

Start the service now **and** enable it to start automatically on every boot:

```bash
sudo systemctl enable --now hostapd
```

## 4. Verify the service is running

```bash
sudo systemctl status hostapd
```

You should see `Active: active (running)`.

## Key configuration options

| Option | Description |
|---|---|
| `interface` | Wireless interface to use as the AP (e.g. `wlan0`) |
| `ssid` | Network name broadcast by the AP |
| `hw_mode` | `g` for 2.4 GHz; `a` for 5 GHz |
| `channel` | Wi-Fi channel (1, 6, or 11 are non-overlapping 2.4 GHz channels) |
| `country_code` | Your ISO 3166-1 alpha-2 country code (e.g. `US`, `DE`) |
| `wpa_passphrase` | Pre-shared key — 8 to 63 ASCII characters |

## Stopping / disabling

```bash
# Stop the service (until next boot)
sudo systemctl stop hostapd

# Stop and disable on boot
sudo systemctl disable --now hostapd

# Re-mask to restore the Debian default
sudo systemctl mask hostapd
```

## Troubleshooting

- **"Failed to create interface mon.wlan0"** — another process (e.g. NetworkManager) may be managing the interface. Stop it first: `sudo systemctl stop NetworkManager` or configure NetworkManager to ignore the interface.
- **"nl80211: Could not configure driver mode"** — ensure the wireless driver supports AP mode: `iw list | grep -A 10 "Supported interface modes"`.
- Check logs for details: `sudo journalctl -u hostapd -n 50`.
