#!/usr/bin/env bash
# Installs the GitHub Actions linters tools/check.sh runs, actionlint and
# zizmor, into the directory given (default ~/.local/bin), skipping one that
# is already there at its pinned version. Each is pinned by version and by
# the SHA-256 of its release archive, checked before it is unpacked. Called
# by tools/bootstrap-agent.sh.
# To bump: change the version and both checksums together (actionlint
# publishes a checksums file; zizmor does not, so hash the release assets).
set -euo pipefail

ACTIONLINT_VERSION=1.7.12
ZIZMOR_VERSION=1.30.1

case "$(uname -s)-$(uname -m)" in
Linux-x86_64)
	actionlint_asset="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
	actionlint_sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
	zizmor_asset=zizmor-x86_64-unknown-linux-gnu.tar.gz
	zizmor_sha256=e65324f4430c2717591937edcec90ccbefaf14c174f8ec9415e03ca875b46e1a
	;;
Darwin-arm64)
	actionlint_asset="actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"
	actionlint_sha256=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f
	zizmor_asset=zizmor-aarch64-apple-darwin.tar.gz
	zizmor_sha256=e28d22b087f9ebb8d99da6e740d348c930f559961c7c3f12badda54f882195a2
	;;
*)
	echo "error: no pinned actionlint and zizmor for $(uname -s)-$(uname -m)" >&2
	exit 1
	;;
esac

bin="${1:-$HOME/.local/bin}"
mkdir -p "$bin"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# install_tool <name> <version> <url> <sha256>: download, verify, unpack into
# $bin, unless $bin already has <name> at <version>.
install_tool() {
	if [ -x "$bin/$1" ] && "$bin/$1" --version 2>/dev/null | grep -qwF "$2"; then
		echo "$1 $2: present"
		return
	fi
	curl -fsSL -o "$tmp/$1.tar.gz" "$3"
	if ! echo "$4  $tmp/$1.tar.gz" | shasum -a 256 --check --status; then
		echo "error: $3 does not match its pinned SHA-256 in tools/install-workflow-linters.sh" >&2
		exit 1
	fi
	tar -xzf "$tmp/$1.tar.gz" -C "$tmp" "$1"
	mv "$tmp/$1" "$bin/$1"
	chmod +x "$bin/$1"
	echo "installed $bin/$1"
}

install_tool actionlint "$ACTIONLINT_VERSION" \
	"https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/$actionlint_asset" "$actionlint_sha256"
install_tool zizmor "$ZIZMOR_VERSION" \
	"https://github.com/zizmorcore/zizmor/releases/download/v$ZIZMOR_VERSION/$zizmor_asset" "$zizmor_sha256"
