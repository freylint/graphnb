FROM docker.io/library/debian:unstable AS base
ARG NVIDIA_ENABLED=false

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
LABEL ostree.bootable=true
COPY --from=builder /output /

# Enable contrib, non-free, and non-free-firmware APT components.
RUN if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i '/^Components:/ { /contrib/! s/$/ contrib/; /non-free /! s/$/ non-free/; /non-free-firmware/! s/$/ non-free-firmware/; }' /etc/apt/sources.list.d/debian.sources ; \
    elif [ -f /etc/apt/sources.list ]; then \
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
    apt install -y \
        btrfs-progs code dosfstools e2fsprogs fdisk firmware-linux-free \
        linux-image-generic skopeo systemd systemd-boot xfsprogs libostree-dev zsh \
        kde-plasma-desktop sddm xorg xwayland plasma-nm powerdevil bluedevil \
        firefox flatpak rustup steam \
        ansible git make neovim openssh-server && \
    apt remove --purge -y konsole && \
    cp /boot/vmlinuz-* "$(find /usr/lib/modules -maxdepth 1 -type d | tail -n 1)/vmlinuz" && \
    if [ "${NVIDIA_ENABLED}" = "true" ]; then \
        apt install -y nvidia-driver nvidia-smi firmware-misc-nonfree; \
    fi && \
    apt clean -y

# Enable graphical login via SDDM.
RUN systemctl enable sddm

# Make zsh the default login shell for all valid users.
RUN if ! grep -q "^$(command -v zsh)$" /etc/shells; then echo "$(command -v zsh)" >> /etc/shells; fi && \
    awk -F: '($7 !~ /(nologin|false)$/){print $1}' /etc/passwd | xargs -r -n1 sh -c 'usermod -s "$(command -v zsh)" "$0"'

# Install oh-my-zsh system-wide with autosuggestions and syntax-highlighting plugins.
# ZSH_CACHE_DIR is set in /etc/zsh/zshrc (sourced before ~/.zshrc) so it resolves to a
# user-writable path; /usr/share is read-only on the deployed system.
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /usr/share/oh-my-zsh && \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /usr/share/oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /usr/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    cp /usr/share/oh-my-zsh/templates/zshrc.zsh-template /etc/skel/.zshrc && \
    sed -i \
        -e 's|^export ZSH=.*|export ZSH=/usr/share/oh-my-zsh|' \
        -e 's|^plugins=(.*)$|plugins=(git z sudo history zsh-autosuggestions zsh-syntax-highlighting)|' \
        /etc/skel/.zshrc && \
    printf '\nHISTSIZE=10000\nSAVEHIST=10000\nsetopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY\n' >> /etc/skel/.zshrc && \
    printf '\nexport ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"\nmkdir -p "$ZSH_CACHE_DIR"\n' >> /etc/zsh/zshrc

# Install WezTerm wrapper, register it as the system default terminal, and add shell aliases.
RUN printf '#!/bin/sh\nexec flatpak run org.wezfurlong.wezterm "$@"\n' > /usr/bin/wezterm && \
    chmod +x /usr/bin/wezterm && \
    update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/wezterm 50 && \
    printf '\nalias terminal=wezterm\nalias term=wezterm\n' >> /etc/zsh/zshrc

# Pre-configure Flathub and schedule flatpak app installs for first boot.
# Remote definition goes in /etc (OS tree) so it survives normalization and upgrades.
# Apps are installed by a oneshot service on first boot to avoid overlay-fs O_TMPFILE
# limitations in the container build environment.
RUN mkdir -p /etc/flatpak/remotes.d && \
    wget -qO /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo && \
    printf '[Unit]\nDescription=Install Flathub applications on first boot\nAfter=network-online.target\nWants=network-online.target\nConditionFirstBoot=yes\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/flatpak install -y --system flathub org.wezfurlong.wezterm dev.lizardbyte.app.Sunshine com.usebottles.bottles\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\n' > /usr/lib/systemd/system/flatpak-install-apps.service && \
    systemctl enable flatpak-install-apps.service

# Generate an initramfs with bootc dracut settings.
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    bash -xeuo pipefail -c 'mkdir -p /usr/lib/dracut/dracut.conf.d/ ; printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf ; printf "reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=\" bootc \"" | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf" ; dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img"'

# Normalize filesystem layout for bootc and prepare OSTree root settings.
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    bash -xeuo pipefail -c 'rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg ; mkdir -p /sysroot /boot /usr/lib/ostree /var ; ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local ; echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" ; printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" ; printf "[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n" | tee "/usr/lib/ostree/prepare-root.conf"'

# Validate the final container image layout with bootc lint.
RUN bootc container lint
