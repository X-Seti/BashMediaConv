#!/bin/bash
#Mooheda (X-Seti) 16/Apr25 - 25/May25
#Dependencies: "exiftool" "mkvpropedit" "sha256sum" "ffmpeg" "imagemagick"

# Script version - date - add_gui on click.
SCRIPT_VERSION="2.0.0 - 24-05-25"

# Global variables - Initialize all counters to prevent arithmetic errors
clean_filenames=false
dry_run=false
backups=false
verbose=false
renameext=false
ifexists=false
recursive=false
convert_to_mp4=false
conv_oldfileformats=false
rm_metadata_files=false
replace_underscores=false
capitalize_filenames=false
use_handbrake_settings=false
process_images=false
optimize_images=false
convert_images=false
image_quality=85
files_processed=0
files_failed=0
files_skipped=0
thumbnails_removed=0
metadata_files_removed=0
bytes_processed=0
skipped_files=0
mp4_files_processed=0
mkv_files_processed=0
mp3_files_processed=0
flac_files_processed=0
audio_files_processed=0
video_files_processed=0
image_files_processed=0
other_files_processed=0
backup_dir="./backups"
newfileext="m4v"
processing_log=".processed_files.log"
audio_output_format="mp3"
image_output_format="jpg"

declare -A audio_bitrates=(
  ["mp3"]="192k"
  ["aac"]="192k"
  ["flac"]="1024k"
  ["ogg"]="192k"
  ["wav"]="1536k"
  ["m4a"]="256k"
  ["wma"]="192k"
  ["opus"]="128k"
  ["amr"]="12.2k"
  ["aiff"]="1536k"
)

declare -A audio_quality=(
  ["mp3"]="0"       # 0-9 (lower is better)
  ["flac"]="8"      # 0-8 (higher is better)
  ["ogg"]="5"       # -1 to 10 (higher is better)
  ["aac"]="4"       # 1-5 (higher is better)
  ["wma"]="3"       # 0-100 (higher is better)
  ["opus"]="10"     # 0-10 (higher is better)
)

declare -A supported_image_formats=(
  ["jpg"]="jpeg"
  ["jpeg"]="jpeg"
  ["png"]="png"
  ["gif"]="gif"
  ["bmp"]="bmp"
  ["tiff"]="tiff"
  ["tif"]="tiff"
  ["webp"]="webp"
  ["heic"]="heic"
  ["heif"]="heif"
  ["avif"]="avif"
  ["tga"]="tga"
  ["dds"]="dds"
  ["cr2"]="cr2"
  ["nef"]="nef"
  ["arw"]="arw"
  ["dng"]="dng"
  ["orf"]="orf"
  ["rw2"]="rw2"
  ["pef"]="pef"
  ["srw"]="srw"
  ["raf"]="raf"
)

parallel_processing=true
max_parallel_jobs=4

#I/O performance with better error handling
improve_io_performance() {
    if command -v ionice >/dev/null 2>&1; then
        ionice -c 2 -n 7 -p $$ 2>/dev/null || true
    fi

    # Set optimal buffer sizes
    export DD_OPTS="bs=64k"
    export TMPDIR="${TMPDIR:-/tmp}"
}

check_dependencies() {
    local deps=("exiftool" "mkvpropedit" "sha256sum" "ffmpeg")
    local optional_deps=("convert" "identify" "zenity" "kdialog" "yad")
    local missing=()
    local outdated=()
    local missing_optional=()

    echo "Checking required dependencies..."
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        else
            case "$cmd" in
                ffmpeg)
                    version=$(ffmpeg -version 2>/dev/null | head -n1 | awk '{print $3}' | cut -d. -f1)
                    if [ -n "$version" ] && [ "$version" -lt 4 ]; then
                        outdated+=("$cmd (version $version, recommended 4.0+)")
                    fi
                    ;;
                exiftool)
                    version=$(exiftool -ver 2>/dev/null | cut -d. -f1)
                    if [ -n "$version" ] && [ "$version" -lt 12 ]; then
                        outdated+=("$cmd (version $version, recommended 12.0+)")
                    fi
                    ;;
            esac
        fi
    done

    echo "Checking optional dependencies..."
    for cmd in "${optional_deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_optional+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "Error: Missing required dependencies: ${missing[*]}"
        echo -e "Please install the missing dependencies:"
        echo -e "Ubuntu/Debian: sudo apt install libimage-exiftool-perl mkvtoolnix-cli coreutils ffmpeg"
        echo -e "Fedora/RHEL: sudo dnf install perl-Image-ExifTool mkvtoolnix coreutils ffmpeg"
        echo -e "macOS: brew install exiftool mkvtoolnix coreutils ffmpeg"
        echo -e "\nPress Enter to exit..."
        read
        exit 1
    fi

    if [ ${#outdated[@]} -gt 0 ]; then
        echo -e "Warning: Some dependencies are outdated: ${outdated[*]}"
        echo -e "The script may not work correctly with older versions."
        read -p "Do you want to continue anyway? [y/N]: " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Exiting. Please update the dependencies and try again."
            exit 1
        fi
    fi

    if [ ${#missing_optional[@]} -gt 0 ]; then
        echo -e "Optional dependencies not found: ${missing_optional[*]}"
        echo -e "Some features may not be available:"
        echo -e "- ImageMagick (convert, identify): Image processing and optimization"
        echo -e "- GUI tools (zenity, kdialog, yad): Graphical user interface"
    fi

    if command -v convert >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; then
        process_images=true
        echo "ImageMagick found - Image processing enabled"
    else
        echo "ImageMagick not found - Image processing will use exiftool only"
    fi
}

handle_error() {
    local error_code=$1
    local error_message=$2
    local operation=$3
    local file=$4
    local line_number=${5:-"unknown"}

    echo -e "Error (code $error_code) at line $line_number during $operation: $error_message" >&2
    echo -e "Failed to process: $file" >&2

    local error_log="${processing_log%.log}_errors.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR[$error_code]: $operation failed for '$file': $error_message (line: $line_number)" >> "$error_log"

    case "$operation" in
        "metadata_removal")
            echo "Attempting alternative method for metadata removal..."
            ;;
        "file_conversion")
            echo "File conversion failed, keeping original file"
            ;;
        "backup_creation")
            echo "Backup creation failed, aborting operation for safety"
            return 1
            ;;
    esac

    files_failed=$((files_failed + 1))
}

rotate_logs() {
    local log_file="$1"
    local max_size=10485760  # 10MB

    if [ -f "$log_file" ]; then
        local file_size
        if command -v stat >/dev/null 2>&1; then
            file_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo "0")
        else
            file_size=$(wc -c < "$log_file" 2>/dev/null || echo "0")
        fi

        if [ "$file_size" -gt "$max_size" ]; then
            local timestamp=$(date +"%Y%m%d%H%M%S")
            local rotated_log="${log_file}.${timestamp}"
            if mv "$log_file" "$rotated_log" 2>/dev/null; then
                echo "Log file rotated to $(basename "$rotated_log")"
            else
                echo "Warning: Failed to rotate log file"
            fi
        fi
    fi
}

check_gui_tools() {
    # Check in order of preference
    if command -v zenity >/dev/null 2>&1; then
        echo "zenity"
    elif command -v yad >/dev/null 2>&1; then
        echo "yad"
    elif command -v kdialog >/dev/null 2>&1; then
        echo "kdialog"
    elif command -v osascript >/dev/null 2>&1; then
        echo "osascript"  # macOS
    else
        echo "none"
    fi
}

show_gui_error() {
    local message="$1"
    local gui_tool=$(check_gui_tools)

    case "$gui_tool" in
        zenity)
            zenity --error --text="$message" --width=400 2>/dev/null
            ;;
        kdialog)
            kdialog --error "$message" 2>/dev/null
            ;;
        yad)
            yad --error --text="$message" --width=400 2>/dev/null
            ;;
        osascript)
            osascript -e "display dialog \"$message\" with icon stop buttons {\"OK\"}" 2>/dev/null
            ;;
        *)
            echo "ERROR: $message" >&2
            ;;
    esac
}

show_gui_info() {
    local message="$1"
    local gui_tool=$(check_gui_tools)

    case "$gui_tool" in
        zenity)
            zenity --info --text="$message" --width=500 2>/dev/null
            ;;
        kdialog)
            kdialog --msgbox "$message" 2>/dev/null
            ;;
        yad)
            yad --info --text="$message" --width=500 2>/dev/null
            ;;
        osascript)
            osascript -e "display dialog \"$message\" buttons {\"OK\"}" 2>/dev/null
            ;;
        *)
            echo "INFO: $message"
            ;;
    esac
}

launch_in_terminal() {
    local script_path="$0"
    local args="$*"

    # Properly escape arguments
    local escaped_args=""
    for arg in "$@"; do
        escaped_args="$escaped_args $(printf '%q' "$arg")"
    done

    local cmd="cd $(printf '%q' "$(pwd)") && $(printf '%q' "$script_path")$escaped_args; exec bash"

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Launching terminal with command: $cmd"
    fi

    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        case "$XDG_CURRENT_DESKTOP" in
            *GNOME*|*Unity*)
                gnome-terminal -- bash -c "$cmd" 2>/dev/null && return 0
                ;;
            *KDE*)
                konsole -e bash -c "$cmd" 2>/dev/null && return 0
                ;;
            *XFCE*)
                xfce4-terminal -e "bash -c \"$cmd\"" 2>/dev/null && return 0
                ;;
            *MATE*)
                mate-terminal -e "bash -c \"$cmd\"" 2>/dev/null && return 0
                ;;
        esac
    fi

    # Fallback terminal attempts
    local terminals=("x-terminal-emulator" "gnome-terminal" "konsole" "xfce4-terminal" "mate-terminal" "xterm" "rxvt" "urxvt")

    for term in "${terminals[@]}"; do
        if command -v "$term" >/dev/null 2>&1; then
            case "$term" in
                gnome-terminal|mate-terminal)
                    "$term" -- bash -c "$cmd" 2>/dev/null && return 0
                    ;;
                konsole)
                    "$term" -e bash -c "$cmd" 2>/dev/null && return 0
                    ;;
                xfce4-terminal)
                    "$term" -e "bash -c \"$cmd\"" 2>/dev/null && return 0
                    ;;
                *)
                    "$term" -e bash -c "$cmd" 2>/dev/null && return 0
                    ;;
            esac
        fi
    done

    # macOS fallback
    if [ "$(uname)" = "Darwin" ]; then
        open -a Terminal -n --args bash -c "$cmd" 2>/dev/null && return 0
    fi

    echo "Unable to open terminal. Please run this script from a terminal."
    return 1
}

# Handle non-terminal execution (double-click from desktop)
if [ ! -t 1 ]; then
    # Not running in terminal
    if [ "$(check_gui_tools)" != "none" ]; then
        # GUI tools available - run in GUI mode
        if [ "$verbose" = "true" ]; then
            echo "DEBUG: Launching GUI mode"
        fi
        run_gui_mode
        exit $?
    else
        # No GUI tools - launch terminal
        if [ "$verbose" = "true" ]; then
            echo "DEBUG: No GUI tools found, launching terminal"
        fi
        launch_in_terminal "$@"
        exit $?
    fi
fi

clean_filename() {
    local file="$1"
    local dir filename extension name new_filename new_path
    local changed=false

    if [ ! -f "$file" ]; then
        echo "Error: File does not exist: $file" >&2
        return 1
    fi

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: clean_filename input: '$file'"
    fi

    dir=$(dirname "$file")
    filename=$(basename "$file")
    extension="${filename##*.}"
    name="${filename%.*}"
    new_filename="$name"

    # Clean filename operations
    if [ "$clean_filenames" = true ]; then
        new_filename=$(echo "$new_filename" | sed 's/\./ /g')
        changed=true
    fi

    if [ "$replace_underscores" = true ]; then
        new_filename=$(echo "$new_filename" | sed 's/_/ /g')
        changed=true
    fi

    if [ "$capitalize_filenames" = true ]; then
        new_filename=$(echo "$new_filename" | awk '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) tolower(substr($i,2)) }}1')
        changed=true
    fi

    # Handle special characters more safely
    new_filename=$(echo "$new_filename" | sed 's/[^[:alnum:][:space:]._-]/_/g')

    # Remove multiple spaces and trim
    new_filename=$(echo "$new_filename" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

    # Add extension back
    new_filename="$new_filename.$extension"
    new_path="$dir/$new_filename"

    if [ "$changed" = true ] && [ "$filename" != "$new_filename" ]; then
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would rename: '$file' -> '$new_path'"
            echo "$file"
            return 0
        else
            # Check if target exists
            if [ -e "$new_path" ] && [ "$new_path" != "$file" ]; then
                echo "Warning: Target filename already exists: '$new_path'"
                echo "Skipping rename to avoid overwrite"
                echo "$file"
                return 0
            fi

            if mv "$file" "$new_path" 2>/dev/null; then
                echo "Renamed: '$file' -> '$new_path'"
                echo "$new_path"
                return 0
            else
                echo "Failed to rename: '$file'"
                echo "$file"
                return 1
            fi
        fi
    fi

    echo "$file"
    return 0
}

backup_file() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local filename basename_file backup_path

    if [ "$backups" != "true" ]; then
        return 0
    fi

    if [ ! -f "$file" ]; then
        handle_error 1 "Source file does not exist" "backup_creation" "$file" "${LINENO}"
        return 1
    fi

    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        handle_error 2 "Cannot create backup directory: $backup_dir" "backup_creation" "$file" "${LINENO}"
        return 1
    fi

    filename=$(basename "$file")
    backup_path="$backup_dir/$filename"

    if [ -f "$backup_path" ]; then
        local timestamp=$(date +"%Y%m%d%H%M%S")
        backup_path="$backup_dir/${filename%.*}_${timestamp}.${filename##*.}"
    fi

    if cp -p "$file" "$backup_path" 2>/dev/null; then
        if [ "$verbose" = "true" ]; then
            echo "Backed up: '$file' -> '$backup_path'"
        fi
        return 0
    else
        handle_error 3 "Failed to create backup" "backup_creation" "$file" "${LINENO}"
        return 1
    fi
}

is_file_processed() {
    local file="$1"
    local file_hash

    if [ -z "$file" ]; then
        echo "Error: Empty filename passed to is_file_processed()" >&2
        return 1
    fi

    if [ ! -f "$file" ]; then
        echo "Error: File does not exist: '$file'" >&2
        return 1
    fi

    [ -f "$processing_log" ] || touch "$processing_log"

    # Use SHA256 hash for reliable file identification
    if command -v sha256sum >/dev/null 2>&1; then
        file_hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        file_hash=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
    else
        file_hash="$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)_$(readlink -f "$file" 2>/dev/null || realpath "$file" 2>/dev/null)"
    fi

    if [ -n "$file_hash" ]; then
        grep -q "$file_hash" "$processing_log" 2>/dev/null
    else
        return 1
    fi
}

#logging with better error handling
log_processed_file() {
    local file="$1"
    local operation="${2:-processed}"
    local file_type="${3:-unknown}"
    local size file_hash abs_path timestamp

    if [ -z "$file" ]; then
        echo "Error: Empty filename passed to log_processed_file()" >&2
        return 1
    fi

    if [ ! -f "$file" ]; then
        echo "Error: File does not exist: '$file'" >&2
        return 1
    fi

    [ -f "$processing_log" ] || touch "$processing_log"

    # Get file info safely
    if command -v sha256sum >/dev/null 2>&1; then
        file_hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        file_hash=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
    else
        file_hash="unknown"
    fi

    abs_path=$(readlink -f "$file" 2>/dev/null || realpath "$file" 2>/dev/null || echo "$file")
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "unknown")

    if ! echo "$timestamp | $file_hash | $operation | $size | $file_type | $abs_path" >> "$processing_log" 2>/dev/null; then
        echo "Warning: Failed to write to processing log" >&2
    fi

    files_processed=$((files_processed + 1))

    if command -v stat >/dev/null 2>&1; then
        local file_size_bytes=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        bytes_processed=$((bytes_processed + file_size_bytes))
    fi

    case "$file_type" in
        mp4)
            mp4_files_processed=$((mp4_files_processed + 1))
            video_files_processed=$((video_files_processed + 1))
            ;;
        mkv)
            mkv_files_processed=$((mkv_files_processed + 1))
            video_files_processed=$((video_files_processed + 1))
            ;;
        mp3)
            mp3_files_processed=$((mp3_files_processed + 1))
            audio_files_processed=$((audio_files_processed + 1))
            ;;
        flac)
            flac_files_processed=$((flac_files_processed + 1))
            audio_files_processed=$((audio_files_processed + 1))
            ;;
        jpeg|jpg|png|gif|bmp|tiff|webp|heic|dds|tga|cr2|nef|arw|dng)
            image_files_processed=$((image_files_processed + 1))
            ;;
        aac|ogg|wav|m4a|iff|8svx|m3v|aud|wma|opus|amr|aiff|au|ra|dts|ac3|mka|oga)
            audio_files_processed=$((audio_files_processed + 1))
            ;;
        avi|mpg|mpeg|flv|mov|m4v|webm|3gp|wmv|asf|rm|rmvb|ts|mts|m2ts|vob|ogv)
            video_files_processed=$((video_files_processed + 1))
            ;;
        *)
            other_files_processed=$((other_files_processed + 1))
            ;;
    esac

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Logged file: '$file' (type: $file_type, total processed: $files_processed)"
    fi

    # Rotate log if needed
    rotate_logs "$processing_log"
}

detect_file_type() {
    local file="$1"
    local ext mime_type

    ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    if command -v file >/dev/null 2>&1; then
        mime_type=$(file -b --mime-type "$file" 2>/dev/null)
        case "$mime_type" in
            image/*)
                # Verify it's a supported image format
                if [ -n "${supported_image_formats[$ext]}" ]; then
                    echo "$ext"
                    return 0
                fi
                ;;
            video/*)
                echo "$ext"
                return 0
                ;;
            audio/*)
                echo "$ext"
                return 0
                ;;
        esac
    fi

    echo "$ext"
}

process_image() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local file_type="$3"

    if is_file_processed "$file"; then
        echo "Skipping already processed image: '$file'"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    local original_file="$file"
    file=$(clean_filename "$file")

    echo "Processing image: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process image: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 4 "File not found or not readable" "image_processing" "$file" "${LINENO}"
        return 1
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    local success=false

    if command -v exiftool >/dev/null 2>&1; then
        if exiftool -overwrite_original -all= -tagsfromfile @ -orientation -colorspace "$file" 2>/dev/null; then
            echo "✓ Removed metadata with exiftool: '$file'"
            success=true
        fi
    fi

    if [ "$success" = false ] && command -v convert >/dev/null 2>&1; then
        local temp_file="${file%.*}_temp.${file##*.}"
        if convert "$file" -strip "$temp_file" 2>/dev/null && mv "$temp_file" "$file" 2>/dev/null; then
            echo "✓ Removed metadata with ImageMagick: '$file'"
            success=true
        else
            rm -f "$temp_file" 2>/dev/null
        fi
    fi

    # Image optimization if requested
    if [ "$success" = true ] && [ "$optimize_images" = true ] && command -v convert >/dev/null 2>&1; then
        optimize_image "$file" "$file_type"
    fi

    # Image conversion if requested
    if [ "$success" = true ] && [ "$convert_images" = true ] && [ "$file_type" != "$image_output_format" ]; then
        convert_image "$file" "$image_output_format"
    fi

    if [ "$success" = true ]; then
        log_processed_file "$file" "processed" "$file_type"
        return 0
    else
        handle_error 5 "All image processing methods failed" "image_processing" "$file" "${LINENO}"
        return 1
    fi
}

optimize_image() {
    local file="$1"
    local file_type="$2"
    local temp_file="${file%.*}_optimized.${file##*.}"

    if [ "$verbose" = "true" ]; then
        echo "Optimizing image: '$file'"
    fi

    case "$file_type" in
        jpg|jpeg)
            if convert "$file" -quality "$image_quality" -sampling-factor 4:2:0 -strip "$temp_file" 2>/dev/null; then
                mv "$temp_file" "$file"
                echo "✓ Optimized JPEG: '$file'"
            fi
            ;;
        png)
            if convert "$file" -strip -define png:compression-level=9 "$temp_file" 2>/dev/null; then
                mv "$temp_file" "$file"
                echo "✓ Optimized PNG: '$file'"
            fi
            ;;
        *)
            if convert "$file" -strip "$temp_file" 2>/dev/null; then
                mv "$temp_file" "$file"
                echo "✓ Optimized image: '$file'"
            fi
            ;;
    esac

    # Clean up temp file if optimization failed
    rm -f "$temp_file" 2>/dev/null
}

convert_image() {
    local file="$1"
    local target_format="$2"
    local output_file="${file%.*}.$target_format"

    if [ "$verbose" = "true" ]; then
        echo "Converting image to $target_format: '$file'"
    fi

    if command -v convert >/dev/null 2>&1; then
        if convert "$file" -strip "$output_file" 2>/dev/null; then
            if [ "$backups" = "false" ]; then
                rm "$file" 2>/dev/null
            fi
            echo "✓ Converted to $target_format: '$output_file'"
            log_processed_file "$output_file" "converted" "$target_format"
        else
            echo "✗ Failed to convert image: '$file'"
            files_failed=$((files_failed + 1))
        fi
    else
        echo "ImageMagick not available for image conversion"
    fi
}

remove_assoc_metadata_files() {
    local file="$1"
    local dir filename base_filename
    local nfo_count=0 thumb_count=0

    if [ "$rm_metadata_files" != "true" ]; then
        return 0
    fi

    dir=$(dirname "$file")
    filename=$(basename "$file" .*)
    base_filename=$(echo "$filename" | sed 's/\.[^.]*$//')

    # Remove NFO files
    local nfo_patterns=("${filename}.nfo" "${base_filename}.nfo")
    for pattern in "${nfo_patterns[@]}"; do
        while IFS= read -r -d '' nfo_file; do
            if [ "$dry_run" = "true" ]; then
                echo "[DRY RUN] Would remove NFO file: '$nfo_file'"
            else
                if rm "$nfo_file" 2>/dev/null; then
                    echo "Removed NFO file: '$nfo_file'"
                    nfo_count=$((nfo_count + 1))
                fi
            fi
        done < <(find "$dir" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
    done

    # Remove thumbnail files
    local thumb_patterns=("${filename}-thumb.jpg" "${filename}.jpg" "${base_filename}*.jpg" "thumb.jpg")
    for pattern in "${thumb_patterns[@]}"; do
        while IFS= read -r -d '' thumb_file; do
            if [ "$dry_run" = "true" ]; then
                echo "[DRY RUN] Would remove thumbnail: '$thumb_file'"
            else
                if rm "$thumb_file" 2>/dev/null; then
                    echo "Removed thumbnail: '$thumb_file'"
                    thumb_count=$((thumb_count + 1))
                fi
            fi
        done < <(find "$dir" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
    done

    # Update global counters
    metadata_files_removed=$((metadata_files_removed + nfo_count))
    thumbnails_removed=$((thumbnails_removed + thumb_count))
}

cleanup_directory_metadata() {
    local dir="$1"
    local nfo_count=0 thumb_count=0

    if [ "$rm_metadata_files" != "true" ] || [ ! -d "$dir" ]; then
        return 0
    fi

    echo "Cleaning metadata files in directory: '$dir'"

    # Remove NFO files
    while IFS= read -r -d '' nfo_file; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove NFO file: '$nfo_file'"
        else
            if rm "$nfo_file" 2>/dev/null; then
                echo "Removed NFO file: '$nfo_file'"
                nfo_count=$((nfo_count + 1))
            fi
        fi
    done < <(find "$dir" -maxdepth 1 -name "*.nfo" -type f -print0 2>/dev/null)

    # Remove thumbnail files (small JPEG files likely to be thumbnails)
    while IFS= read -r -d '' thumb_file; do
        local file_size=0
        if command -v stat >/dev/null 2>&1; then
            file_size=$(stat -c%s "$thumb_file" 2>/dev/null || stat -f%z "$thumb_file" 2>/dev/null || echo "0")
        fi

        # Only remove small image files (likely thumbnails)
        if [ "$file_size" -lt 102400 ]; then  # Less than 100KB
            if [ "$dry_run" = "true" ]; then
                echo "[DRY RUN] Would remove thumbnail: '$thumb_file'"
            else
                if rm "$thumb_file" 2>/dev/null; then
                    echo "Removed thumbnail: '$thumb_file'"
                    thumb_count=$((thumb_count + 1))
                fi
            fi
        fi
    done < <(find "$dir" -maxdepth 1 \( -name "*thumb*.jpg" -o -name "*thumb*.jpeg" -o -name "thumb.*" \) -type f -print0 2>/dev/null)

    # Update global counters
    metadata_files_removed=$((metadata_files_removed + nfo_count))
    thumbnails_removed=$((thumbnails_removed + thumb_count))
}

process_mp3() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    if is_file_processed "$file"; then
        echo "Skipping already processed MP3: '$file'"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    local original_file="$file"
    file=$(clean_filename "$file")

    echo "Processing MP3: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process MP3: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 6 "File not found or not readable" "mp3_processing" "$file" "${LINENO}"
        return 1
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    # Try exiftool first
    if exiftool -overwrite_original -All= "$file" 2>/dev/null; then
        echo "✓ Processed MP3 with exiftool: '$file'"
        log_processed_file "$file" "processed" "mp3"
        return 0
    else
        echo "Exiftool failed, trying ffmpeg..."
        local temp_file="${file%.*}_stripped.mp3"
        if ffmpeg -y -nostdin -i "$file" -c:a copy -map_metadata -1 "$temp_file" 2>/dev/null; then
            if mv "$temp_file" "$file" 2>/dev/null; then
                echo "✓ Processed MP3 with ffmpeg: '$file'"
                log_processed_file "$file" "processed" "mp3"
                return 0
            fi
        fi
        rm -f "$temp_file" 2>/dev/null
        handle_error 7 "Both exiftool and ffmpeg failed" "mp3_processing" "$file" "${LINENO}"
        return 1
    fi
}

convert_audio() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local input_format="${3:-unknown}"
    local output_file bitrate audio_codec temp_file

    if is_file_processed "$file"; then
        echo "Skipping already processed $input_format file: '$file'"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    local original_file="$file"
    file=$(clean_filename "$file")

    echo "Processing $input_format: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert $input_format to $audio_output_format: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 8 "File not found or not readable" "audio_conversion" "$file" "${LINENO}"
        return 1
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    output_file="${file%.*}.$audio_output_format"
    bitrate="${audio_bitrates[$audio_output_format]:-192k}"

    # Set audio codec based on output format
    case "$audio_output_format" in
        mp3) audio_codec="libmp3lame" ;;
        flac) audio_codec="flac" ;;
        ogg) audio_codec="libvorbis" ;;
        wav) audio_codec="pcm_s16le" ;;
        aac) audio_codec="aac" ;;
        m4a) audio_codec="aac"; output_file="${file%.*}.m4a" ;;
        *) audio_codec="libmp3lame"; output_file="${file%.*}.mp3" ;;
    esac

    # If input and output formats are the same, just remove metadata
    if [ "$input_format" = "$audio_output_format" ]; then
        if exiftool -overwrite_original -All= "$file" 2>/dev/null; then
            echo "✓ Removed metadata from $input_format file: '$file'"
            log_processed_file "$file" "processed" "$input_format"
            return 0
        else
            temp_file="${file%.*}_stripped.$input_format"
            if ffmpeg -y -nostdin -i "$file" -c:a copy -map_metadata -1 "$temp_file" 2>/dev/null; then
                if mv "$temp_file" "$file" 2>/dev/null; then
                    echo "✓ Removed metadata with ffmpeg: '$file'"
                    log_processed_file "$file" "processed" "$input_format"
                    return 0
                fi
            fi
            rm -f "$temp_file" 2>/dev/null
        fi
    fi

    # Convert to different format
    if ffmpeg -y -nostdin -i "$file" -vn -ar 44100 -ac 2 -c:a "$audio_codec" -b:a "$bitrate" -map_metadata -1 "$output_file" 2>/dev/null; then
        if [ "$backups" = "false" ]; then
            rm "$file" 2>/dev/null
        fi
        echo "✓ Converted $input_format to $audio_output_format: '$output_file'"
        log_processed_file "$output_file" "processed" "$audio_output_format"
        return 0
    else
        handle_error 9 "Audio conversion failed" "audio_conversion" "$file" "${LINENO}"
        return 1
    fi
}

process_m3u() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    if is_file_processed "$file"; then
        echo "Skipping already processed M3U: '$file'"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    local original_file="$file"
    file=$(clean_filename "$file")

    echo "Processing M3U playlist: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would clean M3U playlist: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 14 "File not found or not readable" "m3u_processing" "$file" "${LINENO}"
        return 1
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    local temp_file="${file%.*}_cleaned.m3u"
    if grep -v "^#" "$file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$file" 2>/dev/null; then
        echo "✓ Cleaned M3U playlist: '$file'"
        log_processed_file "$file" "processed" "m3u"
        return 0
    else
        rm -f "$temp_file" 2>/dev/null
        handle_error 15 "M3U playlist processing failed" "m3u_processing" "$file" "${LINENO}"
        return 1
    fi
}

strip_metadata() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local file_type new_name temp_file

    if is_file_processed "$file"; then
        echo "Skipping already processed file: '$file'"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    local original_file="$file"
    file=$(clean_filename "$file")

    echo "Processing video: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would strip metadata from: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 10 "File not found or not readable" "video_processing" "$file" "${LINENO}"
        return 1
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    remove_assoc_metadata_files "$file"

    file_type=$(detect_file_type "$file")

    if [ "$renameext" = "true" ]; then
        new_name="${file%.*}.$newfileext"
        if mv "$file" "$new_name" 2>/dev/null; then
            file="$new_name"
            echo "Renamed to: '$file'"
        fi
    fi

    local success=false

    # Process based on file type
    case "$file_type" in
        mpg|mpeg|mp4|m4v|flv|mov)
            if command -v exiftool >/dev/null 2>&1; then
                if exiftool -overwrite_original -All= "$file" 2>/dev/null; then
                    echo "✓ Processed with exiftool: '$file'"
                    success=true
                fi
            fi
            ;;
        avi)
            temp_file="${file%.*}_stripped.avi"
            if ffmpeg -y -nostdin -i "$file" -codec copy -map_metadata -1 "$temp_file" 2>/dev/null; then
                if mv "$temp_file" "$file" 2>/dev/null; then
                    echo "✓ Processed AVI with ffmpeg: '$file'"
                    success=true
                fi
            fi
            rm -f "$temp_file" 2>/dev/null
            ;;
        mkv)
            if process_mkv "$file" "$backup_dir"; then
                success=true
            fi
            ;;
        *)
            # Try generic ffmpeg approach
            temp_file="${file%.*}_stripped.${file##*.}"
            if ffmpeg -y -nostdin -i "$file" -c copy -map_metadata -1 "$temp_file" 2>/dev/null; then
                if mv "$temp_file" "$file" 2>/dev/null; then
                    echo "✓ Processed with ffmpeg: '$file'"
                    success=true
                fi
            fi
            rm -f "$temp_file" 2>/dev/null
            ;;
    esac

    if [ "$success" = true ]; then
        log_processed_file "$file" "processed" "$file_type"
        return 0
    else
        handle_error 11 "All video processing methods failed" "video_processing" "$file" "${LINENO}"
        return 1
    fi
}

process_mkv() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local new_name

    if is_file_processed "$file"; then
        echo "Skipping already processed MKV: '$file'"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    local original_file="$file"
    file=$(clean_filename "$file")

    echo "Processing MKV: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process MKV: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 12 "File not found or not readable" "mkv_processing" "$file" "${LINENO}"
        return 1
    fi

    # Handle file renaming if requested
    if [ "$renameext" = "true" ]; then
        new_name="${file%.*}.$newfileext"
        if mv "$file" "$new_name" 2>/dev/null; then
            file="$new_name"
            echo "Renamed to: '$file'"
        fi
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    remove_assoc_metadata_files "$file"

    # Process with mkvpropedit
    if command -v mkvpropedit >/dev/null 2>&1; then
        if mkvpropedit "$file" -d title 2>/dev/null; then
            echo "✓ Processed MKV with mkvpropedit: '$file'"
            log_processed_file "$file" "processed" "mkv"
            return 0
        fi
    fi

    # Fallback to ffmpeg if mkvpropedit fails
    local temp_file="${file%.*}_stripped.mkv"
    if ffmpeg -y -nostdin -i "$file" -c copy -map_metadata -1 "$temp_file" 2>/dev/null; then
        if mv "$temp_file" "$file" 2>/dev/null; then
            echo "✓ Processed MKV with ffmpeg: '$file'"
            log_processed_file "$file" "processed" "mkv"
            return 0
        fi
    fi

    rm -f "$temp_file" 2>/dev/null
    handle_error 13 "MKV processing failed with both mkvpropedit and ffmpeg" "mkv_processing" "$file" "${LINENO}"
    return 1
}

convert_with_handbrake_settings() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local dir filename extension name output_file crop_params

    if [ "$use_handbrake_settings" != "true" ]; then
        return 1
    fi

    echo "Converting with HandBrake settings: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert with HandBrake settings: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 16 "File not found or not readable" "handbrake_conversion" "$file" "${LINENO}"
        return 1
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    dir=$(dirname "$file")
    filename=$(basename "$file")
    extension="${filename##*.}"
    name="${filename%.*}"
    output_file="${dir}/${name}_converted.mkv"

    # Auto-detect crop using ffmpeg cropdetect filter
    crop_params=""
    if command -v ffmpeg >/dev/null 2>&1; then
        crop_params=$(ffmpeg -y -nostdin -ss 60 -i "$file" -t 1 -vf cropdetect -f null - 2>&1 | awk '/crop/ { print $NF }' | tail -1)
        if [ -z "$crop_params" ]; then
            crop_params="crop=66:68:0:0"  # Default crop from HandBrake settings
        fi
    else
        crop_params="crop=66:68:0:0"
    fi

    # Use ffmpeg with HandBrake-like settings
    if ffmpeg -y -nostdin -i "$file" \
        -c:v libx265 -preset medium -crf 32 \
        -vf "$crop_params,scale=1280:720:flags=lanczos,unsharp=5:5:1.0:5:5:0.0,hqdn3d=1.0:1.0:2.0:2.0" \
        -c:a copy \
        -map_metadata -1 \
        -movflags +faststart \
        "$output_file" 2>/dev/null; then

        # If successful and not backing up, remove original
        if [ "$backups" = "false" ]; then
            rm "$file" 2>/dev/null
        fi

        echo "✓ Converted with HandBrake settings: '$output_file'"
        log_processed_file "$output_file" "handbrake_conversion" "mkv"
        return 0
    else
        rm -f "$output_file" 2>/dev/null
        handle_error 17 "HandBrake-style conversion failed" "handbrake_conversion" "$file" "${LINENO}"
        return 1
    fi
}

convert_to_mp4() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local output_file temp_output_file

    if [ "$convert_to_mp4" != "true" ]; then
        return 1
    fi

    echo "Converting to MP4: '$file'"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert to MP4: '$file'"
        return 0
    fi

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        handle_error 18 "File not found or not readable" "mp4_conversion" "$file" "${LINENO}"
        return 1
    fi

    if ! backup_file "$file" "$backup_dir"; then
        echo "Backup failed, skipping file for safety: '$file'"
        return 1
    fi

    output_file="${file%.*}.mp4"
    temp_output_file="${file%.*}_converted.mp4"

    if ffmpeg -y -nostdin -i "$file" -c:v libx264 -c:a aac -strict experimental -map_metadata -1 "$temp_output_file" 2>/dev/null; then
        if [ "$backups" = "false" ]; then
            rm "$file" 2>/dev/null
        fi
        if mv "$temp_output_file" "$output_file" 2>/dev/null; then
            echo "✓ Converted to MP4: '$output_file'"
            log_processed_file "$output_file" "processed" "mp4"
            return 0
        fi
    fi

    rm -f "$temp_output_file" 2>/dev/null
    handle_error 19 "MP4 conversion failed" "mp4_conversion" "$file" "${LINENO}"
    return 1
}

process_files() {
    local dir="${1:-.}"
    local file_count=0
    local processed_count=0

    echo "Processing files in directory: '$dir'"

    if [ ! -d "$dir" ]; then
        echo "Error: Directory does not exist: '$dir'"
        return 1
    fi

    cleanup_directory_metadata "$dir"

    # Build comprehensive file pattern for find
    local find_patterns=""

    # Video formats
    find_patterns+="-iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.m4v' -o "
    find_patterns+="-iname '*.mpg' -o -iname '*.mpeg' -o -iname '*.flv' -o -iname '*.mov' -o "
    find_patterns+="-iname '*.webm' -o -iname '*.3gp' -o -iname '*.wmv' -o -iname '*.asf' -o "
    find_patterns+="-iname '*.rm' -o -iname '*.rmvb' -o -iname '*.ts' -o -iname '*.mts' -o "
    find_patterns+="-iname '*.m2ts' -o -iname '*.vob' -o -iname '*.ogv' -o "

    # Audio formats
    find_patterns+="-iname '*.mp3' -o -iname '*.wav' -o -iname '*.ogg' -o -iname '*.flac' -o "
    find_patterns+="-iname '*.aac' -o -iname '*.m4a' -o -iname '*.wma' -o -iname '*.opus' -o "
    find_patterns+="-iname '*.amr' -o -iname '*.aiff' -o -iname '*.au' -o -iname '*.ra' -o "
    find_patterns+="-iname '*.dts' -o -iname '*.ac3' -o -iname '*.mka' -o -iname '*.oga' -o "
    find_patterns+="-iname '*.iff' -o -iname '*.8svx' -o -iname '*.m3v' -o -iname '*.aud' -o "

    # Image formats
    find_patterns+="-iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o "
    find_patterns+="-iname '*.bmp' -o -iname '*.tiff' -o -iname '*.tif' -o -iname '*.webp' -o "
    find_patterns+="-iname '*.heic' -o -iname '*.heif' -o -iname '*.avif' -o -iname '*.tga' -o "
    find_patterns+="-iname '*.dds' -o -iname '*.cr2' -o -iname '*.nef' -o -iname '*.arw' -o "
    find_patterns+="-iname '*.dng' -o -iname '*.orf' -o -iname '*.rw2' -o -iname '*.pef' -o "
    find_patterns+="-iname '*.srw' -o -iname '*.raf' -o "

    # Playlist formats
    find_patterns+="-iname '*.m3u'"

    # Count files first for progress tracking
    if [ "$verbose" = "true" ]; then
        echo "Counting files..."
    fi

    local depth_option=""
    if [ "$recursive" = "false" ]; then
        depth_option="-maxdepth 1"
    fi

    file_count=$(eval "find \"$dir\" $depth_option -type f \\( $find_patterns \\) -print0 2>/dev/null | tr -cd '\\0' | wc -c")
    echo "Found $file_count files to process"

    # Process files
    while IFS= read -r -d '' file; do
        ((processed_count++))
        if [ "$verbose" = "true" ] || [ $((processed_count % 10)) -eq 0 ]; then
            printf "\rProgress: %d/%d files processed" "$processed_count" "$file_count"
        fi
        process_single_file "$file"
    done < <(eval "find \"$dir\" $depth_option -type f \\( $find_patterns \\) -print0 2>/dev/null")

    echo # New line after progress
    echo "Completed processing $processed_count files"
}

process_single_file() {
    local file="$1"
    local ext file_type

    if [ ! -f "$file" ]; then
        echo "✗ Error: File not found: '$file'"
        files_failed=$((files_failed + 1))
        return 1
    fi

    ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    file_type=$(detect_file_type "$file")

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Processing file: '$file' (type: $file_type)"
    fi

    remove_assoc_metadata_files "$file"

    # Process based on file type
    case "$ext" in
        # Audio formats
        mp3)
            if [ "$audio_output_format" = "mp3" ]; then
                process_mp3 "$file" "$backup_dir"
            else
                convert_audio "$file" "$backup_dir" "mp3"
            fi
            ;;
        wav|ogg|flac|aac|m4a|iff|8svx|m3v|aud|wma|opus|amr|aiff|au|ra|dts|ac3|mka|oga)
            convert_audio "$file" "$backup_dir" "$ext"
            ;;

        # Video formats
        m4v|mkv|mp4)
            strip_metadata "$file" "$backup_dir"
            if [ "$use_handbrake_settings" = "true" ]; then
                convert_with_handbrake_settings "$file" "$backup_dir"
            fi
            ;;
        mpg|mpeg|avi|flv|mov|webm|3gp|wmv|asf|rm|rmvb|ts|mts|m2ts|vob|ogv)
            strip_metadata "$file" "$backup_dir"
            if [ "$conv_oldfileformats" = "true" ]; then
                convert_to_mp4 "$file" "$backup_dir"
            fi
            ;;

        # Image formats
        jpg|jpeg|png|gif|bmp|tiff|tif|webp|heic|heif|avif|tga|dds|cr2|nef|arw|dng|orf|rw2|pef|srw|raf)
            if [ -n "${supported_image_formats[$ext]}" ]; then
                process_image "$file" "$backup_dir" "$ext"
            else
                echo "Unsupported image format: $ext"
                files_skipped=$((files_skipped + 1))
            fi
            ;;

        # Playlist formats
        m3u)
            process_m3u "$file" "$backup_dir"
            ;;

        *)
            echo "Unsupported file format: '$file' (extension: $ext)"
            files_skipped=$((files_skipped + 1))
            ;;
    esac
}

show_stats() {
    echo
    echo "=========================================="
    echo "         PROCESSING STATISTICS"
    echo "=========================================="
    echo "Files processed successfully: $files_processed"
    echo "Files failed: $files_failed"
    echo "Files skipped (already processed): $files_skipped"
    echo "Thumbnails removed: $thumbnails_removed"
    echo "Metadata files (.nfo) removed: $metadata_files_removed"

    if command -v numfmt >/dev/null 2>&1; then
        echo "Total data processed: $(numfmt --to=iec-i --suffix=B $bytes_processed 2>/dev/null || echo "$bytes_processed bytes")"
    else
        echo "Total data processed: $bytes_processed bytes"
    fi

    echo
    echo "Files processed by type:"

    if [ "$video_files_processed" -gt 0 ]; then
        echo "  📹 Video files: $video_files_processed"
        [ "$mp4_files_processed" -gt 0 ] && echo "    - MP4: $mp4_files_processed"
        [ "$mkv_files_processed" -gt 0 ] && echo "    - MKV: $mkv_files_processed"
    fi

    if [ "$audio_files_processed" -gt 0 ]; then
        echo "  🎵 Audio files: $audio_files_processed"
        [ "$mp3_files_processed" -gt 0 ] && echo "    - MP3: $mp3_files_processed"
        [ "$flac_files_processed" -gt 0 ] && echo "    - FLAC: $flac_files_processed"
    fi

    if [ "$image_files_processed" -gt 0 ]; then
        echo "  🖼️  Image files: $image_files_processed"
    fi

    if [ "$other_files_processed" -gt 0 ]; then
        echo "  📄 Other files: $other_files_processed"
    fi

    echo "=========================================="

    # Show error summary if there were failures
    if [ "$files_failed" -gt 0 ]; then
        echo
        echo "⚠️  Some files failed to process. Check the error log:"
        echo "   ${processing_log%.log}_errors.log"
    fi

    # Processing summary
    local total_attempted=$((files_processed + files_failed + files_skipped))
    if [ "$total_attempted" -gt 0 ]; then
        local success_rate=$(( (files_processed * 100) / total_attempted ))
        echo
        echo "Success rate: ${success_rate}% ($files_processed/$total_attempted)"
    fi
}

show_help() {
    cat << 'EOF'
StripMeta (X-Seti) - Media File Metadata Remover & Processor v2.0.0

USAGE:
    ./stripmeta-improved.sh [OPTIONS] [FILES/DIRECTORIES...]
    ./stripmeta-improved.sh [OPTIONS]                    # Interactive mode
    ./stripmeta-improved.sh --gui                        # GUI mode

DESCRIPTION:
    Process video, audio, and image files to remove metadata, clean filenames,
    convert formats, and organize media collections.

SUPPORTED FORMATS:
    Video: mp4, mkv, avi, mpg, mpeg, m4v, flv, mov, webm, 3gp, wmv, ts, mts, vob
    Audio: mp3, flac, wav, ogg, aac, m4a, wma, opus, amr, aiff, au, ra, dts, ac3
    Image: jpg, jpeg, png, gif, bmp, tiff, webp, heic, heif, avif, tga, dds
           cr2, nef, arw, dng, orf, rw2, pef, srw, raf (RAW formats)
    Other: m3u (playlists)

COMMAND LINE OPTIONS:
    -h, --help                      Show this help message
    --gui                           Force GUI mode (requires zenity/kdialog/yad)
    --version                       Display script version
    --formats                       Show supported file formats
    --check-update                  Check for script updates
    --dry-run                       Show what would be done without making changes
    --verbose                       Enable detailed debug output

FILENAME PROCESSING:
    --clean-filenames               Replace dots with spaces in filenames
    --replace-underscores           Replace underscores with spaces
    --capitalize                    Capitalize words in filenames
    --rename                        Change video extensions to m4v

PROCESSING OPTIONS:
    --backups                       Create backup copies before processing
    --backup-dir DIR                Specify backup directory (default: ./backups)
    --recursive                     Process files in subdirectories
    --remove-metadata-files         Remove .nfo files and thumbnails

CONVERSION OPTIONS:
    --audio-format FORMAT           Audio output format: mp3, flac, ogg, wav, aac, m4a, wma, opus
    --conv-oldfileformats           Convert AVI/MPG/FLV/MOV to MP4
    --handbrake                     Use HandBrake-style video compression

IMAGE PROCESSING OPTIONS:
    --process-images                Enable image metadata removal
    --optimize-images               Optimize images (reduce file size)
    --convert-images                Convert images to specified format
    --image-format FORMAT           Image output format: jpg, png, webp, tiff
    --image-quality QUALITY         JPEG quality (1-100, default: 85)

PERFORMANCE:
    --parallel                      Enable parallel processing (experimental)
    --max-jobs N                    Max parallel jobs (default: 4)

LOGGING:
    --reset-log                     Clear the processing log file

EXAMPLES:
    # Interactive mode with all prompts
    ./stripmeta-improved.sh

    # Process images with optimization
    ./stripmeta-improved.sh --process-images --optimize-images --image-quality 90

    # Process directory recursively with backups
    ./stripmeta-improved.sh --recursive --backups /path/to/media

    # Convert all audio to FLAC and optimize images
    ./stripmeta-improved.sh --audio-format flac --process-images --optimize-images

    # Clean filenames and remove all metadata files
    ./stripmeta-improved.sh --clean-filenames --remove-metadata-files

    # Dry run to see what would happen
    ./stripmeta-improved.sh --dry-run --verbose /media/folder

NOTES:
    - Image processing requires ImageMagick (convert, identify commands)
    - RAW image format support depends on ImageMagick delegates
    - GUI mode automatically detects and uses available GUI tools
    - Processing logs are automatically rotated when they exceed 10MB

For more information visit: https://github.com/X-Seti/stripmeta
EOF
}

show_supported_formats() {
    cat << 'EOF'
SUPPORTED MEDIA FORMATS:

VIDEO FORMATS:
    Primary: mp4, mkv, avi, m4v
    Legacy: mpg, mpeg, flv, mov
    Modern: webm, 3gp, wmv
    Broadcast: ts, mts, m2ts
    DVD: vob
    Streaming: rm, rmvb, asf

AUDIO FORMATS:
    Lossy: mp3, aac, m4a, ogg, wma, opus, amr
    Lossless: flac, wav, aiff, iff, 8svx
    Legacy: au, ra, dts, ac3
    Containers: mka, oga

IMAGE FORMATS:
    Common: jpg, jpeg, png, gif, bmp
    Modern: webp, heic, heif, avif
    Professional: tiff, tif, tga, dds
    RAW Formats:
        Canon: cr2
        Nikon: nef
        Sony: arw
        Adobe: dng
        Olympus: orf
        Panasonic: rw2
        Pentax: pef
        Samsung: srw
        Fujifilm: raf

PLAYLIST FORMATS:
    m3u (basic playlist support)

OUTPUT FORMATS:
    Video: mp4 (H.264), mkv (H.265 with HandBrake)
    Audio: mp3, flac, ogg, wav, aac, m4a
    Image: jpg, png, webp, tiff

METADATA REMOVAL:
    - EXIF data from all supported formats
    - Title, artist, album info from audio
    - Creation dates and device info
    - GPS coordinates and camera settings
    - Image orientation and color profiles (preserved when necessary)
    - Associated .nfo files and thumbnails
EOF
}

run_gui_mode() {
    local gui_tool=$(check_gui_tools)

    if [ "$gui_tool" = "none" ]; then
        echo "No GUI tools available. Install zenity, kdialog, yad, or run on macOS for GUI mode."
        return 1
    fi

    # Welcome dialog
    local welcome_text="Welcome to StripMeta File Processor (X-Seti) v$SCRIPT_VERSION

Would you like to continue?"

    case "$gui_tool" in
        zenity)
            if ! zenity --question --text="$welcome_text" --width=500 2>/dev/null; then
                exit 0
            fi
            ;;
        kdialog)
            if ! kdialog --yesno "$welcome_text" 2>/dev/null; then
                exit 0
            fi
            ;;
        yad)
            if ! yad --question --text="$welcome_text" --width=500 2>/dev/null; then
                exit 0
            fi
            ;;
        osascript)
            if ! osascript -e "display dialog \"$welcome_text\" buttons {\"Cancel\", \"Continue\"} default button \"Continue\"" 2>/dev/null; then
                exit 0
            fi
            ;;
    esac

    # File/Directory selection
    local target=""
    case "$gui_tool" in
        zenity)
            target=$(zenity --file-selection --title="Select files or folder to process" --filename="$(pwd)/" --separator="|" --multiple 2>/dev/null)
            ;;
        kdialog)
            target=$(kdialog --getopenfilename "$(pwd)/" "All Media Files (*.mp4 *.mkv *.avi *.mp3 *.flac *.jpg *.png)" 2>/dev/null)
            ;;
        yad)
            target=$(yad --file --title="Select files or folder to process" --filename="$(pwd)/" 2>/dev/null)
            ;;
        osascript)
            target=$(osascript -e 'choose file with prompt "Select files to process" with multiple selections allowed' 2>/dev/null | sed 's/alias /\//g' | tr ',' '\n')
            ;;
    esac

    if [ -z "$target" ]; then
        show_gui_info "No files selected. Exiting."
        exit 0
    fi

    # Set some sensible defaults for GUI mode
    clean_filenames=true
    backups=true
    process_images=true
    optimize_images=true
    rm_metadata_files=true

    # Process the selected files
    show_gui_info "Processing files with default settings..."

    IFS='|' read -ra PATHS <<< "$target"
    for path in "${PATHS[@]}"; do
        if [ -f "$path" ]; then
            process_single_file "$path"
        elif [ -d "$path" ]; then
            process_files "$path"
        fi
    done

    # Show results
    local results_text="Processing Complete!

Files processed successfully: $files_processed
Files failed: $files_failed
Files skipped: $files_skipped
Images processed: $image_files_processed
Thumbnails removed: $thumbnails_removed
Metadata files removed: $metadata_files_removed"

    show_gui_info "$results_text"
    return 0
}

# Update checker function
check_for_updates() {
    echo "Checking for script updates..."
    if command -v curl >/dev/null 2>&1; then
        local latest_version
        latest_version=$(curl -s --connect-timeout 5 "https://api.github.com/repos/X-Seti/stripmeta/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null)
        if [ -n "$latest_version" ] && [ "$latest_version" != "$SCRIPT_VERSION" ]; then
            echo -e "A new version ($latest_version) is available! Current version: $SCRIPT_VERSION"
            echo -e "Visit https://github.com/X-Seti/stripmeta to update"
        else
            echo "You are running the latest version: $SCRIPT_VERSION"
        fi
    elif command -v wget >/dev/null 2>&1; then
        local latest_version
        latest_version=$(wget -qO- --timeout=5 "https://api.github.com/repos/X-Seti/stripmeta/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null)
        if [ -n "$latest_version" ] && [ "$latest_version" != "$SCRIPT_VERSION" ]; then
            echo -e "A new version ($latest_version) is available! Current version: $SCRIPT_VERSION"
            echo -e "Visit https://github.com/X-Seti/stripmeta to update"
        else
            echo "You are running the latest version: $SCRIPT_VERSION"
        fi
    else
        echo "curl or wget not found, cannot check for updates"
    fi
}

# Configuration management functions
prompt_for_save_config() {
    read -p "Would you like to save these settings as default configuration? [y/N]: " save_config_response
    if [[ "$save_config_response" =~ ^[Yy]$ ]]; then
        save_config
    else
        remember_last_choices
    fi
}

check_config() {
    local config_file="$HOME/.stripmeta-config"
    if [ ! -f "$config_file" ]; then
        return 1
    elif [ ! -r "$config_file" ]; then
        echo "Config file is not readable."
        return 1
    else
        return 0
    fi
}

load_conf() {
    local config_file="$HOME/.stripmeta-config"

    if check_config; then
        # Source the configuration file safely
        if [ -r "$config_file" ]; then
            # shellcheck source=/dev/null
            source "$config_file" 2>/dev/null
            echo "Configuration loaded successfully."
            return 0
        fi
    fi
    echo "Failed to load configuration."
    return 1
}

save_config() {
    local config_file="$HOME/.stripmeta-config"
    {
        echo "# StripMeta configuration file"
        echo "# Generated on $(date)"
        echo "clean_filenames=$clean_filenames"
        echo "replace_underscores=$replace_underscores"
        echo "capitalize_filenames=$capitalize_filenames"
        echo "renameext=$renameext"
        echo "backups=$backups"
        echo "verbose=$verbose"
        echo "recursive=$recursive"
        echo "convert_to_mp4=$convert_to_mp4"
        echo "conv_oldfileformats=$conv_oldfileformats"
        echo "use_handbrake_settings=$use_handbrake_settings"
        echo "rm_metadata_files=$rm_metadata_files"
        echo "process_images=$process_images"
        echo "optimize_images=$optimize_images"
        echo "convert_images=$convert_images"
        echo "image_quality=$image_quality"
        echo "backup_dir=\"$backup_dir\""
        echo "newfileext=\"$newfileext\""
        echo "audio_output_format=\"$audio_output_format\""
        echo "image_output_format=\"$image_output_format\""
    } > "$config_file"

    echo "Configuration saved to $config_file"
}

remember_last_choices() {
    local config_file="$HOME/.stripmeta-lastrun"
    {
        echo "# Last run choices"
        echo "last_clean_filenames=$clean_filenames"
        echo "last_replace_underscores=$replace_underscores"
        echo "last_capitalize_filenames=$capitalize_filenames"
        echo "last_rename=$renameext"
        echo "last_backups=$backups"
        echo "last_recursive=$recursive"
        echo "last_convert_to_mp4=$convert_to_mp4"
        echo "last_conv_oldfileformats=$conv_oldfileformats"
        echo "last_use_handbrake_settings=$use_handbrake_settings"
        echo "last_rm_metadata_files=$rm_metadata_files"
        echo "last_process_images=$process_images"
        echo "last_optimize_images=$optimize_images"
        echo "last_convert_images=$convert_images"
        echo "last_audio_output_format=\"$audio_output_format\""
        echo "last_image_output_format=\"$image_output_format\""
        echo "last_image_quality=$image_quality"
    } > "$config_file"
}

load_last_choices() {
    local config_file="$HOME/.stripmeta-lastrun"
    if [ -f "$config_file" ] && [ -r "$config_file" ]; then
        # shellcheck source=/dev/null
        source "$config_file" 2>/dev/null
        # Apply last choices as defaults if not already set
        [ "$clean_filenames" = "false" ] && clean_filenames=${last_clean_filenames:-false}
        [ "$replace_underscores" = "false" ] && replace_underscores=${last_replace_underscores:-false}
        [ "$capitalize_filenames" = "false" ] && capitalize_filenames=${last_capitalize_filenames:-false}
        [ "$renameext" = "false" ] && renameext=${last_rename:-false}
        [ "$backups" = "false" ] && backups=${last_backups:-false}
        [ "$recursive" = "false" ] && recursive=${last_recursive:-false}
        [ "$convert_to_mp4" = "false" ] && convert_to_mp4=${last_convert_to_mp4:-false}
        [ "$conv_oldfileformats" = "false" ] && conv_oldfileformats=${last_conv_oldfileformats:-false}
        [ "$use_handbrake_settings" = "false" ] && use_handbrake_settings=${last_use_handbrake_settings:-false}
        [ "$rm_metadata_files" = "false" ] && rm_metadata_files=${last_rm_metadata_files:-false}
        [ "$process_images" = "false" ] && process_images=${last_process_images:-false}
        [ "$optimize_images" = "false" ] && optimize_images=${last_optimize_images:-false}
        [ "$convert_images" = "false" ] && convert_images=${last_convert_images:-false}
        [ "$audio_output_format" = "mp3" ] && audio_output_format=${last_audio_output_format:-"mp3"}
        [ "$image_output_format" = "jpg" ] && image_output_format=${last_image_output_format:-"jpg"}
        [ "$image_quality" = "85" ] && image_quality=${last_image_quality:-85}
    fi
}

run_interactive_mode() {
    echo -e "🎬 StripMeta File Processor (X-Seti) v$SCRIPT_VERSION\n"

    # Check for config file first
    if check_config; then
        echo -e "✅ StripMeta config file found!"
        read -p "Do you want to use the saved configuration? [y/N]: " use_config
        if [[ "$use_config" =~ ^[Yy]$ ]]; then
            if load_conf; then
                echo -e "\n📋 Configuration loaded successfully!"
                echo -e "\n🚀 Ready to Process"
                read -p "Process all media files with loaded settings? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo -e "\n🔄 Starting processing with config settings..."
                    cleanup_directory_metadata "."
                    process_files "."
                    show_stats
                    echo "✅ Processing complete. Press Enter to exit..."
                    read
                    exit 0
                else
                    echo "❌ Operation cancelled - Press Enter to exit..."
                    read
                    exit 0
                fi
            else
                echo "⚠️  Failed to load configuration. Continuing with interactive setup..."
                sleep 1
            fi
        else
            echo "📝 Continuing with interactive setup..."
        fi
    fi

    # Reset all variables to false to avoid confusion from previous runs or defaults
    clean_filenames=false
    replace_underscores=false
    capitalize_filenames=false
    renameext=false
    backups=false
    recursive=false
    conv_oldfileformats=false
    convert_to_mp4=false
    use_handbrake_settings=false
    rm_metadata_files=false
    process_images=false
    optimize_images=false
    convert_images=false
    audio_output_format="mp3"
    image_output_format="jpg"

    echo -e "\n📁 == Filename Handling Options =="
    read -p "🔄 Rename video file extensions to $newfileext? [y/N]: " rename_response
    if [[ "$rename_response" =~ ^[Yy]$ ]]; then
        renameext=true
    fi

    read -p "🔤 Replace dots with spaces in filenames? [y/N]: " clean_response
    if [[ "$clean_response" =~ ^[Yy]$ ]]; then
        clean_filenames=true
    fi

    read -p "🔗 Replace underscores with spaces in filenames? [y/N]: " underscores_response
    if [[ "$underscores_response" =~ ^[Yy]$ ]]; then
        replace_underscores=true
    fi

    read -p "🔠 Capitalize words in filenames? [y/N]: " capitalize_response
    if [[ "$capitalize_response" =~ ^[Yy]$ ]]; then
        capitalize_filenames=true
    fi

    echo -e "\n🎵 == Audio Processing Options =="
    echo "Choose audio output format:"
    echo "1) MP3 (default - widely compatible)"
    echo "2) FLAC (lossless compression)"
    echo "3) OGG (open source)"
    echo "4) WAV (uncompressed)"
    echo "5) AAC (modern lossy)"
    echo "6) M4A (iTunes compatible)"
    echo "7) WMA (Windows Media)"
    echo "8) Opus (modern low-bitrate)"
    read -p "Select format [1-8] (default: 1): " format_choice
    case "$format_choice" in
        2) audio_output_format="flac" ;;
        3) audio_output_format="ogg" ;;
        4) audio_output_format="wav" ;;
        5) audio_output_format="aac" ;;
        6) audio_output_format="m4a" ;;
        7) audio_output_format="wma" ;;
        8) audio_output_format="opus" ;;
        *) audio_output_format="mp3" ;;
    esac
    echo "Selected audio output format: $audio_output_format"

    echo -e "\n🖼️  == Image Processing Options =="
    read -p "📷 Process image files (remove metadata)? [y/N]: " process_images_response
    if [[ "$process_images_response" =~ ^[Yy]$ ]]; then
        process_images=true

        read -p "🗜️ Optimize images (reduce file size)? [y/N]: " optimize_response
        if [[ "$optimize_response" =~ ^[Yy]$ ]]; then
            optimize_images=true
        fi

        read -p "🔄 Convert images to different format? [y/N]: " convert_response
        if [[ "$convert_response" =~ ^[Yy]$ ]]; then
            convert_images=true
            echo "Choose image output format:"
            echo "1) JPG (widely compatible, smaller files)"
            echo "2) PNG (lossless, larger files)"
            echo "3) WebP (modern, efficient)"
            echo "4) TIFF (professional, large)"
            read -p "Select format [1-4] (default: 1): " img_format_choice
            case "$img_format_choice" in
                2) image_output_format="png" ;;
                3) image_output_format="webp" ;;
                4) image_output_format="tiff" ;;
                *) image_output_format="jpg" ;;
            esac

            if [ "$image_output_format" = "jpg" ]; then
                read -p "🎚️ JPEG quality (1-100, default 85): " quality_input
                if [[ "$quality_input" =~ ^[0-9]+$ ]] && [ "$quality_input" -ge 1 ] && [ "$quality_input" -le 100 ]; then
                    image_quality="$quality_input"
                fi
            fi
        fi
    fi

    echo -e "\n📹 == Video Processing Options =="
    read -p "🎬 Convert videos using HandBrake quality settings? [y/N]: " handbrake_response
    if [[ "$handbrake_response" =~ ^[Yy]$ ]]; then
        use_handbrake_settings=true
    fi

    read -p "🔄 Convert old formats (AVI, MPG, FLV, MOV) to MP4? [y/N]: " convert_old_response
    if [[ "$convert_old_response" =~ ^[Yy]$ ]]; then
        conv_oldfileformats=true
        convert_to_mp4=true
    fi

    echo -e "\n⚙️ == General Options =="
    read -p "💾 Backup files to $backup_dir folder? [y/N]: " backups_response
    if [[ "$backups_response" =~ ^[Yy]$ ]]; then
        backups=true
    fi

    read -p "🗑️ Remove .nfo and thumbnail files? [y/N]: " metadata_files_response
    if [[ "$metadata_files_response" =~ ^[Yy]$ ]]; then
        rm_metadata_files=true
    fi

    read -p "📂 Process files recursively (including subdirectories)? [y/N]: " recursive_response
    if [[ "$recursive_response" =~ ^[Yy]$ ]]; then
        recursive=true
    fi

    # Offer to save configuration
    prompt_for_save_config

    echo -e "\n🚀 == Ready to Process =="
    echo "Summary of selected options:"

    # Only show options that are actually enabled
    local options_selected=false

    if [ "$clean_filenames" = "true" ]; then
        echo "  ✓ Clean filenames (dots to spaces)"
        options_selected=true
    fi

    if [ "$replace_underscores" = "true" ]; then
        echo "  ✓ Replace underscores with spaces"
        options_selected=true
    fi

    if [ "$capitalize_filenames" = "true" ]; then
        echo "  ✓ Capitalize filenames"
        options_selected=true
    fi

    if [ "$renameext" = "true" ]; then
        echo "  ✓ Rename video extensions to $newfileext"
        options_selected=true
    fi

    if [ "$backups" = "true" ]; then
        echo "  ✓ Create backups"
        options_selected=true
    fi

    if [ "$recursive" = "true" ]; then
        echo "  ✓ Process recursively"
        options_selected=true
    fi

    if [ "$rm_metadata_files" = "true" ]; then
        echo "  ✓ Remove metadata files"
        options_selected=true
    fi

    if [ "$process_images" = "true" ]; then
        echo "  ✓ Process images"
        options_selected=true
    fi

    if [ "$optimize_images" = "true" ]; then
        echo "  ✓ Optimize images"
        options_selected=true
    fi

    if [ "$convert_images" = "true" ]; then
        echo "  ✓ Convert images to $image_output_format"
        options_selected=true
    fi

    if [ "$use_handbrake_settings" = "true" ]; then
        echo "  ✓ Use HandBrake video compression"
        options_selected=true
    fi

    if [ "$conv_oldfileformats" = "true" ]; then
        echo "  ✓ Convert old video formats to MP4"
        options_selected=true
    fi

    echo "  🎵 Audio format: $audio_output_format"

    if [ "$options_selected" = "false" ]; then
        echo "  ⚠️  No special processing options selected - will only remove metadata"
    fi

    echo
    read -p "Process all media files with these settings? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Operation cancelled - Press Enter to exit..."
        read
        exit 0
    fi

    echo -e "\n🔄 Starting processing..."
    cleanup_directory_metadata "."
    process_files "."
    show_stats
}

# Set drag and drop defaults
set_drag_drop_defaults() {
    clean_filenames=true
    replace_underscores=true
    capitalize_filenames=false
    renameext=true
    backups=true
    rm_metadata_files=true
    process_images=true
}

main() {
    local is_drag_drop=false

    # Initialize I/O performance improvements
    improve_io_performance

    # Check for drag and drop mode
    if [ $# -gt 0 ]; then
        for path in "$@"; do
            if [ -e "$path" ]; then
                is_drag_drop=true
                break
            fi
        done
    fi

    # Set defaults for drag and drop
    if [ "$is_drag_drop" = true ]; then
        set_drag_drop_defaults
        echo "🎯 Drag and Drop Mode Activated"
    fi

    # Check dependencies before proceeding
    check_dependencies

    # Handle command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --gui)
                run_gui_mode
                exit $?
                ;;
            --formats)
                show_supported_formats
                exit 0
                ;;
            --version)
                echo "StripMeta File Processor version $SCRIPT_VERSION"
                exit 0
                ;;
            --check-update)
                check_for_updates
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
                shift
                ;;
            --backup-dir)
                backup_dir="$2"
                shift 2
                ;;
            --clean-filenames)
                clean_filenames=true
                shift
                ;;
            --replace-underscores)
                replace_underscores=true
                shift
                ;;
            --capitalize)
                capitalize_filenames=true
                shift
                ;;
            --rename)
                renameext=true
                shift
                ;;
            --recursive)
                recursive=true
                shift
                ;;
            --remove-metadata-files)
                rm_metadata_files=true
                shift
                ;;
            --conv-oldfileformats|--convert-avi-mpg-flv-mov)
                conv_oldfileformats=true
                convert_to_mp4=true
                shift
                ;;
            --handbrake)
                use_handbrake_settings=true
                shift
                ;;
            --audio-format)
                if [[ -n "$2" && "$2" =~ ^(mp3|flac|ogg|wav|aac|m4a|wma|opus)$ ]]; then
                    audio_output_format="$2"
                    shift 2
                else
                    echo "Error: Invalid audio format. Supported: mp3, flac, ogg, wav, aac, m4a, wma, opus"
                    exit 1
                fi
                ;;
            --process-images)
                process_images=true
                shift
                ;;
            --optimize-images)
                optimize_images=true
                process_images=true
                shift
                ;;
            --convert-images)
                convert_images=true
                process_images=true
                shift
                ;;
            --image-format)
                if [[ -n "$2" && "$2" =~ ^(jpg|jpeg|png|webp|tiff|bmp|gif)$ ]]; then
                    image_output_format="$2"
                    convert_images=true
                    process_images=true
                    shift 2
                else
                    echo "Error: Invalid image format. Supported: jpg, jpeg, png, webp, tiff, bmp, gif"
                    exit 1
                fi
                ;;
            --image-quality)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 100 ]; then
                    image_quality="$2"
                    shift 2
                else
                    echo "Error: Image quality must be a number between 1 and 100"
                    exit 1
                fi
                ;;
            --parallel)
                parallel_processing=true
                shift
                ;;
            --max-jobs)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ]; then
                    max_parallel_jobs="$2"
                    shift 2
                else
                    echo "Error: Max jobs must be a positive number"
                    exit 1
                fi
                ;;
            --reset-log)
                rm -f "$processing_log" "${processing_log%.log}_errors.log"
                echo "Processing logs reset."
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    # Main processing logic
    if [ $# -eq 0 ]; then
        # Interactive mode
        run_interactive_mode
    else
        # Command line mode - process specified files/directories
        echo "🚀 Processing specified files and directories..."
        for path in "$@"; do
            if [ -f "$path" ]; then
                echo "Processing file: '$path'"
                process_single_file "$path"
            elif [ -d "$path" ]; then
                echo "Processing directory: '$path'"
                process_files "$path"
            else
                echo "⚠️  Path not found: '$path'"
                files_failed=$((files_failed + 1))
            fi
        done
        show_stats
    fi

    echo
    echo "✅ Processing complete!"
    if [ "$files_failed" -gt 0 ]; then
        echo "⚠️  Some files failed - check error log: ${processing_log%.log}_errors.log"
    fi
    echo "Press Enter to exit..."
    read
}

# Execute main function with all arguments
main "$@"
