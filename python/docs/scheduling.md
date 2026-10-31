# Scheduling the Python Scripts

You don't need anything complicated to run these scripts on a schedule.

## macOS / Linux: cron

Open your terminal, run `crontab -e`, and add a line specifying the schedule:

```
# Run uptime check every 5 minutes
*/5 * * * * /usr/bin/python3 /home/user/scripts/website_uptime_monitor.py

# Weekly email report, Monday at 7 AM
0 7 * * 1 /usr/bin/python3 /home/user/scripts/email_report_generator.py

# Git backup every Sunday at midnight
0 0 * * 0 /usr/bin/python3 /home/user/scripts/git_repo_backup.py
```

Example: `0 8 * * 1-5 /usr/bin/python3 /path/to/script.py` runs the script every
weekday at 8:00 AM.

Cron schedule fields, in order: minute, hour, day-of-month, month, day-of-week.

## Windows: Task Scheduler

Use `schtasks` or the Task Scheduler GUI:

```
schtasks /create /tn "UptimeMonitor" /tr "python C:\scripts\website_uptime_monitor.py" /sc minute /mo 5
```

## Tips

- Log output to a file so failures are visible: append `>> /var/log/script.log 2>&1`
  to the cron entry.
- Use absolute paths for the Python interpreter and the script; cron has a minimal
  environment.
- For anything more complex than a schedule, consider `systemd` timers (Linux),
  which support retries and dependencies.
