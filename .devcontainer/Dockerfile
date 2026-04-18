FROM debian:12-slim

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install base tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essentials
    build-essential \
    curl \
    wget \
    ca-certificates \
    git \
    openssh-client \
    # Jupyter
    python3 \
    python3-dev \
    python3-ipykernel \
    python3-nbconvert \
    jupyter-notebook \
    ipython3 \
    python3-ipdb \
    black \
    python3-isort \
    python3-flake8 \
    python3-pytest \
    python3-numpy \
    python3-pandas \
    python3-matplotlib \
    # Node
    nodejs \
    npm \
    node-typescript \
    # Debian Image generation Dependencies
    debootstrap \
    ostree \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Install npm-based tooling used in notebooks and scripts.
# npx is available from the apt-installed npm package, so only install additional CLI tools here.
RUN npm install -g tslab cytoscape html-minifier ts-node @types/node && tslab install --python=/usr/bin/python3

# Workspace folder
WORKDIR /workspace

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
