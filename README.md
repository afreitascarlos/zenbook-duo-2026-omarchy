# Zenbook Duo 2026 (UX8407AA) on Omarchy

Fixes and a small daemon that make the ASUS Zenbook Duo 2026 (UX8407AA, Intel Panther Lake) work well on [Omarchy](https://omarchy.org) (Arch + Hyprland). Covered:

- Both screens, the right way up
- Touch and pen on both screens
- Auto-rotation into sideways "book" mode
- Bottom screen turns off when the keyboard rests on it
- OLED brightness on both screens
- Sensors (accelerometer, light, hinge)
- Bottom screen works after powering on with the keyboard on it
- Keyboard Fn keys, Fn-lock (F1–F12 by default, Fn+Esc toggles) and backlight
- Touchpad palm rejection
- No ghost or flickering cursor on the top screen
- 10-bit colour on both panels
- Lid close with the keyboard docked: the laptop stays asleep
- A visible boot menu for dual boot with Windows
- A power-saver profile that really saves power, and lower idle power

Optional (run by name, not part of `all`):

- **Battery charge limit:** charge to 80% only, with a button in the Omarchy bar for a full charge during the next 24 hours, like MyASUS "Battery care mode" ([`charge-limit`](#charge-limit-optional-not-part-of-all))
- US International keyboard layout with `'` + `c` = `ç` ([`keyboard-intl`](#keyboard-intl-optional-not-part-of-all))

> **Based on [burakgon/zenbook-duo-2026-linux](https://github.com/burakgon/zenbook-duo-2026-linux).** Almost all of the hardware work here comes from burakgon's project: the research, the kernel patches, the patched keyboard driver and the fixes for sensors, touchpad, cursor and sleep. His project targets KDE Plasma. This one adapts his fixes to Omarchy (Arch + Hyprland), replaces the KDE parts with Hyprland equivalents, and adds a few changes of its own. If his work helped you, go give his repo a star. See [Credits](#credits) for details.

> **Made with AI.** Most of this repository (the scripts, the changes on top of burakgon's work, and the documentation) was written with an AI assistant ([Claude Code](https://claude.com/claude-code)), directed and tested by the author on their own laptop.

> **Status:** works on the author's machine with kernel `7.2.15-1-omarchy`, BIOS `UX8407AA.310`. Tested on one laptop only. Read what each step does before running it.

## Install

On a fresh Omarchy install:

```sh
git clone https://github.com/<you>/zenbook-duo-2026-omarchy
cd zenbook-duo-2026-omarchy
./install.sh list          # show the steps
./install.sh all           # run them all, or name steps: ./install.sh packages raydium ...
./install.sh charge-limit  # optional: 80% battery charge limit + bar button
```

Tip: take a restore point first with `omarchy-snapshot create`. It appears in the Limine boot menu; boot it and run `omarchy-snapshot restore` to go back.

Then do the [manual steps](#manual-steps) and reboot.

Every step is safe to run again. Steps that change the system use `sudo`.

## Status

| Area | State | Step |
|---|---|---|
| Top screen upside down | ✅ fixed | `hyprland` |
| Bottom screen (eDP-2) layout | ✅ | `hyprland` |
| Touch + pen on both screens | ✅ fixed | `raydium`, `hyprland` |
| Accelerometer, light, hinge sensors | ✅ fixed | `ish-firmware` |
| Auto-rotation (sideways / book mode) | ✅ | `packages`, `hyprland` |
| Bottom screen off when keyboard is on it | ✅ | `hyprland` |
| OLED brightness, both screens in sync | ✅ | `brightness`, `hyprland` |
| Brightness / Fn keys, keyboard backlight, mic LED | 🧪 installed, testing | `hid-asus` |
| Fn-lock: F1–F12 by default, Fn+Esc toggles | ✅ fixed | `hid-asus` |
| Touchpad palm rejection / disable-while-typing | 🧪 installed, testing | `touchpad-palm` |
| Ghost / flickering cursor on the top screen | ✅ fixed | `psr-et-off` |
| 10-bit colour on both OLED panels (was 6-bit + dithering) | ✅ | `dsc-10bit`, `hyprland` |
| Lid close with keyboard docked: stays asleep | ✅ fixed | `kbd-lid-wake` |
| Power-saver profile really saves power (quiet fans, SoC low-power, GPU power saving) | ✅ fixed | `power-profile-sync` |
| Idle platform devices kept powered on | ✅ fixed (small gain) | `runtime-pm` |
| Battery charge limit 80% + 24 h full charge from the bar | ✅ optional | `charge-limit` |
| CPU power limits per profile (Windows DTT values) | ✅ Omarchy default (thermald) | — |
| Keyboard over Bluetooth | ✅ after pairing | [manual](#manual-steps) |
| Boot menu with Windows entry | ✅ | `limine-menu` |
| Disk password screen (Plymouth) upside down at power-on | ✅ fixed | `boot-orientation` |
| Detached (Bluetooth) keyboard at the disk password | ❌ by design | [known issues](#known-issues) |
| Bottom screen after powering on with keyboard on it | ✅ fixed | `edp2-xe` |
| Hot-unplugging an external monitor | ⚠️ froze once | [known issues](#known-issues) |

Tent mode isn't possible on this laptop, so it isn't handled.

## Steps

### `packages`
Installs `iio-sensor-proxy` (accelerometer → orientation), `dkms` (keyboard driver), and the tools the firmware step needs (`curl`, `libarchive`, `zstd`).

### `raydium`
Writes `blacklist raydium_i2c_ts` to `/etc/modprobe.d/zenbook-duo-raydium.conf` and rebuilds the boot image.

Both touchscreens are Raydium HID-over-I2C devices (`RAYD0001` top, `RAYD0002` bottom), but the legacy `raydium_i2c_ts` driver grabs them and fails with `invalid packet crc`. With it blacklisted, `i2c-hid` handles touch and stylus.

### `ish-firmware`
- **Problem:** the Intel Sensor Hub on Panther Lake only boots firmware signed for the laptop maker. linux-firmware's generic `ish_ptl.bin` is rejected (`ISH loader: cmd 2 failed 10`), so there's no accelerometer, light or hinge sensor.
- **What the step does:**
  1. Downloads ASUS's official Windows driver package `SensorHub_DCH_Intel_Z_V5.8.62.0_48536.exe` (~5 MB) and checks its SHA-256.
  2. Extracts `AsusSign_ishS_SI_CommonPTL_5.8.1.7779_V0018.bin` and checks that too.
  3. Installs it as `/usr/lib/firmware/updates/intel/ish/ish_ptl_59b8d9f2_c68ec386.bin`. That's the name the kernel looks for: `ish_ptl_<crc32(sys_vendor)>_<crc32(product_name)>`.
- The firmware isn't redistributed here.
- If the sensors don't appear, do a cold boot (power off, then on).

### `hyprland`
Installs two files and hooks them into Omarchy's config.

**`~/.config/hypr/zenbook-duo.lua`** is loaded from `monitors.lua`. It sets the screen layout for each orientation:

| Orientation | Layout |
|---|---|
| `normal` | Top screen eDP-1 above, bottom eDP-2 below, both transform 0 (the upside-down top panel is rotated in hardware, see `boot-orientation` below). Software cursor. Both at scale 2. |
| `left-up` | Sideways, top screen on the right. |
| `right-up` | Sideways, top screen on the left. |

Each digitizer is pinned to its own screen and rotated with it. The bottom digitizer is turned off while the bottom screen is off.

**`~/.local/bin/zenbook-duo-rotate`** is a daemon started from `autostart.lua`. It:
- **Rotates** both screens from `monitor-sensor --accel`. A new orientation must hold for 1 s first.
- **Detects the keyboard** through USB `0b05:1cd7`, which is present only while it lies on the bottom screen. Docked → bottom screen and its touch off. Lifted → back on.
- **Guards against the xe #9196 bug.** After turning the bottom screen back on, it checks the kernel log for port-B errors. If any appear, it keeps the screen off for the rest of the boot and shows a notification, because retrying can hang the machine.
- **Syncs brightness** from the top screen to the bottom one. Omarchy's keys, OSD and idle dimming only drive the top screen. The bottom one is matched at startup, after it turns on, and after resume.

Commands:
```sh
zenbook-duo-rotate normal|left-up|right-up   # force a layout
zenbook-duo-rotate lock                      # pause auto-rotation
zenbook-duo-rotate unlock                    # resume it
```
State is kept in `~/.local/state/zenbook-duo/`.

### `brightness`
Adds `xe.enable_dpcd_backlight=1` to `/etc/default/limine` (backup `limine.bak.zenbook-duo`) and rebuilds the boot image. The OLED panels ignore PWM, so without this the brightness keys and menu do nothing visible.

### `limine-menu`
- Omarchy sets `quiet: yes` in `/boot/limine.conf`, which hides the boot menu unless you press a key. This step sets `quiet: no` and `timeout: 4`, with a backup at `limine.conf.bak.zenbook-duo`.
- Omarchy only adds `quiet` when it's missing, so the change stays.
- Add the Windows entry with `sudo limine-scan`.

### `hid-asus`
- **Problem:** the detachable keyboard (USB `0b05:1cd7`, Bluetooth `0b05:1cd8`) isn't in the kernel's `hid-asus` table. It falls back to `hid-generic`, so:
  - The top row sends plain F1–F12. The brightness keys arrive as F5/F6.
  - Fn and Fn-lock do nothing.
  - The keyboard backlight and mic-mute LED don't work.
- **What the step installs:** burakgon's patched driver (his commit `8030783`, his version 1.6) plus our Fn-lock change, as the DKMS package `zenbook-duo-hid-asus` 1.7 (in `dkms/`). It:
  - Adds the keyboard's IDs.
  - Shrinks feature reports to the 16 bytes the keyboard expects (stock sends 64, which time out).
  - Rewrites the `0x5a` hotkey descriptor.
  - Makes F1–F12 the default on the top row, with Fn for the media keys (burakgon's default is the reverse). **Fn+Esc** toggles. The state is shared by the USB and Bluetooth links and resets to F-keys at boot. Set the default with `options hid_asus zenbook_duo_fn_lock=0` (media keys first) in `/etc/modprobe.d/`. Our change is `dkms/zenbook-duo-hid-asus-1.7/fn-lock.patch`.
  - Keeps the keyboard's battery reports from acting as key presses.
- The keyboard switches over without a reboot.
- **Kernel support:** sources exist for kernel **7.2.x and 7.3.x only**. On 7.4+ the build is skipped and the stock driver is used. Check burakgon's repo for a newer version.
- **Undo:** `sudo dkms remove zenbook-duo-hid-asus/1.7 --all`, then reboot.

### `edp2-xe`
- **Problem ([xe #9196](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196)):** the bottom panel uses display port B, whose PHY sits in the Type-C subsystem (TCSS). Only the firmware asks for TCSS power, and only when it lights the bottom panel at power-on, which it skips while the keyboard covers it. Lifting the keyboard later fails (`PHY B failed to request refclk`, `Port B PLL not locked`) and can freeze Hyprland.
- **Fix:** burakgon's TCSS patches ([`display-edp2-tcss`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/display-edp2-tcss), sent upstream). They make `xe` request TCSS power for port B itself.
- **Why not burakgon's module as-is:** his build uses vanilla kernel.org sources. The Omarchy kernel carries about 27 patches of its own to `xe`/`i915` (PSR / panel-replay quirks for Panther Lake laptops, xe shrinker…), and a vanilla build would silently drop them.
- **What the step installs:** the DKMS package `zenbook-duo-omarchy-xe` 1.0 (`dkms/`). Its `build.sh` rebuilds Omarchy's own `xe`:
  1. kernel.org `v<version>`, `drivers/gpu/drm/{xe,i915}` only.
  2. The `xe`/`i915` parts of the linux-omarchy patches, taken from the [omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs) commit with the same `pkgver`/`pkgrel`, applied in PKGBUILD order.
  3. The 3 TCSS patches.
- **Safety check:** the result is compared with the stock `xe.ko`. Any difference beyond the fix's own functions fails the build, and the stock driver stays in use.
- **Also installs:**
  - `/etc/mkinitcpio.conf.d/zenbook-duo-omarchy-xe.conf` (`MODULES+=(xe)`), because the `kms` hook would otherwise put the stock `xe` into the initramfs.
  - A pacman hook (`65-…-sources.hook`, allowed network access) that downloads a new kernel's sources before DKMS builds.
- **Check:** `cat /sys/module/xe/parameters/zenbook_duo_edp2_tcss` → `Y`.
- **If the machine doesn't boot to the LUKS prompt:**
  - Press `e` on the Limine entry and add `modprobe.blacklist=xe` to the command line. The built-in `simpledrm` still shows the password prompt.
  - Then remove the driver: `sudo dkms remove zenbook-duo-omarchy-xe/1.0 --all`, delete the mkinitcpio conf, and run `sudo limine-update`.
  - To keep the driver but switch off only the fix: `xe.zenbook_duo_edp2_tcss=0`.

### `boot-orientation`
- **Problem:** the top panel is mounted upside down. Hyprland could rotate it with `transform = 2`, but at power-on the boot text and Omarchy's disk password screen (Plymouth) are upside down. The lock screen after sleep is fine, since it runs inside Hyprland.
- **Fix:** kernel parameter `video=eDP-1:panel_orientation=upside_down` in `/etc/default/limine` (backup `limine.bak.zenbook-duo-orientation`). The kernel then reports the panel's orientation (DRM `panel orientation` property), which fbcon and Plymouth follow.
- **Side effect in Hyprland:** the boot console/Plymouth set the top panel's primary plane to a hardware rotation of 180° (KMS `rotation` property), and Hyprland (aquamarine 0.15) never resets it. So the picture is already upright with no Hyprland transform, and `zenbook-duo.lua` uses the transforms of an upright panel (normal 0, left-up 1, right-up 3 on eDP-1). The cursor plane is not rotated, so the hardware cursor was drawn upside down and moved the wrong way. `zenbook-duo.lua` therefore sets `cursor.no_hardware_cursors = 1` (software cursor, drawn into the rotated picture). Measured cost: none (within noise; see `docs/log.md`). Direct scanout is off by default anyway.
- **The `hyprland` step depends on this step.** Without the parameter the top screen is upside down in Hyprland. If a future Hyprland/aquamarine starts resetting the plane rotation, the top screen flips: go back to +180° on eDP-1 and hardware cursors.
- **Check:** `sudo grep -A1 "plane 1A" /sys/kernel/debug/dri/0/i915_display_info` → `rotation=180`.
- **Verified** after a reboot: disk password screen upright, top screen and pointer upright in all three orientations, touch and pen land under the finger.
- burakgon tried a kernel parameter and reverted it, because KWin ignores it. Omarchy has no KDE login screen, so his login-screen fix doesn't apply here.
- The Limine boot menu is drawn by the firmware and stays upside down.

### `touchpad-palm`
- **Problem:** the keyboard touchpad reaches the laptop over USB pogo pins (docked) or Bluetooth, so libinput treats it as external and skips disable-while-typing and palm detection. Hyprland's `disable_while_typing` setting is silently ignored.
- **Fix:** burakgon's [`touchpad-palm`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/touchpad-palm): a section in `/etc/libinput/local-overrides.quirks` with `AttrTPKComboLayout=below`, which pairs the touchpad with the keyboard above it. Anything else in that file is kept.
- Takes effect at the next login.

### `psr-et-off`
- **Problem:** two or three frozen copies of the cursor, or a flickering cursor, on the top screen. Caused by the "Early Transport" part of Panel Replay Selective Update in `xe`.
- **Fix:** burakgon's [`display-psr-et-off`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/display-psr-et-off): a systemd service writes `0x20` to `/sys/kernel/debug/dri/0/i915_edp_psr_debug` at boot. That turns off only Early Transport and keeps Panel Replay's power saving.
- **Check:** `systemctl is-active zenbook-duo-psr-et-off`.

### `dsc-10bit`
- **Problem:** at 2880x1800 and 144 Hz the eDP link (HBR2x4) can't carry 8 bits per colour uncompressed. The panels support DSC compression, but `xe` lowers the colour depth instead: `bpp=18` (6 bits per colour) with dithering. It shows mostly in dark gradients.
- **Fix, part 1:** burakgon's [`display-dsc-10bit`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/display-dsc-10bit): a systemd service writes `1` to `/sys/kernel/debug/dri/0/eDP-{1,2}/i915_dsc_fec_support` before the display manager starts, which forces DSC.
- **Fix, part 2 (Hyprland):** DSC alone gave `bpp=24`, because Hyprland asks for 8 bits per colour unless the monitor is set to 10-bit. KDE asks for 10 by default. `zenbook-duo.lua` sets `bitdepth = 10` on both panels (format `XRGB2101010`).
- **Result:** `bpp=30` on both panels, no dithering, Panel Replay Selective Update still on. burakgon measured no extra power use.
- Needs `psr-et-off` (DSC with Early Transport can corrupt the picture, xe #8923).
- **Check:** `sudo grep -E 'pipe src|bpp' /sys/kernel/debug/dri/0/i915_display_info` → `bpp=30`.

### `kbd-lid-wake`
- **Problem:** with the lid closed over the docked keyboard, the keyboard's USB remote wakeup wakes the laptop seconds after it suspends. Seen here: suspend at 08:56:42, awake at 08:56:44.
- **Fix:** burakgon's [`power-kbd-lid-wake`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/power-kbd-lid-wake): a systemd-sleep hook turns the keyboard's USB wakeup off before a lid-closed suspend and back on after resume. With the lid open, a key press still wakes the laptop.

### `power-profile-sync`
- **Problem:** choosing **power-saver** only changed the CPU's energy preference. The firmware (`asus-wmi`) and the Intel SoC Power Slider stayed in `balanced`, so no quiet fans and no low-power limits, and the Xe GPU stayed in `base`. The kernel's combined `platform_profile` only offers choices every handler shares, and `asus-wmi` calls its low-power mode `quiet` while the SoC slider calls it `low-power`.
- **Fix:** burakgon's [`power-profile-sync`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/power-profile-sync), unchanged except the install path (`/usr/local/lib/zenbook-duo/`). A small service follows power-profiles-daemon over D-Bus (no polling) and after resume, and writes each handler itself. A drop-in starts power-profiles-daemon with `--block-driver=platform_profile`, otherwise performance → power-saver snaps back to balanced.
- Works with Omarchy's power menu and its per-AC/battery profile memory (`omarchy-powerprofiles-set` goes through `powerprofilesctl`).
- **Performance limits need nothing:** burakgon's `power-dtt` (thermald `--adaptive` applying the BIOS DTT tables) is already done by Omarchy, which installs and enables thermald on Intel.
- **Result** (MMIO RAPL PL1/PL2):

  | Profile | asus-wmi | SoC slider | Xe GPU | PL1 / PL2 |
  |---|---|---|---|---|
  | power-saver | quiet | low-power | power_saving | 30 / 35 W |
  | balanced | balanced | balanced | base | 42 / 55 W |
  | performance | performance | performance | base | 55 / 64 W |

- **Check:** `grep . /sys/class/platform-profile/*/profile; journalctl -t zenbook-duo-profile-sync`.

### `runtime-pm`
- **Problem:** several Panther Lake platform PCI devices (Bluetooth, CSME/HECI, DTT, telemetry, shared SRAM, eSPI, SPI, host bridge) are left at `power/control = on`, so they can never power down when idle.
- **Fix:** burakgon's [`power-runtime-pm`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/power-runtime-pm) udev rule, unchanged: `power/control = auto` for those devices. The sensor hub, Wi-Fi and NVMe are left alone on purpose.
- **Measured here** (60 s idle each, screens on): package 0.50 → 0.45 W, platform (psys) 5.75 → 5.46 W. A small gain, about the size of the noise; idle was already low.
- **Check:** `grep -l '^on$' /sys/bus/pci/devices/*/power/control` should list only the sensor hub, Wi-Fi, NVMe and the VMD controller/port.
- If the Bluetooth keyboard starts to lag or reconnect slowly, remove `0xe476|` from the rule.

### `keyboard-intl` (optional, not part of `all`)
US International layout, plus an `~/.XCompose` rule so `'` + `c` gives `ç` instead of `ć`. Useful for writing Portuguese on a US keyboard.

### `charge-limit` (optional, not part of `all`)
Replaces MyASUS "Battery care mode" + "Instant full charge".
- The battery charges to **80%** only (`charge_control_end_threshold` of `asus-wmi`, on `BAT0`).
- A button in the Omarchy bar (next to the indicators, left of the clock) allows **100% for 24 hours**. Afterwards the 80% limit comes back by itself. Clicking again during the 24 h goes back to 80% right away.
- The limit is applied again at boot and after every resume, since ASUS firmware can reset it to 100%.
- Pieces:

  | Piece | Path |
  |---|---|
  | Script (`status` / `apply` / `boost` / `cancel` / `toggle`) | `/usr/local/bin/battery-charge-limit` |
  | Boost end time | `/var/lib/battery-charge-limit/boost-until` |
  | Boot + resume service | `/etc/systemd/system/battery-charge-limit.service` |
  | End of boost | transient `battery-charge-limit-restore.timer` (`systemd-run`; created again at boot) |
  | No password for the widget (`toggle`/`boost`/`cancel` only) | `/etc/sudoers.d/battery-charge-limit` |
  | Bar widget | `~/.config/omarchy/plugins/zenbook-duo.charge-limit/` + entry in `~/.config/omarchy/shell.json` (`bar.layout.centerBegin`, backup `shell.json.bak.zenbook-duo-charge-limit`) |

- Widget: `󰂁` dimmed while limited, hidden until the pointer is over the bar centre (like the indicators); `󰂅` highlighted and always shown during the boost. The tooltip says what a click does.
- Not a udev rule on purpose: the battery can register after the rule runs.
- **Check:** `battery-charge-limit status` → `{"limit":80,"threshold":80,"boostUntil":0}`.

## Manual steps

1. **Pair the keyboard over Bluetooth**, so it keeps working when lifted off the screen:
   - Press F11 / the Bluetooth key for pairing mode. The keyboard gets a new address each time.
   - Run `bluetoothctl scan le`, then `pair`, `trust`, `connect` with that address. Type the passkey on the keyboard.
   - **If you dual boot,** using the keyboard in Windows can replace the Linux pairing. If it stops reconnecting after a Windows session, run `bluetoothctl remove <addr>` and pair again.
2. **Windows boot entry** (dual boot): `sudo limine-scan` → "Windows Boot Manager". BitLocker may ask for its recovery key on the first boot.

## Known issues

### Bottom screen fails if the laptop was powered on with the keyboard on it ([xe #9196](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196))
- **Cause:** the bottom panel uses display port B, whose PHY sits in the Type-C subsystem. Only the firmware powers it, and only when it lights the bottom panel at power-on, which it skips while the keyboard covers it.
- **Symptom:** lifting the keyboard later logs `PHY B failed to request refclk`, `Port B PLL not locked`, `Timeout waiting for DDI BUF B`. Hyprland can freeze for ~30 s. `zenbook-duo-rotate` then keeps the screen off for that boot. The bad state survives warm reboots.
- **Fix:** the [`edp2-xe`](#edp2-xe) step. Verified: boot with the keyboard on the bottom screen, lift it, and the screen comes on.
- **Without that step:** power off completely, then power on with the keyboard lifted until the bottom screen lights up.

### The detached keyboard can't type the disk password
The password prompt runs from the initramfs, which has no Bluetooth. Put the keyboard on the bottom screen (it then connects over USB) to type it, and lift it afterwards.
- Not fixed on purpose. Options considered: Bluetooth inside the initramfs (stores the keyboard's pairing key unencrypted on the boot partition; the only existing hook is from 2020), or TPM auto-unlock (no password at all, which together with Omarchy's automatic login means anyone who powers the laptop on gets the desktop).

### Hot-unplugging an external monitor froze the machine
Seen once (`xe intel_dmc_wl.c:227` WARNING storm). No fix yet.

## Layout

```
install.sh                    step runner
files/hypr/zenbook-duo.lua    → ~/.config/hypr/
files/bin/zenbook-duo-rotate  → ~/.local/bin/
files/modprobe.d/             → /etc/modprobe.d/
files/keyboard/               optional US-intl + ç
dkms/zenbook-duo-hid-asus-1.7 burakgon's patched hid-asus + Fn-lock change (DKMS source, GPL-2.0)
dkms/zenbook-duo-omarchy-xe-1.0 Omarchy's xe + burakgon's TCSS patches (DKMS)
files/mkinitcpio.conf.d/      → /etc/mkinitcpio.conf.d/
files/pacman-hooks/           → /etc/pacman.d/hooks/
files/libinput/               → /etc/libinput/local-overrides.quirks (section)
files/systemd/                → /etc/systemd/system/
files/system-sleep/           → /usr/lib/systemd/system-sleep/
files/power/                  → /usr/local/lib/zenbook-duo/
files/udev/                   → /etc/udev/rules.d/
files/battery/                → /usr/local/bin/, /etc/sudoers.d/ (optional charge-limit)
files/omarchy-plugin/         → ~/.config/omarchy/plugins/ (charge-limit bar widget)
docs/hardware.md              devices, IDs and findings
docs/log.md                   what was done, in order, including dead ends
```

## Credits

This project would not exist without **[burakgon/zenbook-duo-2026-linux](https://github.com/burakgon/zenbook-duo-2026-linux)**. Taken from it, as files or as the method behind our version:

| Here | From burakgon |
|---|---|
| `ish-firmware` | [`sensors-ish-firmware`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/sensors-ish-firmware): getting the ASUS-signed sensor hub firmware from ASUS's driver package |
| `hid-asus` | [`keyboard-hid-asus`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/keyboard-hid-asus): the patched driver (our only change is `fn-lock.patch`) |
| `edp2-xe` | [`display-edp2-tcss`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/display-edp2-tcss): the xe #9196 analysis and the 3 TCSS patches (we rebuild them on Omarchy's `xe` instead of vanilla) |
| `touchpad-palm` | [`touchpad-palm`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/touchpad-palm), unchanged |
| `psr-et-off` | [`display-psr-et-off`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/display-psr-et-off), unchanged |
| `dsc-10bit` | [`display-dsc-10bit`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/display-dsc-10bit), unchanged (we add `bitdepth = 10` on the Hyprland side) |
| `kbd-lid-wake` | [`power-kbd-lid-wake`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/power-kbd-lid-wake), unchanged |
| `power-profile-sync` | [`power-profile-sync`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/power-profile-sync), unchanged (install path only) |
| `runtime-pm` | [`power-runtime-pm`](https://github.com/burakgon/zenbook-duo-2026-linux/tree/main/modules/power-runtime-pm), unchanged |
| `raydium`, `brightness`, rotation | his hardware report: the touchscreen driver conflict, DPCD backlight, the accelerometer mount matrix, and the keyboard USB/Bluetooth IDs |

Written for this project: the Hyprland side (`zenbook-duo.lua`, the `zenbook-duo-rotate` daemon for rotation, keyboard dock and brightness sync), `install.sh`, the Omarchy-kernel `xe` rebuild and its safety check, the Fn-lock change, and the battery charge limit with its bar widget (`charge-limit`, first written on a Zenbook S14).

- The ISH firmware belongs to ASUS and Intel and is downloaded from ASUS at install time.

## License

GPL-2.0, see [LICENSE](LICENSE). `dkms/` contains a modified Linux kernel driver (GPL-2.0-or-later).
