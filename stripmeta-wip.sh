#!/bin/bash
#Moocow Mooheda 16/Apr25
#Dependencies: "exiftool" "mkvpropedit" "sha256sum" "ffmpeg"

#Tdo; add functions to load config file y/n prompt

# Script version - date
SCRIPT_VERSION="1.9.2 - 18-05-25"

# Global variables
clean_filenames=false
dry_run=false
backups=false
verbose=false
renameext=false
ifexists=false
recursive=false
# Default video output format
convert_to_mp4=false
conv_oldfileformats=false
rm_metadata_files=false
replace_underscores=false
capitalize_filenames=false
use_handbrake_settings=false
files_processed=0
files_failed=0
bytes_processed=0
skipped_files=0
mp4_files_processed=0
mkv_files_processed=0
mp3_files_processed=0
flac_files_processed=0
audio_files_processed=0
video_files_processed=0
other_files_processed=0
backup_dir="./backups"
newfileext="m4v"
processing_log=".processed_files.log"
# Default audio output format
audio_output_format="mp3"
# Audio bitrates for different formats
declare -A audio_bitrates=(
  ["mp3"]="192k"
  ["aac"]="192k"
  ["flac"]="1024k"
  ["ogg"]="192k"
  ["wav"]="1536k"
  ["m4a"]="256k"
)
declare -A audio_quality=(
  ["mp3"]="0"       # 0-9 (lower is better)
  ["flac"]="8"      # 0-8 (higher is better)
  ["ogg"]="5"       # -1 to 10 (higher is better)
  ["aac"]="4"       # 1-5 (higher is better)
)

parallel_processing=true
max_parallel_jobs=4

improve_io_performance() {
    # Increase buffer size for better I/O performance
    if command -v ionice >/dev/null 2>&1; then
        ionice -c 2 -n 7 -p $$
    fi

    # Set higher buffer sizes for better file I/O
    if command -v dd >/dev/null 2>&1; then
        export DD_OPTS="bs=64k"
    fi
}

improve_io_performance

check_dependencies() {
    local deps=("exiftool" "mkvpropedit" "sha256sum" "ffmpeg")
    local missing=()
    local outdated=()

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        else
            # Check versions for critical dependencies
            case "$cmd" in
                ffmpeg)
                    # Check if ffmpeg version is at least 4.0
                    version=$(ffmpeg -version | head -n1 | awk '{print $3}' | cut -d. -f1)
                    if [ -n "$version" ] && [ "$version" -lt 4 ]; then
                        outdated+=("$cmd (version $version, recommended 4.0+)")
                    fi
                    ;;
                exiftool)
                    # Check if exiftool version is at least 12.0
                    version=$(exiftool -ver | cut -d. -f1)
                    if [ -n "$version" ] && [ "$version" -lt 12 ]; then
                        outdated+=("$cmd (version $version, recommended 12.0+)")
                    fi
                    ;;
            esac
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        echo "Please install the missing dependencies and try again."
        echo "Press Enter to exit..."
        read
        exit 1
    fi

    if [ ${#outdated[@]} -gt 0 ]; then
        echo "Warning: Some dependencies are outdated: ${outdated[*]}"
        echo "The script may not work correctly with older versions."
        echo "Do you want to continue anyway? [y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Exiting. Please update the dependencies and try again."
            exit 1
        fi
    fi
}

# Handle_error function
handle_error() {
    local error_code=$1
    local error_message=$2
    local operation=$3
    local file=$4

    echo "Error (code $error_code) during $operation: $error_message" >&2
    echo "Failed to process: $file" >&2

    # Log error to file
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $operation failed for $file: $error_message" >> "${processing_log%.log}_errors.log"

    # Attempt recovery based on operation type
    case "$operation" in
        "metadata_removal")
            echo "Attempting alternative method for metadata removal..."
            # Try alternative method here
            ;;
    esac
}

rotate_logs() {
    # Rotate logs if they get too big (>10MB)
    if [ -f "$processing_log" ] && [ $(stat -c%s "$processing_log" 2>/dev/null || stat -f%z "$processing_log") -gt 10485760 ]; then
        local timestamp=$(date +"%Y%m%d%H%M%S")
        mv "$processing_log" "${processing_log}.${timestamp}"
        echo "Log file rotated to ${processing_log}.${timestamp}"
    fi
}

if [ -t 1 ]; then
    # Already in a terminal, continue normal execution
    : # no-op
else
    # Try to detect the desktop environment
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        case "$XDG_CURRENT_DESKTOP" in
            GNOME|Unity)
                gnome-terminal -- bash -c "$0 $*; exec bash" || xterm -e bash -c "$0 $*; exec bash"
                ;;
            KDE)
                konsole -e bash -c "$0 $*; exec bash" || xterm -e bash -c "$0 $*; exec bash"
                ;;
            XFCE)
                xfce4-terminal -e "bash -c \"$0 $*; exec bash\"" || xterm -e bash -c "$0 $*; exec bash"
                ;;
            *)
                # Try common terminals
                x-terminal-emulator -e "$0 $*" || \
                gnome-terminal -- bash -c "$0 $*; exec bash" || \
                konsole -e bash -c "$0 $*; exec bash" || \
                xterm -e bash -c "$0 $*; exec bash" || \
                open -a Terminal "$0" || \
                echo "Unable to open terminal"
                ;;
        esac
    elif [ "$(uname)" = "Darwin" ]; then
        # macOS
        open -a Terminal "$0"
    else
        # Try common terminals as fallback
        x-terminal-emulator -e "$0 $*" || \
        gnome-terminal -- bash -c "$0 $*; exec bash" || \
        konsole -e bash -c "$0 $*; exec bash" || \
        xterm -e bash -c "$0 $*; exec bash" || \
        echo "Unable to open terminal"
    fi
    exit 0
fi

# Clean filename by replacing dots with spaces, ensuring proper .ext format
clean_filename() {
    local file="$1"
    local dir=$(dirname "$file")
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    local name="${filename%.*}"
    local new_filename="$name"
    local changed=false

    # Clean filename if option enabled
    if [ "$clean_filenames" = true ]; then
        # Replace dots with spaces in the filename
        new_filename=$(echo "$new_filename" | sed 's/\./ /g')
        changed=true
    fi

    # Replace underscores with spaces if option enabled
    if [ "$replace_underscores" = true ]; then
        new_filename=$(echo "$new_filename" | sed 's/_/ /g')
        changed=true
    fi

    # Capitalize filename if option enabled
    if [ "$capitalize_filenames" = true ]; then
        # Capitalize first letter of each word
        new_filename=$(echo "$new_filename" | awk '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) tolower(substr($i,2)) }}1')
        changed=true
    fi

    # Handle special characters
    new_filename=$(echo "$new_filename" | sed 's/[^[:alnum:][:space:]._-]/_/g')

    # Add extension back
    new_filename="$new_filename.$extension"
    local new_path="$dir/$new_filename"

    # Only rename if the filename actually changes
    if [ "$changed" = true ] && [ "$filename" != "$new_filename" ]; then
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would rename: $file -> $new_path"
            echo "$file"
            return 0
        else
            if mv "$file" "$new_path"; then
                echo "Renamed: $file -> $new_path"
                echo "$new_path"
                return 0
            else
                echo "Failed to rename: $file"
                echo "$file"
                return 1
            fi
        fi
    fi
    echo "$file"
}

convert_with_handbrake_settings() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    # If HandBrake conversion is disabled, return
    if [ "$use_handbrake_settings" = false ]; then
        return 1
    fi

    echo "Converting using HandBrake settings: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert with HandBrake settings: $file"
        return 0
    fi

    # Backup the original file if backups are enabled
    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    # Create output filename
    local dir=$(dirname "$file")
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    local name="${filename%.*}"
    local output_file="${dir}/${name}_converted.mkv"

    # Parse the file to determine crop values
    local crop_params=""
    if command -v ffmpeg >/dev/null 2>&1; then
        # Auto-detect crop using ffmpeg cropdetect filter
        crop_params=$(ffmpeg -ss 60 -i "$file" -t 1 -vf cropdetect -f null - 2>&1 | awk '/crop/ { print $NF }' | tail -1)
        if [ -z "$crop_params" ]; then
            # Default crop from HandBrake settings
            crop_params="crop=66:68:0:0"
        fi
    else
        # Default crop from HandBrake settings
        crop_params="crop=66:68:0:0"
    fi

    # Use ffmpeg with settings similar to HandBrake preset
    if ffmpeg -i "$file" \
        -c:v libx265 -preset medium -crf 32 \
        -vf "$crop_params,scale=1280:720:flags=lanczos,unsharp=5:5:1.0:5:5:0.0,hqdn3d=1.0:1.0:2.0:2.0" \
        -c:a copy \
        -map_metadata -1 \
        -movflags +faststart \
        "$output_file"; then

        # If successful and not backing up, remove original
        if [ "$backups" = "false" ]; then
            rm "$file"
        fi

        echo "✓ Converted with HandBrake settings: $output_file"
        files_processed=$((files_processed + 1))
        log_processed_file "$output_file" "handbrake_conversion"
        return 0
    else
        echo "✗ Failed to convert with HandBrake settings: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

# Show progress
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percent=$((current * 100 / total))
    local completed=$((width * current / total))

    printf "\r[%${completed}s%${((width - completed))}s] %d%% (%d/%d)" | tr ' ' '#' | tr '#' ' '
    printf " %d%% (%d/%d)" "$percent" "$current" "$total"

    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

show_stats() {
 echo "========== Processing Statistics =========="
 echo "Files processed successfully: $files_processed"
 echo "Files failed: $files_failed"
 echo "Total data processed: $(numfmt --to=iec-i --suffix=B $bytes_processed 2>/dev/null || echo "$bytes_processed bytes")"
 echo ""
 echo "Files processed by type:"
  if [ "$video_files_processed" -gt 0 ]; then
    echo "  Video files: $video_files_processed"
  fi
  if [ "$mp4_files_processed" -gt 0 ]; then
    echo "    - MP4: $mp4_files_processed"
  fi
  if [ "$mkv_files_processed" -gt 0 ]; then
    echo "    - MKV: $mkv_files_processed"
  fi
  if [ "$audio_files_processed" -gt 0 ]; then
    echo "  Audio files: $audio_files_processed"
  fi
  if [ "$mp3_files_processed" -gt 0 ]; then
    echo "    - MP3: $mp3_files_processed"
  fi
  if [ "$flac_files_processed" -gt 0 ]; then
    echo "    - FLAC: $flac_files_processed"
  fi
  if [ "$other_files_processed" -gt 0 ]; then
    echo "  Other files: $other_files_processed"
  fi
  echo "==========================================="

}
update_progress() {
    local current=$1
    local total=$2
    local file=$3
    local percent=$((current * 100 / total))

    # Create a progress bar
    local completed=$((percent / 2))
    local remaining=$((50 - completed))

    printf "\r[%${completed}s%${remaining}s] %3d%% - %s" | tr ' ' '#' | tr '#' ' '
    printf " %3d%% - Processing: %s" "$percent" "$(basename "$file")"
}

check_for_updates() {
    echo "Checking for script updates..."
    # This would need to be customized based on where you host your script
    # Example for a script hosted on GitHub:
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s https://raw.githubusercontent.com/yourusername/stripmeta/main/version.txt)
        if [ -n "$latest_version" ] && [ "$latest_version" != "$SCRIPT_VERSION" ]; then
            echo "A new version ($latest_version) is available! Current version: $SCRIPT_VERSION"
            echo "Visit https://github.com/yourusername/stripmeta to update"
        else
            echo "You are running the latest version: $SCRIPT_VERSION"
        fi
    else
        echo "curl not found, cannot check for updates"
    fi
}

prompt_for_save_config() {
    read -p "Would you like to save these settings as default configuration? [y/N]: " save_config_response
    if [[ "$save_config_response" =~ ^[Yy]$ ]]; then
        save_config
    else
        # Still remember for next run
        remember_last_choices
    fi
}

check_conf() {
    #local conf_file="$1"
    local config_file="$HOME/.stripmeta-config"
    if [[ -z "$HOME/.stripmeta-config" ]]; then
        echo "No config file specified."
        #Seems to be having issues detecting the file in my home folder
        return 1
    elif [[ ! -f "$HOME/.stripmeta-config" ]]; then
        echo "Config file '$HOME/.stripmeta-config' does not exist."
        return 1
    elif [[ ! -r "$HOME/.stripmeta-config" ]]; then
        echo "Config file '$HOME/.stripmeta-config' is not readable."
        return 1
    else
        ifexists="true"
        return 0
    fi
}

load_conf() (
    local conf_file="$1"
    if check_conf "$home/$config_file"; then
        # shellcheck source=/dev/null
         local config_file="$HOME/.stripmeta-config"
        source "$home/$config_file"
        echo "# Loaded saved choices" > "$config_file"
        echo "last_clean_filenames=$clean_filenames" >> "$config_file"
        echo "last_replace_underscores=$replace_underscores" >> "$config_file"
        echo "last_capitalize_filenames=$capitalize_filenames" >> "$config_file"
        echo "last_rename=$renameext" >> "$config_file"
        echo "last_backups=$backups" >> "$config_file"
        echo "last_recursive=$recursive" >> "$config_file"
        echo "last_convert_to_mp4=$convert_to_mp4" >> "$config_file"
        echo "last_conv_oldfileformats=$conv_oldfileformats" >> "$config_file"
        echo "last_use_handbrake_settings=$use_handbrake_settings" >> "$config_file"
        echo "last_rm_metadata_files=$rm_metadata_files" >> "$config_file"
        echo "last_audio_output_format=\"$audio_output_format\"" >> "$config_file"
        echo " "
        echo -e "\n== Ready to Process =="
        read -p "Process all video and audio files, Continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled - Press Enter to exit.."
            read
            exit 0
        fi
        else
        echo "Failed to load configuration."
        return 1
    fi
)

# Save config
save_config() {
    local config_file="$HOME/.stripmeta-config"

    echo "# StripMeta configuration file" > "$config_file"
    echo "# Generated on $(date)" >> "$config_file"
    echo "clean_filenames=$clean_filenames" >> "$config_file"
    echo "replace_underscores=$replace_underscores" >> "$config_file"
    echo "capitalize_filenames=$capitalize_filenames" >> "$config_file"
    echo "rename=$renameext" >> "$config_file"
    echo "backups=$backups" >> "$config_file"
    echo "verbose=$verbose" >> "$config_file"
    echo "recursive=$recursive" >> "$config_file"
    echo "convert_to_mp4=$convert_to_mp4" >> "$config_file"
    echo "conv_oldfileformats=$conv_oldfileformats" >> "$config_file"
    echo "use_handbrake_settings=$use_handbrake_settings" >> "$config_file"
    echo "rm_metadata_files=$rm_metadata_files" >> "$config_file"
    echo "backup_dir=\"$backup_dir\"" >> "$config_file"
    echo "newfileext=\"$newfileext\"" >> "$config_file"
    echo "audio_output_format=\"$audio_output_format\"" >> "$config_file"

    echo "Configuration saved to $config_file"
}

remember_last_choices() {
    local config_file="$HOME/.stripmeta-lastrun"
    echo "# Last run choices" > "$config_file"
    echo "last_clean_filenames=$clean_filenames" >> "$config_file"
    echo "last_replace_underscores=$replace_underscores" >> "$config_file"
    echo "last_capitalize_filenames=$capitalize_filenames" >> "$config_file"
    echo "last_rename=$renameext" >> "$config_file"
    echo "last_backups=$backups" >> "$config_file"
    echo "last_recursive=$recursive" >> "$config_file"
    echo "last_convert_to_mp4=$convert_to_mp4" >> "$config_file"
    echo "last_conv_oldfileformats=$conv_oldfileformats" >> "$config_file"
    echo "last_use_handbrake_settings=$use_handbrake_settings" >> "$config_file"
    echo "last_rm_metadata_files=$rm_metadata_files" >> "$config_file"
    echo "last_audio_output_format=\"$audio_output_format\"" >> "$config_file"
}

load_last_choices() {

    local config_file="$HOME/.stripmeta-lastrun"
    if [ -f "$config_file" ]; then
        . "$config_file"
        # Apply last choices as defaults if not already set
        [ -z "$clean_filenames" ] && clean_filenames=${last_clean_filenames:-false}
        [ -z "$replace_underscores" ] && replace_underscores=${last_replace_underscores:-false}
        [ -z "$capitalize_filenames" ] && capitalize_filenames=${last_capitalize_filenames:-false}
        [ -z "$renameext" ] && renameext=${last_rename:-false}
        [ -z "$backups" ] && backups=${last_backups:-false}
        [ -z "$recursive" ] && recursive=${last_recursive:-false}
        [ -z "$convert_to_mp4" ] && convert_to_mp4=${last_convert_to_mp4:-false}
        [ -z "$conv_oldfileformats" ] && conv_oldfileformats=${last_conv_oldfileformats:-false}
        [ -z "$use_handbrake_settings" ] && use_handbrake_settings=${last_use_handbrake_settings:-false}
        [ -z "$rm_metadata_files" ] && rm_metadata_files=${last_rm_metadata_files:-false}
        [ -z "$audio_output_format" ] && audio_output_format=${last_audio_output_format:-"mp3"}
    fi
}

verify_file_integrity() {
    local file="$1"
    local original_size=$2

    # Check if file exists
    if [ ! -f "$file" ]; then
        echo "Error: Output file not found: $file"
        return 1
    fi

    # Check if file size is reasonable (not zero and not significantly smaller)
    local new_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
    if [ "$new_size" -eq 0 ]; then
        echo "Error: Output file is empty: $file"
        return 1
    fi

    # For media files, try to validate with ffmpeg
    if [[ "$file" =~ \.(mp4|mp3|mkv|m4v|flv|mov|avi|wav|ogg|flac)$ ]]; then
        if ! ffmpeg -v error -i "$file" -f null - >/dev/null 2>&1; then
            echo "Error: Output file fails integrity check: $file"
            return 1
        fi
    fi

    return 0
}

# Verification function
verify_metadata_removal() {
    local file="$1"
    local file_type="$2"

    if [ "$verbose" = "true" ]; then
        echo -n "Verifying metadata removal for $file... "
    fi

    # Create a temp file for output
    local temp_output=$(mktemp)

    case "$file_type" in
        mp3|mp4|m4v|m4a|flv|mov)
            # Use exiftool for thorough check
            exiftool "$file" > "$temp_output"
            if grep -i -E '(title|artist|album|year|comment|genre|copyright|manufacturer|model|created)' "$temp_output"; then
                echo "WARNING: Some metadata may remain in the file."
                rm "$temp_output"
                return 1
            else
                [ "$verbose" = "true" ] && echo "OK"
                rm "$temp_output"
                return 0
            fi
            ;;
        mkv)
            # More comprehensive MKV check
            if command -v mkvinfo >/dev/null 2>&1; then
                mkvinfo "$file" > "$temp_output"
                if grep -i -E "(title|date|comment|description|copyright)" "$temp_output"; then
                    echo "WARNING: Metadata may remain in the MKV file."
                    rm "$temp_output"
                    return 1
                else
                    [ "$verbose" = "true" ] && echo "OK"
                    rm "$temp_output"
                    return 0
                fi
            else
                [ "$verbose" = "true" ] && echo "Skipped (mkvinfo not available)"
                rm "$temp_output"
                return 2
            fi
            ;;
    esac

    rm "$temp_output"
    return 0
}

# Add function to detect file type by content
detect_file_content_type() {
    local file="$1"
    local file_output

    # Check if file command exists
    if command -v file >/dev/null 2>&1; then
        file_output=$(file -b --mime-type "$file")
        echo "$file_output"
    else
        # Fall back to extension if file command is not available
        detect_file_type "$file"
    fi
}

# Remove all .nfo and thumb.jpg files in directory
cleanup_directory_metadata() {
    local dir="$1"

    if [ "$rm_metadata_files" = false ]; then
        return 0
    fi

    echo "Cleaning metadata files in directory: $dir"

    # Find and remove .nfo files
    find "$dir" -maxdepth 1 -name "*.nfo" -type f | while read -r nfo_file; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove NFO file: $nfo_file"
        else
            rm "$nfo_file"
            echo "Removed NFO file: $nfo_file"
        fi
    done

    # Find and remove thumb.jpg files
    find "$dir" -maxdepth 1 -name "*thumb.jpg" -type f | while read -r thumb_file; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove thumbnail: $thumb_file"
        else
            rm "$thumb_file"
            echo "Removed thumbnail: $thumb_file"
        fi
    done

    # Also try to find and remove any other .jpg files that might be thumbs
    find "$dir" -maxdepth 1 -name "*.jpg" -type f -size -100k | while read -r jpg_file; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove potential thumbnail: $jpg_file"
        else
            rm "$jpg_file"
            echo "Removed potential thumbnail: $jpg_file"
        fi
    done
}

# Remove associated metadata files for a specific video file
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
        "$dir/$base_filename"*".jpg"        # Any jpg with base name
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
        files_processed=$((files_processed + 1))
        return 0
    else
        echo "✗ Failed to convert to MP4: $file"
        files_failed=$((files_failed + 1))
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

# Improve the log_processed_file function
# Improve the log_processed_file function
log_processed_file() {
    local file="$1"
    local operation="${2:-processed}"
    local size=$(du -h "$file" | cut -f1)
    local file_type="${3:-unknown}"

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

    # Get file hash and log it with detailed info
    local file_hash=$(sha256sum "$file" | awk '{print $1}')
    local abs_path=$(readlink -f "$file")
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp | $file_hash | $operation | $size | $file_type | $abs_path" >> "$processing_log"

    # Update counters based on file type
    files_processed=$((files_processed+1))
    bytes_processed=$((bytes_processed+$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")))

    # Update file type counters
    case "$file_type" in
        mp4) mp4_files_processed=$((mp4_files_processed+1)); video_files_processed=$((video_files_processed+1)) ;;
        mkv) mkv_files_processed=$((mkv_files_processed+1)); video_files_processed=$((video_files_processed+1)) ;;
        mp3) mp3_files_processed=$((mp3_files_processed+1)); audio_files_processed=$((audio_files_processed+1)) ;;
        flac) flac_files_processed=$((flac_files_processed+1)); audio_files_processed=$((audio_files_processed+1)) ;;
        audio_*) audio_files_processed=$((audio_files_processed+1)) ;;
        video_*) video_files_processed=$((video_files_processed+1)) ;;
        *) other_files_processed=$((other_files_processed+1)) ;;
    esac

    # Rotate logs if needed
    rotate_logs
}

# Process MP3 audio files
process_mp3() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    # Check if file has been processed
    if is_file_processed "$file"; then
        echo "Skipping already processed MP3 file: $file"
        return 0
    fi

    # Clean filename first
    file=$(clean_filename "$file")

    echo "Processing MP3: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process MP3: $file"
        return 0
    fi

    # Backup the original file if backups are enabled
    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    # Use exiftool to strip metadata from MP3
    if exiftool -overwrite_original -All= "$file"; then
        echo "✓ Processed MP3 with exiftool: $file"
        log_processed_file "$file" "processed" "mp3"
        files_processed=$((files_processed + 1))
        return 0
    else
        echo "✗ Failed to process MP3 with exiftool: $file"
        files_failed=$((files_failed + 1))

        # Alternative: Try ffmpeg as a fallback
        local temp_file="${file%.*}_stripped.mp3"
        if ffmpeg -i "$file" -c:a copy -map_metadata -1 "$temp_file"; then
            # Replace original file
            mv "$temp_file" "$file"
            echo "✓ Processed MP3 with ffmpeg: $file"
            # Log processed file
            log_processed_file "$file"
            return 0
        fi

        return 1
    fi
}

# General function to convert audio files to chosen format
convert_audio() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local input_format="${3:-unknown}"

    # Check if file has been processed
    if is_file_processed "$file"; then
        echo "Skipping already processed $input_format file: $file"
        return 0
    fi

    # Clean filename first
    file=$(clean_filename "$file")

    echo "Processing $input_format: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert $input_format to $audio_output_format: $file"
        return 0
    fi

    # Backup the original file if backups are enabled
    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    # Create output filename
    local output_file="${file%.*}.$audio_output_format"

    # Get appropriate bitrate for the chosen format
    local bitrate="${audio_bitrates[$audio_output_format]:-192k}"

    # Different audio codecs based on format
    local audio_codec
    case "$audio_output_format" in
        mp3)
            audio_codec="libmp3lame"
            ;;
        flac)
            audio_codec="flac"
            ;;
        ogg)
            audio_codec="libvorbis"
            ;;
        wav)
            audio_codec="pcm_s16le"
            ;;
        aac)
            audio_codec="aac"
            ;;
        m4a)
            audio_codec="aac" # AAC in M4A container
            output_file="${file%.*}.m4a" # Ensure M4A extension
            ;;
        *)
            audio_codec="libmp3lame" # Default to MP3
            output_file="${file%.*}.mp3" # Default to MP3 extension
            ;;
    esac

    # Skip conversion if input and output formats are the same
    if [ "$input_format" = "$audio_output_format" ]; then
        echo "Input and output formats are the same. Just removing metadata..."
        if exiftool -overwrite_original -All= "$file"; then
            echo "✓ Removed metadata from $input_format file: $file"
            log_processed_file "$file"
            return 0
        else
            local temp_file="${file%.*}_stripped.$input_format"
            if ffmpeg -i "$file" -c:a copy -map_metadata -1 "$temp_file"; then
                mv "$temp_file" "$file"
                echo "✓ Removed metadata with ffmpeg: $file"
                log_processed_file "$file"
                return 0
            fi
        fi
    fi

    # Use ffmpeg to convert audio file
    if ffmpeg -i "$file" -vn -ar 44100 -ac 2 -c:a "$audio_codec" -b:a "$bitrate" -map_metadata -1 "$output_file"; then
        # Remove original file if conversion successful and not backing up
        if [ "$backups" = "false" ]; then
            rm "$file"
        fi
        echo "✓ Converted $input_format to $audio_output_format: $output_file"
        # Log processed file
        log_processed_file "$output_file" "processed" "$audio_output_format"
        files_processed=$((files_processed + 1))
        return 0
    else
        echo "✗ Failed to convert $input_format to $audio_output_format: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

# Process M3U playlist files
process_m3u() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    # Check if file has been processed
    if is_file_processed "$file"; then
        echo "Skipping already processed M3U file: $file"
        return 0
    fi

    # Clean filename first
    file=$(clean_filename "$file")

    echo "Processing M3U: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would clean M3U playlist: $file"
        return 0
    fi

    # Backup the original file if backups are enabled
    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    # Create a clean version of the playlist without metadata
    local temp_file="${file%.*}_cleaned.m3u"
    grep -v "^#" "$file" > "$temp_file"

    # Replace original file
    mv "$temp_file" "$file"
    echo "✓ Cleaned M3U playlist: $file"

    # Log processed file
    log_processed_file "$file" "playlist" "m3u"
    return 0
}

# Function to process files in a directory
process_files() {
    local dir="${1:-.}"  # Use current directory if no argument provided

    # First, clean up metadata files in the directory
    cleanup_directory_metadata "$dir"

    # Find video and audio files based on extensions and recursion flag
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
        "-name" "*.mov" "-o"
        "-name" "*.mp3" "-o"
        "-name" "*.wav" "-o"
        "-name" "*.ogg" "-o"
        "-name" "*.iff" "-o"
        "-name" "*.8svx" "-o"
        "-name" "*.flac" "-o"
        "-name" "*.aac" "-o"
        "-name" "*.m4a" "-o"
        "-name" "*.m3u" "-o"
        "-name" "*.m3v" "-o"
        "-name" "*.aud"
    \))

    # Process each found file
    while IFS= read -r file; do
        ext="${file##*.}"
        ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        case "$ext" in
            mp3)
                # Process MP3 audio files (only strip metadata if same as output format)
                if [ "$audio_output_format" = "mp3" ]; then
                    process_mp3 "$file" "$backup_dir"
                else
                    convert_audio "$file" "$backup_dir" "mp3"
                fi
                ;;
            wav|ogg|flac|aac|m4a|iff|8svx|m3v|aud)
                # Convert audio files to selected format
                convert_audio "$file" "$backup_dir" "$ext"
                ;;
            m3u)
                # Process M3U playlist files
                process_m3u "$file" "$backup_dir"
                ;;
            m4v|mkv|mp4)
            # Strip metadata first
                strip_metadata "$file" "$backup_dir"
                # If HandBrake settings are enabled, convert using them
                if [ "$use_handbrake_settings" = "true" ]; then
                    convert_with_handbrake_settings "$file" "$backup_dir"
                fi
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

    # If recursive, process subdirectories separately
    if [ "$recursive" = true ]; then
        find "$dir" -mindepth 1 -type d | while read -r subdir; do
            if [ "$verbose" = "true" ]; then
                echo "Processing subdirectory: $subdir"
            fi
            cleanup_directory_metadata "$subdir"
        done
    fi
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
    if [ "$renameext" = "true" ]; then
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
            log_processed_file "$file" "processed" "$file_type"
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
            log_processed_file "$file" "processed" "avi"
            files_processed=$((files_processed + 1))
            return 0
        else
            echo "✗ Failed to process AVI with ffmpeg: $file"
            files_failed=$((files_failed + 1))
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
    if [ "$renameext" = "true" ]; then
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
        files_processed=$((files_processed + 1))
        # Log processed file
        log_processed_file "$file" "processed" "mkv"
    else
        echo "✗ Failed to process with mkvpropedit: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

# Set drag and drop specific defaults
set_drag_drop_defaults() {
    clean_filenames=true
    replace_underscores=true
    capitalize_filenames=false  # Set to false by default for drag and drop
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

    # check configuration file
    check_config

    # Parse command-line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check-update)
                check_for_updates
                exit 0
                ;;
            --parallel)
                parallel_processing=true
                shift
                ;;
            --max-jobs)
                max_parallel_jobs="$2"
                shift 2
                ;;
            --audio-format)
                if [[ -n "$2" && "$2" =~ ^(mp3|flac|ogg|wav|aac|m4a)$ ]]; then
                    audio_output_format="$2"
                    shift 2
                else
                    echo "Error: Invalid audio format. Supported formats: mp3, flac, ogg, wav, aac, m4a"
                    exit 1
                fi
                ;;
            --version)
                echo "Video File Processor version $SCRIPT_VERSION"
                exit 0
                ;;
            --dry-run)
                dry_run=true
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
            --handbrake)
                use_handbrake_settings=true
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
            --rename)
                rename=true
                shift
                ;;
            --recursive)
                recursive=true
                shift
                ;;
           # --convert-to-mp4)
           #     convert_to_mp4=true
           #     shift
           #     ;;
            --convert-avi-mpg-flv-mov|--conv-oldfileformats)
                conv_oldfileformats=true
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

    if [ $# -eq 0 ]; then
    # Load last choices first to use as defaults
    load_last_choices
    echo "==== StripMeta File Processor ===="
    echo "Script version: $SCRIPT_VERSION"

    #if exists ~="$home/stripmeta-config"
    if [ "$ifexists" = true ]; then
            read -p "StripMeta config file found, You it? [y/N]: " file_exists
            if [[ "$file_exists" =~ ^[Yy]$ ]]; then
                load_conf
            fi
    else
    # Ask about processing options in groups
    echo -e "\n== Filename Handling Options =="
        if [ "$renameext" = false ]; then
            read -p "Rename video file extensions to $newfileext? [y/N]: " rename_response
            if [[ "$rename_response" =~ ^[Yy]$ ]]; then
                renameext=true
            fi
        fi

        if [ "$clean_filenames" = false ]; then
            read -p "Replace dots with spaces in filenames? [y/N]: " clean_response
            if [[ "$clean_response" =~ ^[Yy]$ ]]; then
                clean_filenames=true
            fi
        fi

        if [ "$replace_underscores" = false ]; then
            read -p "Replace underscores with spaces in filenames? [y/N]: " underscores_response
            if [[ "$underscores_response" =~ ^[Yy]$ ]]; then
                replace_underscores=true
            fi
        fi

        if [ "$capitalize_filenames" = false ]; then
            read -p "Capitalize words in filenames? [y/N]: " capitalize_response
            if [[ "$capitalize_response" =~ ^[Yy]$ ]]; then
                capitalize_filenames=true
            fi
        fi

        echo -e "\n== Audio Processing Options =="
        echo "Choose audio output format:"
        echo "1) MP3 (default)"
        echo "2) FLAC (lossless)"
        echo "3) OGG"
        echo "4) WAV (uncompressed)"
        echo "5) AAC"
        echo "6) M4A"
        read -p "Select format [1-6] (default: 1): " format_choice
        case "$format_choice" in
        2) audio_output_format="flac" ;;
        3) audio_output_format="ogg" ;;
        4) audio_output_format="wav" ;;
        5) audio_output_format="aac" ;;
        6) audio_output_format="m4a" ;;
        *) audio_output_format="mp3" ;; # Default or invalid input
        esac
        echo "Selected audio output format: $audio_output_format"

        echo -e "\n== Video Processing Options =="
        if [ "$use_handbrake_settings" = false ]; then
            read -p "Convert videos using HandBrake quality settings? [y/N]: " handbrake_response
            if [[ "$handbrake_response" =~ ^[Yy]$ ]]; then
                use_handbrake_settings=true
            fi
        fi

        if [ "$convert_to_mp4" = true ]; then
        read -p "Convert AVI, MPG, FLV, MOV, MPEG (Old Movie Formats) to MP4? [y/N]: " convert_specific_response
            if [[ "$convert_specific_response" =~ ^[Yy]$ ]]; then
                conv_oldfileformats=true
                convert_to_mp4=true
            fi
        fi
        echo -e "\n== General Options =="
        if [ "$backups" = false ]; then
            read -p "Backup files to $backup_dir folder? [y/N]: " backups_response
            if [[ "$backups_response" =~ ^[Yy]$ ]]; then
                backups=true
            fi
        fi

        if [ "$rm_metadata_files" = false ]; then
            read -p "Remove .nfo and thumb.jpg files? [y/N]: " metadata_files_response
            if [[ "$metadata_files_response" =~ ^[Yy]$ ]]; then
            rm_metadata_files=true
            fi
        fi

        if [ "$recursive" = false ]; then
        read -p "Process files recursively? [y/N]: " recursive_response
            if [[ "$recursive_response" =~ ^[Yy]$ ]]; then
            recursive=true
            fi
        fi

        # Ask to save configuration
        prompt_for_save_config
        echo -e "\n== Ready to Process =="
        read -p "Process all video and audio files, Continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled - Press Enter to exit.."
            read
            exit 0
        fi
    fi
    # Process files
    cleanup_directory_metadata "."
    process_files
    # Show stats at the end
    show_stats

    else
        # Process specified files or directories
          for path in "$@"; do
            if [ -f "$path" ]; then
                # Process individual files
                ext="${path##*.}"
                ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
                case "$ext" in
                    mp3)
                        # First clean up the directory of the file
                        cleanup_directory_metadata "$(dirname "$path")"
                        # Process MP3 audio file
                        process_mp3 "$path" "$backup_dir"
                        ;;
                    wav)
                        # First clean up the directory of the file
                        cleanup_directory_metadata "$(dirname "$path")"
                        # Process WAV audio file - convert to MP3
                        convert_audio "$path" "$backup_dir" "wav"
                        ;;
                    ogg)
                        # First clean up the directory of the file
                        cleanup_directory_metadata "$(dirname "$path")"
                        # Process OGG audio file - convert to MP3
                        convert_audio "$path" "$backup_dir" "ogg"
                        ;;
                    iff)
                        # First clean up the directory of the file
                        cleanup_directory_metadata "$(dirname "$path")"
                        # Process IFF audio file - convert to MP3
                        convert_audio "$path" "$backup_dir" "iff"
                        ;;
                  mpeg|mpg|mp4|avi|m4v|flv|mov)
                        # First clean up the directory of the file
                        cleanup_directory_metadata "$(dirname "$path")"
                        strip_metadata "$path" "$backup_dir"
                        if [ "$conv_oldfileformats" = "true" ]; then
                            convert_to_mp4 "$path" "$backup_dir"
                        elif [ "$use_handbrake_settings" = "true" ]; then
                            convert_with_handbrake_settings "$path" "$backup_dir"
                        fi
                        ;;
                    mkv)
                        # First clean up the directory of the file
                        cleanup_directory_metadata "$(dirname "$path")"
                        process_mkv "$path" "$backup_dir"
                        if [ "$use_handbrake_settings" = "true" ]; then
                            convert_with_handbrake_settings "$path" "$backup_dir"
                        fi
                        ;;
                    *)
                        echo "Unsupported file type: $path"
                        ;;
                esac
            elif [ -d "$path" ]; then
                # Clean up directory first
                cleanup_directory_metadata "$path"

                # Process files in specified directory
                echo "Processing files in directory: $path"
                process_files "$path"
            else
                echo "Not a file or directory: $path"
            fi
        done
    fi
    echo "Processing complete. Press Enter to exit..."
    read
}

# Call main function with all arguments
main "$@"
