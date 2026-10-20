#!/usr/bin/env bash
# Install the AVMatrix VC12-4K driver (HwsUHDX1Capture) through DKMS.
#
# Copies the sources to /usr/src/HwsUHDX1CaptureForLinux-<version>, then
# builds and installs the module for every installed kernel that has its
# headers. DKMS rebuilds it for kernels installed later. Run it again to
# reinstall; uninstall.sh removes everything this or older installers put
# on the system.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -- "$0" "$@"

NAME=HwsUHDX1CaptureForLinux
MODULE=HwsUHDX1Capture
HERE=$(cd "$(dirname "$0")" && pwd)
VER=$(sed -n 's/^PACKAGE_VERSION=//p' "$HERE/src/dkms.conf")
[ -n "$VER" ] || { echo "no PACKAGE_VERSION in $HERE/src/dkms.conf" >&2; exit 1; }

# in a subshell: os-release defines NAME too
# shellcheck source=/dev/null
os=$(. /etc/os-release 2>/dev/null; echo "${ID:-} ${ID_LIKE:-}")
hint() {
    case " $os " in
        *" fedora "*|*" rhel "*|*" centos "*) echo "sudo dnf install dkms gcc make kernel-devel-$(uname -r)" ;;
        *" debian "*|*" ubuntu "*) echo "sudo apt install dkms gcc make linux-headers-$(uname -r)" ;;
        *" arch "*) echo "sudo pacman -S dkms gcc make linux-headers" ;;
        *) echo "install dkms, gcc, make and the headers for kernel $(uname -r)" ;;
    esac
}
for tool in dkms make gcc; do
    command -v "$tool" >/dev/null || { echo "$tool is missing. Install the build tools first:" >&2; hint >&2; exit 1; }
done
if [ ! -e "/lib/modules/$(uname -r)/build/Makefile" ]; then
    echo "The headers for the running kernel ($(uname -r)) are missing. Install them first:" >&2
    hint >&2
    exit 1
fi

src=/usr/src/$NAME-$VER
echo "Installing $NAME $VER"
if [ -d "/var/lib/dkms/$NAME/$VER" ]; then
    echo "  removing the earlier install of $VER"
    dkms remove -m "$NAME" -v "$VER" --all >/dev/null
fi
rm -rf "$src"
mkdir -p "$src"
# sources only: build output in the tree would be reused instead of compiled
find "$HERE/src" -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' -o -name Makefile -o -name dkms.conf \) \
    ! -name '*.mod.c' -exec cp -t "$src" {} +
dkms add -m "$NAME" -v "$VER" >/dev/null

built=()
for kb in /lib/modules/*/build; do
    k=$(basename "$(dirname "$kb")")
    if [ ! -e "$kb/Makefile" ]; then
        echo "  skipping kernel $k: its headers aren't installed"
        continue
    fi
    echo "  building for kernel $k"
    if ! dkms install -m "$NAME" -v "$VER" -k "$k" --force >/dev/null 2>&1; then
        echo "  build failed for $k; the log is under /var/lib/dkms/$NAME/$VER/build/make.log" >&2
        exit 1
    fi
    built+=("$k")
done
echo "Installed for: ${built[*]}"

# Secure Boot only loads modules signed with an enrolled key.
if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
    key=""
    for k in /var/lib/dkms/mok.pub /var/lib/shim-signed/mok/MOK.der; do
        [ -e "$k" ] && { key=$k; break; }
    done
    if [ -n "$key" ] && ! mokutil --test-key "$key" 2>/dev/null | grep -qi "is already enrolled"; then
        cat <<EOF

Secure Boot is on, and the key DKMS signs the module with isn't enrolled yet:
  1. sudo mokutil --import $key
     (choose a one-time password)
  2. Reboot. In the blue MOK manager screen choose "Enroll MOK", then
     "Continue", "Yes", enter that password, and reboot.
Until then the kernel refuses the module ("Key was rejected by service").
EOF
    elif [ -z "$key" ]; then
        echo
        echo "Secure Boot is on, but no DKMS signing key was found; see the README."
    fi
fi

if [ -d "/sys/module/$MODULE" ]; then
    echo "An older version of the driver is loaded. Reboot to use $VER."
elif modprobe "$MODULE" 2>/dev/null; then
    echo "Loaded. Check with: v4l2-ctl --list-devices; arecord -l"
else
    echo "Not loaded yet. Reboot, or run: sudo modprobe $MODULE"
fi
