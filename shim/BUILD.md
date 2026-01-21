# BUILD.md

# Build the docker image:
docker build --network host -t pico8-arm-env .
# to open a shell in the docker instance:
docker run --rm -it --platform linux/arm64 --network host -v ${PWD}:/shim pico8-arm-env
# to build directly:
docker run --rm -it --platform linux/arm64 --network host -v ${PWD}:/shim -w /shim pico8-arm-env /bin/bash -c "./build.sh"
