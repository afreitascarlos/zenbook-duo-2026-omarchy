# Hardware notes: Zenbook Duo UX8407AA

Facts gathered while setting the laptop up. Kernel `7.2.15-1-omarchy`, BIOS `UX8407AA.310`.

## Displays

| Connector | Panel | Notes |
|---|---|---|
| eDP-1 (top) | BOE NB140B9M-T01, 2880×1800 OLED | Mounted upside down: needs transform 2 in the normal position |
| eDP-2 (bottom) | BOE NB140B9M-T02, 2880×1800 OLED | Display port B (DDI B / PHY B, a C20 PHY inside the Type-C subsystem) |

- Default scale 2 (logical 1440×900 each); any clean scale set in `monitors.lua` works, e.g. 1.25 gives 2304×1440.
- eDP-2 only appears if the firmware lit it at power-on, i.e. the keyboard was not lying on it (xe #9196). Otherwise the kernel logs `[ENCODER:520:DDI B/PHY B] failed to retrieve link info, disabling eDP` at boot, or `PHY B failed to request refclk` when it is enabled later.
- **Backlight:** the OLEDs ignore PWM. Brightness needs `xe.enable_dpcd_backlight=1`, which gives DPCD brightness with a range of 0–504.
  - `intel_backlight` is eDP-1.
  - `card<N>-eDP-2-backlight` is eDP-2. N changes between boots.
- `asus_screenpad` also exists under `/sys/class/backlight`. It isn't used here.

## Touch and pen

| Device | Screen | Driver |
|---|---|---|
| `RAYD0001` (`2386:8C05`) | top, eDP-1 | `i2c-hid` (`PNP0C50`) |
| `RAYD0002` (`2386:8C06`) | bottom, eDP-2 | `i2c-hid` |

- `raydium_i2c_ts` binds to them by ACPI ID and fails (`invalid packet crc`), so it must be blacklisted.
- Hyprland device names: `rayd0001:00-2386:8c05`, `…-stylus`, `rayd0002:00-2386:8c06`, `…-stylus`.
- Both digitizers are aligned with eDP-2's native orientation, so both take eDP-2's transform.

## Sensors (Intel ISH, `8086:e445`)

- **Firmware:** needs the ASUS-signed `ish_ptl_59b8d9f2_c68ec386.bin`.
  - The kernel name is `ish_ptl_<crc32(sys_vendor)>_<crc32(product_name)>`, using zlib CRC-32 with the final XOR.
  - Careful: `crc32(~0, s)` *without* the final XOR gives the wrong name (`a647260d_39713c79`).
- **Devices** after the firmware loads: `accel_3d`, `als`, `hinge`, `prox`, `hid_sensor_custom_intel_hinge`.
- **Accelerometer:** it sits in the top lid. With no `ACCEL_MOUNT_MATRIX`, `iio-sensor-proxy` reports:
  - `normal` when the laptop is upright.
  - `left-up` when sideways with the top screen on the right.
  - `right-up` when sideways with the top screen on the left.
- burakgon's hwdb matrix (`-1,0,0;0,-1,0;0,0,1`) is relative to eDP-1's flipped native panel, the way KDE uses it. With it, upright reads as `bottom-up`, so it's **not** used here.

## Keyboard

| Connection | ID | Driver (stock) |
|---|---|---|
| USB (on the bottom screen, pogo pins) | `0b05:1cd7` "Primax ASUS Zenbook Duo Keyboard" | `hid-generic` (+ `hid-multitouch` for touchpad) |
| Bluetooth LE (off the screen) | `0b05:1cd8` | `hid-generic` via uhid |

- When the keyboard is lifted, its USB device disappears and Bluetooth reconnects about 1 s later, if it's paired.
- **Hotkeys:** they come on USB interface 4 (usage page `0xff31`), report `0x5a`.
  - Byte 1 codes: `0x10` / `0x20` brightness, `0xc7` keyboard backlight, `0x7c` mic, `0x6a` ScreenPad, `0x9c` display switch, `0x86` MyASUS, `0x5f` ScreenXpert.
  - Fn-lock command: `5A D0 4E 01/00`.
- With `hid-generic`, the brightness keys arrive as plain `KEY_F5` (scan `0x7003e`) and `KEY_F6` (`0x7003f`).
- **Battery** is reported as `5a 3d <percent> <status>` in the same report. Read as hotkeys, those reports press random keys. The patched driver drops them.

## Boot

- Omarchy uses Limine with a UKI. Edit the kernel command line in `/etc/default/limine`, then run `sudo limine-update`.
- `/boot` is root-only, so read `limine.conf` with sudo.
- Windows has its own EFI partition. `limine-scan` finds it.

## Kernel bugs seen

- **xe #9196:** eDP-2 after a power-on with the keyboard on it. See README.
- **Hot-unplugging an external DP monitor:** `xe intel_dmc_wl.c:227` WARNING storm, then a freeze.
