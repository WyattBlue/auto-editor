"""Main entry point for auto-editor when run as a module."""

import os
import sys
import subprocess
from pathlib import Path


def main():
    """Run the auto-editor binary."""
    # Find the binary in the package directory
    package_dir = Path(__file__).parent
    
    # Determine the binary name based on platform
    if sys.platform.startswith('win'):
        binary_name = 'auto-editor.exe'
    else:
        binary_name = 'auto-editor'
    
    binary_path = package_dir / 'bin' / binary_name
    
    if not binary_path.exists():
        print(f"Error: auto-editor binary not found at {binary_path}", file=sys.stderr)
        sys.exit(1)
    
    # Execute the binary with all arguments
    try:
        result = subprocess.run([str(binary_path)] + sys.argv[1:])
        sys.exit(result.returncode)
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:
        print(f"Error running auto-editor: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()