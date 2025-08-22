"""Setup script for auto-editor binary distribution."""

import os
import sys
import shutil
from pathlib import Path
from setuptools import setup, find_packages
from setuptools.command.build_py import build_py


class BuildPyCommand(build_py):
    """Custom build command to include binary."""
    
    def run(self):
        # Run the normal build
        super().run()
        
        # Copy the binary to the package
        self.copy_binary()
    
    def copy_binary(self):
        """Copy the appropriate binary to the package."""
        # Determine binary name and source path
        if sys.platform.startswith('win'):
            binary_name = 'auto-editor.exe'
        else:
            binary_name = 'auto-editor'
        
        # Look for binary in current directory (where build places it)
        source_binary = Path('.') / binary_name
        
        if not source_binary.exists():
            # Try alternative names for cross-compilation
            platform_binaries = [
                f'auto-editor-linux-x86_64',
                f'auto-editor-macos-x86_64',
                f'auto-editor-macos-arm64',
                f'auto-editor-windows-amd64.exe'
            ]
            
            for alt_binary in platform_binaries:
                alt_path = Path('.') / alt_binary
                if alt_path.exists():
                    source_binary = alt_path
                    break
        
        if not source_binary.exists():
            print(f"Warning: Binary {binary_name} not found, wheel will not include binary")
            return
        
        # Create bin directory in the built package
        package_dir = Path(self.build_lib) / 'auto_editor'
        bin_dir = package_dir / 'bin'
        bin_dir.mkdir(parents=True, exist_ok=True)
        
        # Copy binary
        dest_binary = bin_dir / binary_name
        shutil.copy2(source_binary, dest_binary)
        
        # Make it executable on Unix systems
        if not sys.platform.startswith('win'):
            dest_binary.chmod(0o755)
        
        print(f"Copied binary {source_binary} to {dest_binary}")


if __name__ == '__main__':
    setup(
        cmdclass={
            'build_py': BuildPyCommand,
        }
    )