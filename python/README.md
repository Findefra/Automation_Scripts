# Python Automation Scripts

Standalone Python 3.9+ utilities. Every script is a CLI tool with `--help`,
and anything that renames, moves, or deletes files defaults to a dry run —
pass `--apply` to make real changes.

## Setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Scripts

| Script | Purpose |
|---|---|
| `bulk_file_renamer.py` | Rename files matching a regex pattern (dry run by default) |
| `clipboard_history_manager.py` | Monitor the clipboard and log entries with timestamps |
| `csv_cleaner_deduplicator.py` | Clean, deduplicate, and standardize CSV files |
| `email_report_generator.py` | Email a summary report from CSV data (SMTP creds from env) |
| `git_repo_backup.py` | Clone or update repos as bare mirrors from a repo list file |
| `image_batch_processor.py` | Resize, compress, and convert images in bulk |
| `pdf_merger_splitter.py` | Merge PDFs or extract page ranges |
| `smart_file_organizer.py` | Rename to snake_case and sort files into extension folders |
| `web_api_fetcher.py` | Fetch JSON from APIs with env-based auth and timeouts |
| `website_uptime_monitor.py` | Poll sites and report UP/DOWN status with latency |

## Examples

```bash
# Preview (dry run) then apply a cleanup of Downloads
python smart_file_organizer.py ~/Downloads
python smart_file_organizer.py ~/Downloads --apply

# Merge PDFs
python pdf_merger_splitter.py merge q1.pdf q2.pdf -o half-year.pdf

# Monitor three sites every 5 minutes
python website_uptime_monitor.py --interval 300 \
    "Site A=https://a.example.com" "Site B=https://b.example.com"
```

See [docs/scheduling.md](docs/scheduling.md) for running these on a schedule
(cron, systemd timers, or Windows Task Scheduler).

## Conventions

- Credentials come from environment variables, never hardcoded strings.
- Mutating operations are opt-in via `--apply`, and previews print first.
- Each script runs from `if __name__ == "__main__":` so it can be imported
  as a module without side effects.
