#!/bin/bash
#
# Install the software needed to deploy cluster stacks from this VM
#
# (c) Kurt Garloff <s7n@garloff.de>, 2/2025
# SPDX-License-Identifier: CC-BY-SA-4.0

# Detect architecture and OS
ARCH=$(uname -m)
ARCH="${ARCH/x86_64/amd64}"
OS=$(uname -s | tr A-Z a-z)

# Detect distribution details from os-release
if [ -f /etc/os-release ]; then
    # Load variables from os-release file
    . /etc/os-release
    OS_ID=$ID
    OS_VERSION_ID=$VERSION_ID
    OS_ID_LIKE=$ID_LIKE
else
    # Fallback to basic detection
    OS_ID="unknown"
    OS_VERSION_ID="unknown"
    OS_ID_LIKE=""
fi

echo "Detected OS: $OS_ID $OS_VERSION_ID"

# Usage: install_via_pkgmgr pkgnm [pkgnm [...]]
install_via_pkgmgr()
{
    echo "Installing packages: $@"
    sudo $INSTCMD "$@" || { echo "Failed to install packages: $@"; return 1; }
    echo "Successfully installed packages: $@"
}

# Verify sha256sum
test_sha256()
{
    OUT=$(sha256sum "$1")
    OUT=${OUT%% *}
    if test "$OUT" != "$2"; then 
        echo "ERROR: Checksum mismatch for ${1}" 1>&2
        echo "Expected: $2" 1>&2
        echo "Got:      $OUT" 1>&2
        return 1
    else 
        echo "Checksum verified for ${1}"
        return 0 
    fi
}

# Usage install_via_download_bin URL sha256 [newname]
install_via_download_bin()
{
    cd ~/Download || { echo "ERROR: Failed to cd into ~/Download"; return 1; }
    echo "Downloading $1..."
    curl -LO "$1" || { echo "ERROR: Failed to download $1"; return 1; }
    FNM="${1##*/}"
    if ! test_sha256 "$FNM" "$2"; then return 1; fi
    chmod +x "$FNM" || { echo "ERROR: Failed to set executable permissions on $FNM"; return 1; }
    
    # Determine target filename
    local TARGET="/usr/local/bin/${FNM}"
    if [ -n "$3" ] && [ "$3" != "." ]; then
        TARGET="/usr/local/bin/$3"
    fi
    
    echo "Moving $FNM to $TARGET"
    sudo mv "$FNM" "$TARGET" || { echo "ERROR: Failed to move $FNM to $TARGET"; return 1; }
    echo "Successfully installed $TARGET"
}

# Usage install_via_download_tgz URL sha256 extrpath [newname]
install_via_download_tgz()
{
    cd ~/Download || { echo "ERROR: Failed to cd into ~/Download"; return 1; }
    echo "Downloading $1..."
    curl -LO "$1" || { echo "ERROR: Failed to download $1"; return 1; }
    FNM="${1##*/}"
    if ! test_sha256 "$FNM" "$2"; then return 1; fi
    
    echo "Extracting $FNM..."
    tar xzf "$FNM" || { echo "ERROR: Failed to extract $FNM"; return 1; }
    
    # Determine target filename
    local TARGET="/usr/local/bin/${3##*/}"
    if [ -n "$4" ] && [ "$4" != "." ]; then
        TARGET="/usr/local/bin/$4"
    fi
    
    echo "Moving $3 to $TARGET"
    sudo mv "$3" "$TARGET" || { 
        echo "ERROR: Failed to move $3 to $TARGET"; 
        echo "Looking for file to move...";
        find . -name "${3##*/}" -type f;
        return 1; 
    }
    echo "Successfully installed $TARGET"
}

# Ensure the Download directory exists and is writable
echo "Creating Download directory if needed..."
mkdir -p ~/Download
if [ ! -d ~/Download ]; then
    echo "ERROR: Could not create ~/Download directory"
    exit 1
fi
# Make sure we have write permissions
touch ~/Download/.write_test && rm ~/Download/.write_test || {
    echo "ERROR: Cannot write to ~/Download directory"
    exit 1
}

# Set up package manager command
INSTCMD="apt-get install -y --no-install-recommends --no-install-suggests"

# Define package list with conditional logic for Docker based on distribution
if [ "$OS_ID" = "ubuntu" ]; then
    echo "Setting up Docker repository for Ubuntu..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin golang jq git gh python3-openstackclient)
elif [ "$OS_ID" = "debian" ] || [[ "$OS_ID_LIKE" == *"debian"* ]]; then
    echo "Using Debian package sources..."
    PACKAGES=(docker.io golang jq git gh python3-openstackclient)
else
    echo "Using default package list for unknown distribution..."
    PACKAGES=(docker.io golang jq git gh python3-openstackclient)
fi

# Define binary downloads with their checksums
TARBALLS=("https://get.helm.sh/helm-v3.17.1-${OS}-${ARCH}.tar.gz")
TARBALL_CHECKSUMS=("3b66f3cd28409f29832b1b35b43d9922959a32d795003149707fea84cbcd4469")
TARBALL_EXTRACT_PATHS=("${OS}-${ARCH}/helm")
TARBALL_NEW_NAMES=(".")

BINARIES=("https://github.com/kubernetes-sigs/kind/releases/download/v0.26.0/kind-${OS}-${ARCH}"
          "https://dl.k8s.io/release/v1.31.6/bin/${OS}/${ARCH}/kubectl"
          "https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.9.4/clusterctl-${OS}-${ARCH}")
BINARY_CHECKSUMS=("d445b44c28297bc23fd67e51cc24bb294ae7b977712be2d4d312883d0835829b"
                  "c46b2f5b0027e919299d1eca073ebf13a4c5c0528dd854fc71a5b93396c9fa9d"
                  "0c80a58f6158cd76075fcc9a5d860978720fa88860c2608bb00944f6af1e5752")
BINARY_NEW_NAMES=("kind" "." "clusterctl")

# Update package lists
echo "Updating package lists..."
sudo apt-get update

# Install packages
echo "Installing required packages..."
install_via_pkgmgr "${PACKAGES[@]}" || exit 1

# Install tools from tarballs
echo "Installing tools from tarballs..."
for i in $(seq 0 $((${#TARBALLS[*]}-1))); do
    echo "Processing tarball ${TARBALLS[$i]}..."
    install_via_download_tgz "${TARBALLS[$i]}" "${TARBALL_CHECKSUMS[$i]}" "${TARBALL_EXTRACT_PATHS[$i]}" "${TARBALL_NEW_NAMES[$i]}" || exit 2
done

# Install binary tools
echo "Installing binary tools..."
for i in $(seq 0 $((${#BINARIES[*]}-1))); do
    echo "Processing binary ${BINARIES[$i]}..."
    install_via_download_bin "${BINARIES[$i]}" "${BINARY_CHECKSUMS[$i]}" "${BINARY_NEW_NAMES[$i]}" || exit 3
done

# Install envsubst
echo "Installing envsubst..."
GOBIN=/tmp go install github.com/drone/envsubst/v2/cmd/envsubst@latest
sudo mv /tmp/envsubst /usr/local/bin/

# Set up bash aliases if they don't exist
echo "Setting up bash aliases..."
if [ ! -e ~/.bash_aliases ]; then
    echo -e "alias ll='ls -lF'\nalias k=kubectl" > ~/.bash_aliases
    echo "Created ~/.bash_aliases file"
fi

# Set up Docker group
echo "Adding current user to Docker group..."
# First check if docker group exists
if getent group docker > /dev/null; then
    # Add user to docker group - different syntax for Ubuntu vs Debian
    if [ "$OS_ID" = "ubuntu" ]; then
        echo "Using Ubuntu-specific command to add user to docker group..."
        sudo usermod -aG docker $(whoami)
    else
        echo "Using Debian-specific command to add user to docker group..."
        sudo groupmod -a -U $(whoami) docker
    fi
    echo "User $(whoami) added to docker group"
else
    echo "Docker group does not exist. Creating docker group first..."
    sudo groupadd docker
    echo "Adding user $(whoami) to docker group..."
    sudo usermod -aG docker $(whoami)
    echo "User $(whoami) added to docker group"
fi

echo "Note: You may need to log out and back in for group changes to take effect"

# Start Docker
echo "Enabling and starting Docker service..."
sudo systemctl enable --now docker

echo "Installation complete! You may need to log out and back in for group changes to take effect."

