FROM docker.io/library/debian:unstable AS base
ARG NVIDIA_ENABLED="false"
ARG SYSTEM_PACKAGES="btrfs-progs code dosfstools e2fsprogs fdisk firmware-linux-free linux-image-generic skopeo systemd systemd-boot* xfsprogs libostree-dev zsh"
ARG NVIDIA_PACKAGES="nvidia-driver nvidia-smi firmware-misc-nonfree"
ARG DESKTOP_PACKAGES="kde-plasma-desktop plasma-workspace-wayland sddm xorg xwayland plasma-nm powerdevil bluedevil"
ARG USER_PACKAGES="firefox rustup steam bottles sunshine"
ARG DEV_PACKAGES="ansible git make neovim openssh-server"

FROM base AS builder

# Install build toolchain and bootc build dependencies.
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root --mount=type=tmpfs,dst=/boot \
    apt update -y && \
    apt install -y git curl make build-essential go-md2man libzstd-dev pkgconf dracut libostree-dev ostree

ENV CARGO_HOME=/tmp/rust
ENV RUSTUP_HOME=/tmp/rust
WORKDIR /home/build
# Build bootc from source and stage binaries into /output.
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root --mount=type=tmpfs,dst=/boot \
    curl --proto '=https' --tlsv1.2 -sSf "https://sh.rustup.rs" | sh -s -- --profile minimal -y && \
    bash -xeuo pipefail -c '. ${RUSTUP_HOME}/env ; git clone "https://github.com/bootc-dev/bootc.git" . ; make bin install-all DESTDIR=/output'

FROM base AS system
ARG NVIDIA_ENABLED
ARG SYSTEM_PACKAGES
ARG NVIDIA_PACKAGES
ARG DESKTOP_PACKAGES
ARG USER_PACKAGES
ARG DEV_PACKAGES
COPY --from=builder /output /

# Enable contrib, non-free, and non-free-firmware APT components.
RUN if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then \
        sed -i '/^Components:/ { /contrib/! s/$/ contrib/; /non-free /! s/$/ non-free/; /non-free-firmware/! s/$/ non-free-firmware/; }' /etc/apt/sources.list.d/debian.sources ; \
    elif [[ -f /etc/apt/sources.list ]]; then \
        sed -i 's/^deb \(.*\) main$/deb \1 main contrib non-free non-free-firmware/' /etc/apt/sources.list ; \
    fi

# Enable 32-bit (i386) architecture for Steam and other 32-bit applications.
RUN dpkg --add-architecture i386

# Configure VS Code APT repo and install all packages in a single pass.
# First update bootstraps ca-certificates/gpg/wget; second picks up the VS Code repo.
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root --mount=type=tmpfs,dst=/boot \
    apt update -y && \
    apt install -y ca-certificates gpg wget && \
    install -d -m 0755 /etc/apt/keyrings && \
    arch="$(dpkg --print-architecture)" && \
    wget -qO- "https://packages.microsoft.com/keys/microsoft.asc" | gpg --dearmor > /etc/apt/keyrings/packages.microsoft.gpg && \
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list && \
    apt update -y && \
    apt install -y ${SYSTEM_PACKAGES} ${DESKTOP_PACKAGES} ${USER_PACKAGES} ${DEV_PACKAGES} && \
    cp /boot/vmlinuz-* "$(find /usr/lib/modules -maxdepth 1 -type d | tail -n 1)/vmlinuz" && \
    if [[ "${NVIDIA_ENABLED}" == "true" ]]; then apt install -y ${NVIDIA_PACKAGES}; fi && \
    apt clean -y

# Enable graphical login via SDDM.
RUN systemctl enable sddm

# Make zsh the default login shell for all valid users.
RUN if ! grep -q "^$(command -v zsh)$" /etc/shells; then echo "$(command -v zsh)" >> /etc/shells; fi && \
    awk -F: '($7 !~ /(nologin|false)$/){print $1}' /etc/passwd | xargs -r -n1 sh -c 'usermod -s "$(command -v zsh)" "$0"'

# Generate an initramfs with bootc dracut settings.
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    bash -xeuo pipefail -c 'mkdir -p /usr/lib/dracut/dracut.conf.d/ ; printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf ; printf "reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=\" bootc \"" | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf" ; dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img"'

# Normalize filesystem layout for bootc and prepare OSTree root settings.
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    bash -xeuo pipefail -c 'rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg ; mkdir -p /sysroot /boot /usr/lib/ostree /var ; ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local ; echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" ; printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" ; printf "[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n" | tee "/usr/lib/ostree/prepare-root.conf"'

# Validate the final container image layout with bootc lint.
RUN bootc container lint
