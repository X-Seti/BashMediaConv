#!/bin/bash
#Moocow Mooheda 16/Apr25 - Updated 23/May25
#StripMeta GUI - Media File Metadata Remover & Processor with Graphical Interface
#Dependencies: "exiftool" "mkvpropedit" "sha256sum" "ffmpeg"
#Optional: "zenity" "kdialog" "yad" "curl" "numfmt" "ionice"

#TODO: Add parallel processing support, batch operations

# Script version - date
SCRIPT_VERSION="2.0.0 - 23-05-25"

# Global variables
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
other_files_processed=0
backup_dir="./backups"
newfileext="m4v"
processing_log=".processed_files.log"
audio_output_format="mp3"
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

parallel_processing=true
max_parallel_jobs=4

improve_io_performance() {
    # Increase buffer size for better I/O performance
    if command -v ionice >/dev/null 2>&1; then
        ionice -c 2 -n 7 -p $$
    fi
    if command -v dd >/dev/null 2>&1; then
        export DD_OPTS="bs=64k"
    fi
}

improve_io_performance

check_dependencies() {
    local deps=("exiftool" "mkvpropedit" "sha256sum" "ffmpeg")
    local optional_deps=("zenity" "kdialog" "yad" "curl" "numfmt" "ionice")
    local missing=()
    local outdated=()
    local missing_optional=()

    echo "Checking dependencies for StripMeta GUI v$SCRIPT_VERSION..."

    # Check required dependencies
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        else
            case "$cmd" in
                ffmpeg)
                    # Check if ffmpeg version is at least 4.0
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

    # Check optional dependencies
    for cmd in "${optional_deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_optional+=("$cmd")
        fi
    done

    # Report missing required dependencies
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "❌ Error: Missing required dependencies: ${missing[*]}"
        echo -e "\nInstallation commands:"
        echo "Ubuntu/Debian: sudo apt install ${missing[*]}"
        echo "Arch Linux: sudo pacman -S ${missing[*]}"
        echo "Fedora: sudo dnf install ${missing[*]}"
        echo -e "\nPlease install the missing dependencies and try again"
        echo "Press Enter to exit..."
        read
        exit 1
    fi

    # Report outdated dependencies
    if [ ${#outdated[@]} -gt 0 ]; then
        echo -e "⚠️  Warning: Some dependencies are outdated: ${outdated[*]}"
        echo -e "The script may not work correctly with older versions."
        echo "Do you want to continue anyway? [y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Exiting. Please update the dependencies and try again."
            exit 1
        fi
    fi

    # Report missing optional dependencies
    if [ ${#missing_optional[@]} -gt 0 ]; then
        echo -e "ℹ️  Info: Missing optional dependencies: ${missing_optional[*]}"

        # Check specifically for GUI tools
        if [[ " ${missing_optional[*]} " =~ " zenity " ]] && \
           [[ " ${missing_optional[*]} " =~ " kdialog " ]] && \
           [[ " ${missing_optional[*]} " =~ " yad " ]]; then
            echo -e "📋 GUI Mode: Install zenity, kdialog, or yad for graphical interface"
            echo "   Ubuntu/Debian: sudo apt install zenity"
            echo "   KDE: sudo apt install kdialog"
            echo "   Advanced: sudo apt install yad"
        fi

        if [[ " ${missing_optional[*]} " =~ " curl " ]]; then
            echo -e "🔄 Updates: Install curl to check for script updates"
        fi

        if [[ " ${missing_optional[*]} " =~ " numfmt " ]]; then
            echo -e "📊 Formatting: Install coreutils for better file size display"
        fi

        echo ""
    fi

    echo "✅ Required dependencies check passed!"

    # Show available GUI tools
    local gui_tool=$(check_gui_tools)
    if [ "$gui_tool" != "none" ]; then
        echo "🎨 GUI Mode: Available ($gui_tool)"
    else
        echo "💻 Terminal Mode: GUI tools not found"
    fi

    echo ""
}

handle_error() {
    local error_code=$1
    local error_message=$2
    local operation=$3
    local file=$4

    echo -e "Error (code $error_code) during $operation: $error_message" >&2 "\nFailed to process: $file" >&2 "\n."
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $operation failed for $file: $error_message" >> "${processing_log%.log}_errors.log"

    case "$operation" in
        "metadata_removal")
            echo "Attempting alternative method for metadata removal..."
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
    : # Running in terminal, continue normally
else
    # Not running in terminal (double-clicked from desktop/file manager)
    # Try GUI mode first, fall back to terminal if no GUI tools available

    if [ "$(check_gui_tools)" != "none" ]; then
        # GUI tools available - run in GUI mode
        if [ "$verbose" = "true" ]; then
            echo "DEBUG: Launching GUI mode"
        fi
        run_gui_mode
        exit $?
    else
        # No GUI tools - fall back to terminal launch
        if [ "$verbose" = "true" ]; then
            echo "DEBUG: No GUI tools found, launching terminal"
        fi

        # Properly escape arguments with spaces for terminal relaunch
        escaped_args=""
        for arg in "$@"; do
            escaped_args="$escaped_args $(printf '%q' "$arg")"
        done

        if [ "$verbose" = "true" ]; then
            echo "DEBUG: Relaunching in terminal with args: $escaped_args"
            echo "DEBUG: Current directory: $(pwd)"
        fi

        if [ -n "$XDG_CURRENT_DESKTOP" ]; then
            case "$XDG_CURRENT_DESKTOP" in
                GNOME|Unity)
                    gnome-terminal -- bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
                    xterm -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash"
                    ;;
                KDE)
                    konsole -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
                    xterm -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash"
                    ;;
                XFCE)
                    xfce4-terminal -e "bash -c \"cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash\"" || \
                    xterm -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash"
                    ;;
                *)
                    x-terminal-emulator -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
                    gnome-terminal -- bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
                    konsole -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
                    xterm -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
                    open -a Terminal -n --args bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
                    echo "Unable to open terminal"
                    ;;
            esac
        elif [ "$(uname)" = "Darwin" ]; then
            # macOS
            open -a Terminal -n --args bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash"
        else # fallback
            x-terminal-emulator -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
            gnome-terminal -- bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
            konsole -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
            xterm -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash" || \
            echo "Unable to open terminal. Please run this script from a terminal or install zenity for GUI mode."
        fi
        exit 0
    fi
fi

clean_filename() {               # Dots with Spaces
    local file="$1"
    local dir
    local filename
    local extension
    local name
    local new_filename
    local new_path
    local changed=false

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: clean_filename input: '$file'"
    fi

    dir=$(dirname "$file")
    filename=$(basename "$file")
    extension="${filename##*.}"
    name="${filename%.*}"
    new_filename="$name"

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: dir='$dir', filename='$filename', extension='$extension', name='$name'"
    fi

    # Clean filename
    if [ "$clean_filenames" = true ]; then
        # Replace dots with spaces in the filename
        new_filename=$(echo "$new_filename" | sed 's/\./ /g')
        changed=true
    fi

    # Underscores with spaces
    if [ "$replace_underscores" = true ]; then
        new_filename=$(echo "$new_filename" | sed 's/_/ /g')
        changed=true
    fi

    # Capitalize filename
    if [ "$capitalize_filenames" = true ]; then
        new_filename=$(echo "$new_filename" | awk '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) tolower(substr($i,2)) }}1')
        changed=true
    fi

    # Handle special characters
    new_filename=$(echo "$new_filename" | sed 's/[^[:alnum:][:space:]._-]/_/g')

    # Add extension back
    new_filename="$new_filename.$extension"
    new_path="$dir/$new_filename"

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: new_filename='$new_filename', new_path='$new_path'"
    fi

    # Only rename if the filename actually changes
    if [ "$changed" = true ] && [ "$filename" != "$new_filename" ]; then
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would rename: $file -> $new_path"
            echo "$file"
            return 0
        else
            if mv "$file" "$new_path"; then
                echo "Renamed: $file -> $new_path"
                if [ "$verbose" = "true" ]; then
                    echo "DEBUG: clean_filename output: '$new_path'"
                fi
                echo "$new_path"
                return 0
            else
                echo "Failed to rename: $file"
                echo "$file"
                return 1
            fi
        fi
    fi

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: clean_filename output (unchanged): '$file'"
    fi
    echo "$file"
}

convert_with_handbrake_settings() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local dir
    local filename
    local extension
    local name
    local output_file
    local crop_params

    if [ "$use_handbrake_settings" = false ]; then
        return 1
    fi

    echo "Converting using HandBrake settings: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert with HandBrake settings: $file"
        return 0
    fi

    # Check if file exists before processing
    if [ ! -f "$file" ]; then
        echo "✗ Error: File not found: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi

    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    dir=$(dirname "$file")
    filename=$(basename "$file")
    extension="${filename##*.}"
    name="${filename%.*}"
    output_file="${dir}/${name}_converted.mkv"

    echo "DEBUG: Processing file: '$file'"
    echo "DEBUG: Output will be: '$output_file'"

    # Parse the file to determine crop values
    crop_params=""
    if command -v ffmpeg >/dev/null 2>&1; then
        # Auto-detect crop using ffmpeg cropdetect filter
        crop_params=$(ffmpeg -y -nostdin -ss 60 -i "$file" -t 1 -vf cropdetect -f null - 2>&1 | awk '/crop/ { print $NF }' | tail -1)
        if [ -z "$crop_params" ]; then
            # Default crop from HandBrake settings
            crop_params="crop=66:68:0:0"
        fi
    else
        # Default crop from HandBrake settings
        crop_params="crop=66:68:0:0"
    fi

    # Use ffmpeg with settings similar to HandBrake preset
    if ffmpeg -y -nostdin -i "$file" \
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
        log_processed_file "$output_file" "handbrake_conversion" "mkv"
        return 0
    else
        echo "✗ Failed to convert with HandBrake settings: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

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
    # Debug output to help troubleshoot counter issues
    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Stats counters at display time:"
        echo "  files_processed=$files_processed"
        echo "  files_failed=$files_failed"
        echo "  files_skipped=$files_skipped"
        echo "  thumbnails_removed=$thumbnails_removed"
        echo "  metadata_files_removed=$metadata_files_removed"
    fi

    echo -e "========== Processing Statistics =========="
    echo "Files processed successfully: $files_processed"
    echo "Files failed: $files_failed"
    echo "Files skipped (already processed): $files_skipped"
    echo "Thumbnails removed: $thumbnails_removed"
    echo "Metadata files (.nfo) removed: $metadata_files_removed"
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
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s https://github.com/X-Seti/stripmeta/main/version.txt)
        if [ -n "$latest_version" ] && [ "$latest_version" != "$SCRIPT_VERSION" ]; then
            echo -e "A new version ($latest_version) is available! Current version\n $SCRIPT_VERSION\nVisit https://github.com/X-Seti/stripmeta to update"
        else
            echo "You are running the latest version: $SCRIPT_VERSION"
        fi
    else
        echo "curl not found, cannot check for updates"
    fi
}

check_gui_tools() {
    if command -v zenity >/dev/null 2>&1; then
        echo "zenity"
    elif command -v kdialog >/dev/null 2>&1; then
        echo "kdialog"
    elif command -v yad >/dev/null 2>&1; then
        echo "yad"
    else
        echo "none"
    fi
}

show_gui_error() {
    local message="$1"
    local gui_tool=$(check_gui_tools)

    case "$gui_tool" in
        zenity)
            zenity --error --text="$message" --width=400
            ;;
        kdialog)
            kdialog --error "$message"
            ;;
        yad)
            yad --error --text="$message" --width=400
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
            zenity --info --text="$message" --width=500
            ;;
        kdialog)
            kdialog --msgbox "$message"
            ;;
        yad)
            yad --info --text="$message" --width=500
            ;;
        *)
            echo "INFO: $message"
            ;;
    esac
}

show_gui_progress() {
    local title="$1"
    local text="$2"
    local gui_tool=$(check_gui_tools)

    case "$gui_tool" in
        zenity)
            zenity --progress --title="$title" --text="$text" --width=400 --auto-close
            ;;
        kdialog)
            kdialog --progressbar "$text" 100
            ;;
        yad)
            yad --progress --title="$title" --text="$text" --width=400 --auto-close
            ;;
    esac
}

show_gui_progress_advanced() {
    local title="$1"
    local total_files="$2"
    local log_file="$3"
    local gui_tool=$(check_gui_tools)

    case "$gui_tool" in
        zenity)
            (
                echo "0"
                echo "# Initializing processing..."

                local current=0
                while [ $current -lt $total_files ]; do
                    if [ -f "$log_file.progress" ]; then
                        current=$(cat "$log_file.progress" 2>/dev/null || echo $current)
                        local percent=$((current * 100 / total_files))
                        local current_file=$(tail -n1 "$log_file.current" 2>/dev/null || echo "Processing...")
                        echo "$percent"
                        echo "# [$current/$total_files] $current_file"
                        sleep 0.5
                    else
                        sleep 1
                    fi
                done

                echo "100"
                echo "# Processing complete!"
            ) | zenity --progress --title="$title" --width=600 --height=200 --auto-close
            ;;
        yad)
            (
                echo "0"
                echo "# Initializing processing..."

                local current=0
                while [ $current -lt $total_files ]; do
                    if [ -f "$log_file.progress" ]; then
                        current=$(cat "$log_file.progress" 2>/dev/null || echo $current)
                        local percent=$((current * 100 / total_files))
                        local current_file=$(tail -n1 "$log_file.current" 2>/dev/null || echo "Processing...")
                        echo "$percent"
                        echo "# [$current/$total_files] $current_file"
                        sleep 0.5
                    else
                        sleep 1
                    fi
                done

                echo "100"
                echo "# Processing complete!"
            ) | yad --progress --title="$title" --width=600 --height=200 --auto-close
            ;;
        *)
            echo "Processing $total_files files..."
            ;;
    esac
}

scan_directory_for_preview() {
    local target="$1"
    local video_count=0
    local audio_count=0
    local total_size=0
    local temp_scan="/tmp/stripmeta_scan.$"

    echo "Scanning directory..." > "$temp_scan.status"

    if [ -d "$target" ]; then
        # Count video files
        video_count=$(find "$target" ${recursive:+-o -path "$target"} -type f \( \
            -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.m4v" -o \
            -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.flv" -o -iname "*.mov" -o \
            -iname "*.webm" -o -iname "*.3gp" -o -iname "*.wmv" -o -iname "*.ts" \
        \) | wc -l)

        # Count audio files
        audio_count=$(find "$target" ${recursive:+-o -path "$target"} -type f \( \
            -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o \
            -iname "*.aac" -o -iname "*.m4a" -o -iname "*.wma" -o -iname "*.opus" \
        \) | wc -l)

        # Calculate total size (in MB)
        total_size=$(find "$target" ${recursive:+-o -path "$target"} -type f \( \
            -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp3" -o \
            -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.aac" \
        \) -exec du -bc {} + 2>/dev/null | tail -1 | cut -f1)
    elif [ -f "$target" ]; then
        case "${target,,}" in
            *.mp4|*.mkv|*.avi|*.m4v|*.mpg|*.mpeg|*.flv|*.mov|*.webm|*.3gp|*.wmv|*.ts)
                video_count=1
                ;;
            *.mp3|*.flac|*.wav|*.ogg|*.aac|*.m4a|*.wma|*.opus)
                audio_count=1
                ;;
        esac
        total_size=$(stat -c%s "$target" 2>/dev/null || echo 0)
    fi

    echo "$video_count|$audio_count|$total_size" > "$temp_scan.result"
    rm -f "$temp_scan.status"
}

run_gui_mode() {
    local gui_tool=$(check_gui_tools)

    if [ "$gui_tool" = "none" ]; then
        echo "No GUI tools available. Install zenity, kdialog, or yad for GUI mode."
        return 1
    fi

    # Welcome dialog
    case "$gui_tool" in
        zenity)
            if ! zenity --question --title="StripMeta GUI File Processor" \
                --text="Welcome to StripMeta GUI v$SCRIPT_VERSION (X-Seti) \n\n🎨 Advanced Media File Processor with Graphical Interface\n\nCapabilities:\n• Remove metadata from 25+ video and 15+ audio formats\n• Clean filenames (dots/underscores to spaces)\n• Convert between audio/video formats\n• Remove .nfo files and thumbnails\n• Create backups of original files\n• Real-time progress tracking\n\nWould you like to continue?" \
                --width=550 --height=250; then
                exit 0
            fi
            ;;
        kdialog)
            if ! kdialog --title="StripMeta GUI File Processor" --yesno "Welcome to StripMeta GUI v$SCRIPT_VERSION (X-Seti) \n\nAdvanced Media File Processor\n\nWould you like to continue?"; then
                exit 0
            fi
            ;;
        yad)
            if ! yad --question --title="StripMeta GUI File Processor" \
                --text="Welcome to StripMeta GUI v$SCRIPT_VERSION (X-Seti) \n\n🎨 Advanced Media File Processor\n\nWould you like to continue?" \
                --width=550 --height=200; then
                exit 0
            fi
            ;;
    esac

    # Main configuration dialog
    local config_result=""
    case "$gui_tool" in
        zenity)
            config_result=$(zenity --forms --title="StripMeta Configuration" \
                --text="Configure your processing options:" \
                --add-entry="Source Path:" \
                --add-combo="Source Type:" --combo-values="Directory|Files" \
                --add-combo="Recursive Processing:" --combo-values="No|Yes" \
                --add-combo="Clean Filenames:" --combo-values="No|Replace dots|Replace underscores|Both" \
                --add-combo="Video Processing:" --combo-values="Metadata only|Convert old to MP4|HandBrake compression" \
                --add-combo="Audio Conversion:" --combo-values="No|Yes" \
                --add-combo="Audio Format:" --combo-values="mp3|flac|ogg|wav|aac|m4a|wma|opus" \
                --add-combo="Create Backups:" --combo-values="No|Yes" \
                --add-combo="Remove Metadata Files:" --combo-values="No|Yes" \
                --add-entry="Backup Directory:" \
                --separator="|" --width=600 --height=400)
            ;;
        yad)
            config_result=$(yad --form --title="StripMeta Configuration" \
                --text="Configure your processing options:" \
                --field="Source Path:DIR" "$(pwd)" \
                --field="Source Type:CB" "Directory!Files" \
                --field="Recursive Processing:CHK" FALSE \
                --field="Clean Filenames - Replace dots:CHK" FALSE \
                --field="Clean Filenames - Replace underscores:CHK" FALSE \
                --field="Capitalize Filenames:CHK" FALSE \
                --field="Audio Conversion:CHK" FALSE \
                --field="Audio Format:CB" "mp3!flac!ogg!wav!aac!m4a!wma!opus" \
                --field="Convert Old Video Formats:CHK" FALSE \
                --field="Use HandBrake Compression:CHK" FALSE \
                --field="Create Backups:CHK" TRUE \
                --field="Remove Metadata Files:CHK" FALSE \
                --field="Backup Directory:DIR" "./backups" \
                --separator="|" --width=600 --height=500)
            ;;
        kdialog)
            # Simplified configuration for kdialog
            local source_path=$(kdialog --getexistingdirectory "$(pwd)" --title "Select Source Directory")
            if [ -z "$source_path" ]; then
                exit 0
            fi

            local do_backups="false"
            if kdialog --yesno "Create backup copies of files?"; then
                do_backups="true"
            fi

            local do_recursive="false"
            if kdialog --yesno "Process subdirectories recursively?"; then
                do_recursive="true"
            fi

            local clean_files="false"
            if kdialog --yesno "Clean filenames (replace dots with spaces)?"; then
                clean_files="true"
            fi

            # Set variables directly for kdialog
            target="$source_path"
            backups=$do_backups
            recursive=$do_recursive
            clean_filenames=$clean_files
            ;;
    esac

    if [ -z "$config_result" ] && [ "$gui_tool" != "kdialog" ]; then
        show_gui_info "Configuration cancelled."
        exit 0
    fi

    # Parse configuration results
    if [ "$gui_tool" = "zenity" ]; then
        IFS='|' read -r source_path source_type recursive_choice filename_choice video_choice audio_conv audio_fmt backup_choice metadata_choice backup_dir <<< "$config_result"

        target="$source_path"
        [ "$recursive_choice" = "Yes" ] && recursive=true
        [ "$backup_choice" = "Yes" ] && backups=true
        [ "$metadata_choice" = "Yes" ] && rm_metadata_files=true
        [ "$audio_conv" = "Yes" ] && audio_output_format="$audio_fmt"

        case "$filename_choice" in
            *"dots"*) clean_filenames=true ;;
            *"underscores"*) replace_underscores=true ;;
            *"Both"*) clean_filenames=true; replace_underscores=true ;;
        esac

        case "$video_choice" in
            *"MP4"*) conv_oldfileformats=true; convert_to_mp4=true ;;
            *"HandBrake"*) use_handbrake_settings=true ;;
        esac

        backup_dir="$backup_dir"

    elif [ "$gui_tool" = "yad" ]; then
        IFS='|' read -r source_path source_type recursive_proc clean_dots clean_underscores capitalize audio_conv audio_fmt convert_old handbrake_comp create_backups remove_meta backup_dir_path <<< "$config_result"

        target="$source_path"
        [ "$recursive_proc" = "TRUE" ] && recursive=true
        [ "$clean_dots" = "TRUE" ] && clean_filenames=true
        [ "$clean_underscores" = "TRUE" ] && replace_underscores=true
        [ "$capitalize" = "TRUE" ] && capitalize_filenames=true
        [ "$audio_conv" = "TRUE" ] && audio_output_format="$audio_fmt"
        [ "$convert_old" = "TRUE" ] && conv_oldfileformats=true && convert_to_mp4=true
        [ "$handbrake_comp" = "TRUE" ] && use_handbrake_settings=true
        [ "$create_backups" = "TRUE" ] && backups=true
        [ "$remove_meta" = "TRUE" ] && rm_metadata_files=true
        backup_dir="$backup_dir_path"
    fi

    # If no source selected, prompt for file/directory selection
    if [ -z "$target" ] || [ ! -e "$target" ]; then
        case "$gui_tool" in
            zenity)
                target=$(zenity --file-selection --title="Select files or folder to process" --filename="$(pwd)/" --directory)
                ;;
            kdialog)
                target=$(kdialog --getexistingdirectory "$(pwd)" --title="Select directory to process")
                ;;
            yad)
                target=$(yad --file --directory --title="Select folder to process" --filename="$(pwd)/")
                ;;
        esac

        if [ -z "$target" ]; then
            show_gui_info "No source selected. Exiting."
            exit 0
        fi
    fi

    # Preview/scan phase
    local temp_scan="/tmp/stripmeta_scan.$"

    # Show scanning dialog
    case "$gui_tool" in
        zenity)
            (
                echo "25"; echo "# Scanning directory structure..."
                sleep 1
                scan_directory_for_preview "$target" &
                local scan_pid=$!

                while kill -0 $scan_pid 2>/dev/null; do
                    echo "50"; echo "# Analyzing files..."
                    sleep 1
                done

                echo "100"; echo "# Scan complete!"
                sleep 1
            ) | zenity --progress --title="Scanning Files" --width=400 --auto-close
            ;;
        yad)
            (
                echo "25"; echo "# Scanning directory structure..."
                sleep 1
                scan_directory_for_preview "$target" &
                local scan_pid=$!

                while kill -0 $scan_pid 2>/dev/null; do
                    echo "50"; echo "# Analyzing files..."
                    sleep 1
                done

                echo "100"; echo "# Scan complete!"
                sleep 1
            ) | yad --progress --title="Scanning Files" --width=400 --auto-close
            ;;
        *)
            scan_directory_for_preview "$target"
            ;;
    esac

    # Read scan results
    if [ -f "$temp_scan.result" ]; then
        IFS='|' read -r video_count audio_count total_size < "$temp_scan.result"
        rm -f "$temp_scan.result"
    else
        video_count=0
        audio_count=0
        total_size=0
    fi

    # Format file size
    local size_formatted
    if [[ "$total_size" =~ ^[0-9]+$ ]]; then
        if [ "$total_size" -gt 1073741824 ]; then
        size_formatted="$((total_size / 1073741824)) GB"
        elif [ "$total_size" -gt 1048576 ]; then
        size_formatted="$((total_size / 1048576)) MB"
        else
        size_formatted="$((total_size / 1024)) KB"
        fi
    else
        size_formatted="Unknown size"
    fi

    # Estimate processing time (rough calculation)
    local total_files=$((video_count + audio_count))
    local estimated_minutes=$((total_files / 10 + 1))

    # Preview and confirmation dialog
    local preview_text="Files found: $video_count video, $audio_count audio\n"
    preview_text+="Total size: $size_formatted\n"
    preview_text+="Estimated time: ~$estimated_minutes minutes\n\n"
    preview_text+="Settings:\n"
    [ "$clean_filenames" = "true" ] && preview_text+="• Clean filenames: Replace dots\n"
    [ "$replace_underscores" = "true" ] && preview_text+="• Clean filenames: Replace underscores\n"
    [ "$backups" = "true" ] && preview_text+="• Create backups: Yes\n"
    [ "$recursive" = "true" ] && preview_text+="• Recursive: Yes\n"
    [ "$rm_metadata_files" = "true" ] && preview_text+="• Remove metadata files: Yes\n"
    [ "$conv_oldfileformats" = "true" ] && preview_text+="• Convert old formats to MP4: Yes\n"
    [ "$use_handbrake_settings" = "true" ] && preview_text+="• HandBrake compression: Yes\n"
    [ -n "$audio_output_format" ] && [ "$audio_output_format" != "mp3" ] && preview_text+="• Audio format: $audio_output_format\n"
    preview_text+="\nProceed with processing?"

    case "$gui_tool" in
        zenity)
            if ! zenity --question --title="Confirm Processing" --text="$preview_text" --width=500 --height=300; then
                exit 0
            fi
            ;;
        kdialog)
            if ! kdialog --yesno "$preview_text"; then
                exit 0
            fi
            ;;
        yad)
            if ! yad --question --title="Confirm Processing" --text="$preview_text" --width=500 --height=300; then
                exit 0
            fi
            ;;
    esac

    # Processing phase with advanced progress
    local progress_log="/tmp/stripmeta_progress.$"
    echo "0" > "$progress_log.progress"
    echo "Starting..." > "$progress_log.current"

    # Start progress dialog in background
    show_gui_progress_advanced "Processing Files" "$total_files" "$progress_log" &
    local progress_pid=$!

    # Process files and update progress
    local current_count=0

    if [ -f "$target" ]; then
        echo "Processing: $(basename "$target")" > "$progress_log.current"
        process_single_file "$target"
        current_count=1
        echo "$current_count" > "$progress_log.progress"
    elif [ -d "$target" ]; then
        # Custom file processing with progress updates
        if [ "$recursive" = false ]; then
            while IFS= read -r -d '' file; do
                echo "Processing: $(basename "$file")" > "$progress_log.current"
                process_single_file "$file"
                current_count=$((current_count + 1))
                echo "$current_count" > "$progress_log.progress"
            done < <(find "$target" -maxdepth 1 -type f \( \
                -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp3" -o \
                -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.aac" \
            \) -print0)
        else
            while IFS= read -r -d '' file; do
                echo "Processing: $(basename "$file")" > "$progress_log.current"
                process_single_file "$file"
                current_count=$((current_count + 1))
                echo "$current_count" > "$progress_log.progress"
            done < <(find "$target" -type f \( \
                -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp3" -o \
                -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.aac" \
            \) -print0)
        fi
    fi

    # Wait for progress dialog to complete
    wait $progress_pid 2>/dev/null

    # Clean up progress files
    rm -f "$progress_log.progress" "$progress_log.current"

    # Show results dialog
    local results_text="Processing Complete!\n\n"
    results_text+="Files processed successfully: $files_processed\n"
    results_text+="Files failed: $files_failed\n"
    results_text+="Files skipped (already processed): $files_skipped\n"
    results_text+="Thumbnails removed: $thumbnails_removed\n"
    results_text+="Metadata files (.nfo) removed: $metadata_files_removed\n\n"
    results_text+="Files by type:\n"
    [ "$video_files_processed" -gt 0 ] && results_text+="Video files: $video_files_processed\n"
    [ "$audio_files_processed" -gt 0 ] && results_text+="Audio files: $audio_files_processed\n"
    [ "$other_files_processed" -gt 0 ] && results_text+="Other files: $other_files_processed\n"

    show_gui_info "$results_text"

    return 0
}

show_help() {
    cat << 'EOF'
StripMeta GUI - Media File Metadata Remover & Processor with Graphical Interface

USAGE:
    ./stripmeta-gui.sh [OPTIONS] [FILES/DIRECTORIES...]
    ./stripmeta-gui.sh [OPTIONS]                    # Interactive mode
    ./stripmeta-gui.sh --gui                        # GUI mode (default when double-clicked)

DESCRIPTION:
    Advanced media file processor with both GUI and command-line interfaces.
    Removes metadata, cleans filenames, converts formats, and organizes media collections.

    When double-clicked from desktop, automatically launches GUI mode if
    zenity, kdialog, or yad is available, otherwise opens in terminal.

SUPPORTED FORMATS:
    Video: mp4, mkv, avi, mpg, mpeg, m4v, flv, mov, webm, 3gp, wmv, ts, mts, m2ts, vob
    Audio: mp3, flac, wav, ogg, aac, m4a, wma, opus, amr, aiff, iff, 8svx, au
    Other: m3u (playlists)

GUI MODE FEATURES:
    ✓ Intuitive graphical interface with organized options
    ✓ Directory scanning with file preview and size estimation
    ✓ Real-time progress tracking with activity log
    ✓ Comprehensive results summary with statistics
    ✓ Cross-platform support (GNOME, KDE, XFCE)

COMMAND LINE OPTIONS:
    -h, --help                      Show this help message
    --gui                           Force GUI mode (requires zenity/kdialog/yad)
    --version                       Display script version and dependency status
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
    --audio-format FORMAT           Audio output: mp3, flac, ogg, wav, aac, m4a, wma, opus
    --conv-oldfileformats           Convert AVI/MPG/FLV/MOV to MP4
    --handbrake                     Use HandBrake-style video compression

PERFORMANCE:
    --parallel                      Enable parallel processing (experimental)
    --max-jobs N                    Max parallel jobs (default: 4)

LOGGING:
    --reset-log                     Clear the processing log file

DEPENDENCIES:
    Required: exiftool, mkvpropedit, sha256sum, ffmpeg
    GUI Mode: zenity (GNOME) OR kdialog (KDE) OR yad (advanced)
    Optional: curl (updates), numfmt (formatting), ionice (performance)

INSTALLATION:
    Ubuntu/Debian: sudo apt install exiftool mkvtoolnix-cli coreutils ffmpeg zenity
    Arch Linux: sudo pacman -S perl-image-exiftool mkvtoolnix-cli coreutils ffmpeg zenity
    Fedora: sudo dnf install perl-Image-ExifTool mkvtoolnix coreutils ffmpeg zenity

EXAMPLES:
    # GUI mode (automatic when double-clicked)
    ./stripmeta-gui.sh --gui

    # Interactive terminal mode
    ./stripmeta-gui.sh

    # Process specific files
    ./stripmeta-gui.sh "Movie File.mkv" "Song.mp3"

    # Process directory recursively with backups
    ./stripmeta-gui.sh --recursive --backups "/path/to/media"

    # Clean filenames and remove metadata files
    ./stripmeta-gui.sh --clean-filenames --remove-metadata-files

    # Convert audio to FLAC with HandBrake video compression
    ./stripmeta-gui.sh --audio-format flac --handbrake

    # Preview mode to see what would happen
    ./stripmeta-gui.sh --dry-run --verbose "/media/folder"

CONFIGURATION:
    Settings can be saved to ~/.stripmeta-config for automatic loading.
    Use the interactive mode to configure and save your preferences.

LOGS:
    Processing log: .processed_files.log
    Error log: .processed_files_errors.log

PROJECT:
    StripMeta GUI v2.0.0 - Advanced Media File Processor
    For updates and documentation: https://github.com/X-Seti/stripmeta
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

PLAYLIST FORMATS:
    m3u (basic playlist support)

OUTPUT FORMATS:
    Video: mp4 (H.264), mkv (H.265 with HandBrake)
    Audio: mp3, flac, ogg, wav, aac, m4a

METADATA REMOVAL:
    - EXIF data from media files
    - Title, artist, album info from audio
    - Creation dates and device info
    - GPS coordinates and camera settings
    - Associated .nfo files and thumbnails
EOF
}


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
        # Source the configuration file
        # shellcheck source=/dev/null
        source "$config_file"
        echo "Configuration loaded successfully."
        return 0
    else
        echo "Failed to load configuration."
        return 1
    fi
}

save_config() {
    local config_file="$HOME/.stripmeta-config"
    echo "# StripMeta configuration file" > "$config_file"
    echo "# Generated on $(date)" >> "$config_file"
    echo "clean_filenames=$clean_filenames" >> "$config_file"
    echo "replace_underscores=$replace_underscores" >> "$config_file"
    echo "capitalize_filenames=$capitalize_filenames" >> "$config_file"
    echo "renameext=$renameext" >> "$config_file"
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

    if [ ! -f "$file" ]; then
        echo "Error: Output file not found: $file"
        return 1
    fi

    local new_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
    if [ "$new_size" -eq 0 ]; then
        echo "Error: Output file is empty: $file"
        return 1
    fi

    if [[ "$file" =~ \.(mp4|mp3|mkv|m4v|flv|mov|avi|wav|ogg|flac)$ ]]; then
        if ! ffmpeg -y -nostdin -v error -i "$file" -f null - >/dev/null 2>&1; then
            echo "Error: Output file fails integrity check: $file"
            return 1
        fi
    fi

    return 0
}

verify_metadata_removal() {
    local file="$1"
    local file_type="$2"

    if [ "$verbose" = "true" ]; then
        echo -n "Verifying metadata removal for $file... "
    fi

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

detect_file_content_type() {
    local file="$1"
    local file_output

    if command -v file >/dev/null 2>&1; then
        file_output=$(file -b --mime-type "$file")
        echo "$file_output"
    else
        detect_file_type "$file"
    fi
}

cleanup_directory_metadata() {
    local dir="$1"
    local count_file
    local nfo_count=0
    local thumb_count=0

    if [ "$rm_metadata_files" = false ]; then
        return 0
    fi

    echo "Cleaning metadata files in directory: $dir"

    # Count and remove NFO files
    while IFS= read -r -d '' nfo_file; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove NFO file: $nfo_file"
        else
            rm "$nfo_file"
            echo "Removed NFO file: $nfo_file"
            nfo_count=$((nfo_count + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -name "*.nfo" -type f -print0)

    # Count and remove thumbnail files
    while IFS= read -r -d '' thumb_file; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove thumbnail: $thumb_file"
        else
            rm "$thumb_file"
            echo "Removed thumbnail: $thumb_file"
            thumb_count=$((thumb_count + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -name "*thumb.jpg" -type f -print0)

    # Count and remove potential thumbnails
    while IFS= read -r -d '' jpg_file; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove potential thumbnail: $jpg_file"
        else
            rm "$jpg_file"
            echo "Removed potential thumbnail: $jpg_file"
            thumb_count=$((thumb_count + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -name "*.jpg" -type f -size -100k -print0)

    # Update global counters
    metadata_files_removed=$((metadata_files_removed + nfo_count))
    thumbnails_removed=$((thumbnails_removed + thumb_count))
}

remove_assoc_metadata_files() {
    local file="$1"
    local dir
    local filename
    local base_filename
    local nfo_count=0
    local thumb_count=0

    dir=$(dirname "$file")
    filename=$(basename "$file" .*)
    base_filename=$(echo "$filename" | sed 's/\.[^.]*$//')

    # If flag is not set, return
    if [ "$rm_metadata_files" = false ]; then
        return 0
    fi

    # Remove exact filename NFO files
    while IFS= read -r -d '' nfo; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove NFO file: $nfo"
        else
            rm "$nfo"
            echo "Removed NFO file: $nfo"
            nfo_count=$((nfo_count + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -name "${filename}.nfo" -type f -print0)

    # Remove base filename NFO files
    while IFS= read -r -d '' nfo; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove NFO file: $nfo"
        else
            rm "$nfo"
            echo "Removed NFO file: $nfo"
            nfo_count=$((nfo_count + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -name "${base_filename}.nfo" -type f -print0)

    # Remove thumbnail files
    while IFS= read -r -d '' thumb; do
        if [ "$dry_run" = "true" ]; then
            echo "[DRY RUN] Would remove thumbnail: $thumb"
        else
            rm "$thumb"
            echo "Removed thumbnail: $thumb"
            thumb_count=$((thumb_count + 1))
        fi
    done < <(find "$dir" -maxdepth 1 \( -name "${filename}-thumb.jpg" -o -name "${filename}.jpg" -o -name "${base_filename}*.jpg" -o -name "thumb.jpg" \) -type f -print0)

    # Update global counters
    metadata_files_removed=$((metadata_files_removed + nfo_count))
    thumbnails_removed=$((thumbnails_removed + thumb_count))

    return 0
}

convert_to_mp4() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local output_file
    local temp_output_file

    if [ "$convert_to_mp4" = false ]; then
        return 1
    fi

    echo "Converting to MP4: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert to MP4: $file"
        return 0
    fi

    # Check if file exists before processing
    if [ ! -f "$file" ]; then
        echo "✗ Error: File not found: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi

    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    output_file="${file%.*}.mp4"
    temp_output_file="${file%.*}_converted.mp4"

    if ffmpeg -y -nostdin -i "$file" -c:v libx264 -c:a aac -strict experimental "$temp_output_file"; then
        rm "$file"
        mv "$temp_output_file" "$output_file"
        echo "✓ Converted to MP4: $output_file"
        log_processed_file "$output_file" "processed" "mp4"
        return 0
    else
        echo "✗ Failed to convert to MP4: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

detect_file_type() {
    local file="$1"
    local ext="${file##*.}"
    echo "${ext,,}"  # Convert to lowercase
}

backup_file() {
    local file="$1"
    if [ "$backups" = "true" ]; then
        local backup_dir="${2:-./backups}"
        mkdir -p "$backup_dir"
        local filename
        filename=$(basename "$file")
        cp -p "$file" "$backup_dir/$filename"
        if [ "$verbose" = "true" ]; then
            echo "Backed up: $file -> $backup_dir/$filename"
        fi
        return 0
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
        echo "Error: File does not exist: $file" >&2
        return 1
    fi

    [ -f "$processing_log" ] || touch "$processing_log"
    file_hash=$(sha256sum "$file" | awk '{print $1}')
    grep -q "$file_hash" "$processing_log"
}

log_processed_file() {
    local file="$1"
    local operation="${2:-processed}"
    local file_type="${3:-unknown}"
    local size
    local file_hash
    local abs_path
    local timestamp

    if [ -z "$file" ]; then
        echo "Error: Empty filename passed to log_processed_file()" >&2
        return 1
    fi

    if [ ! -f "$file" ]; then
        echo "Error: File does not exist: $file" >&2
        return 1
    fi

    [ -f "$processing_log" ] || touch "$processing_log"

    # Get file info
    file_hash=$(sha256sum "$file" | awk '{print $1}')
    abs_path=$(readlink -f "$file")
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    size=$(du -h "$file" | cut -f1)

    # Log to file
    echo "$timestamp | $file_hash | $operation | $size | $file_type | $abs_path" >> "$processing_log"

    # Debug output
    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Logging file: $file (type: $file_type)"
    fi

    # Increment counters - ONLY HERE, not in individual functions
    files_processed=$((files_processed+1))
    bytes_processed=$((bytes_processed+$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")))

    # Increment type-specific counters
    case "$file_type" in
        mp4)
            mp4_files_processed=$((mp4_files_processed+1))
            video_files_processed=$((video_files_processed+1))
            ;;
        mkv)
            mkv_files_processed=$((mkv_files_processed+1))
            video_files_processed=$((video_files_processed+1))
            ;;
        mp3)
            mp3_files_processed=$((mp3_files_processed+1))
            audio_files_processed=$((audio_files_processed+1))
            ;;
        flac)
            flac_files_processed=$((flac_files_processed+1))
            audio_files_processed=$((audio_files_processed+1))
            ;;
        aac|ogg|wav|m4a|iff|8svx|m3v|aud|wma|opus|amr|aiff|au|ra|dts|ac3|mka|oga)
            audio_files_processed=$((audio_files_processed+1))
            ;;
        avi|mpg|mpeg|flv|mov|m4v|webm|3gp|wmv|asf|rm|rmvb|ts|mts|m2ts|vob|ogv)
            video_files_processed=$((video_files_processed+1))
            ;;
        *)
            other_files_processed=$((other_files_processed+1))
            ;;
    esac

    # Debug output for counters
    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Current counters - processed: $files_processed, type: $file_type"
    fi

    rotate_logs
}

process_mp3() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    if is_file_processed "$file"; then
        echo "Skipping already processed MP3 file: $file"
        return 0
    fi

    file=$(clean_filename "$file")

    echo "Processing MP3: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process MP3: $file"
        return 0
    fi

    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    if exiftool -overwrite_original -All= "$file"; then
        echo "✓ Processed MP3 with exiftool: $file"
        log_processed_file "$file" "processed" "mp3"
        files_processed=$((files_processed + 1))
        return 0
    else
        echo "✗ Failed to process MP3 with exiftool: $file"
        files_failed=$((files_failed + 1))
        local temp_file="${file%.*}_stripped.mp3"
        if ffmpeg -i "$file" -c:a copy -map_metadata -1 "$temp_file"; then
            mv "$temp_file" "$file"
            echo "✓ Processed MP3 with ffmpeg: $file"
            log_processed_file "$file"
            return 0
        fi

        return 1
    fi
}

convert_audio() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local input_format="${3:-unknown}"
    local output_file
    local bitrate
    local audio_codec
    local temp_file

    if is_file_processed "$file"; then
        echo "Skipping already processed $input_format file: $file"
        return 0
    fi

    file=$(clean_filename "$file")

    echo "Processing $input_format: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would convert $input_format to $audio_output_format: $file"
        return 0
    fi

    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    output_file="${file%.*}.$audio_output_format"
    bitrate="${audio_bitrates[$audio_output_format]:-192k}"

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

    if [ "$input_format" = "$audio_output_format" ]; then
        echo "Input and output formats are the same. Just removing metadata..."
        if exiftool -overwrite_original -All= "$file"; then
            echo "✓ Removed metadata from $input_format file: $file"
            log_processed_file "$file"
            return 0
        else
            temp_file="${file%.*}_stripped.$input_format"
            if ffmpeg -i "$file" -c:a copy -map_metadata -1 "$temp_file"; then
                mv "$temp_file" "$file"
                echo "✓ Removed metadata with ffmpeg: $file"
                log_processed_file "$file"
                return 0
            fi
        fi
    fi

    if ffmpeg -i "$file" -vn -ar 44100 -ac 2 -c:a "$audio_codec" -b:a "$bitrate" -map_metadata -1 "$output_file"; then
        if [ "$backups" = "false" ]; then
            rm "$file"
        fi
        echo "✓ Converted $input_format to $audio_output_format: $output_file"
        log_processed_file "$output_file" "processed" "$audio_output_format"
        files_processed=$((files_processed + 1))
        return 0
    else
        echo "✗ Failed to convert $input_format to $audio_output_format: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

process_m3u() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    if is_file_processed "$file"; then
        echo "Skipping already processed M3U file: $file"
        return 0
    fi

    file=$(clean_filename "$file")

    echo "Processing M3U: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would clean M3U playlist: $file"
        return 0
    fi

    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    local temp_file="${file%.*}_cleaned.m3u"
    grep -v "^#" "$file" > "$temp_file"
    mv "$temp_file" "$file"
    echo "✓ Cleaned M3U playlist: $file"
    log_processed_file "$file" "playlist" "m3u"
    return 0
}

process_files() {
    local dir="${1:-.}"
    local file_count=0

    echo "DEBUG: Starting to process files in directory: $dir"
    cleanup_directory_metadata "$dir"

    # Use a more robust find approach with null delimiters for spaces
    if [ "$recursive" = false ]; then
        while IFS= read -r -d '' file; do
            file_count=$((file_count + 1))
            if [ "$verbose" = "true" ]; then
                echo "DEBUG: Found file #$file_count: $file"
            fi
            process_single_file "$file"
        done < <(find "$dir" -maxdepth 1 -type f \( \
            -iname "*.mp4" -o \
            -iname "*.mpg" -o \
            -iname "*.mpeg" -o \
            -iname "*.avi" -o \
            -iname "*.m4v" -o \
            -iname "*.mkv" -o \
            -iname "*.flv" -o \
            -iname "*.mov" -o \
            -iname "*.webm" -o \
            -iname "*.3gp" -o \
            -iname "*.wmv" -o \
            -iname "*.asf" -o \
            -iname "*.rm" -o \
            -iname "*.rmvb" -o \
            -iname "*.ts" -o \
            -iname "*.mts" -o \
            -iname "*.m2ts" -o \
            -iname "*.vob" -o \
            -iname "*.ogv" -o \
            -iname "*.mp3" -o \
            -iname "*.wav" -o \
            -iname "*.ogg" -o \
            -iname "*.iff" -o \
            -iname "*.8svx" -o \
            -iname "*.flac" -o \
            -iname "*.aac" -o \
            -iname "*.m4a" -o \
            -iname "*.wma" -o \
            -iname "*.opus" -o \
            -iname "*.amr" -o \
            -iname "*.aiff" -o \
            -iname "*.au" -o \
            -iname "*.ra" -o \
            -iname "*.dts" -o \
            -iname "*.ac3" -o \
            -iname "*.mka" -o \
            -iname "*.oga" -o \
            -iname "*.m3u" -o \
            -iname "*.m3v" -o \
            -iname "*.aud" \
        \) -print0)
    else
        while IFS= read -r -d '' file; do
            file_count=$((file_count + 1))
            if [ "$verbose" = "true" ]; then
                echo "DEBUG: Found file #$file_count: $file"
            fi
            process_single_file "$file"
        done < <(find "$dir" -type f \( \
            -iname "*.mp4" -o \
            -iname "*.mpg" -o \
            -iname "*.mpeg" -o \
            -iname "*.avi" -o \
            -iname "*.m4v" -o \
            -iname "*.mkv" -o \
            -iname "*.flv" -o \
            -iname "*.mov" -o \
            -iname "*.webm" -o \
            -iname "*.3gp" -o \
            -iname "*.wmv" -o \
            -iname "*.asf" -o \
            -iname "*.rm" -o \
            -iname "*.rmvb" -o \
            -iname "*.ts" -o \
            -iname "*.mts" -o \
            -iname "*.m2ts" -o \
            -iname "*.vob" -o \
            -iname "*.ogv" -o \
            -iname "*.mp3" -o \
            -iname "*.wav" -o \
            -iname "*.ogg" -o \
            -iname "*.iff" -o \
            -iname "*.8svx" -o \
            -iname "*.flac" -o \
            -iname "*.aac" -o \
            -iname "*.m4a" -o \
            -iname "*.wma" -o \
            -iname "*.opus" -o \
            -iname "*.amr" -o \
            -iname "*.aiff" -o \
            -iname "*.au" -o \
            -iname "*.ra" -o \
            -iname "*.dts" -o \
            -iname "*.ac3" -o \
            -iname "*.mka" -o \
            -iname "*.oga" -o \
            -iname "*.m3u" -o \
            -iname "*.m3v" -o \
            -iname "*.aud" \
        \) -print0)
    fi

    echo "DEBUG: Total files found and processed: $file_count"

    if [ "$recursive" = true ]; then
        while IFS= read -r -d '' subdir; do
            if [ "$verbose" = "true" ]; then
                echo "Processing subdirectory: $subdir"
            fi
            cleanup_directory_metadata "$subdir"
        done < <(find "$dir" -mindepth 1 -type d -print0)
    fi
}

# New helper function to process individual files
process_single_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Processing single file: '$file' (ext: $ext)"
    fi

    # Verify file exists before processing
    if [ ! -f "$file" ]; then
        echo "✗ ERROR: File not found during processing: '$file'"
        files_failed=$((files_failed + 1))
        return 1
    fi

    case "$ext" in
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
        m3u)
            process_m3u "$file" "$backup_dir"
            ;;
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
    esac
}

strip_metadata() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local file_type
    local new_name
    local temp_file

    if is_file_processed "$file"; then
        echo "Skipping already processed file: $file"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    file=$(clean_filename "$file")
    echo "Processing: $file"

    # Check if file exists before processing
    if [ ! -f "$file" ]; then
        echo "✗ Error: File not found: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi

    remove_assoc_metadata_files "$file"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would strip metadata from: $file"
        return 0
    fi

    backup_file "$file" "$backup_dir"
    file_type=$(detect_file_type "$file")

    if [ "$renameext" = "true" ]; then
        new_name="${file%.*}.$newfileext"
        mv "$file" "$new_name"
        file="$new_name"
        echo "Renamed to: $file"
    fi

    if [[ "$file_type" == "mpg" || "$file_type" == "mpeg" || "$file_type" == "mp4" || "$file_type" == "m4v" || "$file_type" == "flv" || "$file_type" == "mov" ]]; then
        if exiftool -overwrite_original -All= "$file"; then
            echo "✓ Processed with exiftool: $file"
            log_processed_file "$file" "processed" "$file_type"
            return 0
        fi
    fi

    if [[ "$file_type" == "avi" ]]; then
        temp_file="${file%.*}_stripped.avi"
        if ffmpeg -y -nostdin -i "$file" -codec copy -map_metadata -1 "$temp_file"; then
            mv "$temp_file" "$file"
            echo "✓ Processed AVI with ffmpeg: $file"
            log_processed_file "$file" "processed" "avi"
            return 0
        else
            echo "✗ Failed to process AVI with ffmpeg: $file"
            files_failed=$((files_failed + 1))
            return 1
        fi
    fi

    if [ "$file_type" = "mkv" ]; then
        process_mkv "$file" "$backup_dir"
        return $?
    fi

    echo "!! Unable to process file: $file"
    return 1
}

process_mkv() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local new_name

    if is_file_processed "$file"; then
        echo "Skipping already processed file: $file"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    file=$(clean_filename "$file")
    remove_assoc_metadata_files "$file"

    echo "Processing MKV: $file"
    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process MKV: $file"
        return 0
    fi

    if [ "$renameext" = "true" ]; then
        new_name="${file%.*}.$newfileext"
        mv "$file" "$new_name"
        file="$new_name"
        echo "Renamed to: $file"
    fi

    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    if mkvpropedit "$file" -d title; then
        echo "✓ Processed with mkvpropedit: $file"
        log_processed_file "$file" "processed" "mkv"
        return 0
    else
        echo "✗ Failed to process with mkvpropedit: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

set_drag_drop_defaults() {
    clean_filenames=true
    replace_underscores=true
    capitalize_filenames=false  # Set to false by default for drag and drop
    renameext=true
    backups=true
    rm_metadata_files=true
}

main() {
    local is_drag_drop=false

    # Check for drag and drop first
    if [ $# -gt 0 ]; then
        for path in "$@"; do
            if [ -e "$path" ]; then
                is_drag_drop=true
                break
            fi
        done
    fi

    if [ "$is_drag_drop" = true ]; then
        set_drag_drop_defaults
        echo "Drag and Drop Mode Activated"
    fi

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
                if [[ -n "$2" && "$2" =~ ^(mp3|flac|ogg|wav|aac|m4a|wma|opus)$ ]]; then
                    audio_output_format="$2"
                    shift 2
                else
                    echo "Error: Invalid audio format. Supported formats: mp3, flac, ogg, wav, aac, m4a, wma, opus"
                    exit 1
                fi
                ;;
            --version)
                echo "StripMeta GUI - Advanced Media File Processor"
                echo "Version: $SCRIPT_VERSION"
                echo ""
                echo "Capabilities:"
                echo "✓ Graphical User Interface (GUI Mode)"
                echo "✓ Command Line Interface (CLI Mode)"
                echo "✓ Interactive Terminal Mode"
                echo "✓ 25+ Video Formats • 15+ Audio Formats"
                echo "✓ Metadata Removal • Format Conversion"
                echo "✓ Filename Cleaning • Backup Support"
                echo ""
                check_dependencies
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
                renameext=true
                shift
                ;;
            --recursive)
                recursive=true
                shift
                ;;
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
                rm -f "$processing_log"
                echo "Processing log reset."
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    # If no command line arguments, start interactive mode
    if [ $# -eq 0 ]; then
        echo -e "==== StripMeta File Processor ====\nScript version: $SCRIPT_VERSION"

        # CHECK FOR CONFIG FILE FIRST
        if check_config; then
            echo -e "\nStripMeta config file found!"
            read -p "Do you want to use the saved configuration? [y/N]: " use_config
            if [[ "$use_config" =~ ^[Yy]$ ]]; then
                if load_conf; then
                    echo -e "\nConfiguration loaded successfully!"
                    echo -e "\n== Ready to Process =="
                    read -p "Process all video and audio files with loaded settings? (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        echo -e "\nStarting processing with config settings..."
                        cleanup_directory_metadata "."
                        process_files
                        show_stats
                        echo "Processing complete. Press Enter to exit..."
                        read
                        exit 0
                    else
                        echo "Operation cancelled - Press Enter to exit.."
                        read
                        exit 0
                    fi
                else
                    echo "Failed to load configuration. Continuing with interactive setup..."
                fi
            else
                echo "Continuing with interactive setup..."
            fi
        fi

        # ONLY REACH HERE IF NO CONFIG OR USER DECLINED CONFIG
        # Load last choices for defaults
        load_last_choices

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

        echo -e "\n== Audio Processing Options ==\nChoose audio output format:\n1) MP3 (default - widely compatible)\n2) FLAC (lossless compression)\n3) OGG (open source)\n4) WAV (uncompressed)\n5) AAC (modern lossy)\n6) M4A (iTunes compatible)\n7) WMA (Windows Media)\n8) Opus (modern low-bitrate)"
        read -p "Select format [1-8] (default: 1): " format_choice
        case "$format_choice" in
        2) audio_output_format="flac" ;;
        3) audio_output_format="ogg" ;;
        4) audio_output_format="wav" ;;
        5) audio_output_format="aac" ;;
        6) audio_output_format="m4a" ;;
        7) audio_output_format="wma" ;;
        8) audio_output_format="opus" ;;
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

        if [ "$convert_to_mp4" = false ]; then
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

        prompt_for_save_config
        echo -e "\n== Ready to Process =="
        read -p "Process all video and audio files, Continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled - Press Enter to exit.."
            read
            exit 0
        fi

        cleanup_directory_metadata "."
        process_files
        show_stats

    else
        # COMMAND LINE ARGUMENTS PROVIDED - PROCESS INDIVIDUAL FILES
        for path in "$@"; do
            if [ -f "$path" ]; then
                cleanup_directory_metadata "$(dirname "$path")"
                process_single_file "$path"
            elif [ -d "$path" ]; then
                cleanup_directory_metadata "$path"
                echo "Processing files in directory: $path"
                process_files "$path"
            else
                echo "Not a file or directory: $path"
            fi
        done
        show_stats
    fi

    echo "Processing complete. Press Enter to exit..."
    read
}

main "$@"
