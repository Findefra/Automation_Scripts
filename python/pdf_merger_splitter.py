#!/usr/bin/env python3
"""PDF Merger and Splitter.

Merge multiple PDFs into one file, or extract a page range from a PDF.

Usage:
    python pdf_merger_splitter.py merge a.pdf b.pdf -o merged.pdf
    python pdf_merger_splitter.py split full_report.pdf --start 12 --end 18 -o section_3.pdf
"""
import argparse
from PyPDF2 import PdfReader, PdfWriter


def merge_pdfs(pdf_list, output_path):
    """Merge multiple PDFs into a single file."""
    writer = PdfWriter()
    for pdf_file in pdf_list:
        reader = PdfReader(pdf_file)
        for page in reader.pages:
            writer.add_page(page)
        print(f"  Added: {pdf_file} ({len(reader.pages)} pages)")
    with open(output_path, "wb") as f:
        writer.write(f)
    print(f"\nMerged into: {output_path}")


def split_pdf(input_path, start_page, end_page, output_path):
    """Extract a range of pages from a PDF (1-based, inclusive)."""
    reader = PdfReader(input_path)
    writer = PdfWriter()
    for i in range(start_page - 1, min(end_page, len(reader.pages))):
        writer.add_page(reader.pages[i])
    with open(output_path, "wb") as f:
        writer.write(f)
    print(f"Extracted pages {start_page}-{end_page} -> {output_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p_merge = sub.add_parser("merge", help="Merge multiple PDFs into one")
    p_merge.add_argument("pdfs", nargs="+", help="PDF files to merge")
    p_merge.add_argument("-o", "--output", default="merged.pdf", help="Output file")

    p_split = sub.add_parser("split", help="Extract a page range from a PDF")
    p_split.add_argument("pdf", help="Input PDF file")
    p_split.add_argument("--start", type=int, required=True, help="First page (1-based)")
    p_split.add_argument("--end", type=int, required=True, help="Last page (inclusive)")
    p_split.add_argument("-o", "--output", default="extracted.pdf", help="Output file")

    args = parser.parse_args()
    if args.command == "merge":
        merge_pdfs(args.pdfs, args.output)
    else:
        split_pdf(args.pdf, args.start, args.end, args.output)


if __name__ == "__main__":
    main()
