#!/usr/bin/env python3
"""Automated Email Report Generator.

Reads rows from a CSV file and sends a formatted summary email report.
SMTP credentials come from environment variables — never hardcode them:

    export SMTP_USER="you@example.com"
    export SMTP_PASSWORD="your_app_password"

The CSV must contain 'revenue' and 'product' columns.

Usage:
    python email_report_generator.py sales_data.csv team@example.com
"""
import argparse
import csv
import os
import smtplib
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText


def generate_weekly_report(csv_path, recipient):
    """Read data from CSV and send a formatted email report."""
    with open(csv_path, "r", newline="") as f:
        rows = list(csv.DictReader(f))

    total_revenue = sum(float(r["revenue"]) for r in rows)
    avg_revenue = total_revenue / len(rows) if rows else 0
    top_product = max(rows, key=lambda r: float(r["revenue"]))
    report_date = datetime.now().strftime("%B %d, %Y")

    body = f"""
    Weekly Report - {report_date}
    Total Revenue: ${total_revenue:,.2f}
    Average per Entry: ${avg_revenue:,.2f}
    Top Performer: {top_product['product']} (${float(top_product['revenue']):,.2f})
    Total Records: {len(rows)}
    """

    sender = os.environ["SMTP_USER"]
    password = os.environ["SMTP_PASSWORD"]

    msg = MIMEMultipart()
    msg["From"] = sender
    msg["To"] = recipient
    msg["Subject"] = f"Weekly Report - {report_date}"
    msg.attach(MIMEText(body, "plain"))

    with smtplib.SMTP("smtp.gmail.com", 587) as server:
        server.starttls()
        server.login(sender, password)
        server.send_message(msg)
    print(f"Report sent to {recipient}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("csv_path", help="Path to the CSV data file")
    parser.add_argument("recipient", help="Recipient email address")
    args = parser.parse_args()

    generate_weekly_report(args.csv_path, args.recipient)


if __name__ == "__main__":
    main()
