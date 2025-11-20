#!/bin/bash
# Build Windows EXE installer on macOS
# This script creates a Windows EXE using Go cross-compilation

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Building Windows EXE Installer on macOS              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "❌ Go is not installed"
    echo ""
    echo "Install Go:"
    echo "  brew install go"
    echo ""
    exit 1
fi

echo "✓ Go found: $(go version)"
echo ""

# Check if install.ps1 exists
if [ ! -f "install.ps1" ]; then
    echo "❌ install.ps1 not found in current directory"
    exit 1
fi

# Create temporary directory for Go program
TEMP_DIR=$(mktemp -d)
GO_PROG="$TEMP_DIR/installer.go"
GO_MOD="$TEMP_DIR/go.mod"

echo "Creating Go wrapper..."

# Create Go module
cat > "$GO_MOD" << 'EOF'
module installer

go 1.21
EOF

# Create Go program that reads PowerShell script from embedded data
# We'll use base64 encoding to safely embed the script
# Use input redirection for compatibility
POWERSHELL_B64=$(base64 < install.ps1 | tr -d '\n')

cat > "$GO_PROG" << 'GOSOURCE'
package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

const powershellScriptB64 = `POWERSHELL_SCRIPT_B64_PLACEHOLDER`

func main() {
	if runtime.GOOS != "windows" {
		fmt.Println("This program is designed for Windows only")
		os.Exit(1)
	}

	// Decode PowerShell script
	scriptBytes, err := base64.StdEncoding.DecodeString(powershellScriptB64)
	if err != nil {
		fmt.Printf("Error decoding script: %v\n", err)
		os.Exit(1)
	}

	// Get executable directory
	exePath, err := os.Executable()
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
	exeDir := filepath.Dir(exePath)

	// Create temporary PowerShell script
	scriptPath := filepath.Join(exeDir, "install-temp.ps1")
	err = os.WriteFile(scriptPath, scriptBytes, 0644)
	if err != nil {
		fmt.Printf("Error creating script: %v\n", err)
		os.Exit(1)
	}
	defer os.Remove(scriptPath)

	// Execute PowerShell script with all arguments
	cmd := exec.Command("powershell.exe", "-ExecutionPolicy", "Bypass", "-File", scriptPath)
	cmd.Args = append(cmd.Args, os.Args[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	err = cmd.Run()
	if err != nil {
		os.Exit(1)
	}
}
GOSOURCE

# Replace placeholder with base64 encoded script
sed -i '' "s|POWERSHELL_SCRIPT_B64_PLACEHOLDER|${POWERSHELL_B64}|g" "$GO_PROG"

echo "✓ Go wrapper created"
echo ""

# Build for Windows
echo "Building Windows EXE..."
echo "  Target: windows/amd64"
echo "  This may take a minute..."

cd "$TEMP_DIR"
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o "$OLDPWD/install.exe" installer.go
cd "$OLDPWD"

if [ -f "install.exe" ]; then
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           EXE created successfully!                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "✓ File: install.exe"
    EXE_SIZE=$(du -h install.exe | cut -f1)
    echo "✓ Size: $EXE_SIZE"
    echo ""
    echo "You can now distribute install.exe for Windows"
    echo "Just copy install.exe and .conf file to the same folder"
    echo ""
else
    echo "❌ Error creating EXE"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"
