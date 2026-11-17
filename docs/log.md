# Log

What was done, in order, including what didn't work. Newest at the bottom.

## 2026-11-16

- **Fresh Omarchy install.** The top screen was upside down and the bottom screen wasn't detected. An external monitor was used meanwhile.
- **Top screen:** `transform = 2` on eDP-1.
- **Bottom screen:** not detected when booting with the keyboard on it (`failed to retrieve link info, disabling eDP`), and lifting the keyboard without a reboot didn't help. Booting with the keyboard lifted made eDP-2 appear. It was placed at `0x900` below eDP-1, both at scale 2.
- **Touch:** the bottom touchscreen was bound to `raydium_i2c_ts` (`invalid packet crc`). Rebinding it to `i2c-hid` live fixed touch and pen, and a modprobe blacklist made it permanent. The blacklist was confirmed after a reboot.
- **Sensors:**
  - Only `hid_sensor_prox` loaded. The ISH rejected linux-firmware's `ish_ptl.bin` (`cmd 2 failed 10`).
  - The ASUS-signed firmware was found in the Windows DriverStore (`ishheciextensiontemplate.inf…/FwImage/0004/`).
  - First attempt used the wrong file name (CRC without the final XOR). With the right name (`ish_ptl_59b8d9f2_c68ec386`), reloading `intel_ish_ipc` brought up accel, als, hinge and prox.
- **Rotation:**
  - Installed `iio-sensor-proxy`.
  - Tried burakgon's `ACCEL_MOUNT_MATRIX` and removed it, because upright read as `bottom-up`.
  - Wrote `zenbook-duo.lua` (layouts) and the `zenbook-duo-rotate` daemon.
  - Verified sideways in both directions, including touch and pen.
  - Later added a 1 s debounce, lock/unlock, retries when Hyprland isn't ready, and re-applying the layout after a config reload.
- **External monitor:** unplugging it froze the machine (xe WARNING storm). Stopped using it.
- **Keyboard dock:**
  - The daemon watches USB `0b05:1cd7` and turns eDP-2 and its digitizer off while docked.
  - If the kernel logs port-B errors after re-enabling, eDP-2 is marked unsafe for the boot.
  - burakgon's "<20 s after boot" guard was not copied. Docking the keyboard at ~15 s to type the LUKS password is fine when the panel was already lit, so the kernel error messages are the real signal.
- **Brightness:**
  - The keys changed `intel_backlight` but nothing visible happened (OLED ignores PWM).
  - Added `xe.enable_dpcd_backlight=1`, after which the top screen works.
  - Added mirroring to eDP-2: the daemon follows `intel_backlight` changes through udev backlight events and re-syncs after enable and resume. Verified.
- **Dual boot:** added the Windows entry with `limine-scan`, and set `timeout: 4`.

## 2026-11-17

- **Boot menu:** it still didn't show, because an Omarchy migration added `quiet: yes`. Set `quiet: no`, and the menu now shows.
- **Brightness keys:**
  - They sent plain F5/F6. Fn and Fn+Esc did nothing.
  - burakgon's `keyboard-hid-asus` explains why: the keyboard isn't in the `hid-asus` table, and the hotkeys come on report `0x5a`.
  - Installed his DKMS driver (`zenbook-duo-hid-asus` 1.6). All keyboard interfaces moved to `asus`, and the `asus::kbd_backlight` and `asus::micmute` LEDs appeared. Key test pending.
- **Undock test after that:**
  1. eDP-2 failed (PHY B / Port B PLL / DDI BUF B errors, Hyprland froze ~30 s), and the daemon marked it unsafe. This boot had the keyboard docked 9 s after power-on, which is the xe #9196 case. It is not related to `hid-asus`. The fix is burakgon's `display-edp2-tcss`, not installed yet.
  2. The keyboard didn't reconnect over Bluetooth. Re-pairing fixed it. Booting Windows in between probably replaced the pairing.
- **Project:** started this repository to keep everything reproducible.
- **Bottom screen fix (xe #9196):**
  - burakgon's `display-edp2-tcss` would build vanilla kernel.org `xe` and drop the 27 `xe`/`i915` patches the Omarchy kernel carries.
  - Wrote `zenbook-duo-omarchy-xe` instead: vanilla `v7.2.15` + Omarchy's `xe`/`i915` patches from omarchy-pkgs `326470ed` (= linux-omarchy 7.2.15-1) + burakgon's 3 TCSS patches.
  - Without the TCSS patches, the rebuild matched the stock `xe.ko` exactly (same functions and parameters). With them, the only additions are the TCSS functions and the `zenbook_duo_edp2_tcss` parameter, and `build.sh` now checks this on every build.
  - Gotcha: some Omarchy patches use `c/` `i/` diff prefixes instead of `a/` `b/`.
  - Took restore point snapper #5 first, then installed via DKMS + `MODULES+=(xe)` + `limine-update`.
  - **Verified:** rebooted with the keyboard lying on the bottom screen (USB attach at ~9 s). `xe.zenbook_duo_edp2_tcss=Y`, eDP-2 stayed `connected`, the daemon kept it off while docked, and lifting the keyboard brought it back with no PHY B / Port B PLL errors.
- **Four more issues** (all checked against burakgon first):
  - **Lid close:** logind did suspend, but with the keyboard docked the laptop woke 2 s later (08:56:42 → 08:56:44) and logind re-suspended ~30 s after. Same wake loop as burakgon's `power-kbd-lid-wake`. Installed his sleep hook. **Verified:** lid closed 09:48:21 with the keyboard docked, one suspend, asleep until the lid opened at 09:53:31, keyboard wakeup re-enabled after.
  - **Ghost / flickering cursor:** installed burakgon's `display-psr-et-off` (PSR debug `0x20`, Panel Replay SU stays on). **Verified** by the user: flicker gone.
  - **Palm rejection:** libinput reported the touchpad as external, so Hyprland's `disable_while_typing = true` did nothing. Installed burakgon's `touchpad-palm` quirk. Needs a re-login; user keeping an eye on it.
  - **Fn+Esc:** a key capture showed Fn+Esc arriving as `KEY_FN_ESC`, but burakgon's driver only toggles Fn-lock for ROG keyboards, and its Duo re-init forces media keys on every connect and resume. Wrote `fn-lock.patch`: a `zenbook_duo_fn_lock` module parameter (default `Y` = F1–F12), toggled by Fn+Esc and re-sent on re-init. Bumped the DKMS package to 1.7 (1.6 removed). **Verified** by the user: F-keys by default, Fn+Esc toggles.
  - Not applied: burakgon's `touchpad-motion` (Bluetooth jump fix as a libinput Lua plugin; not yet confirmed that Hyprland loads libinput plugins) and `touchpad-accel` (KWin-only LD_PRELOAD).
- **Upside-down boot screen:** Plymouth's disk password screen (and the boot text) were upside down at power-on; the lock screen after sleep was fine. burakgon only fixed the KDE login screen. Checked Linux 7.2.15 `drm_connector.c`: `video=<connector>:panel_orientation=` goes through `drm_connector_set_panel_orientation()`, so the property is attached and Plymouth's DRM renderer (which reads `panel orientation`) can follow it. Added the parameter (`boot-orientation` step).
- **Bluetooth keyboard at the disk password:** no Bluetooth in the initramfs. The user chose to keep docking the keyboard for it; documented as a known issue.
- **10-bit colour:** both panels were at `bpp=18`, dithered (DSC supported by the panels but not used). Installed burakgon's `display-dsc-10bit` service. After toggling eDP-2, it came up with DSC but only `bpp=24`: Hyprland requests 8 bpc by default. Added `bitdepth = 10` to the monitors in `zenbook-duo.lua` → `XRGB2101010`, `bpp=30` on both panels, no dithering, DSC on, Panel Replay SU still on, no kernel errors. Reboot check pending: at boot the service must run before Hyprland's first modeset.
- **Reboot check (10:18):**
  - Disk password screen upright. ✅
  - The top screen was upside down again: `transform = 2` added another 180°. Removed the extra 180° for eDP-1 in all orientations (normal 2→0, left-up 3→1, right-up 1→3). Touch needed no change. Both screens upright in every orientation.
  - Then the **mouse pointer** on the top screen was upside down and moved the wrong way (going down reached the bottom screen via the top edge). debugfs showed eDP-1's primary plane at KMS `rotation=180`, cursor plane at 0. aquamarine 0.15.1 reads `panel orientation` but never sets the plane `rotation`, so the 180° left by fbcon/Plymouth stays; Hyprland itself does not use the property. Fix: `cursor.no_hardware_cursors = 1` in `zenbook-duo.lua`. **Verified** by the user: pointer correct. burakgon has nothing on this (KWin handles rotation itself).
  - 10-bit colour survives the reboot: `bpp=30` on both panels, DSC 10 bpc; no colour glitches seen. ✅
- **Software cursor power test** (on battery, 2 rounds × 20 s still + 30 s of circling the mouse on the top screen per cursor type, RAPL every 0.5 s): package 1.72 W (software) vs 1.95 W (hardware) while moving, psys 17.0 W vs 18.5 W; still: 0.49 vs 0.45 W package (round 2). The differences are smaller than the round-to-round spread (move psys 16.2–19.1 W), so there is **no measurable cost**. Kept the software cursor.
- **burakgon's power modules:**
  - `power-dtt` (performance): not needed. Omarchy installs thermald with `--adaptive`; the MMIO power limits already follow the profile (balanced 42/55 W, performance 55/64 W).
  - `power-profile-sync`: needed. power-saver left asus-wmi and the SoC slider in `balanced` and the Xe GPU in `base`. Omarchy's power-profiles-daemon fork supports `--block-driver`. Installed (`power-profile-sync` step). Verified: power-saver → quiet / low-power / power_saving, PL1/PL2 30/35 W; performance → power-saver no longer snaps back.
  - `power-runtime-pm`: needed (all 9 devices at `on`). Installed (`runtime-pm` step). Idle 60 s before/after, screens on: package 0.50 → 0.45 W, psys 5.75 → 5.46 W, PC10 residency 55 % → 56 %. Small; within noise. Bluetooth keyboard still connected afterwards.
- **pacman hook broke every transaction:** installing a package failed with `hook /etc/pacman.d/hooks/65-zenbook-duo-omarchy-xe-sources.hook line 14: invalid option NetworkAccess`. The option came from burakgon's similar mac80211 hook, whose README says pacman 7.1 runs hooks without network. Arch's pacman `7.1.0.r9` only sandboxes downloads (`DisableSandbox*`, `DownloadUser`), so hooks already have network access and the option is unknown. Removed it from the hook; `install.sh` adds it back only if `libalpm.so` contains `NetworkAccess`.
