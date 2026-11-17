#!/bin/bash
# Build Omarchy's own xe.ko plus the Zenbook Duo eDP-2 (port B) TCSS fix.
#
#   build.sh KERNELVER KERNEL_BUILD_DIR   called by DKMS (MAKE in dkms.conf)
#   build.sh --fetch                      pacman hook: usr/lib/modules/<kver>/build/include/
#                                         lines on stdin; caches sources for those kernels
#
# Sources for KERNELVER (e.g. 7.2.15-1-omarchy) are put together exactly like the
# linux-omarchy package does it, restricted to drivers/gpu/drm/{xe,i915}:
#   1. kernel.org stable tag v7.2.15 (sparse clone, a few MB)
#   2. the xe/i915 parts of Omarchy's kernel patches, in PKGBUILD order, taken from the
#      omarchy-pkgs commit that has pkgver=7.2.15 pkgrel=1
#   3. patches/ (burakgon/zenbook-duo-2026-linux display-edp2-tcss, xe #9196)
# The result is checked against the stock xe.ko of that kernel: the only allowed
# differences are the functions the fix adds. Any other difference fails the build,
# and the stock xe stays in use.
#
# A pacman hook (65-...-sources.hook) runs --fetch first and the DKMS build only reads the
# cache, so the build works offline and in case a pacman sandboxes hooks.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cache="${ZDX_CACHE:-/var/cache/zenbook-duo-omarchy-xe}"
pkgs_repo=https://github.com/omacom-io/omarchy-pkgs.git
stable_repo=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
export GIT_TERMINAL_PROMPT=0
git_net() { timeout "$1" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "${@:2}"; }
log() { echo "zenbook-duo-omarchy-xe: $*" >&2; }

# parse KERNELVER into ver (7.2.15), rel (1) and the upstream tag (v7.2.15; v7.3 for 7.3.0)
parse_kver() {
	[[ $1 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-([0-9]+)-omarchy$ ]] || { log "not an Omarchy kernel: $1"; return 1; }
	ver="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
	rel="${BASH_REMATCH[4]}"
	tag="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
	[[ ${BASH_REMATCH[3]} == 0 ]] || tag+=".${BASH_REMATCH[3]}"
}

# omarchy-pkgs clone (history only, file contents fetched on demand)
pkgs_git() {
	local repo="$cache/omarchy-pkgs.git"
	if [[ ! -d $repo ]]; then
		mkdir -p "$cache"
		git_net 300 clone -q --bare --filter=blob:none "$pkgs_repo" "$repo.part" && mv "$repo.part" "$repo" || {
			rm -rf "$repo.part"
			return 1
		}
	elif [[ ${1:-} == update ]]; then
		git_net 300 -C "$repo" fetch -q origin '+refs/heads/*:refs/heads/*' || log "could not update omarchy-pkgs, using the cached copy"
	fi
	echo "$repo"
}

# newest omarchy-pkgs commit whose linux-omarchy PKGBUILD has pkgver=$ver pkgrel=$rel
find_commit() {
	local repo="$1" c pb
	for c in $(git -C "$repo" log --format=%H HEAD -- pkgbuilds/linux-omarchy/PKGBUILD); do
		pb="$(git -C "$repo" show "$c:pkgbuilds/linux-omarchy/PKGBUILD" 2>/dev/null)" || continue
		grep -qxE "pkgver=($ver|${ver%.0})" <<<"$pb" && grep -qx "pkgrel=$rel" <<<"$pb" && { echo "$c"; return 0; }
	done
	return 1
}

# sources KERNELVER: make sure $cache/src/KERNELVER holds vanilla + Omarchy xe/i915 sources
sources() {
	local kver="$1" dest="$cache/src/$1" repo commit work p n=0
	[[ -f $dest/.complete ]] && return 0
	parse_kver "$kver" || return 1
	repo="$(pkgs_git update)" || { log "cannot clone $pkgs_repo"; return 1; }
	commit="$(find_commit "$repo")" || { log "no omarchy-pkgs commit with linux-omarchy $ver-$rel"; return 1; }
	log "sources for $kver: $tag + omarchy-pkgs ${commit:0:10}"

	rm -rf "$cache"/work.* # leftovers of an interrupted run
	work="$(mktemp -d "$cache/work.XXXXXX")"
	git_net 600 -c advice.detachedHead=false clone -q --depth 1 --filter=blob:none --no-checkout --branch "$tag" "$stable_repo" "$work/src" 2>/dev/null &&
		git -C "$work/src" sparse-checkout set --no-cone /drivers/gpu/drm/xe/ /drivers/gpu/drm/i915/ &&
		git_net 600 -C "$work/src" checkout -q || { log "cannot fetch $stable_repo $tag"; return 1; }
	rm -rf "$work/src/.git"

	# Omarchy applies every *.patch of its source array in order with --fuzz=0.
	for p in $(git -C "$repo" show "$commit:pkgbuilds/linux-omarchy/PKGBUILD" | grep -oE '^\s+[0-9]{4}-[^ {]+\.patch' | tr -d ' \t'); do
		git -C "$repo" show "$commit:pkgbuilds/linux-omarchy/$p" | python3 "$here/filter-drm.py" >"$work/p.diff"
		[[ -s $work/p.diff ]] || continue
		patch -d "$work/src" -Np1 --fuzz=0 --quiet <"$work/p.diff" || { log "Omarchy patch $p does not apply"; return 1; }
		n=$((n + 1))
	done
	log "applied $n Omarchy xe/i915 patches"
	echo "$commit" >"$work/src/.omarchy-pkgs-commit"
	touch "$work/src/.complete"
	rm -rf "$dest" && mkdir -p "$cache/src" && mv "$work/src" "$dest"
	rm -rf "$work"
	# keep the three newest kernels
	ls -1dt "$cache"/src/*/ 2>/dev/null | tail -n +4 | xargs -r rm -rf
}

# symbol names, without compiler suffixes
syms() { nm --defined-only "$1" | awk '{print $3}' | sed -E 's/\.(cold|isra|constprop|part)\.?[0-9.]*//g' | sort -u; }

# check the patched module against the stock one of the same kernel
verify() {
	local kver="$1" built="$2" stock="" f tmp diffs
	for f in "/usr/lib/modules/$kver/kernel/drivers/gpu/drm/xe/xe.ko"{.zst,.xz,} \
		/var/lib/dkms/zenbook-duo-omarchy-xe/original_module/"$kver"/*/xe.ko{.zst,.xz,}; do
		[[ -f $f ]] && { stock="$f"; break; }
	done
	[[ -n $stock ]] || { log "WARNING: no stock xe.ko for $kver to compare with, skipping the check"; return 0; }
	tmp="$(mktemp --suffix=.ko)"
	case "$stock" in
	*.zst) zstd -dcq "$stock" >"$tmp" ;;
	*.xz) xz -dc "$stock" >"$tmp" ;;
	*) cp "$stock" "$tmp" ;;
	esac
	diffs="$(diff <(syms "$tmp") <(syms "$built") | grep -E '^[<>]' |
		grep -vE '^[<>] (\.L|__print_once|__UNIQUE_ID_|__func__|__already_done|__warned)' |
		grep -vE '^> (__pfx_)?(intel_cx0_request_tcss_power|intel_tc_request_tcss_power|xelpdp_tc_power_request_wa|zenbook_duo_edp2_tcss)$' |
		grep -vE '^> __param(_str)?_zenbook_duo_edp2_tcss$' || true)"
	if ! diff -q <(modinfo -p "$tmp" | grep -v zenbook_duo | sort) <(modinfo -p "$built" | grep -v zenbook_duo | sort) >/dev/null; then
		diffs+=$'\nmodule parameters differ'
	fi
	rm -f "$tmp"
	if [[ -n $diffs ]]; then
		log "the built xe differs from the stock one beyond the fix:"
		echo "$diffs" | head -20 >&2
		return 1
	fi
	log "checked against $stock: only the TCSS fix differs"
}

if [[ ${1:-} == --fetch ]]; then
	while read -r path; do
		kver="${path#usr/lib/modules/}"
		kver="${kver%%/*}"
		[[ $kver == *-omarchy ]] || continue
		sources "$kver" || log "could not prepare sources for $kver (the stock xe will be used)"
	done
	exit 0
fi

kver="$1" kdir="$2"
sources "$kver"
rm -rf src
cp -a "$cache/src/$kver" src
for p in "$here"/patches/*.patch; do
	patch -d src -Np1 --fuzz=0 --quiet <"$p" || { log "$(basename "$p") does not apply to $kver"; exit 1; }
done

# Out-of-tree build: xe compiles the display code from ../i915/display, and the
# trace headers point TRACE_INCLUDE_PATH at the in-tree location.
cd src/drivers/gpu/drm
sed -i 's|\$(srctree)/drivers/gpu/drm/i915/|$(src)/../i915/|g' xe/Makefile
sed -i 's|^#define TRACE_INCLUDE_PATH \.\./\.\./drivers/gpu/drm/.*|#define TRACE_INCLUDE_PATH .|' \
	xe/xe_trace*.h i915/display/intel_display_trace.h
llvm=()
grep -q '^CONFIG_CC_IS_CLANG=y' "$kdir/.config" && llvm=(LLVM=1)
make -C "$kdir" M="$PWD/xe" "${llvm[@]}" -j"$(nproc)" modules
verify "$kver" "$PWD/xe/xe.ko"
