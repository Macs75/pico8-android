gcc -g -shared -fPIC -ldl -O3 -o picoshim.so shim.c && chmod +x package/rootfs/home/pico/wget && echo BUILT!
