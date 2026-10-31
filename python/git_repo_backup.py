#!/usr/bin/env python3
"""Git Repository Backup Script.

Clone or update git repos as bare mirrors (all branches, tags, and refs).
Reads repo URLs from a text file (one URL per line).

Usage:
    python git_repo_backup.py repos.txt --backup-dir ~/git_backups
"""
import argparse
import subprocess
from datetime import datetime
from pathlib import Path


def backup_repos(repos, backup_dir="~/git_backups"):
    """Clone or update git repos as bare mirrors."""
    backup_path = Path(backup_dir).expanduser()
    backup_path.mkdir(parents=True, exist_ok=True)
    print(f"Backup started: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")

    for repo_url in repos:
        repo_name = repo_url.split("/")[-1].replace(".git", "")
        repo_dir = backup_path / f"{repo_name}.git"
        if repo_dir.exists():
            # Update existing mirror
            print(f"  Updating: {repo_name}")
            result = subprocess.run(
                ["git", "-C", str(repo_dir), "remote", "update"],
                capture_output=True, text=True,
            )
        else:
            # Clone as bare mirror (all branches, tags, refs)
            print(f"  Cloning: {repo_name}")
            result = subprocess.run(
                ["git", "clone", "--mirror", repo_url, str(repo_dir)],
                capture_output=True, text=True,
            )
        if result.returncode == 0:
            print("    Done.")
        else:
            print(f"    Failed: {result.stderr.strip()}")

    print(f"\nBackup complete. Location: {backup_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("repos_file",
                        help="Text file with one repo URL per line")
    parser.add_argument("--backup-dir", default="~/git_backups",
                        help="Directory for the mirrors (default: ~/git_backups)")
    args = parser.parse_args()

    with open(args.repos_file) as f:
        repos = [line.strip() for line in f if line.strip()]

    backup_repos(repos, backup_dir=args.backup_dir)


if __name__ == "__main__":
    main()
