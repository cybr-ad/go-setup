#!/bin/bash

# Go Installation Script
# Supports Linux (amd64, arm64, 386, armv6l)

set -e  # Exit on error

# Configuration
GO_VERSION="${1:-1.26.2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print colored output
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_step() {
    echo -e "${CYAN}==>${NC} $1"
}

# Require root before checking the system or making any changes.
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root. Run: sudo -H bash $0"
    exit 1
fi
print_info "Running as root; configuring Go for $HOME."

# Check OS
OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
    print_error "This script is designed for Linux systems. Detected: $OS"
    exit 1
fi

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)
        GO_ARCH="amd64"
        ;;
    aarch64|arm64)
        GO_ARCH="arm64"
        ;;
    armv6l|armv7l)
        GO_ARCH="armv6l"
        ;;
    i386|i686)
        GO_ARCH="386"
        ;;
    *)
        print_error "Unsupported system architecture: $ARCH"
        exit 1
        ;;
esac


# Check for download tool (curl or wget)
DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
else
    print_error "Neither 'curl' nor 'wget' was found. Please install one first: apt install curl (or wget)"
    exit 1
fi

TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
DOWNLOAD_URL="https://go.dev/dl/${TARBALL}"
TMP_DIR="$(mktemp -d -t go-install-XXXXXX)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Step 1: Create GOPATH directory
print_step "Step 1: Setting up GOPATH directory (~/go)..."
mkdir -p "$HOME/go"/{bin,pkg,src}
print_success "Workspace directory ready at $HOME/go"

# Step 2: Download Go tarball
print_step "Step 2: Downloading Go ${GO_VERSION} (${GO_ARCH})..."
cd "$TMP_DIR"

if [ "$DOWNLOADER" = "curl" ]; then
    if ! curl -fSL -o "$TARBALL" "$DOWNLOAD_URL"; then
        print_error "Failed to download Go from $DOWNLOAD_URL. Please verify version ${GO_VERSION} exists."
        exit 1
    fi
else
    if ! wget -q --show-progress -O "$TARBALL" "$DOWNLOAD_URL"; then
        print_error "Failed to download Go from $DOWNLOAD_URL. Please verify version ${GO_VERSION} exists."
        exit 1
    fi
fi
print_success "Downloaded $TARBALL successfully"

# Step 3: Remove old Go installation and extract tarball to /usr/local
print_step "Step 3: Installing Go to /usr/local/go (running as root)..."
if [ -d "/usr/local/go" ]; then
    print_info "Removing existing /usr/local/go to prevent installation corruption..."
    rm -rf /usr/local/go
fi

tar -C /usr/local -xzf "$TARBALL"
print_success "Extracted Go to /usr/local/go"

# Create symlinks in /usr/local/bin for immediate system-wide availability
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
print_success "Created symlinks in /usr/local/bin"

# Step 4: Configure environment variables in shell profile files
print_step "Step 4: Configuring environment variables..."

# Function to safely append Go environment variables
configure_shell_file() {
    local file="$1"
    [ -z "$file" ] && return 0

    # Create file if it doesn't exist
    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    # Ensure file ends with a newline before appending
    if [ -s "$file" ] && [ "$(tail -c 1 "$file")" != "" ]; then
        echo "" >> "$file"
    fi

    local needs_update=0

    if ! grep -q 'GOPATH=' "$file"; then
        echo 'export GOPATH="$HOME/go"' >> "$file"
        needs_update=1
    fi

    if ! grep -q '/usr/local/go/bin' "$file"; then
        echo 'export PATH="$PATH:/usr/local/go/bin"' >> "$file"
        needs_update=1
    fi

    if ! grep -q '\$GOPATH/bin' "$file" && ! grep -q '$GOPATH/bin' "$file"; then
        echo 'export PATH="$PATH:$GOPATH/bin"' >> "$file"
        needs_update=1
    fi

    if [ "$needs_update" -eq 1 ]; then
        print_success "Updated Go paths in $file"
    else
        print_info "Go paths already present in $file (skipping duplicate entry)"
    fi
}

# Update all standard shell profile files
configure_shell_file "$HOME/.profile"
configure_shell_file "$HOME/.zshrc"
configure_shell_file "$HOME/.bashrc"
if [ -f "$HOME/.bash_profile" ]; then
    configure_shell_file "$HOME/.bash_profile"
fi

# Step 5: Refresh paths and hash tables
print_step "Step 5: Updating current session..."

# Set paths in current script process for verification
export GOPATH="$HOME/go"
export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"

# Safely refresh hash table for bash
hash -r 2>/dev/null || true

# If zsh is available, test config and rehash
if command -v zsh >/dev/null 2>&1; then
    zsh -c "rehash" 2>/dev/null || true
fi

# Step 6: Verify installation
print_step "Step 6: Verifying installation..."
INSTALLED_VERSION="$(/usr/local/go/bin/go version)"
print_success "Go installed: $INSTALLED_VERSION"

echo ""
print_success "=========================================================="
print_success "        Go Installation Completed Successfully!           "
print_success "=========================================================="
print_info "Go Version : $INSTALLED_VERSION"
print_info "GOROOT     : /usr/local/go"
print_info "GOPATH     : $HOME/go"
print_info "Binary     : $(which go 2>/dev/null || echo '/usr/local/go/bin/go')"
echo ""
print_info "NOTE: Child scripts cannot change your active shell's environment."
print_info "To use Go immediately in your CURRENT terminal window, run:"
echo ""
echo -e "  ${CYAN}For Zsh:${NC}  source ~/.zshrc && rehash"
echo -e "  ${CYAN}For Bash:${NC} source ~/.profile && hash -r  (or: source ~/.bashrc)"
echo ""
print_info "Alternatively, simply open a new terminal window or tab."
