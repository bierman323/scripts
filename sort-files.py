#!/usr/bin/env python3
"""Sort loose files in ~/Documents and ~/Downloads into categorized subdirectories."""

import argparse
import re
import shutil
from collections import defaultdict
from pathlib import Path

DOCUMENTS_DIR = Path.home() / "Documents"
DOWNLOADS_DIR = Path.home() / "Downloads"

EXTENSION_MAP = {
    "images": {"png", "jpg", "jpeg", "svg", "webp", "heic", "gif"},
    "videos": {"mp4", "mov", "mkv", "mp3", "m4a", "wav"},
    "presentations": {"pptx", "ppt", "pot", "key"},
    "data-exports": {"xlsx", "xls", "xlsm", "csv", "tsv", "json", "sqlite3", "iqy"},
    "certs-and-keys": {"pem", "asc", "cer", "crt", "p12", "pfx", "gpg"},
    "ebooks": {"epub", "mobi"},
}

DOWNLOADS_ONLY_EXTENSIONS = {
    "installers": {"dmg", "msi", "pkg"},
}

AMBIGUOUS_EXTENSIONS = {"pdf", "docx", "doc", "rtf", "html", "md", "txt", "zip"}

# PDF heuristics, checked in order
PDF_RULES = [
    ("training", re.compile(r"cert|certificate|slides_|course|training|sans|cissp")),
    ("reports", re.compile(r"report|pentest|threat|assessment|analysis|incident|briefing|whitepaper")),
    ("ebooks", re.compile(r"handbook|guide|book|manual")),
    ("templates", re.compile(r"template")),
    ("personal", re.compile(r"receipt|invoice|bonus|benefit|insurance|rental|offer.letter|rsu|disability|salary")),
    ("reference", re.compile(r"cheatsheet|cheat-sheet|quickref|checklist")),
]

CONFERENCE_PAPER_RE = re.compile(r"^[a-z]+ [a-z']+_.+")


def classify_by_extension(ext, is_downloads):
    for category, extensions in EXTENSION_MAP.items():
        if ext in extensions:
            return category
    if is_downloads:
        for category, extensions in DOWNLOADS_ONLY_EXTENSIONS.items():
            if ext in extensions:
                return category
    if ext in AMBIGUOUS_EXTENSIONS:
        return None
    return None


def classify_pdf(name_lower, is_downloads):
    if is_downloads and CONFERENCE_PAPER_RE.match(name_lower):
        return "conference-papers"
    for category, pattern in PDF_RULES:
        if pattern.search(name_lower):
            return category
    return "work-docs"


def classify_by_name(filename, ext, is_downloads):
    name_lower = filename.lower()
    if ext == "pdf":
        return classify_pdf(name_lower, is_downloads)
    if ext in {"docx", "doc", "rtf"}:
        return "work-docs"
    if ext == "html":
        return "reference"
    if ext in {"md", "txt"}:
        return "reference"
    if ext == "zip" and is_downloads:
        return "installers"
    return None


def resolve_collision(dest):
    if not dest.exists():
        return dest
    stem = dest.stem
    suffix = dest.suffix
    parent = dest.parent
    counter = 1
    while True:
        candidate = parent / f"{stem}_{counter}{suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def process_directory(directory, dry_run, verbose):
    is_downloads = directory == DOWNLOADS_DIR
    counts = defaultdict(int)

    for filepath in sorted(directory.iterdir()):
        if not filepath.is_file() or filepath.name.startswith("."):
            continue

        ext = filepath.suffix.lstrip(".").lower()
        if not ext:
            continue

        category = classify_by_extension(ext, is_downloads)
        if category is None:
            category = classify_by_name(filepath.name, ext, is_downloads)
        if category is None:
            continue

        dest_dir = directory / category
        if not dest_dir.is_dir():
            continue

        dest = resolve_collision(dest_dir / filepath.name)

        if dry_run:
            if verbose:
                print(f"  [dry run] {filepath.name} -> {category}/")
        else:
            shutil.move(str(filepath), str(dest))
            if verbose:
                print(f"  {filepath.name} -> {category}/")

        counts[category] += 1

    return counts


def print_summary(counts, dry_run):
    total = sum(counts.values())
    if total == 0:
        print("No loose files found.")
        return

    prefix = "[dry run] " if dry_run else ""
    print(f"\n{prefix}Summary:")
    for category in sorted(counts):
        print(f"  {category:<20s} {counts[category]}")
    print("  ---")
    print(f"  {'Total':<20s} {total}")


def main():
    parser = argparse.ArgumentParser(description="Sort loose files into categorized subdirectories.")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Show what would be moved")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show each move")
    parser.add_argument("directories", nargs="*", help="Directories to sort (default: ~/Documents ~/Downloads)")
    args = parser.parse_args()

    if args.directories:
        dirs = []
        for d in args.directories:
            p = Path(d).resolve()
            if not p.is_dir():
                print(f"Error: '{d}' is not a valid directory")
                raise SystemExit(1)
            dirs.append(p)
    else:
        dirs = [DOCUMENTS_DIR, DOWNLOADS_DIR]

    all_counts = defaultdict(int)
    for directory in dirs:
        print(f"--- Sorting {directory.name} ---")
        counts = process_directory(directory, args.dry_run, args.verbose)
        for cat, n in counts.items():
            all_counts[cat] += n

    print_summary(all_counts, args.dry_run)


if __name__ == "__main__":
    main()
