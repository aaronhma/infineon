"""Download public datasets for driver awareness training.

Usage:
    uv run python -m models.datasets.download --dataset statefarm
    uv run python -m models.datasets.download --dataset mrl_eyes
    uv run python -m models.datasets.download --list
    uv run python -m models.datasets.download --dataset statefarm --zip /path/to/state-farm-distracted-driver-detection.zip
"""

import argparse
import os
import subprocess
import sys
import zipfile
from pathlib import Path

from tqdm import tqdm

DATA_DIR = Path(__file__).parent.parent / "data"

DATASETS = {
    "statefarm": {
        "description": "State Farm Distracted Driver Detection (~22K images, 10 classes)",
        "method": "kaggle_competition",
        "competition": "state-farm-distracted-driver-detection",
        "rules_url": "https://www.kaggle.com/competitions/state-farm-distracted-driver-detection/rules",
        "output_dir": "raw/statefarm",
    },
    "mrl_eyes": {
        "description": "MRL Eye Dataset (~85K eye images, open/closed)",
        "method": "url",
        "url": "http://mrl.cs.vsb.cz/data/eyedataset/mrlEyes_2018_01.zip",
        "output_dir": "raw/mrl_eyes",
    },
}


def extract_zip(zip_path: Path, output_dir: Path) -> None:
    """Extract a zip file with a progress bar."""
    with zipfile.ZipFile(zip_path, "r") as zf:
        members = zf.namelist()
        with tqdm(members, desc=f"Extracting {zip_path.name}", unit="file") as pbar:
            for member in pbar:
                zf.extract(member, output_dir)


def extract_zips(directory: Path) -> None:
    """Extract all zip files in a directory and remove them."""
    for zip_file in sorted(directory.glob("*.zip")):
        extract_zip(zip_file, directory)
        zip_file.unlink()


def download_kaggle_competition(
    dataset_info: dict, manual_zip: str | None = None
) -> Path:
    """Download a Kaggle competition dataset.

    Competition datasets require accepting the rules on Kaggle's website
    before the API allows downloading. If the API returns 403 Forbidden,
    the user must either:
        1. Accept rules at the competition URL, then retry
        2. Download the zip manually and pass it via --zip
    """
    output_dir = DATA_DIR / dataset_info["output_dir"]
    output_dir.mkdir(parents=True, exist_ok=True)

    competition = dataset_info["competition"]
    rules_url = dataset_info["rules_url"]

    # Option 1: User provided a manually-downloaded zip
    if manual_zip:
        zip_path = Path(manual_zip)
        if not zip_path.exists():
            print(f"Error: zip file not found: {zip_path}")
            sys.exit(1)
        size_mb = zip_path.stat().st_size / (1024 * 1024)
        print(f"Using manually downloaded zip: {zip_path} ({size_mb:.1f} MB)")
        extract_zip(zip_path, output_dir)
        extract_zips(output_dir)
        _print_done(output_dir)
        return output_dir

    # Option 2: Try the Kaggle API
    kaggle_json = Path.home() / ".kaggle" / "kaggle.json"
    if not kaggle_json.exists() and not os.environ.get("KAGGLE_USERNAME"):
        _print_kaggle_help(competition, rules_url, output_dir)
        sys.exit(1)

    print(f"Downloading from Kaggle: {competition}")
    print(
        f"(You must have accepted the competition rules first at: https://www.kaggle.com/c/state-farm-distracted-driver-detection)"
    )

    try:
        # Let kaggle print its own progress bar directly to the terminal
        result = subprocess.run(
            [
                "kaggle",
                "competitions",
                "download",
                "-c",
                competition,
                "-p",
                str(output_dir),
            ],
        )

        if result.returncode != 0:
            print()
            print("Kaggle download failed. If you see 403 Forbidden:")
            print()
            print(f"  1. Go to: {rules_url}")
            print(f"  2. Click 'I Understand and Accept'")
            print(f"  3. Re-run this command")
            print()
            print("Or download the zip manually from Kaggle and use --zip:")
            print(
                f"  uv run python -m models.datasets.download --dataset statefarm --zip /path/to/download.zip"
            )
            sys.exit(1)

    except FileNotFoundError:
        print("kaggle CLI not found. Install with: uv pip install kaggle")
        sys.exit(1)

    extract_zips(output_dir)
    _print_done(output_dir)
    return output_dir


def _print_kaggle_help(competition: str, rules_url: str, output_dir: Path) -> None:
    """Print setup instructions for Kaggle downloads."""
    print("Kaggle API credentials required.")
    print()
    print("Setup:")
    print("  1. Get your API key from: https://www.kaggle.com/settings")
    print("  2. Place kaggle.json at ~/.kaggle/kaggle.json")
    print(f"  3. Accept competition rules at: {rules_url}")
    print("  4. Re-run this command")
    print()
    print("Or download manually and use --zip:")
    print(
        f"  uv run python -m models.datasets.download --dataset statefarm --zip /path/to/download.zip"
    )


def download_url(dataset_info: dict) -> Path:
    """Download a dataset from a direct URL with progress bar."""
    import urllib.request

    output_dir = DATA_DIR / dataset_info["output_dir"]
    output_dir.mkdir(parents=True, exist_ok=True)

    url = dataset_info["url"]
    filename = url.split("/")[-1]
    filepath = output_dir / filename

    if filepath.exists():
        print(f"Already downloaded: {filepath}")
    else:
        print(f"Downloading {url}...")

        # Get file size for progress bar
        response = urllib.request.urlopen(url)
        total_size = int(response.headers.get("Content-Length", 0))

        with tqdm(
            total=total_size, unit="B", unit_scale=True, desc=f"Downloading {filename}"
        ) as pbar:

            def _reporthook(block_num, block_size, total):
                pbar.update(block_size)

            urllib.request.urlretrieve(url, filepath, reporthook=_reporthook)

        size_mb = filepath.stat().st_size / (1024 * 1024)
        print(f"Saved: {filepath} ({size_mb:.1f} MB)")

    # Extract if zip
    if filepath.suffix == ".zip":
        extract_zip(filepath, output_dir)
        filepath.unlink()

    _print_done(output_dir)
    return output_dir


def _print_done(output_dir: Path) -> None:
    """Print summary of downloaded dataset."""
    file_count = sum(1 for _ in output_dir.rglob("*") if _.is_file())
    total_bytes = sum(f.stat().st_size for f in output_dir.rglob("*") if f.is_file())
    total_mb = total_bytes / (1024 * 1024)
    print(f"Done: {output_dir} ({file_count:,} files, {total_mb:.1f} MB)")


def main():
    parser = argparse.ArgumentParser(description="Download driver awareness datasets")
    parser.add_argument(
        "--dataset", type=str, choices=list(DATASETS.keys()), help="Dataset to download"
    )
    parser.add_argument("--list", action="store_true", help="List available datasets")
    parser.add_argument("--all", action="store_true", help="Download all datasets")
    parser.add_argument(
        "--zip",
        type=str,
        default=None,
        help="Path to a manually downloaded zip file (for Kaggle competition datasets)",
    )
    args = parser.parse_args()

    if args.list or (not args.dataset and not args.all):
        print("Available datasets:")
        print()
        for name, info in DATASETS.items():
            print(f"  {name:20s} {info['description']}")
        print()
        print("Usage: uv run python -m models.datasets.download --dataset <name>")
        print(
            "       uv run python -m models.datasets.download --dataset statefarm --zip /path/to/download.zip"
        )
        return

    targets = list(DATASETS.keys()) if args.all else [args.dataset]

    for name in targets:
        info = DATASETS[name]
        print(f"\n{'=' * 60}")
        print(f"Downloading: {name}")
        print(f"{'=' * 60}")

        if info["method"] == "kaggle_competition":
            download_kaggle_competition(info, manual_zip=args.zip)
        elif info["method"] == "url":
            download_url(info)


if __name__ == "__main__":
    main()
