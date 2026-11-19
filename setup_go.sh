#!/usr/bin/env bash
# ==============================================================================
# Script: setup_go.sh
# Description: Automated interactive Go installation script following go.txt
# Requirements: Linux OS, root / sudo privileges, curl or wget, tar
# ==============================================================================

set -euo pipefail

# ANSI color codes for readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "${CYAN}${BOLD}       Automated Go Setup & Installation Script     ${NC}"
echo -e "${CYAN}${BOLD}====================================================${NC}\n"

# 1. Check for root privileges
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script requires root privileges to modify /usr/local and /root files.${NC}"
    echo -e "${YELLOW}Please run with sudo: sudo bash $0${NC}"
    exit 1
fi

# 2. Check essential tools
for cmd in tar uname; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}[ERROR] Required command '$cmd' is not installed.${NC}"
        exit 1
    fi
done

DOWNLOADER=""
if command -v curl &>/dev/null; then
    DOWNLOADER="curl"
elif command -v wget &>/dev/null; then
    DOWNLOADER="wget"
else
    echo -e "${YELLOW}[INFO] Neither curl nor wget found. Attempting to install curl...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y curl
        DOWNLOADER="curl"
    elif command -v yum &>/dev/null; then
        yum install -y curl
        DOWNLOADER="curl"
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm curl
        DOWNLOADER="curl"
    else
        echo -e "${RED}[ERROR] Please install curl or wget first.${NC}"
        exit 1
    fi
fi

# 3. Detect OS Architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [ "$OS" != "linux" ]; then
    echo -e "${RED}[ERROR] This script is designed for Linux (detected: $OS).${NC}"
    exit 1
fi

MACHINE_ARCH="$(uname -m)"
case "$MACHINE_ARCH" in
    x86_64|amd64)
        GOARCH="amd64"
        ;;
    aarch64|arm64)
        GOARCH="arm64"
        ;;
    armv6l)
        GOARCH="armv6l"
        ;;
    armv7l)
        GOARCH="armv6l"
        ;;
    i386|i686)
        GOARCH="386"
        ;;
    ppc64le)
        GOARCH="ppc64le"
        ;;
    s390x)
        GOARCH="s390x"
        ;;
    *)
        echo -e "${YELLOW}[WARNING] Architecture '$MACHINE_ARCH' not automatically mapped.${NC}"
        read -rp "Enter Go architecture manually (e.g. amd64, arm64, 386): " GOARCH
        ;;
esac

echo -e "${GREEN}[✓] Detected Architecture:${NC} ${BOLD}linux-${GOARCH}${NC} (${MACHINE_ARCH})\n"

# 4. Fetch available Go versions from go.dev
echo -e "${CYAN}[i] Fetching available Go versions from https://go.dev/dl/ ...${NC}"

VERSIONS=()
if [ "$DOWNLOADER" = "curl" ]; then
    JSON_DATA=$(curl -sSL "https://go.dev/dl/?mode=json" 2>/dev/null || true)
else
    JSON_DATA=$(wget -qO- "https://go.dev/dl/?mode=json" 2>/dev/null || true)
fi

if [ -n "$JSON_DATA" ]; then
    # Extract version strings (e.g., go1.23.3)
    if command -v grep &>/dev/null && grep --version 2>&1 | grep -q GNU; then
        mapfile -t VERSIONS < <(echo "$JSON_DATA" | grep -oP '"version":\s*"\Kgo[0-9]+(\.[0-9]+)*' | awk '!seen[$0]++' | head -n 10)
    elif command -v sed &>/dev/null; then
        mapfile -t VERSIONS < <(echo "$JSON_DATA" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | awk '!seen[$0]++' | head -n 10)
    fi
fi

# Fallback versions if API fetch failed
if [ ${#VERSIONS[@]} -eq 0 ]; then
    echo -e "${YELLOW}[!] Could not automatically fetch the release list. Using known recent stable versions.${NC}"
    VERSIONS=("go1.23.3" "go1.23.2" "go1.22.9" "go1.22.8" "go1.21.13")
fi

# 5. Ask user with complete details which version to install
echo -e "\n${BOLD}Available Go versions for linux-${GOARCH}:${NC}"
for i in "${!VERSIONS[@]}"; do
    if [ "$i" -eq 0 ]; then
        echo -e "  ${BOLD}$((i + 1)))${NC} ${VERSIONS[$i]} ${GREEN}(Latest Stable)${NC}"
    else
        echo -e "  ${BOLD}$((i + 1)))${NC} ${VERSIONS[$i]}"
    fi
done
echo -e "  ${BOLD}C)${NC} Enter custom version manually"

SELECTED_VERSION=""
while [ -z "$SELECTED_VERSION" ]; do
    read -rp "Select an option [1-${#VERSIONS[@]} or C] (Default: 1): " USER_CHOICE
    USER_CHOICE="${USER_CHOICE:-1}"

    if [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] && [ "$USER_CHOICE" -ge 1 ] && [ "$USER_CHOICE" -le "${#VERSIONS[@]}" ]; then
        SELECTED_VERSION="${VERSIONS[$((USER_CHOICE - 1))]}"
    elif [[ "$USER_CHOICE" =~ ^[cC]$ ]]; then
        read -rp "Enter Go version (e.g., 1.23.3 or go1.23.3): " CUSTOM_INPUT
        CUSTOM_INPUT="$(echo "$CUSTOM_INPUT" | xargs)"
        if [[ ! "$CUSTOM_INPUT" =~ ^go ]]; then
            SELECTED_VERSION="go${CUSTOM_INPUT}"
        else
            SELECTED_VERSION="$CUSTOM_INPUT"
        fi
    else
        echo -e "${RED}Invalid selection. Please choose a valid number or 'C'.${NC}"
    fi
done

TARBALL="${SELECTED_VERSION}.linux-${GOARCH}.tar.gz"
DOWNLOAD_URL="https://go.dev/dl/${TARBALL}"

echo -e "\n${BOLD}----------------------------------------------------${NC}"
echo -e "Version to install: ${GREEN}${BOLD}${SELECTED_VERSION}${NC}"
echo -e "Archive:            ${CYAN}${TARBALL}${NC}"
echo -e "Download URL:       ${CYAN}${DOWNLOAD_URL}${NC}"
echo -e "Target Directory:   ${CYAN}/usr/local/go${NC}"
echo -e "${BOLD}----------------------------------------------------${NC}\n"

# 6. Step 1 from go.txt: rm -rf /usr/local/go [ if available ]
if [ -d "/usr/local/go" ]; then
    echo -e "${YELLOW}[*] Existing Go installation found at /usr/local/go. Removing...${NC}"
    rm -rf /usr/local/go
    echo -e "${GREEN}[✓] Removed /usr/local/go successfully.${NC}"
else
    echo -e "${CYAN}[i] No previous installation found at /usr/local/go.${NC}"
fi

# 7. Download selected version
TMP_DIR="$(mktemp -d /tmp/go-setup-XXXXXX)"
ARCHIVE_PATH="${TMP_DIR}/${TARBALL}"

echo -e "\n${CYAN}[*] Downloading ${TARBALL}...${NC}"
if [ "$DOWNLOADER" = "curl" ]; then
    if ! curl -fL --progress-bar -o "$ARCHIVE_PATH" "$DOWNLOAD_URL"; then
        echo -e "${RED}[ERROR] Failed to download from ${DOWNLOAD_URL}.${NC}"
        echo -e "${YELLOW}Please verify if version '${SELECTED_VERSION}' exists for 'linux-${GOARCH}'.${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
else
    if ! wget -q --show-progress -O "$ARCHIVE_PATH" "$DOWNLOAD_URL"; then
        echo -e "${RED}[ERROR] Failed to download from ${DOWNLOAD_URL}.${NC}"
        echo -e "${YELLOW}Please verify if version '${SELECTED_VERSION}' exists for 'linux-${GOARCH}'.${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
fi
echo -e "${GREEN}[✓] Download completed.${NC}"

# 8. Step from go.txt: tar -C /usr/local -xzf go-something.tar.gz
echo -e "${CYAN}[*] Extracting ${TARBALL} to /usr/local ...${NC}"
tar -C /usr/local -xzf "$ARCHIVE_PATH"
echo -e "${GREEN}[✓] Extraction completed. Go installed to /usr/local/go.${NC}"

# Clean up downloaded archive
rm -rf "$TMP_DIR"

# 9. Step from go.txt: Add Go path to /root/.zshrc and /root/.profile
ENV_BLOCK='
##  Add Go Path
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
'

add_go_path_to_file() {
    local target_file="$1"
    local dir_name
    dir_name="$(dirname "$target_file")"

    if [ ! -d "$dir_name" ]; then
        mkdir -p "$dir_name"
    fi

    if [ -f "$target_file" ] && grep -q "export GOROOT=/usr/local/go" "$target_file"; then
        echo -e "${YELLOW}[i] Go environment variables already present in ${target_file}${NC}"
    else
        echo -e "${CYAN}[*] Adding Go environment variables to ${target_file}...${NC}"
        # Ensure file ends with a newline before appending
        if [ -f "$target_file" ] && [ -s "$target_file" ] && [ "$(tail -c 1 "$target_file" | wc -l)" -eq 0 ]; then
            echo "" >> "$target_file"
        fi
        echo -e "$ENV_BLOCK" >> "$target_file"
        echo -e "${GREEN}[✓] Configured ${target_file}${NC}"
    fi
}

echo -e "\n${CYAN}[*] Configuring environment variables...${NC}"

# Config for /root/.zshrc
add_go_path_to_file "/root/.zshrc"

# Config for /root/.profile
add_go_path_to_file "/root/.profile"

# Also configure the non-root invoking user's config if script was run with sudo
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
    if [ -d "$USER_HOME" ]; then
        echo -e "\n${CYAN}[*] Sudo caller detected ($SUDO_USER). Also configuring user shell profiles...${NC}"
        [ -f "$USER_HOME/.zshrc" ] && add_go_path_to_file "$USER_HOME/.zshrc"
        [ -f "$USER_HOME/.profile" ] && add_go_path_to_file "$USER_HOME/.profile"
        [ -f "$USER_HOME/.bashrc" ] && add_go_path_to_file "$USER_HOME/.bashrc"
    fi
fi

# 10. Automatically link binaries into standard system PATH (/usr/local/bin)
# This makes 'go' and 'gofmt' immediately accessible system-wide in any terminal without restarting or sourcing
echo -e "\n${CYAN}[*] Creating system-wide symlinks in /usr/local/bin...${NC}"
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
echo -e "${GREEN}[✓] Linked /usr/local/go/bin/go -> /usr/local/bin/go${NC}"

# Add system-wide profile integration
if [ -d "/etc/profile.d" ]; then
    echo -e "${CYAN}[*] Adding system-wide configuration to /etc/profile.d/go.sh...${NC}"
    cat << 'EOF' > /etc/profile.d/go.sh
##  Add Go Path
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
EOF
    chmod 644 /etc/profile.d/go.sh
    echo -e "${GREEN}[✓] Created /etc/profile.d/go.sh${NC}"
fi

# Export in the current execution context
export GOPATH="$HOME/go"
export GOROOT="/usr/local/go"
export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"

# 11. Verify installation
echo -e "\n${BOLD}====================================================${NC}"
if [ -x "/usr/local/go/bin/go" ]; then
    INSTALLED_VER=$(/usr/local/go/bin/go version)
    echo -e "${GREEN}${BOLD}[SUCCESS] Go has been successfully installed and configured!${NC}"
    echo -e "${BOLD}Version:${NC} ${INSTALLED_VER}"
    echo -e "${GREEN}[✓] Go is immediately ready to use! (Symlinked to /usr/local/bin/go)${NC}"
    echo -e "${BOLD}====================================================${NC}\n"

    # Automatically reload active shell session if running interactively
    if [ -t 0 ] && [ -t 1 ]; then
        TARGET_SHELL="${SHELL:-/bin/bash}"
        echo -e "${CYAN}[*] Automatically refreshing your shell session now...${NC}\n"
        # If run via sudo, drop back to the invoking user in an updated shell
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            exec sudo -u "$SUDO_USER" -i
        else
            exec "$TARGET_SHELL" -l
        fi
    fi
else
    echo -e "${RED}[ERROR] Go binary not found at /usr/local/go/bin/go.${NC}"
    exit 1
fi
