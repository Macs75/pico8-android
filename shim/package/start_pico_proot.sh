#!/usr/bin/busybox ash
ROOTFS_LOCATION=$(pwd)/rootfs

echo "Host script started at $(date)"

# Ensure tmp directory exists
LD_LIBRARY_PATH=. ./busybox mkdir -p tmp

# Create PICO-8 pipes on HOST filesystem (bound to /tmp in proot) if they don't exist
[ -p tmp/pico8.vid ] || LD_LIBRARY_PATH=. ./busybox mkfifo tmp/pico8.vid
[ -p tmp/pico8.in ] || LD_LIBRARY_PATH=. ./busybox mkfifo tmp/pico8.in
chmod 666 tmp/pico8.vid tmp/pico8.in


# Running pulsar.sh in background, logging to PUBLIC log directory
LOG_DIR="/sdcard/Documents/pico8/logs"
mkdir -p "$LOG_DIR"
LD_LIBRARY_PATH=. ./busybox ash pulsar.sh > "$LOG_DIR/pulse.log" 2>&1 &


while [ ! -d tmp/pulse ]; do
    sleep 0.02
done

# Open File Descriptor 9 to current directory (package)
# This allows proot to access the loader via /proc/self/fd/9/prootlb regardless of CWD.
# AND allows binding the tmp subdir for Video.
exec 9< .

# Open FD 7 to the DIRECTORY 'tmp'
# Back to the strategy that worked for Internal Storage Audio
exec 7< tmp/pulse

# FIX: Use File Descriptor 8 for PROOT_TMP_DIR
# This bypasses the UNIX socket path limit (108 chars) on Adoptable Storage.
# 1. Create directory
# 2. Open FD 8 to it
# 3. Use /proc/self/fd/8 as the path (short & absolute)
mkdir -p ptmp
exec 8< ./ptmp

PROOT_TMP_DIR="/proc/self/fd/8"
# Patch proot binary to use FD path for loader (23 chars target + 22 slashes padding = 45 chars total)
LD_LIBRARY_PATH=. ./busybox sed -i 's|/data/data/com.termux/files/usr/libexec/proot|///////////////////////proc/self/fd/9/prootlb|g' ./proot

echo "Using FD 8 strategy for tmp: $PROOT_TMP_DIR"

LD_LIBRARY_PATH=. PROOT_TMP_DIR=$PROOT_TMP_DIR ./proot \
    -p \
    -L \
    --kernel-release=6.2.1-Pico8-Shim \
    --sysvipc \
    --link2symlink \
    --kill-on-exit \
    --cwd=/home/pico/pico-8 \
    --bind=.:/package \
    --bind=$(pwd) \
    --bind=/system \
    --bind=/linkerconfig/ld.config.txt \
    --bind=/linkerconfig/com.android.art/ld.config.txt \
    --bind=/apex \
    --bind=/proc/self/fd/9/tmp:/tmp \
    --bind=/proc/self/fd/7:/tmp/pulse \
    --bind=/dev --bind=/sys --bind=/proc \
    --bind=/sdcard/Documents/pico8:/home/public \
    ${PROOT_EXTRA_BIND:+"$PROOT_EXTRA_BIND"} \
    ${PROOT_ROOT_BIND:+"$PROOT_ROOT_BIND"} \
    ${PROOT_BBS_BIND:+"$PROOT_BBS_BIND"} \
    --rootfs=$ROOTFS_LOCATION \
    /usr/bin/busybox env PATH=/usr/bin /usr/bin/busybox ash /home/pico/start_pico.sh "$@"

#echo "quit-daemon" > tmp/xdgopen
