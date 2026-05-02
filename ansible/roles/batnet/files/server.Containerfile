ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite:stable"
FROM ${BASE_IMAGE}

# Define the build-time variables with default values
ARG RPMFUSION_BASE_URL="https://mirrors.rpmfusion.org"
ARG VSCODE_REPO_URL="https://packages.microsoft.com/yumrepos/vscode"
ARG VSCODE_GPG_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
ARG DS_DM_PASSWORD="admin"
ARG SUFFIX_NAME="dc=lmpriestley,dc=com"

# Enable third party repositories
RUN rpm --import ${VSCODE_GPG_KEY_URL} && \
    cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=${VSCODE_REPO_URL}
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=${VSCODE_GPG_KEY_URL}
EOF

# Set global DNF defaults so all package operations use parallel downloads.
RUN grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf && \
    sed -i 's/^max_parallel_downloads=.*/max_parallel_downloads=20/' /etc/dnf/dnf.conf || \
    printf '\nmax_parallel_downloads=20\n' >> /etc/dnf/dnf.conf

RUN dnf install -y \
    ${RPMFUSION_BASE_URL}/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    ${RPMFUSION_BASE_URL}/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    dnf copr enable lizardbyte/beta -y

# Install RPM Packages
RUN dnf install -y git neovim code steam bottles sunshine rustup openssh-server firefox ansible zsh && dnf clean all

# Make zsh the default login shell for all valid users.
RUN if ! grep -q "^$(command -v zsh)$" /etc/shells; then echo "$(command -v zsh)" >> /etc/shells; fi && \
    awk -F: '($7 !~ /(nologin|false)$/){print $1}' /etc/passwd | xargs -r -n1 sh -c 'usermod -s "$(command -v zsh)" "$0"'

# Enable SSH daemon so Cockpit can connect to this machine over SSH.
RUN systemctl enable sshd.service

# Install and configure 389ds as a Quadlet
RUN mkdir -p /usr/share/containers/systemd/ && \
    cat <<EOF > /usr/share/containers/systemd/389ds.container
[Unit]
Description=389 Directory Server (LDAP)
After=network-online.target
Wants=network-online.target

[Container]
Image=quay.io/389ds/dirsrv:latest
ContainerName=389ds-ldap
PublishPort=3389:3389
PublishPort=3636:3636
Volume=/var/srv/389ds:/data:Z
Environment=DS_DM_PASSWORD=${DS_DM_PASSWORD}
Environment=SUFFIX_NAME=${SUFFIX_NAME}

[Service]
ExecStartPre=/usr/bin/install -d -o 389 -g 389 -m 0750 /var/srv/389ds
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Install and configure Cockpit Web Service as a separate Quadlet
RUN mkdir -p /usr/share/containers/systemd/ && \
    cat <<EOF > /usr/share/containers/systemd/cockpit.container
[Unit]
Description=Cockpit Web Service
After=network-online.target
Wants=network-online.target

[Container]
Image=quay.io/cockpit/ws:latest
ContainerName=cockpit-ws
PublishPort=9090:9090

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
EOF

## Verify final image and contents are correct.
RUN bootc container lint
