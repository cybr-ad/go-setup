# Automated Go Setup for Linux

An automated, interactive Bash script to cleanly install, update, and configure the Go programming language on Linux according to the setup specifications in `go.txt`.

---

## 🚀 Features

- **Automated Architecture Detection**: Automatically identifies your system architecture (`amd64`, `arm64`, `386`, `armv6l`, etc.) using `uname -m`.
- **Interactive Version Selection**: Fetches current official Go releases directly from [go.dev/dl](https://go.dev/dl/) and lets you choose from a numbered menu (or enter any specific version manually).
- **Clean Old Installation**: Safely checks for and removes any existing Go installation at `/usr/local/go`.
- **Automated Environment Variable Configuration**: Adds the required path configurations to `/root/.zshrc` and `/root/.profile` (and regular user profiles if run via `sudo`):
  ```bash
  ##  Add Go Path
  export GOPATH=$HOME/go
  export GOROOT=/usr/local/go
  export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
  ```
- **Zero Manual Reload Needed**:
  - Automatically symlinks `go` and `gofmt` to `/usr/local/bin` so they work immediately in all terminal sessions.
  - Automatically generates `/etc/profile.d/go.sh` for system-wide persistence.
  - Automatically refreshes the current interactive shell session at completion—no manual `source ~/.zshrc` or terminal restart required.

---

## 📋 Prerequisites

- **OS**: Linux (Ubuntu, Debian, CentOS, RHEL, Arch Linux, etc.)
- **Privileges**: Root or `sudo` access
- **Tools**: `curl` or `wget`, `tar` (the script will attempt to install `curl` if missing)

---

## 🛠️ Usage

1. **Clone or transfer the script to your Linux machine**:
   Ensure `setup_go.sh` is present in your desired directory.

2. **Make the script executable**:
   ```bash
   chmod +x setup_go.sh
   ```

3. **Run with `sudo` or as `root`**:
   ```bash
   sudo ./setup_go.sh
   ```

4. **Select a Go Version**:
   - The script will display available stable versions fetched from `go.dev`:
     ```text
     Available Go versions for linux-amd64:
       1) go1.23.3 (Latest Stable)
       2) go1.23.2
       3) go1.22.9
       4) go1.22.8
       ...
       C) Enter custom version manually
     Select an option [1-10 or C] (Default: 1):
     ```
   - Press **Enter** to install the latest stable version, or enter a number/custom version.

5. **Done!**
   The script downloads, extracts, configures paths, symlinks binaries, and automatically refreshes your shell session.

---

## 🔍 Verification

Once the script finishes, verify the installation by typing:

```bash
go version
```

Output:
```text
go version go1.23.3 linux/amd64
```

To check Go environment variables:
```bash
go env GOPATH GOROOT
```

---

## 📁 Files Reference

- **[setup_go.sh](setup_go.sh)**: The executable installation script.
- **[go.txt](go.txt)**: Original instruction sheet detailing installation steps and shell path configurations.
