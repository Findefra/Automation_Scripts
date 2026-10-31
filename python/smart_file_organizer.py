#!/usr/bin/env python3
"""Smart File Organizer & Bulk Renamer.

Scans a directory, safely previews or renames files matching a pattern,
and sorts them into per-extension subfolders.

Usage:
    python smart_file_organizer.py ~/Downloads            # dry run
    python smart_file_organizer.py ~/Downloads --apply    # make changes
"""
import argparse
import re
import shutil
from pathlib import Path


def smart_organizer(directory_path, pattern=r"^.+", dry_run=True):
    """Rename matching files to snake_case and sort all files into extension folders."""
    target_dir = Path(directory_path).expanduser()
    if not target_dir.exists():
        print(f"Directory {target_dir} does not exist.")
        return

    print(f"--- Running (dry run = {dry_run}) ---")
    for file_path in sorted(target_dir.iterdir()):
        if not file_path.is_file():
            continue

        # Rename matching files: lowercase, spaces -> underscores
        if re.match(pattern, file_path.name):
            new_name = file_path.name.lower().replace(" ", "_")
            new_path = file_path.parent / new_name
            if dry_run:
                print(f"[MATCH] Would rename: {file_path.name} -> {new_name}")
            else:
                file_path.rename(new_path)
                print(f"[RENAME] Completed: {file_path.name} -> {new_name}")
                file_path = new_path

        # Sort by extension type
        ext = file_path.suffix.lower().strip(".")
        if ext:
            dest_folder = target_dir / ext
            if dry_run:
                print(f"[SORT]  Would move: {file_path.name} -> {ext}/")
            else:
                dest_folder.mkdir(exist_ok=True)
                shutil.move(str(file_path), str(dest_folder / file_path.name))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("directory", help="Directory to organize")
    parser.add_argument("--pattern", default=r"^.+",
                        help="Regex the file name must match to be renamed (default: all)")
    parser.add_argument("--apply", action="store_true",
                        help="Actually make changes (default is a dry run)")
    args = parser.parse_args()

    smart_organizer(args.directory, pattern=args.pattern, dry_run=not args.apply)


if __name__ == "__main__":
    main()
