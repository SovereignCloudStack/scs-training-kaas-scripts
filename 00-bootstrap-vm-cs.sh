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
	cd ~/Download
	curl -LO "$1" || return
	FNM="${1##*/}"
	if ! test_sha256 "$FNM" "$2"; then echo "Checksum mismatch for ${FNM}" 1>&2; return 1; fi
	chmod +x "$FNM"
	sudo mv "$FNM" /usr/local/bin/"$3"
}

# Usage install_via_download_bin URL sha256 extrpath [newname]
install_via_download_tgz()
{
	cd ~/Download
	curl -LO "$1" || return
	FNM="${1##*/}"
	if ! test_sha256 "$FNM" "$2"; then echo "Checksum mismatch for ${FNM}" 1>&2; return 1; fi
	tar xvzf "$FNM"
	sudo mv "$3" /usr/local/bin/"$4"
}

# Debian 12 (Bookworm)
mkdir -p ~/Download
INSTCMD="apt-get install -y --no-install-recommends --no-install-suggests"
DEB12_PKGS=(docker.io docker-cli golang jq yq git gh python3-openstackclient)
DEB12_TGZS=("https://get.helm.sh/helm-v3.20.0-${OS}-${ARCH}.tar.gz")
DEB12_TCHK=("dbb4c8fc8e19d159d1a63dda8db655f9ffa4aac1b9a6b188b34a40957119b286")
DEB12_TOLD=("${OS}-${ARCH}/helm")
DEB12_TNEW=(".")
DEB12_BINS=("https://github.com/kubernetes-sigs/kind/releases/download/v0.31.0/kind-${OS}-${ARCH}"
	    "https://dl.k8s.io/release/v1.35.0/bin/${OS}/${ARCH}/kubectl"
	    "https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.12.2/clusterctl-${OS}-${ARCH}"
	)
DEB12_BCHK=("eb244cbafcc157dff60cf68693c14c9a75c4e6e6fedaf9cd71c58117cb93e3fa"
	    "a2e984a18a0c063279d692533031c1eff93a262afcc0afdc517375432d060989"
	    "c9f05fb8a7839067bcfb2c897f4b7cab37b7c2780aef12669b5fd89a1dd6dffd"
    )
DEB12_BNEW=("kind" "." "clusterctl")

sudo apt-get update
install_via_pkgmgr "${DEB12_PKGS[@]}" || exit 1
for i in $(seq 0 $((${#DEB12_TGZS[*]}-1))); do
	install_via_download_tgz "${DEB12_TGZS[$i]}" "${DEB12_TCHK[$i]}" "${DEB12_TOLD[$i]}" "${DEB12_TNEW[$i]}" || exit 2
done
for i in $(seq 0 $((${#DEB12_BINS[*]}-1))); do
	install_via_download_bin "${DEB12_BINS[$i]}" "${DEB12_BCHK[$i]}" "${DEB12_BNEW[$i]}" || exit 3
done

GOBIN=/tmp go install github.com/drone/envsubst/v2/cmd/envsubst@latest
sudo mv /tmp/envsubst /usr/local/bin/

test -e "~/.bash_aliases" || echo -e "alias ll='ls -lF'\nalias k=kubectl" > ~/.bash_aliases
sudo groupmod -a -U `whoami` docker
sudo systemctl enable --now docker

