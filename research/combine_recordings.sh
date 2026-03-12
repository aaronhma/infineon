#!/bin/bash

# Combine MKV chunks in recordings/ folders into single MP4 files
# Each UUID folder contains chunk_XXXX.mkv files that are combined into UUID.mp4

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECORDINGS_DIR="$SCRIPT_DIR/recordings"

if [ ! -d "$RECORDINGS_DIR" ]; then
    echo "Error: recordings/ directory not found at $RECORDINGS_DIR"
    exit 1
fi

# Check for ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is required but not installed"
    exit 1
fi

# Find all UUID folders (directories that match UUID pattern)
shopt -s nullglob
for folder in "$RECORDINGS_DIR"/*/; do
    # Get folder name (UUID)
    folder_name=$(basename "$folder")
    
    # Skip if not a UUID pattern (8-4-4-4-12 hex format)
    if [[ ! "$folder_name" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo "Skipping non-UUID folder: $folder_name"
        continue
    fi
    
    output_file="$RECORDINGS_DIR/${folder_name}.mp4"
    
    # Skip if output already exists
    if [ -f "$output_file" ]; then
        echo "Skipping $folder_name - MP4 already exists"
        continue
    fi
    
    # Check for MKV chunks
    shopt -s nullglob
    chunks=("$folder"chunk_*.mkv)
    shopt -u nullglob
    
    if [ ${#chunks[@]} -eq 0 ]; then
        echo "No MKV chunks found in $folder_name"
        continue
    fi
    
    echo "Processing $folder_name (${#chunks[@]} chunks)..."
    
    # Create temp file list for ffmpeg concat
    concat_file=$(mktemp)
    for chunk in "${chunks[@]}"; do
        # Escape single quotes in path
        escaped_path=$(sed "s/'/'\\\\''/g" <<< "$chunk")
        echo "file '$escaped_path'" >> "$concat_file"
    done
    
    # Combine using ffmpeg concat demuxer with timestamp regeneration
    # -fflags +genpts: regenerate PTS if missing
    # -avoid_negative_ts make_zero: fix timestamp discontinuities between chunks
    # -map 0: include all streams
    ffmpeg -f concat -safe 0 -fflags +genpts -i "$concat_file" \
        -c copy -map 0 -movflags +faststart \
        "$output_file" -y 2>/dev/null
    
    rm -f "$concat_file"
    
    if [ -f "$output_file" ]; then
        # Get duration for confirmation
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$output_file" 2>/dev/null || echo "unknown")
        echo "  ✓ Created $folder_name.mp4 (${duration}s)"
    else
        echo "  ✗ Failed to create $folder_name.mp4"
    fi
done

echo ""
echo "Done! Combined videos are in: $RECORDINGS_DIR/"
