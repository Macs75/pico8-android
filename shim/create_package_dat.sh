#!/bin/bash
# Run this inside your ARM64 Docker container

DIST_DIR="/shim/pico8_dist"
ROOTFS="$DIST_DIR/rootfs"

# 1. Create the directory structure
mkdir -p $DIST_DIR/prootlb $DIST_DIR/pulselibs $ROOTFS/usr/lib/aarch64-linux-gnu
mkdir -p $ROOTFS/lib/aarch64-linux-gnu

# 2. Install necessary packages to harvest files
apt-get update
apt-get install -y proot bash busybox pulseaudio libtalloc2 libreadline8 libncursesw6 libiconv-hook1

# 3. Copy the Main Binaries
cp /usr/bin/proot $DIST_DIR/
cp /bin/bash $DIST_DIR/
cp /bin/busybox $DIST_DIR/
cp /usr/bin/pulseaudio $DIST_DIR/

# 4. Copy the Core Loader (shown in your second image)
cp /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 $ROOTFS/lib/

# 5. Copy the Shared Libraries to rootfs/usr/lib
# These are the ones PICO-8 and PRoot need to function
LIBS=(
    "libtalloc.so.2"
    "libreadline.so.8"
    "libncursesw.so.6"
    "libiconv.so.2"
    "libbusybox.so.1.37.0"
)

for lib in "${LIBS[@]}"; do
    find /lib /usr/lib -name "$lib*" -exec cp {} $ROOTFS/usr/lib/aarch64-linux-gnu/ \;
done

echo "Environment harvested in $DIST_DIR"
