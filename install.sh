#!/bin/bash
# Re-apply the Zenbook Duo UX8407AA tweaks on a fresh Omarchy install.
#
#   ./install.sh list          show the steps
#   ./install.sh all           run every step in order
#   ./install.sh <step> ...    run only the given steps
#
# Run as your normal user from a terminal on Omarchy; steps that touch the system call sudo.
# Every step is safe to run again. See README.md for what each one does and why.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/files"

# "all" runs STEPS; OPTIONAL steps only run when named.
STEPS=(packages raydium ish-firmware hyprland brightness boot-orientation hid-asus edp2-xe touchpad-palm psr-et-off dsc-10bit kbd-lid-wake power-profile-sync runtime-pm)
OPTIONAL=(keyboard-intl charge-limit limine-menu)

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# Append a line to a file unless it is already there.
ensure_line() {
	local file="$1" line="$2"
	grep -qxF -- "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
}

NEED_LIMINE_UPDATE=0

step_packages() {
	say "packages: iio-sensor-proxy (accelerometer), dkms (patched keyboard driver)"
	sudo pacman -S --needed --noconfirm iio-sensor-proxy dkms curl libarchive zstd
}

step_keyboard_intl() {
	say "keyboard-intl (optional): US International layout + ' c = ç (for Portuguese on a US keyboard)"
	local layouts=~/.config/omarchy/keyboard-layouts
	mkdir -p ~/.config/omarchy
	if [[ -f $layouts ]] && ! cmp -s "$F/keyboard/keyboard-layouts" "$layouts"; then
		cp "$layouts" "$layouts.bak.zenbook-duo-keyboard"
	fi
	cp "$F/keyboard/keyboard-layouts" "$layouts"
	if ! grep -q 'dead_acute> <c>' ~/.XCompose 2>/dev/null; then
		cat "$F/keyboard/xcompose-ccedilla" >>~/.XCompose
	fi
	command -v omarchy-restart-xcompose >/dev/null && omarchy-restart-xcompose || true
	note "Layout is read by Hyprland on reload (hyprland step reloads it)."
}

step_charge_limit() {
	say "charge-limit (optional): charge the battery to 80% only, bar button for a 24 h full charge"
	if ! ls /sys/class/power_supply/BAT*/charge_control_end_threshold >/dev/null 2>&1; then
		note "No BAT*/charge_control_end_threshold (asus-wmi not loaded?). Skipping."
		return 0
	fi
	sudo install -D -m 0755 "$F/battery/battery-charge-limit" /usr/local/bin/battery-charge-limit
	sudo install -m 0644 "$F/systemd/battery-charge-limit.service" /etc/systemd/system/battery-charge-limit.service
	# Lets the bar widget toggle the boost without a password (only toggle/boost/cancel).
	local tmp
	tmp=$(mktemp)
	sed "s/^USERNAME /$USER /" "$F/battery/battery-charge-limit.sudoers" >"$tmp"
	sudo visudo -cf "$tmp" >/dev/null
	sudo install -D -m 0440 "$tmp" /etc/sudoers.d/battery-charge-limit
	rm -f "$tmp"
	sudo systemctl daemon-reload
	sudo systemctl enable battery-charge-limit.service
	sudo systemctl start battery-charge-limit.service
	# Bar widget: plugin folder + entry right after the indicators, left of the clock.
	mkdir -p ~/.config/omarchy/plugins
	rm -rf ~/.config/omarchy/plugins/zenbook-duo.charge-limit
	cp -r "$F/omarchy-plugin/zenbook-duo.charge-limit" ~/.config/omarchy/plugins/
	local cfg=~/.config/omarchy/shell.json
	if [[ -f $cfg ]] && ! jq -e '.. | objects | select(.id? == "zenbook-duo.charge-limit")' "$cfg" >/dev/null; then
		cp "$cfg" "$cfg.bak.zenbook-duo-charge-limit"
		jq '.bar.layout.centerBegin = ((.bar.layout.centerBegin // [{"id": "omarchy.indicators"}]) + [{"id": "zenbook-duo.charge-limit"}])' \
			"$cfg.bak.zenbook-duo-charge-limit" >"$cfg"
	fi
	command -v omarchy >/dev/null && omarchy restart shell >/dev/null 2>&1 || true
	note "Now: $(battery-charge-limit status)"
}

step_raydium() {
	say "raydium: stop raydium_i2c_ts from grabbing the touchscreens"
	sudo install -m 0644 "$F/modprobe.d/zenbook-duo-raydium.conf" /etc/modprobe.d/zenbook-duo-raydium.conf
	NEED_LIMINE_UPDATE=1 # the blacklist must also be inside the initramfs
}

step_ish_firmware() {
	say "ish-firmware: ASUS-signed sensor hub firmware (accelerometer, light, hinge)"
	# ASUS's firmware can't be redistributed, so take it from ASUS's own Windows
	# driver package (same method as burakgon/zenbook-duo-2026-linux).
	local url="https://dlcdnets.asus.com/pub/ASUS/nb/Image/Driver/Chipset/48536/SensorHub_DCH_Intel_Z_V5.8.62.0_48536.exe?model=UX8407AA"
	local pkg_sha=735a2915b421e0d35975211e0dee94bffc89c33bc688ab0567e09ee407f6e575
	local member="IshHeciExtensionTemplate/x64/FWImage/0004/AsusSign_ishS_SI_CommonPTL_5.8.1.7779_V0018.bin"
	local fw_sha=e031f54f5a4fbdc51dc9beb3937f52fdc5d2ba00f005313cf73a8cfe0f9b2060
	local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zenbook-duo-omarchy"
	local pkg="$cache/SensorHub_DCH_Intel_Z_V5.8.62.0_48536.exe"
	local work offset name
	mkdir -p "$cache"
	if ! sha256sum -c --status <<<"$pkg_sha  $pkg" 2>/dev/null; then
		note "Downloading ASUS Sensor Hub driver package (~5 MB)"
		curl -fL --retry 3 -o "$pkg.part" "$url"
		mv "$pkg.part" "$pkg"
	fi
	sha256sum -c --status <<<"$pkg_sha  $pkg" || { echo "package checksum mismatch, refusing" >&2; return 1; }
	work="$(mktemp -d)"
	# The .exe is a PE stub with a 7z archive appended: cut it out, extract one file.
	offset="$(LC_ALL=C grep -obUaP '7z\xbc\xaf\x27\x1c' "$pkg" | head -1 | cut -d: -f1)"
	[[ -n $offset ]] || { echo "no 7z payload in package" >&2; rm -rf "$work"; return 1; }
	tail -c +$((offset + 1)) "$pkg" >"$work/pkg.7z"
	bsdtar -xf "$work/pkg.7z" -C "$work" "$member"
	sha256sum -c --status <<<"$fw_sha  $work/$member" || { echo "firmware checksum mismatch, refusing" >&2; rm -rf "$work"; return 1; }

	# The kernel looks for ish_ptl_<crc32(sys_vendor)>_<crc32(product_name)>.bin
	# (zlib CRC-32, read here from gzip's trailer). UX8407AA: ish_ptl_59b8d9f2_c68ec386.bin
	crc() { printf '%s' "$1" | gzip -c | tail -c8 | head -c4 | od -An -tx4 | tr -d ' \n'; }
	name="ish_ptl_$(crc "$(cat /sys/class/dmi/id/sys_vendor)")_$(crc "$(cat /sys/class/dmi/id/product_name)").bin"
	[[ $name == ish_ptl_59b8d9f2_c68ec386.bin ]] || note "WARNING: this is not a UX8407AA ($name); the firmware may not fit."
	sudo install -D -m 0644 "$work/$member" "/usr/lib/firmware/updates/intel/ish/$name"
	rm -rf "$work"
	if lsmod | grep -q '^intel_ish_ipc'; then
		sudo modprobe -r intel_ish_ipc && sudo modprobe intel_ish_ipc || note "Reload failed: a cold boot is needed."
	fi
	note "Check: cat /sys/bus/iio/devices/iio:device*/name  (accel_3d, als, hinge...)"
}

step_hyprland() {
	say "hyprland: two-screen layout, rotation, keyboard-dock screen off, brightness mirror"
	install -D -m 0644 "$F/hypr/zenbook-duo.lua" ~/.config/hypr/zenbook-duo.lua
	install -D -m 0755 "$F/bin/zenbook-duo-rotate" ~/.local/bin/zenbook-duo-rotate
	ensure_line ~/.config/hypr/monitors.lua 'dofile(os.getenv("HOME") .. "/.config/hypr/zenbook-duo.lua")'
	ensure_line ~/.config/hypr/autostart.lua 'o.launch_on_start("zenbook-duo-rotate")'
	if hyprctl version >/dev/null 2>&1; then
		hyprctl reload >/dev/null || true
		pgrep -f '/zenbook-duo-rotate$' >/dev/null || (setsid ~/.local/bin/zenbook-duo-rotate >/dev/null 2>&1 &)
	fi
}

step_brightness() {
	say "brightness: OLED panels need DPCD backlight (xe.enable_dpcd_backlight=1)"
	if ! grep -q 'xe.enable_dpcd_backlight=1' /etc/default/limine; then
		sudo cp /etc/default/limine /etc/default/limine.bak.zenbook-duo
		echo 'KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=1"' | sudo tee -a /etc/default/limine >/dev/null
	fi
	NEED_LIMINE_UPDATE=1
}

step_boot_orientation() {
	say "boot-orientation: tell the kernel the top panel is mounted upside down (boot text, LUKS prompt)"
	# Sets the DRM "panel orientation" property on eDP-1. fbcon and Plymouth rotate by it;
	# Side effect: fbcon/Plymouth leave eDP-1's primary plane at KMS rotation 180 and
	# Hyprland never resets it, so zenbook-duo.lua has NO extra 180° for eDP-1 and uses
	# software cursors (the cursor plane is not rotated). The hyprland step needs this one.
	if ! grep -q 'panel_orientation=upside_down' /etc/default/limine; then
		sudo cp /etc/default/limine /etc/default/limine.bak.zenbook-duo-orientation
		echo 'KERNEL_CMDLINE[default]+=" video=eDP-1:panel_orientation=upside_down"' | sudo tee -a /etc/default/limine >/dev/null
	fi
	NEED_LIMINE_UPDATE=1
}

step_limine_menu() {
	say "limine-menu (optional): always show the boot menu (4 s) so Windows can be picked"
	local conf=/boot/limine.conf
	sudo cp "$conf" "$conf.bak.zenbook-duo"
	if sudo grep -qE '^\s*quiet:' "$conf"; then
		sudo sed -i -E 's/^(\s*)quiet:.*/\1quiet: no/' "$conf"
	else
		sudo sed -i '1i quiet: no' "$conf"
	fi
	if sudo grep -qE '^\s*timeout:' "$conf"; then
		sudo sed -i -E 's/^(\s*)timeout:.*/\1timeout: 4/' "$conf"
	else
		sudo sed -i '1i timeout: 4' "$conf"
	fi
	if ! sudo grep -q 'Windows Boot Manager' "$conf"; then
		note "No Windows entry yet: run  sudo limine-scan  and pick 'Windows Boot Manager'."
	fi
}

step_hid_asus() {
	say "hid-asus: patched ASUS keyboard driver (Fn keys, brightness keys, backlight, mic LED)"
	local name=zenbook-duo-hid-asus ver=1.7 k old
	k="$(uname -r)"
	[[ $k =~ ^7\.[23]\. ]] || note "WARNING: kernel $k is not 7.2/7.3; the driver source may not build. Check burakgon's repo for a newer version."
	sudo pacman -S --needed --noconfirm dkms
	for old in /usr/src/$name-*; do
		[[ -e $old && ${old##*-} != "$ver" ]] || continue
		sudo dkms remove -m $name -v "${old##*-}" --all 2>/dev/null || true
		sudo rm -rf "$old"
	done
	sudo rm -rf "/usr/src/$name-$ver"
	sudo cp -a "$HERE/dkms/$name-$ver" "/usr/src/$name-$ver"
	sudo chown -R root:root "/usr/src/$name-$ver"
	sudo dkms add -m $name -v $ver 2>/dev/null || true
	sudo dkms install -m $name -v $ver -k "$k"
	# Switch the keyboard over without rebooting.
	sudo modprobe -r hid_asus 2>/dev/null || true
	sudo modprobe hid_asus
	local d drv
	for d in /sys/bus/hid/devices/0003:0B05:1CD7.* /sys/bus/hid/devices/0005:0B05:1CD8.*; do
		[[ -e $d ]] || continue
		od -An -tx1 -v "$d/report_descriptor" | tr -d '\n' | grep -q '06 31 ff 09 76' || continue
		drv="$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null || true)"
		[[ $drv == asus ]] && continue
		[[ -n $drv ]] && echo "${d##*/}" | sudo tee "/sys/bus/hid/drivers/$drv/unbind" >/dev/null
		echo "${d##*/}" | sudo tee /sys/bus/hid/drivers/asus/bind >/dev/null || true
	done
	note "Check: ls /sys/class/leds | grep asus   (asus::kbd_backlight, asus::micmute)"
}

step_edp2_xe() {
	say "edp2-xe: Omarchy's xe driver + fix for the bottom screen after a docked power-on (xe #9196)"
	local name=zenbook-duo-omarchy-xe ver=1.0 k
	k="$(uname -r)"
	[[ $k == *-omarchy ]] || { note "Kernel $k is not linux-omarchy; skipping."; return 0; }
	sudo pacman -S --needed --noconfirm dkms git patch pahole python zstd
	sudo rm -rf "/usr/src/$name-$ver"
	sudo cp -a "$HERE/dkms/$name-$ver" "/usr/src/$name-$ver"
	sudo chown -R root:root "/usr/src/$name-$ver"
	# Download this kernel's sources (a few MB) before DKMS builds; later kernels are
	# fetched by the pacman hook below.
	echo "usr/lib/modules/$k/build/include/" | sudo bash "/usr/src/$name-$ver/build.sh" --fetch
	sudo dkms add -m $name -v $ver 2>/dev/null || true
	sudo dkms install -m $name -v $ver -k "$k"
	sudo install -D -m 0644 "$F/pacman-hooks/65-zenbook-duo-omarchy-xe-sources.hook" /etc/pacman.d/hooks/65-zenbook-duo-omarchy-xe-sources.hook
	# Only a pacman that sandboxes hooks knows NetworkAccess; 7.1 rejects it and fails every transaction.
	if grep -q -a 'NetworkAccess' /usr/lib/libalpm.so; then
		sudo sed -i 's/^Depends = git$/&\nNetworkAccess = allowed/' /etc/pacman.d/hooks/65-zenbook-duo-omarchy-xe-sources.hook
	fi
	sudo install -D -m 0644 "$F/mkinitcpio.conf.d/zenbook-duo-omarchy-xe.conf" /etc/mkinitcpio.conf.d/zenbook-duo-omarchy-xe.conf
	NEED_LIMINE_UPDATE=1
	note "After the reboot: cat /sys/module/xe/parameters/zenbook_duo_edp2_tcss  (Y = fix active)"
}

step_touchpad_palm() {
	say "touchpad-palm: palm rejection + disable-while-typing for the keyboard touchpad"
	# libinput reads a single local quirks file: keep anything else in it, replace our section.
	local dest=/etc/libinput/local-overrides.quirks tmp
	tmp="$(mktemp)"
	if [[ -f $dest ]]; then
		sed '/^# >>> zenbook-duo-2026-linux touchpad-palm$/,/^# <<< zenbook-duo-2026-linux touchpad-palm$/d' "$dest" >"$tmp"
		[[ -s $tmp ]] && echo >>"$tmp"
	fi
	cat "$F/libinput/zenbook-duo-touchpad.quirks" >>"$tmp"
	sudo install -D -m 0644 "$tmp" "$dest"
	rm -f "$tmp"
	note "Takes effect at the next login (Hyprland loads libinput quirks at start)."
}

step_psr_et_off() {
	say "psr-et-off: Panel Replay without Early Transport (ghost / flickering cursor on the top screen)"
	sudo install -m 0644 "$F/systemd/zenbook-duo-psr-et-off.service" /etc/systemd/system/zenbook-duo-psr-et-off.service
	sudo systemctl daemon-reload
	sudo systemctl enable --now zenbook-duo-psr-et-off.service
}

step_dsc_10bit() {
	say "dsc-10bit: both OLED panels at 10 bits per colour through DSC (instead of 6 bits + dithering)"
	# Needs psr-et-off (DSC + Panel Replay Early Transport can corrupt the picture, xe #8923).
	# The Hyprland side is bitdepth = 10 in zenbook-duo.lua (hyprland step).
	sudo install -m 0644 "$F/systemd/zenbook-duo-dsc-10bit.service" /etc/systemd/system/zenbook-duo-dsc-10bit.service
	sudo systemctl daemon-reload
	sudo systemctl enable --now zenbook-duo-dsc-10bit.service
	note "Takes effect when each panel is next switched on: reboot."
}

step_kbd_lid_wake() {
	say "kbd-lid-wake: the docked keyboard must not wake the laptop while the lid is closed"
	sudo install -D -m 0755 "$F/system-sleep/zenbook-duo-kbd-lid-wake" /usr/lib/systemd/system-sleep/zenbook-duo-kbd-lid-wake
}

step_power_profile_sync() {
	say "power-profile-sync: power-saver really saves power (asus-wmi quiet, SoC low-power, Xe power_saving)"
	# The CPU power limits per profile come from thermald --adaptive (Intel DTT tables in
	# the BIOS). Omarchy already installs and enables thermald on Intel, so nothing to do there.
	local d=/etc/systemd/system/power-profiles-daemon.service.d f prof
	for f in "$d"/*.conf; do
		[[ -e $f && $f != */50-zenbook-duo-block-platform-profile.conf ]] || continue
		if grep -q '^ExecStart=' "$f"; then
			note "$f already sets ExecStart: add --block-driver=platform_profile there. Skipping."
			return 0
		fi
	done
	sudo install -D -m 0755 "$F/power/zenbook-duo-profile-sync" /usr/local/lib/zenbook-duo/zenbook-duo-profile-sync
	sudo install -m 0644 "$F/systemd/zenbook-duo-profile-sync.service" /etc/systemd/system/zenbook-duo-profile-sync.service
	sudo install -D -m 0644 "$F/systemd/power-profiles-daemon.service.d/50-zenbook-duo-block-platform-profile.conf" "$d/50-zenbook-duo-block-platform-profile.conf"
	sudo systemctl daemon-reload
	# PPD does not restore its saved profile when its drivers change: put the current one back.
	prof="$(powerprofilesctl get 2>/dev/null || echo balanced)"
	sudo systemctl restart power-profiles-daemon.service
	sleep 1
	powerprofilesctl set "$prof" 2>/dev/null || true
	sudo systemctl enable zenbook-duo-profile-sync.service
	sudo systemctl restart zenbook-duo-profile-sync.service
}

step_runtime_pm() {
	say "runtime-pm: let idle platform PCI devices (Bluetooth, CSME, DTT, telemetry, SPI...) power down"
	sudo install -m 0644 "$F/udev/90-zenbook-duo-runtime-pm.rules" /etc/udev/rules.d/90-zenbook-duo-runtime-pm.rules
	sudo udevadm control --reload
	sudo udevadm trigger --subsystem-match=pci --action=add
}

run_step() {
	local s="$1"
	[[ " ${STEPS[*]} ${OPTIONAL[*]} " == *" $s "* ]] || { echo "unknown step: $s (try: $0 list)" >&2; exit 1; }
	"step_${s//-/_}"
}

case "${1:-}" in
"" | -h | --help | list)
	echo "Steps (run in this order with '$0 all'):"
	printf '  %s\n' "${STEPS[@]}"
	echo "Optional (run by name only):"
	printf '  %s\n' "${OPTIONAL[@]}"
	exit 0
	;;
all) set -- "${STEPS[@]}" ;;
esac

for s in "$@"; do run_step "$s"; done

if ((NEED_LIMINE_UPDATE)); then
	say "Rebuilding the boot image (limine-update)"
	sudo limine-update
fi
say "Done. Reboot if you changed raydium, brightness or ish-firmware."
