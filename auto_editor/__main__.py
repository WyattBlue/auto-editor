import platform
import subprocess
import sys
import urllib.request
from pathlib import Path

from . import __version__

version = __version__


def get_binary_info():
    system = platform.system().lower()
    machine = platform.machine().lower()

    if system == "windows":
        binary_name = "auto-editor-windows-amd64.exe"
        local_name = "auto-editor.exe"
    elif system == "darwin":
        if machine == "arm64":
            binary_name = "auto-editor-macos-arm64"
        else:
            binary_name = "auto-editor-macos-x86_64"
        local_name = "auto-editor"
    elif system == "linux":
        binary_name = "auto-editor-linux-x86_64"
        local_name = "auto-editor"
    else:
        raise RuntimeError(f"Unsupported platform: {system} {machine}")

    url = f"https://github.com/WyattBlue/auto-editor/releases/download/{version}/{binary_name}"
    return binary_name, local_name, url


def get_binary_version(binary_path):
    try:
        result = subprocess.run(
            [str(binary_path), "--version"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return result.stdout.strip()
    except Exception:
        return None


def download_binary():
    """Download the appropriate binary from GitHub releases."""
    package_dir = Path(__file__).parent
    bin_dir = package_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    binary_name, local_name, url = get_binary_info()
    binary_path = bin_dir / local_name

    if binary_path.exists():
        binary_version = get_binary_version(binary_path)
        if binary_version == version:
            return binary_path
        print(f"Removing outdated version ({binary_version})...")
        binary_path.unlink()

    print("Downloading auto-editor binary for your platform...")
    print(f"URL: {url}")

    try:
        urllib.request.urlretrieve(url, binary_path)
        binary_path.chmod(0o755)  # Make executable on Unix systems
        print("Download completed successfully!")
        return binary_path
    except Exception as e:
        print(f"Error downloading binary: {e}", file=sys.stderr)
        print(f"Please download manually from: {url}", file=sys.stderr)
        sys.exit(1)


def main():
    package_dir = Path(__file__).parent

    # Determine the binary name based on platform
    _, local_name, _ = get_binary_info()
    binary_path = package_dir / "bin" / local_name

    # Download binary if it doesn't exist
    if not binary_path.exists():
        binary_path = download_binary()

    # Execute the binary with all arguments
    try:
        result = subprocess.run([str(binary_path)] + sys.argv[1:])
        sys.exit(result.returncode)
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:
        print(f"Error running auto-editor: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
