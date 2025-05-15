#!/bin/bash
#
# Install the software needed to deploy cluster stacks from this VM
#
# (c) Kurt Garloff <s7n@garloff.de>, 2/2025
# SPDX-License-Identifier: CC-BY-SA-4.0

# ToDo: Magic to switch b/w apt, zypper, dnf, pacman, ...
ARCH=$(uname -m)
ARCH="${ARCH/x86_64/amd64}"
OS=$(uname -s | tr A-Z a-z)

# Usage: install_via_pkgmgr pkgnm [pkgnm [...]]
install_via_pkgmgr()
{
	sudo $INSTCMD "$@"
}

# Verify sha256sum
test_sha256()
{
	OUT=$(sha256sum "$1")
	OUT=${OUT%% *}
	if test "$OUT" != "$2"; then return 1; else return 0; fi
}

# Usage install_via_download_bin URL sha256 [newname]
install_via_download_bin()
{
	cd ~/Download || { echo "ERROR: Failed to cd into ~/Download"; return 1; }
	echo "Downloading $1..."
	curl -LO "$1" || { echo "ERROR: Failed to download $1"; return 1; }
	FNM="${1##*/}"
	if ! test_sha256 "$FNM" "$2"; then echo "ERROR: Checksum mismatch for ${FNM}" 1>&2; return 1; fi
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

# Usage install_via_download_bin URL sha256 extrpath [newname]
install_via_download_tgz()
{
	cd ~/Download || { echo "ERROR: Failed to cd into ~/Download"; return 1; }
	echo "Downloading $1..."
	curl -LO "$1" || { echo "ERROR: Failed to download $1"; return 1; }
	FNM="${1##*/}"
	if ! test_sha256 "$FNM" "$2"; then echo "ERROR: Checksum mismatch for ${FNM}" 1>&2; return 1; fi
	
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

# Debian 12 (Bookworm)
mkdir -p ~/Download
# Ensure Download directory exists and is accessible
if [ ! -d ~/Download ]; then
    echo "Failed to create ~/Download directory, creating it again"
    mkdir -p ~/Download
    if [ ! -d ~/Download ]; then
        echo "ERROR: Could not create ~/Download directory"
        exit 1
    fi
fi
# Make sure we have write permissions
touch ~/Download/.write_test && rm ~/Download/.write_test
INSTCMD="apt-get install -y --no-install-recommends --no-install-suggests"

# Detect Ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
else
    OS_NAME="unknown"
    OS_VERSION="unknown"
fi

# Set packages based on OS version
if [ "$OS_NAME" = "ubuntu" ] && [ "$OS_VERSION" = "22.04" ]; then
    echo "Detected Ubuntu 22.04"
    # For Ubuntu 22.04, use Docker's official repository instead of docker.io
    echo "Setting up Docker repository..."
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    DEB12_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin golang jq git gh python3-openstackclient)
else
    echo "Using default package list for Debian 12 or other distributions"
    DEB12_PKGS=(docker.io golang jq git gh python3-openstackclient)
fi

DEB12_TGZS=("https://get.helm.sh/helm-v3.17.1-${OS}-${ARCH}.tar.gz")
DEB12_TCHK=("3b66f3cd28409f29832b1b35b43d9922959a32d795003149707fea84cbcd4469")
DEB12_TOLD=("${OS}-${ARCH}/helm")
DEB12_TNEW=(".")
DEB12_BINS=("https://github.com/kubernetes-sigs/kind/releases/download/v0.26.0/kind-${OS}-${ARCH}"
	    "https://dl.k8s.io/release/v1.31.6/bin/${OS}/${ARCH}/kubectl"
	    "https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.9.4/clusterctl-${OS}-${ARCH}"
	)
DEB12_BCHK=("d445b44c28297bc23fd67e51cc24bb294ae7b977712be2d4d312883d0835829b"
	    "c46b2f5b0027e919299d1eca073ebf13a4c5c0528dd854fc71a5b93396c9fa9d"
	    "0c80a58f6158cd76075fcc9a5d860978720fa88860c2608bb00944f6af1e5752"
    )
DEB12_BNEW=("kind" "." "clusterctl")

sudo apt-get update
install_via_pkgmgr "${DEB12_PKGS[@]}" || exit 1
for i in $(seq 0 $((${#DEB12_TGZS[*]}-1))); do
	echo "Processing tarball ${DEB12_TGZS[$i]}..."
	install_via_download_tgz "${DEB12_TGZS[$i]}" "${DEB12_TCHK[$i]}" "${DEB12_TOLD[$i]}" "${DEB12_TNEW[$i]}" || exit 2
done
for i in $(seq 0 $((${#DEB12_BINS[*]}-1))); do
	echo "Processing binary ${DEB12_BINS[$i]}..."
	install_via_download_bin "${DEB12_BINS[$i]}" "${DEB12_BCHK[$i]}" "${DEB12_BNEW[$i]}" || exit 3
done

GOBIN=/tmp go install github.com/drone/envsubst/v2/cmd/envsubst@latest
sudo mv /tmp/envsubst /usr/local/bin/

test -e "~/.bash_aliases" || echo -e "alias ll='ls -lF'\nalias k=kubectl" > ~/.bash_aliases
sudo groupmod -a -U `whoami` docker
sudo systemctl enable --now docker

