# Use ARM64 Ubuntu
FROM --platform=linux/arm64 ubuntu:24.04

# Prevent interactive prompts during install
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt update && apt install -y \
    build-essential \
    libsdl2-dev \
    pkg-config \
    file

WORKDIR /shim