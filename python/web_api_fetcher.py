#!/usr/bin/env python3
"""Robust Web API Data Fetcher.

Fetches raw JSON payloads from internal or public API infrastructure safely.
Reads the API token from the PLATFORM_API_KEY environment variable — never
hardcode credentials.

Usage:
    PLATFORM_API_KEY=... python web_api_fetcher.py https://internal.network/metrics
"""
import argparse
import os
import sys

import requests
from requests.exceptions import RequestException


def fetch_platform_metrics(endpoint_url):
    """Fetch JSON from an API endpoint, returning None on failure."""
    api_token = os.getenv("PLATFORM_API_KEY")
    headers = {
        "Authorization": f"Bearer {api_token}",
        "Accept": "application/json",
    }

    try:
        response = requests.get(endpoint_url, headers=headers, timeout=10)
        # Raises HTTPError if status code is 4xx or 5xx
        response.raise_for_status()
        return response.json()

    except RequestException as err:
        print(f"Automation Fault: Network communication failure. Details: {err}",
              file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("url", help="API endpoint URL")
    args = parser.parse_args()

    data = fetch_platform_metrics(args.url)
    if data is not None:
        print(data)


if __name__ == "__main__":
    main()
