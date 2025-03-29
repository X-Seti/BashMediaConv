#!/bin/bash
#(X-Seti) Mooheda 29Mar25
#Dependencies: "exiftool" "mkvpropedit" "sha256sum" "ffmpeg"

# Script version
SCRIPT_VERSION="1.4.2"

# Global variables
clean_filenames=false
dry_run=false
backups=false
verbose=false
rename=false
recursive=false
convert_to_mp4=false
conv_oldfileformats=false
rm_metadata_files=false
backup_dir="./backups"
newfileext="m4v"
processing_log=".processed_files.log"

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
        echo "Press Enter to exit..."
        read
        exit 1
    fi
}

# Check if running in a terminal
if [ -t 1 ]; then
    # Already in a terminal, continue normal execution
    : # no-op
else
    # Not in a terminal, launch a new terminal
    x-terminal-emulator -e "$0" || \
    gnome-terminal -- bash -c "$0; exec bash" || \
    konsole -e bash "$0" || \
    xterm -e bash "$0" || \
    open -a Terminal "$0" || \
    echo "Unable to open terminal"
    exit 0
fi

# Clean filename by replacing dots with spaces, ensuring proper .ext format
clean_filename() {
    local file="$1"
    if [ "$clean_filenames" = true ]; then
        local dir=$(dirname "$file")
        local filename=$(basename "$file")
        local extension="${filename##*.}"
        local name="${filename%.*}"

        # Replace dots with spaces in the filename, then add a dot before the ext
        local new_filename=$(echo "$name" | sed 's/\./ /g')."$extension"
        local new_path="$dir/$new_filename"

        # Only rename if the filename actually changes
        if [ "$filename" != "$new_filename" ]; then
            mv "$file" "$new_path"
            echo "Renamed: $file -> $new_path"
            return 0
        fi
    fi
    echo "$file"
}

# Remove associated metadata files
remove_assoc_metadata_files() {
    local file="$1"
    local dir=$(dirname "$file")
    local filename=$(basename "$file" .*) # Get filename without extension
    local base_filename=$(echo "$filename" | sed 's/\.[^.]*$//')  # Remove resolution/quality part

    # If flag is not set, return
    if [ "$rm_metadata_files" = false ]; then
        return 0
    fi

    # Remove .nfo files with various naming patterns
    local nfo_patterns=(
        "$dir/$filename.nfo"                # Exact match
        "$dir/$base_filename.nfo"           # Without resolution
        "$dir/"*"$base_filename"*".nfo"     # Wildcard match
    )

    # Remove thumbnail files with various naming patterns
    local thumb_patterns=(
        "$dir/$filename-thumb.jpg"          # With hyphen
        "$dir/$filename.jpg"                # Direct match
        "$dir/$base_filename"*"-thumb.jpg"  # Wildcard match
        "$dir/thumb.jpg"                    # Generic thumb
    )

    # Remove matching NFO files
    for pattern in "${nfo_patterns[@]}"; do
        for nfo in $pattern; do
            if [ -f "$nfo" ]; then
                if [ "$dry_run" = "true" ]; then
                    echo "[DRY RUN] Would remove NFO file: $nfo"
                else
                    rm "$nfo"
                    echo "Removed NFO file: $nfo"
                fi
            fi
        done
    done

    # Remove matching thumbnail files
    for pattern in "${thumb_patterns[@]}"; do
        for thumb in $pattern; do
            if [ -f "$thumb" ]; then
                if [ "$dry_run" = "true" ]; then
                    echo "[DRY RUN] Would remove thumbnail: $thumb"
                else
                    rm "$thumb"
                    echo "Removed thumbnail: $thumb"
                fi
            fi
        done
    done

    return 0
}

# Convert file to MP4
convert_to_mp4() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    # If conversion is disabled, return
    if [ "$convert_to_mp4" = false ]; then
        return 1
    fi

    echo "Converting to MP4: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert to MP4: $file"
        return 0
    fi

    # Backup the original file if backups are enabled
    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    # Create output filename
    local output_file="${file%.*}.mp4"
    local temp_output_file="${file%.*}_converted.mp4"

    # Use ffmpeg to convert the file
    if ffmpeg -i "$file" -c:v libx264 -c:a aac -strict experimental "$temp_output_file"; then
        # Remove original file and rename temp file
        rm "$file"
        mv "$temp_output_file" "$output_file"

        echo "✓ Converted to MP4: $output_file"
        log_processed_file "$output_file"
        return 0
    else
        echo "✗ Failed to convert to MP4: $file"
        return 1
    fi
}

# Detect file type using file extension
detect_file_type() {
    local file="$1"
    local ext="${file##*.}"
    echo "${ext,,}"  # Convert to lowercase
}

# Backup file to specified backup directory
backup_file() {
    local file="$1"
    if [ "$backups" = "true" ]; then
        local backup_dir="${2:-./backups}"

        # Create backup directory if it doesn't exist
        mkdir -p "$backup_dir"

        # Get filename
        local filename=$(basename "$file")
        # Copy file to backup directory
        cp -p "$file" "$backup_dir/$filename"
        if [ "$verbose" = "true" ]; then
            echo "Backed up: $file -> $backup_dir/$filename"
        fi
        return 0
    fi
}

# Check if file has been processed previously
is_file_processed() {
    local file="$1"

    # Validate file parameter
    if [ -z "$file" ]; then
        echo "Error: Empty filename passed to is_file_processed()" >&2
        return 1
    fi

    # Check if file actually exists
    if [ ! -f "$file" ]; then
        echo "Error: File does not exist: $file" >&2
        return 1
    fi

    # Create log file if it doesn't exist
    [ -f "$processing_log" ] || touch "$processing_log"

    # Check if file hash exists in log
    local file_hash=$(sha256sum "$file" | awk '{print $1}')
    grep -q "$file_hash" "$processing_log"
}

# Log processed file
log_processed_file() {
    local file="$1"

    # Validate file parameter
    if [ -z "$file" ]; then
        echo "Error: Empty filename passed to log_processed_file()" >&2
        return 1
    fi

    # Check if file actually exists
    if [ ! -f "$file" ]; then
        echo "Error: File does not exist: $file" >&2
        return 1
    fi

    # Ensure log file exists
    [ -f "$processing_log" ] || touch "$processing_log"

    # Get file hash and log it with absolute path
    local file_hash=$(sha256sum "$file" | awk '{print $1}')
    local abs_path=$(readlink -f "$file")
    echo "$file_hash $abs_path" >> "$processing_log"
}

# Function to process files in a directory
process_files() {
    local dir="${1:-.}"  # Use current directory if no argument provided
    # Find video files based on extensions and recursion flag
    local find_cmd=("find" "$dir" "-type" "f")
    if [ "$recursive" = false ]; then
        find_cmd+=("-maxdepth" "1")
    fi
    find_cmd+=(\(
        "-name" "*.mp4" "-o"
        "-name" "*.mpg" "-o"
        "-name" "*.mpeg" "-o"
        "-name" "*.avi" "-o"
        "-name" "*.m4v" "-o"
        "-name" "*.mkv" "-o"
        "-name" "*.flv" "-o"
        "-name" "*.mov"
    \))

    # Process each found file
    while IFS= read -r file; do
        ext="${file##*.}"
        ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        case "$ext" in
            m4v|mkv|mp4)
                # Do not convert these file types
                strip_metadata "$file" "$backup_dir"
                ;;
            mpg|mpeg|avi|flv|mov)
                # Conditionally convert other file types
                strip_metadata "$file" "$backup_dir"
                if [ "$conv_oldfileformats" = "true" ]; then
                    convert_to_mp4 "$file" "$backup_dir"
                fi
                ;;
        esac
    done < <("${find_cmd[@]}")
}

# Function to strip metadata from video files
strip_metadata() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local file_type

    # Check if file has been processed
    if is_file_processed "$file"; then
        echo "Skipping already processed file: $file"
        return 0
    fi

    # Clean filename first
    file=$(clean_filename "$file")
    echo "Processing: $file"

    # Remove associated metadata files BEFORE processing the video file
    remove_assoc_metadata_files "$file"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would strip metadata from: $file"
        return 0
    fi

    # Backup the original file
    backup_file "$file" "$backup_dir"

    # Detect file type
    file_type=$(detect_file_type "$file")

    # Rename file to .m4v if rename option is true
    if [ "$rename" = "true" ]; then
        local new_name="${file%.*}.$newfileext"
        mv "$file" "$new_name"
        file="$new_name"
        echo "Renamed to: $file"
    fi

    # Try exiftool for MPEG/MPG/MP4/M4V/FLV/MOV
    if [[ "$file_type" == "mpg" || "$file_type" == "mpeg" || "$file_type" == "mp4" || "$file_type" == "m4v" || "$file_type" == "flv" || "$file_type" == "mov" ]]; then
        if exiftool -overwrite_original -All= "$file"; then
            echo "✓ Processed with exiftool: $file"
            # Log processed file
            log_processed_file "$file"
            return 0
        fi
    fi

    # For AVI files, use ffmpeg
    if [[ "$file_type" == "avi" ]]; then
        local temp_file="${file%.*}_stripped.avi"
        if ffmpeg -i "$file" -codec copy -map_metadata -1 "$temp_file"; then
            # Replace original file
            mv "$temp_file" "$file"
            echo "✓ Processed AVI with ffmpeg: $file"
            # Log processed file
            log_processed_file "$file"
            return 0
        else
            echo "✗ Failed to process AVI with ffmpeg: $file"
            return 1
        fi
    fi

    # If MKV, use existing MKV processing
    if [ "$file_type" = "mkv" ]; then
        process_mkv "$file" "$backup_dir"
        return $?
    fi

    # If all methods fail
    echo "!! Unable to process file: $file"
    return 1
}

# Function to process MKV files
process_mkv() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    # Check if file has been processed
    if is_file_processed "$file"; then
        echo "Skipping already processed file: $file"
        return 0
    fi

    # Clean filename first
    file=$(clean_filename "$file")

    # Remove associated metadata files BEFORE processing the MKV file
    remove_assoc_metadata_files "$file"

    echo "Processing MKV: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process MKV: $file"
        return 0
    fi

    # Rename file to .m4v if rename option is true
    if [ "$rename" = "true" ]; then
        local new_name="${file%.*}.$newfileext"
        mv "$file" "$new_name"
        file="$new_name"
        echo "Renamed to: $file"
    fi

    if [ "$backups" = "true" ]; then
        # Backup the original file
        backup_file "$file" "$backup_dir"
    fi

    # Remove title metadata
    if mkvpropedit "$file" -d title; then
        echo "✓ Processed with mkvpropedit: $file"
        # Log processed file
        log_processed_file "$file"
    else
        echo "✗ Failed to process with mkvpropedit: $file"
        return 1
    fi
}

# Set drag and drop specific defaults
set_drag_drop_defaults() {
    clean_filenames=true
    rename=true
    backups=true
    rm_metadata_files=true
}

# Main script for processing
main() {
    # Check if script is invoked with drag and drop
    local is_drag_drop=false

    # Detect drag and drop by checking first argument's source
    if [ $# -gt 0 ]; then
        for path in "$@"; do
            # Assuming drag and drop if paths exist and are files/directories
            if [ -e "$path" ]; then
                is_drag_drop=true
                break
            fi
        done
    fi

    # Set defaults for drag and drop mode
    if [ "$is_drag_drop" = true ]; then
        set_drag_drop_defaults
        echo "Drag and Drop Mode Activated"
    fi

    # Check dependencies before processing
    check_dependencies

    # Parse command-line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --convert-avi-mpg-flv-mov|--conv-oldfileformats)
                conv_oldfileformats=true
                shift
                ;;
            --version)
                echo "Video File Processor version $SCRIPT_VERSION"
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --backups)
                backups=true
                shift 2
                ;;
            --backup-dir)
                backup_dir="$2"
                shift 2
                ;;
            --clean-filenames)
                clean_filenames=true
                shift
                ;;
            --rename)
                rename=true
                shift
                ;;
            --recursive)
                recursive=true
                shift
                ;;
            --convert-to-mp4)
                convert_to_mp4=true
                shift
                ;;
            --remove-metadata-files)
                rm_metadata_files=true
                shift
                ;;
            --reset-log)
                # Option to reset processing log
                rm -f "$processing_log"
                echo "Processing log reset."
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    # If no arguments, prompt user
    if [ $# -eq 0 ]; then
        # Ask about filename cleaning if not specified via CLI
        if [ "$clean_filenames" = false ]; then
            read -p "Replace dots with spaces in filenames? [y/N]: " clean_response
            if [[ "$clean_response" =~ ^[Yy]$ ]]; then
                clean_filenames=true
            fi
        fi
        # Rename file .ext for processed files
        if [ "$rename" = false ]; then
            read -p "Rename file .ext for processed files? [y/N]: " rename_response
            if [[ "$rename_response" =~ ^[Yy]$ ]]; then
                rename=true
            fi
        fi
        # Ask about file conversion
        if [ "$convert_to_mp4" = false ]; then
            read -p "Convert video files to MP4? [y/N]: " convert_response
            if [[ "$convert_response" =~ ^[Yy]$ ]]; then
                convert_to_mp4=true
            fi
        fi
        # Ask about converting specific file types
        if [ "$convert_to_mp4" = true ]; then
            read -p "Convert AVI, MPG, FLV, MOV, MPEG (Old Movie Formats) to MP4? [y/N]: " convert_specific_response
            if [[ "$convert_specific_response" =~ ^[Yy]$ ]]; then
                conv_oldfileformats=true
                convert_to_mp4=false
            fi
        fi
        # Ask about file backup processing
        if [ "$backups" = false ]; then
            read -p "Backup files to ./backups folder? [y/N]: " backups_response
            if [[ "$backups_response" =~ ^[Yy]$ ]]; then
                backups=true
            fi
        fi
        # Ask about removing metadata files
        if [ "$rm_metadata_files" = false ]; then
            read -p "Remove .nfo and thumb.jpg files? [y/N]: " metadata_files_response
            if [[ "$metadata_files_response" =~ ^[Yy]$ ]]; then
                rm_metadata_files=true
            fi
        fi
        # Ask about recursive processing
        if [ "$recursive" = false ]; then
            read -p "Process files recursively? [y/N]: " recursive_response
            if [[ "$recursive_response" =~ ^[Yy]$ ]]; then
                recursive=true
            fi
        fi
        read -p "Process all video files, Continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            echo "Press Enter to exit..."
            read
            exit 0
        fi
        # Process files in current directory
        process_files
    else
        # Process specified files or directories
        for path in "$@"; do
            if [ -f "$path" ]; then
                # Process individual files
                ext="${path##*.}"
                ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
                case "$ext" in
                    mpeg|mpg|mp4|avi|m4v|flv|mov)
                        strip_metadata "$path" "$backup_dir"
                        if [ "$conv_oldfileformats" = "true" ]; then
                            convert_to_mp4 "$path" "$backup_dir"
                        fi
                        ;;
                    mkv)
                        process_mkv "$path" "$backup_dir"
                        ;;
                    *)
                        echo "Unsupported file type: $path"
                        ;;
                esac
            elif [ -d "$path" ]; then
                # Process files in specified directory
                echo "Processing files in directory: $path"
                process_files "$path"
            else
                echo "Not a file or directory: $path"
            fi
        done
    fi

    echo "===================="
    echo "Processing complete."
    echo "Press Enter to exit..."
    read
}

# Call main function with all arguments
main "$@"

