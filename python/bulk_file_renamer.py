#!/usr/bin/env python3
"""Bulk File Renamer with Pattern Matching.

Rename files matching a regex pattern. Runs as a dry run by default;
pass --apply to make changes.

Usage:
    python bulk_file_renamer.py ~/Desktop/screenshots \\
        --pattern "Screenshot (\\d{4})-(\\d{2})-(\\d{2}) at .+\\.png" \\
        --replacement "\\1\\2\\3_capture.png"
"""
import argparse
import re
from pathlib import Path


def bulk_rename(directory, pattern, replacement, dry_run=True):
    """Rename files in a directory whose names match a regex pattern."""
    target_dir = Path(directory).expanduser()
    renamed = []

    for file_path in sorted(target_dir.iterdir()):
        if file_path.is_file():
            new_name = re.sub(pattern, replacement, file_path.name)
            if new_name != file_path.name:
                new_path = file_path.parent / new_name
                if dry_run:
                    print(f"  Would rename: {file_path.name} -> {new_name}")
                else:
                    file_path.rename(new_path)
                    print(f"  Renamed: {file_path.name} -> {new_name}")
                renamed.append((file_path.name, new_name))

    print(f"\n{'Would rename' if dry_run else 'Renamed'} {len(renamed)} files.")
    return renamed


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("directory", help="Directory containing the files")
    parser.add_argument("--pattern", required=True,
                        help="Regex pattern to match in file names")
    parser.add_argument("--replacement", required=True,
                        help="Replacement string (supports \\1-style backreferences)")
    parser.add_argument("--apply", action="store_true",
                        help="Actually make changes (default is a dry run)")
    args = parser.parse_args()

    bulk_rename(args.directory, args.pattern, args.replacement, dry_run=not args.apply)


if __name__ == "__main__":
    main()
