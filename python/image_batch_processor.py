#!/usr/bin/env python3
"""Image Batch Processor (Resize, Compress, Convert).

Resize, compress, and convert images in bulk.

Usage:
    python image_batch_processor.py raw_screenshots/ optimized/ --max-width 1000
"""
import argparse
from pathlib import Path

from PIL import Image


def batch_process_images(input_dir, output_dir, max_width=1200,
                         quality=85, output_format="WEBP"):
    """Resize, compress, and convert images in bulk."""
    in_path = Path(input_dir)
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    supported = {".png", ".jpg", ".jpeg", ".bmp", ".tiff"}
    processed = 0

    for img_file in sorted(in_path.iterdir()):
        if img_file.suffix.lower() not in supported:
            continue

        with Image.open(img_file) as img:
            # Resize if wider than max_width, keep aspect ratio
            if img.width > max_width:
                ratio = max_width / img.width
                new_size = (max_width, int(img.height * ratio))
                img = img.resize(new_size, Image.LANCZOS)
            # Convert RGBA to RGB for formats that don't support alpha
            if img.mode == "RGBA" and output_format in ("JPEG", "WEBP"):
                img = img.convert("RGB")
            ext = ".webp" if output_format == "WEBP" else f".{output_format.lower()}"
            output_file = out_path / f"{img_file.stem}{ext}"
            img.save(output_file, format=output_format, quality=quality)
            processed += 1
            print(f"  Processed: {img_file.name} -> {output_file.name}")

    print(f"\nDone. Processed {processed} images.")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input_dir", help="Directory of source images")
    parser.add_argument("output_dir", help="Directory for processed images")
    parser.add_argument("--max-width", type=int, default=1200,
                        help="Max width in pixels (default: 1200)")
    parser.add_argument("--quality", type=int, default=85,
                        help="Output quality 1-100 (default: 85)")
    parser.add_argument("--format", default="WEBP", dest="output_format",
                        choices=["WEBP", "JPEG", "PNG"],
                        help="Output format (default: WEBP)")
    args = parser.parse_args()

    batch_process_images(args.input_dir, args.output_dir,
                         max_width=args.max_width, quality=args.quality,
                         output_format=args.output_format)


if __name__ == "__main__":
    main()
