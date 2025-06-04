#!/bin/bash
# Moocow Mooheda 25/Mar25
# Dependencies: "exiftool" "mkvpropedit" "sha256sum" "ffmpeg"

SCRIPT_VERSION="1.6.1-kde"
newfileext="m4v"

# Check for required dependencies
check_dependencies() {
    local deps=("exiftool" "mkvpropedit" "sha256sum" "ffmpeg")
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        exit 1
    fi
}

# Strip metadata from file
strip_metadata() {
    local file="$1"
    echo "Stripping metadata from: $file"
    exiftool -overwrite_original -all= "$file"
    mkvpropedit "$file" --tags all: --delete title 2>/dev/null
}

# Optionally rename to .m4v
rename_file_ext() {
    local file="$1"
    local dir=$(dirname "$file")
    local base=$(basename "$file")
    local name="${base%.*}"
    local newname="$dir/${name}.${newfileext}"
    if [[ "$file" != "$newname" ]]; then
        mv "$file" "$newname"
        echo "Renamed to: $newname"
    fi
}

# Process single file
process_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Skipping non-file: $file"
        return
    fi
    strip_metadata "$file"
    rename_file_ext "$file"
}

# Entry point
main() {
    check_dependencies

    # If files were passed via arguments (from Dolphin, Caja, etc.)
    if [ "$#" -gt 0 ]; then
        for file in "$@"; do
            process_file "$file"
        done
        exit 0
    fi

    # No files provided, fallback to interactive usage
    echo "No files passed. Please run from a file manager context menu or provide files as arguments."
    exit 1
}

main "$@"
