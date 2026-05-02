ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite:stable"
FROM ${BASE_IMAGE}

# Define build-time variables with default values.
ARG RPMFUSION_BASE_URL="https://mirrors.rpmfusion.org"
ARG VSCODE_REPO_URL="https://packages.microsoft.com/yumrepos/vscode"
ARG VSCODE_GPG_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"

# Enable third-party repositories.
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

# Client image packages.
RUN dnf install -y \
    git \
    neovim \
    code \
    steam \
    bottles \
    sunshine \
    rustup \
    openssh-server \
    ansible \
    firefox \
    && dnf clean all


# Verify final image and contents are correct.
RUN bootc container lint
