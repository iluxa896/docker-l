#!/usr/bin/env bash
#
# Production-ready Swap Setup Script for Ubuntu / Debian
# Configures a 2GB swap file with hardened permissions and optimized swappiness.
#
set -euo pipefail

SWAP_FILE="/swapfile"
SWAP_SIZE="${1:-2G}"
SWAPPINESS_VALUE=10
VFS_CACHE_PRESSURE=50

echo "=================================================="
echo " Starting Swap Setup for Ubuntu"
echo "=================================================="

# 1. Require root / sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (use sudo)." >&2
    exit 1
fi

# 2. Check if swap is already active
CURRENT_SWAP=$(swapon --show --noheadings || true)
if [ -n "$CURRENT_SWAP" ]; then
    echo "[!] Active swap detected:"
    swapon --show
    echo "[!] Swap is already configured. Exiting to avoid duplicate swap."
    exit 0
fi

# 3. Check if /swapfile already exists on disk
if [ -f "$SWAP_FILE" ]; then
    echo "[!] File $SWAP_FILE already exists. Removing old unmounted file..."
    rm -f "$SWAP_FILE"
fi

# 4. Allocate swap file space (fallocate with dd fallback)
echo "[+] Allocating ${SWAP_SIZE} for ${SWAP_FILE}..."
if ! fallocate -l "$SWAP_SIZE" "$SWAP_FILE" 2>/dev/null; then
    echo "[*] fallocate failed (possibly unsupported filesystem), falling back to dd..."
    # Convert standard size strings (e.g. 2G -> 2048M)
    COUNT_MB=2048
    if [[ "$SWAP_SIZE" =~ ^([0-9]+)G$ ]]; then
        COUNT_MB=$((${BASH_REMATCH[1]} * 1024))
    elif [[ "$SWAP_SIZE" =~ ^([0-9]+)M$ ]]; then
        COUNT_MB=${BASH_REMATCH[1]}
    fi
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$COUNT_MB" status=progress
fi

# 5. Security: Restrict permissions (strict root only)
echo "[+] Setting strict permissions (chmod 600)..."
chmod 600 "$SWAP_FILE"

# 6. Format swap
echo "[+] Formatting ${SWAP_FILE} as swap area..."
mkswap "$SWAP_FILE"

# 7. Activate swap
echo "[+] Activating swap with swapon..."
swapon "$SWAP_FILE"

# 8. Persist in /etc/fstab for auto-mount on reboot
echo "[+] Configuring persistence in /etc/fstab..."
if ! grep -q "^$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    echo "[+] Added ${SWAP_FILE} to /etc/fstab."
else
    echo "[*] ${SWAP_FILE} already present in /etc/fstab."
fi

# 9. Tune kernel parameters (swappiness & cache pressure)
echo "[+] Tuning kernel parameters in /etc/sysctl.d/99-swap.conf..."
cat <<EOF > /etc/sysctl.d/99-swap.conf
# Keep swappiness low on low-RAM servers to prioritize fast RAM
vm.swappiness=${SWAPPINESS_VALUE}
# Balance inode/dentry cache reclamation
vm.vfs_cache_pressure=${VFS_CACHE_PRESSURE}
EOF

sysctl -p /etc/sysctl.d/99-swap.conf >/dev/null

echo "=================================================="
echo " Swap Configuration Completed Successfully!"
echo "=================================================="
echo ""
echo "Active Swap Devices:"
swapon --show
echo ""
echo "Current Memory Status:"
free -h
echo ""
echo "Swappiness value: $(cat /proc/sys/vm/swappiness)"
