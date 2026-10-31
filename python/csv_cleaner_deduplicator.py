#!/usr/bin/env python3
"""CSV Data Cleaner and Deduplicator.

Clean, deduplicate, and standardize a CSV file. Writes a *_cleaned.csv
file unless --output is given.

Usage:
    python csv_cleaner_deduplicator.py messy_client_data.csv
"""
import argparse
from pathlib import Path

import pandas as pd


def clean_csv(input_file, output_file=None):
    """Clean, deduplicate, and standardize a CSV file."""
    df = pd.read_csv(input_file)
    original_rows = len(df)
    print(f"  Original: {original_rows} rows, {len(df.columns)} columns")

    # Strip whitespace from string columns
    for col in df.select_dtypes(include=["object"]).columns:
        df[col] = df[col].str.strip()

    # Drop fully empty rows
    df.dropna(how="all", inplace=True)

    # Remove exact duplicate rows
    dupes = df.duplicated().sum()
    df.drop_duplicates(inplace=True)

    # Standardize column names: lowercase, replace spaces with underscores
    df.columns = [col.strip().lower().replace(" ", "_") for col in df.columns]

    # Fill missing values in numeric columns with 0
    for col in df.select_dtypes(include=["number"]).columns:
        df[col] = df[col].fillna(0)

    if output_file is None:
        output_file = str(Path(input_file).with_suffix("")) + "_cleaned.csv"
    df.to_csv(output_file, index=False)
    print(f"  Removed {dupes} duplicates")
    print(f"  Final: {len(df)} rows -> {output_file}")
    return df


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input_file", help="Path to the CSV file to clean")
    parser.add_argument("-o", "--output", default=None,
                        help="Output CSV path (default: <input>_cleaned.csv)")
    args = parser.parse_args()

    clean_csv(args.input_file, args.output)


if __name__ == "__main__":
    main()
