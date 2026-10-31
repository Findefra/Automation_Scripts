#!/usr/bin/env python3
"""Website Uptime Monitor.

Check that a list of sites responds with a 200 status, on an interval.
Sites are passed as NAME=URL pairs; if none are given, a demo list is used.

Usage:
    python website_uptime_monitor.py --interval 300 \\
        "Portfolio=https://yoursite.com" "API=https://api.example.dev/health"
"""
import argparse
import time
from datetime import datetime

import requests

DEFAULT_SITES = [
    {"name": "Portfolio", "url": "https://yoursite.com"},
    {"name": "Client Blog", "url": "https://clientblog.com"},
    {"name": "Side Project API", "url": "https://api.sideproject.dev/health"},
]


def check_uptime(sites, timeout=10):
    """Check if each site responds with a 200 status."""
    results = []
    for site in sites:
        try:
            response = requests.get(site["url"], timeout=timeout)
            status = "UP" if response.status_code == 200 else f"DOWN ({response.status_code})"
            latency = response.elapsed.total_seconds()
        except requests.exceptions.RequestException as e:
            status = f"DOWN ({type(e).__name__})"
            latency = None
        results.append({
            "name": site["name"],
            "status": status,
            "latency": f"{latency:.2f}s" if latency else "N/A",
            "checked_at": datetime.now().strftime("%H:%M:%S"),
        })
        print(f"  [{status}] {site['name']} - {results[-1]['latency']}")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("sites", nargs="*", metavar="NAME=URL",
                        help="Sites to monitor as NAME=URL pairs")
    parser.add_argument("--interval", type=int, default=300,
                        help="Seconds between checks (default: 300)")
    parser.add_argument("--timeout", type=int, default=10,
                        help="Request timeout in seconds (default: 10)")
    args = parser.parse_args()

    sites = ([{"name": s.split("=", 1)[0], "url": s.split("=", 1)[1]}
              for s in args.sites] or DEFAULT_SITES)

    while True:
        print(f"\n--- Uptime Check: {datetime.now().strftime('%Y-%m-%d %H:%M')} ---")
        check_uptime(sites, timeout=args.timeout)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
