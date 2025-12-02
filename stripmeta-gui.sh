#!/bin/bash
#Moocow Mooheda 16/Apr25 - Updated 25/May25
#StripMeta GUI - Media File Metadata Remover & Processor with Complete Graphical Interface
#Dependencies: "exiftool" "mkvpropedit" "sha256sum" "ffmpeg" "imagemagick"
#Optional: "zenity" "kdialog" "yad" "curl" "numfmt" "ionice"

#TODO: Add parallel processing support, batch operations

# Script version - date
SCRIPT_VERSION="2.1.0 - 25-05-25"

# Suppress GTK warnings for cleaner output
export GTK_DEBUG=""
export G_MESSAGES_DEBUG=""

# Create temporary directory for warning logs
mkdir -p /tmp/stripmeta_logs 2>/dev/null

# Cleanup function for temporary files
cleanup() {
    rm -f /tmp/zenity_warnings.log /tmp/yad_warnings.log 2>/dev/null
    rm -rf /tmp/stripmeta_logs 2>/dev/null
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Global variables
clean_filenames=false
dry_run=false
backups=false
verbose=false
rename_to_m4v=false
debug_mode=false
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
image_format="jpg"

# Check if debug mode should be enabled
if [ -n "$STRIPMETA_DEBUG" ] || [ -t 1 ]; then
    debug_mode=true
    verbose=true
fi
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

# Image format associations
declare -A image_formats=(
  ["jpg"]="jpeg"
  ["jpeg"]="jpeg"
  ["png"]="png"
  ["gif"]="gif"
  ["bmp"]="bmp"
  ["tiff"]="tiff"
  ["tif"]="tiff"
  ["webp"]="webp"
  ["tga"]="tga"
  ["dds"]="dds"
  ["dxt"]="dxt"
  ["pcx"]="pcx"
  ["psd"]="psd"
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
    local optional_deps=("zenity" "kdialog" "yad" "curl" "numfmt" "ionice" "convert" "identify")
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

        if [[ " ${missing_optional[*]} " =~ " convert " ]] || [[ " ${missing_optional[*]} " =~ " identify " ]]; then
            echo -e "🖼️  Image Processing: Install ImageMagick for image conversion"
            echo "   Ubuntu/Debian: sudo apt install imagemagick"
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

    # Show ImageMagick status
    if command -v convert >/dev/null 2>&1; then
        echo "🖼️  Image Processing: Available (ImageMagick)"
    else
        echo "🖼️  Image Processing: Not available (install imagemagick)"
    fi

    echo ""
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
            zenity --error --text="$message" --width=400 2>/dev/null
            ;;
        kdialog)
            kdialog --error "$message" 2>/dev/null
            ;;
        yad)
            yad --error --text="$message" --width=400 2>/dev/null
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
        *)
            echo "INFO: $message"
            ;;
    esac
}

gui_file_selection() {
    local gui_tool=$(check_gui_tools)
    local selection=""
    local selection_type=""

    case "$gui_tool" in
        zenity)
            # Ask user what they want to select
            selection_type=$(zenity --list --radiolist \
                --title="File Selection Type" \
                --text="What would you like to process?" \
                --column="Select" --column="Type" --column="Description" \
                TRUE "files" "Select individual files to process" \
                FALSE "directory" "Select a directory to process" \
                --width=500 --height=200 2>/dev/null)

            if [ "$?" -ne 0 ] || [ -z "$selection_type" ]; then
                return 1
            fi

            if [ "$selection_type" = "files" ]; then
                selection=$(zenity --file-selection --multiple --separator='|' \
                    --title="Select files to process" \
                    --file-filter="Media files|*.mp4 *.mkv *.avi *.mov *.mp3 *.flac *.wav *.jpg *.png *.gif *.bmp *.tiff *.tga *.dds *.dxt" \
                    --file-filter="All files|*" 2>/dev/null)
            else
                selection=$(zenity --file-selection --directory \
                    --title="Select directory to process" 2>/dev/null)
            fi
            ;;

        yad)
            # Ask user what they want to select
            selection_type=$(yad --list --radiolist \
                --title="File Selection Type" \
                --text="What would you like to process?" \
                --column="Select:RD" --column="Type" --column="Description" \
                TRUE "files" "Select individual files to process" \
                FALSE "directory" "Select a directory to process" \
                --width=500 --height=200 2>/dev/null)

            if [ "$?" -ne 0 ] || [ -z "$selection_type" ]; then
                return 1
            fi

            # Extract the selection type (yad returns the full line)
            selection_type=$(echo "$selection_type" | cut -d'|' -f2)

            if [ "$selection_type" = "files" ]; then
                selection=$(yad --file --multiple --separator='|' \
                    --title="Select files to process" \
                    --file-filter="Media files|*.mp4 *.mkv *.avi *.mov *.mp3 *.flac *.wav *.jpg *.png *.gif *.bmp *.tiff *.tga *.dds *.dxt" \
                    --file-filter="All files|*" 2>/dev/null)
            else
                selection=$(yad --file --directory \
                    --title="Select directory to process" 2>/dev/null)
            fi
            ;;

        kdialog)
            # KDE dialog - ask for selection type first
            if kdialog --yesno "Select files (Yes) or directory (No)?" 2>/dev/null; then
                selection=$(kdialog --getopenfilename "$(pwd)" "Media files (*.mp4 *.mkv *.avi *.mov *.mp3 *.flac *.wav *.jpg *.png)|All files (*)" 2>/dev/null)
                selection_type="files"
            else
                selection=$(kdialog --getexistingdirectory "$(pwd)" 2>/dev/null)
                selection_type="directory"
            fi
            ;;
        *)
            return 1
            ;;
    esac

    if [ -z "$selection" ]; then
        return 1
    fi

    # Validate that selected files/directories exist
    if [ "$selection_type" = "files" ]; then
        # Handle multiple files (split by |)
        IFS='|' read -ra FILE_ARRAY <<< "$selection"
        SELECTED_FILES=()

        for file in "${FILE_ARRAY[@]}"; do
            if [ -f "$file" ]; then
                SELECTED_FILES+=("$file")
            else
                echo "Warning: File not found: $file"
            fi
        done

        if [ ${#SELECTED_FILES[@]} -eq 0 ]; then
            show_gui_error "No valid files were selected or files could not be found."
            return 1
        fi

        SELECTION_TYPE="files"
    else
        if [ -d "$selection" ]; then
            SELECTED_FILES=("$selection")
            SELECTION_TYPE="directory"
        else
            show_gui_error "Selected directory does not exist: $selection"
            return 1
        fi
    fi

    return 0
}

gui_configuration_dialog() {
    local gui_tool=$(check_gui_tools)
    local config_result=""

    case "$gui_tool" in
        zenity)
            config_result=$(zenity --forms --title="StripMeta Configuration" \
                --text="Configure your processing options:" \
                --add-combo="Recursive Processing:" --combo-values="No|Yes" \
                --add-combo="Clean Filenames (replace dots):" --combo-values="No|Yes" \
                --add-combo="Replace Underscores:" --combo-values="No|Yes" \
                --add-combo="Capitalize Filenames:" --combo-values="No|Yes" \
                --add-combo="Rename Extensions to M4V:" --combo-values="No|Yes" \
                --add-combo="Video Processing:" --combo-values="Metadata only|Convert old to MP4|HandBrake compression" \
                --add-combo="Audio Conversion:" --combo-values="No|Yes" \
                --add-combo="Audio Format:" --combo-values="mp3|flac|ogg|wav|aac|m4a|wma|opus" \
                --add-combo="Image Processing:" --combo-values="No|Yes" \
                --add-combo="Image Format:" --combo-values="jpg|png|gif|bmp|tiff|webp" \
                --add-combo="Create Backups:" --combo-values="Yes|No" \
                --add-combo="Remove Metadata Files (.nfo):" --combo-values="No|Yes" \
                --add-entry="Backup Directory:" \
                --separator="|" --width=600 --height=500 2>/dev/null)
            ;;

        yad)
            config_result=$(yad --form --title="StripMeta Configuration" \
                --text="Configure your processing options:" \
                --field="Recursive Processing:CHK" FALSE \
                --field="Clean Filenames (replace dots):CHK" FALSE \
                --field="Replace Underscores:CHK" FALSE \
                --field="Capitalize Filenames:CHK" FALSE \
                --field="Rename Extensions to M4V:CHK" FALSE \
                --field="Audio Conversion:CHK" FALSE \
                --field="Audio Format:CB" "mp3!flac!ogg!wav!aac!m4a!wma!opus" \
                --field="Convert Old Video Formats:CHK" FALSE \
                --field="Use HandBrake Compression:CHK" FALSE \
                --field="Image Processing:CHK" FALSE \
                --field="Image Format:CB" "jpg!png!gif!bmp!tiff!webp" \
                --field="Create Backups:CHK" TRUE \
                --field="Remove Metadata Files:CHK" FALSE \
                --field="Backup Directory:DIR" "./backups" \
                --separator="|" --width=600 --height=600 2>/dev/null)
            ;;

        kdialog)
            # Simplified configuration for kdialog with individual dialogs
            if kdialog --yesno "Process subdirectories recursively?" 2>/dev/null; then
                recursive=true
            fi

            if kdialog --yesno "Clean filenames (replace dots with spaces)?" 2>/dev/null; then
                clean_filenames=true
            fi

            if kdialog --yesno "Replace underscores with spaces?" 2>/dev/null; then
                replace_underscores=true
            fi

            if kdialog --yesno "Rename video extensions to M4V?" 2>/dev/null; then
                rename_to_m4v=true
            fi

            if kdialog --yesno "Create backup copies of files?" 2>/dev/null; then
                backups=true
            fi

            if kdialog --yesno "Process images?" 2>/dev/null; then
                process_images=true
            fi

            return 0  # Skip parsing for kdialog
            ;;
    esac

    if [ -z "$config_result" ] && [ "$gui_tool" != "kdialog" ]; then
        return 1
    fi

    # Parse configuration results
    parse_config_result "$config_result" "$gui_tool"
    return 0
}

parse_config_result() {
    local config_result="$1"
    local gui_tool="$2"

    if [ "$gui_tool" = "zenity" ]; then
        IFS='|' read -r recursive_choice clean_choice underscore_choice capitalize_choice rename_choice \
                     video_choice audio_conv audio_fmt img_proc img_fmt backup_choice metadata_choice \
                     backup_dir_path <<< "$config_result"

        [ "$recursive_choice" = "Yes" ] && recursive=true
        [ "$clean_choice" = "Yes" ] && clean_filenames=true
        [ "$underscore_choice" = "Yes" ] && replace_underscores=true
        [ "$capitalize_choice" = "Yes" ] && capitalize_filenames=true
        [ "$rename_choice" = "Yes" ] && rename_to_m4v=true
        [ "$backup_choice" = "Yes" ] && backups=true
        [ "$metadata_choice" = "Yes" ] && rm_metadata_files=true
        [ "$audio_conv" = "Yes" ] && audio_output_format="$audio_fmt"
        [ "$img_proc" = "Yes" ] && process_images=true && image_format="$img_fmt"

        case "$video_choice" in
            *"MP4"*) conv_oldfileformats=true; convert_to_mp4=true ;;
            *"HandBrake"*) use_handbrake_settings=true ;;
        esac

        [ -n "$backup_dir_path" ] && backup_dir="$backup_dir_path"

    elif [ "$gui_tool" = "yad" ]; then
        IFS='|' read -r recursive_proc clean_dots clean_underscores capitalize_names rename_m4v \
                     audio_conv audio_fmt convert_old handbrake_comp img_proc img_fmt \
                     create_backups remove_meta backup_dir_path <<< "$config_result"

        [ "$recursive_proc" = "TRUE" ] && recursive=true
        [ "$clean_dots" = "TRUE" ] && clean_filenames=true
        [ "$clean_underscores" = "TRUE" ] && replace_underscores=true
        [ "$capitalize_names" = "TRUE" ] && capitalize_filenames=true
        [ "$rename_m4v" = "TRUE" ] && rename_to_m4v=true
        [ "$audio_conv" = "TRUE" ] && audio_output_format="$audio_fmt"
        [ "$convert_old" = "TRUE" ] && conv_oldfileformats=true && convert_to_mp4=true
        [ "$handbrake_comp" = "TRUE" ] && use_handbrake_settings=true
        [ "$img_proc" = "TRUE" ] && process_images=true && image_format="$img_fmt"
        [ "$create_backups" = "TRUE" ] && backups=true
        [ "$remove_meta" = "TRUE" ] && rm_metadata_files=true

        [ -n "$backup_dir_path" ] && backup_dir="$backup_dir_path"
    fi
}

gui_progress_window() {
    local title="$1"
    local total_files="$2"
    local gui_tool=$(check_gui_tools)

    [ "$debug_mode" = "true" ] && echo "DEBUG: Starting progress window for $total_files files"

    case "$gui_tool" in
        zenity)
            # Suppress GTK warnings for cleaner output
            exec 3> >(zenity --progress --title="$title" --text="Initializing..." \
                --width=600 --height=200 --auto-close --no-cancel 2>/dev/null)
            PROGRESS_FD=3
            [ "$debug_mode" = "true" ] && echo "DEBUG: Zenity progress started (GTK warnings suppressed)"
            ;;
        yad)
            # Suppress GTK warnings for cleaner output
            exec 3> >(yad --progress --title="$title" --text="Initializing..." \
                --width=600 --height=200 --auto-close --no-buttons 2>/dev/null)
            PROGRESS_FD=3
            [ "$debug_mode" = "true" ] && echo "DEBUG: YAD progress started (GTK warnings suppressed)"
            ;;
        kdialog)
            # KDialog approach (no GTK warnings)
            PROGRESS_PID=$(kdialog --progressbar "Processing files..." "$total_files" 2>/dev/null)
            qdbus $PROGRESS_PID showCancelButton false 2>/dev/null
            [ "$debug_mode" = "true" ] && echo "DEBUG: KDialog progress started with PID: $PROGRESS_PID"
            ;;
    esac

    return 0
}

update_progress() {
    local current="$1"
    local total="$2"
    local filename="$3"
    local gui_tool=$(check_gui_tools)

    local percent=$((current * 100 / total))

    # Always show progress in terminal
    echo "Processing file $current/$total ($percent%): $(basename "$filename")"

    [ "$debug_mode" = "true" ] && echo "DEBUG: Updating progress: $current/$total ($percent%) - $(basename "$filename")"

    case "$gui_tool" in
        zenity|yad)
            if [ -n "$PROGRESS_FD" ]; then
                echo "$percent" >&$PROGRESS_FD
                echo "# [$current/$total] Processing: $(basename "$filename")" >&$PROGRESS_FD
            fi
            ;;
        kdialog)
            if [ -n "$PROGRESS_PID" ]; then
                qdbus $PROGRESS_PID Set "" value $current 2>/dev/null
                qdbus $PROGRESS_PID setLabelText "[$current/$total] Processing: $(basename "$filename")" 2>/dev/null
            fi
            ;;
    esac
}

close_progress() {
    local gui_tool=$(check_gui_tools)

    [ "$debug_mode" = "true" ] && echo "DEBUG: Closing progress window"

    case "$gui_tool" in
        zenity|yad)
            if [ -n "$PROGRESS_FD" ]; then
                echo "100" >&$PROGRESS_FD
                echo "# Complete!" >&$PROGRESS_FD
                exec {PROGRESS_FD}>&-
            fi
            ;;
        kdialog)
            if [ -n "$PROGRESS_PID" ]; then
                qdbus $PROGRESS_PID close 2>/dev/null
            fi
            ;;
    esac
}

show_results_dialog() {
    local gui_tool=$(check_gui_tools)
    local results_text="Processing Complete!\n\n"
    results_text+="Files processed successfully: $files_processed\n"
    results_text+="Files failed: $files_failed\n"
    results_text+="Files skipped (already processed): $files_skipped\n"
    results_text+="Thumbnails removed: $thumbnails_removed\n"
    results_text+="Metadata files (.nfo) removed: $metadata_files_removed\n\n"
    results_text+="Files processed by type:\n"
    [ "$video_files_processed" -gt 0 ] && results_text+="Video files: $video_files_processed\n"
    [ "$audio_files_processed" -gt 0 ] && results_text+="Audio files: $audio_files_processed\n"
    [ "$image_files_processed" -gt 0 ] && results_text+="Image files: $image_files_processed\n"
    [ "$other_files_processed" -gt 0 ] && results_text+="Other files: $other_files_processed\n"

    show_gui_info "$results_text"
}

# Image processing functions
process_image() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    local input_format="${3:-unknown}"

    if ! command -v convert >/dev/null 2>&1; then
        echo "ImageMagick not installed, skipping image: $file"
        return 1
    fi

    if is_file_processed "$file"; then
        echo "Skipping already processed image: $file"
        files_skipped=$((files_skipped + 1))
        return 0
    fi

    file=$(clean_filename "$file")
    echo "Processing image: $file"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process image: $file"
        return 0
    fi

    if [ "$backups" = "true" ]; then
        backup_file "$file" "$backup_dir"
    fi

    # Remove metadata from image
    local temp_file="${file%.*}_processed.${image_format}"

    if convert "$file" -strip "$temp_file"; then
        if [ "$image_format" != "$input_format" ] || [ "$temp_file" != "$file" ]; then
            # Format conversion or different filename
            if [ "$backups" = "false" ]; then
                rm "$file"
            fi
            mv "$temp_file" "${file%.*}.${image_format}"
            file="${file%.*}.${image_format}"
        else
            # Same format, just replace original
            mv "$temp_file" "$file"
        fi

        echo "✓ Processed image: $file"
        log_processed_file "$file" "processed" "$image_format"
        image_files_processed=$((image_files_processed + 1))
        return 0
    else
        echo "✗ Failed to process image: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi
}

# Enhanced file detection for images
detect_file_type() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "${ext,,}")  # Convert to lowercase

    # Check if it's a known image format
    if [[ -n "${image_formats[$ext]}" ]]; then
        echo "$ext"
    else
        echo "$ext"
    fi
}

process_single_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    echo "=== Processing File: $(basename "$file") ==="
    echo "Original path: $file"
    echo "Extension: $ext"
    echo "M4V renaming enabled: $rename_to_m4v"
    echo "Clean filenames enabled: $clean_filenames"
    echo "Replace underscores enabled: $replace_underscores"

    if [ "$verbose" = "true" ] || [ "$debug_mode" = "true" ]; then
        echo "DEBUG: Processing single file: '$file' (ext: $ext)"
    fi

    # Verify file exists before processing
    if [ ! -f "$file" ]; then
        echo "✗ ERROR: File not found during processing: '$file'"
        files_failed=$((files_failed + 1))
        return 1
    fi

    # Image processing
    if [[ -n "${image_formats[$ext]}" ]] && [ "$process_images" = "true" ]; then
        echo "→ Processing as image file"
        process_image "$file" "$backup_dir" "$ext"
        return $?
    fi

    # Audio processing
    case "$ext" in
        mp3)
            echo "→ Processing as MP3 audio file"
            if [ "$audio_output_format" = "mp3" ]; then
                process_mp3 "$file" "$backup_dir"
            else
                convert_audio "$file" "$backup_dir" "mp3"
            fi
            ;;
        wav|ogg|flac|aac|m4a|iff|8svx|m3v|aud|wma|opus|amr|aiff|au|ra|dts|ac3|mka|oga)
            echo "→ Processing as audio file ($ext)"
            convert_audio "$file" "$backup_dir" "$ext"
            ;;
        m3u)
            echo "→ Processing as playlist file"
            process_m3u "$file" "$backup_dir"
            ;;
        m4v|mkv|mp4)
            echo "→ Processing as video file ($ext)"
            strip_metadata "$file" "$backup_dir"
            if [ "$use_handbrake_settings" = "true" ]; then
                convert_with_handbrake_settings "$file" "$backup_dir"
            fi
            ;;
        mpg|mpeg|avi|flv|mov|webm|3gp|wmv|asf|rm|rmvb|ts|mts|m2ts|vob|ogv)
            echo "→ Processing as video file ($ext)"
            strip_metadata "$file" "$backup_dir"
            if [ "$conv_oldfileformats" = "true" ]; then
                convert_to_mp4 "$file" "$backup_dir"
            fi
            ;;
        *)
            echo "→ Unknown file type: $ext"
            ;;
    esac

    echo "=== Finished processing $(basename "$file") ==="
    echo ""
}

# Updated file finding for images
find_all_files() {
    local target="$1"

    [ "$debug_mode" = "true" ] && echo "DEBUG: find_all_files called with target: $target"
    [ "$debug_mode" = "true" ] && echo "DEBUG: recursive setting: $recursive"
    [ "$debug_mode" = "true" ] && echo "DEBUG: process_images setting: $process_images"

    if [ ! -d "$target" ] && [ ! -f "$target" ]; then
        [ "$debug_mode" = "true" ] && echo "DEBUG: Target is neither file nor directory: $target"
        return 1
    fi

    local find_args=("$target")

    if [ "$recursive" = "false" ]; then
        find_args+=("-maxdepth" "1")
        [ "$debug_mode" = "true" ] && echo "DEBUG: Using non-recursive search"
    else
        [ "$debug_mode" = "true" ] && echo "DEBUG: Using recursive search"
    fi

    find_args+=("-type" "f")

    # Build the condition for file extensions
    local conditions=()

    # Video extensions
    conditions+=("-iname" "*.mp4" "-o" "-iname" "*.mpg" "-o" "-iname" "*.mpeg" "-o" "-iname" "*.avi")
    conditions+=("-o" "-iname" "*.m4v" "-o" "-iname" "*.mkv" "-o" "-iname" "*.flv" "-o" "-iname" "*.mov")
    conditions+=("-o" "-iname" "*.webm" "-o" "-iname" "*.3gp" "-o" "-iname" "*.wmv" "-o" "-iname" "*.asf")
    conditions+=("-o" "-iname" "*.rm" "-o" "-iname" "*.rmvb" "-o" "-iname" "*.ts" "-o" "-iname" "*.mts")
    conditions+=("-o" "-iname" "*.m2ts" "-o" "-iname" "*.vob" "-o" "-iname" "*.ogv")

    # Audio extensions
    conditions+=("-o" "-iname" "*.mp3" "-o" "-iname" "*.wav" "-o" "-iname" "*.ogg" "-o" "-iname" "*.iff")
    conditions+=("-o" "-iname" "*.8svx" "-o" "-iname" "*.flac" "-o" "-iname" "*.aac" "-o" "-iname" "*.m4a")
    conditions+=("-o" "-iname" "*.wma" "-o" "-iname" "*.opus" "-o" "-iname" "*.amr" "-o" "-iname" "*.aiff")
    conditions+=("-o" "-iname" "*.au" "-o" "-iname" "*.ra" "-o" "-iname" "*.dts" "-o" "-iname" "*.ac3")
    conditions+=("-o" "-iname" "*.mka" "-o" "-iname" "*.oga" "-o" "-iname" "*.m3u" "-o" "-iname" "*.m3v")
    conditions+=("-o" "-iname" "*.aud")

    # Image extensions (if image processing is enabled)
    if [ "$process_images" = "true" ]; then
        [ "$debug_mode" = "true" ] && echo "DEBUG: Adding image formats to search"
        conditions+=("-o" "-iname" "*.jpg" "-o" "-iname" "*.jpeg" "-o" "-iname" "*.png" "-o" "-iname" "*.gif")
        conditions+=("-o" "-iname" "*.bmp" "-o" "-iname" "*.tiff" "-o" "-iname" "*.tif" "-o" "-iname" "*.webp")
        conditions+=("-o" "-iname" "*.tga" "-o" "-iname" "*.dds" "-o" "-iname" "*.dxt" "-o" "-iname" "*.pcx")
        conditions+=("-o" "-iname" "*.psd")
    fi

    # Combine everything
    find_args+=("(" "${conditions[@]}" ")")
    find_args+=("-print0")

    [ "$debug_mode" = "true" ] && echo "DEBUG: Running find command with ${#find_args[@]} arguments"
    [ "$debug_mode" = "true" ] && echo "DEBUG: find command: find ${find_args[*]}"

    # Execute the find command
    find "${find_args[@]}" 2>/dev/null
}

run_gui_mode() {
    local gui_tool=$(check_gui_tools)

    if [ "$gui_tool" = "none" ]; then
        echo "No GUI tools available. Install zenity, kdialog, or yad for GUI mode."
        return 1
    fi

    # Enable debug mode for troubleshooting
    [ "$debug_mode" = "true" ] && echo "DEBUG: Starting GUI mode with $gui_tool"

    # Welcome dialog
    case "$gui_tool" in
        zenity)
            if ! zenity --question --title="StripMeta GUI File Processor" \
                --text="Welcome to StripMeta GUI v$SCRIPT_VERSION (X-Seti) \n\n🎨 Advanced Media File Processor with Complete Graphical Interface\n\nNew Features:\n• Complete GUI interface for all operations\n• Visual file and directory selection\n• Image processing support (JPG, PNG, DXT, TGA, etc.)\n• Real-time progress tracking\n• Enhanced format support\n\nCapabilities:\n• Remove metadata from 25+ video and 15+ audio formats\n• Process images with format conversion\n• Clean filenames (dots/underscores to spaces)\n• Convert between audio/video formats\n• Remove .nfo files and thumbnails\n• Create backups of original files\n\nWould you like to continue?" \
                --width=600 --height=350 2>/dev/null; then
                exit 0
            fi
            ;;
        kdialog)
            if ! kdialog --title="StripMeta GUI File Processor" --yesno "Welcome to StripMeta GUI v$SCRIPT_VERSION\n\nAdvanced Media File Processor with Complete GUI\n\nWould you like to continue?" 2>/dev/null; then
                exit 0
            fi
            ;;
        yad)
            if ! yad --question --title="StripMeta GUI File Processor" \
                --text="Welcome to StripMeta GUI v$SCRIPT_VERSION (X-Seti) \n\n🎨 Advanced Media File Processor with Complete GUI\n\nWould you like to continue?" \
                --width=600 --height=250 2>/dev/null; then
                exit 0
            fi
            ;;
    esac

    [ "$debug_mode" = "true" ] && echo "DEBUG: Welcome dialog completed"

    # File selection
    [ "$debug_mode" = "true" ] && echo "DEBUG: Starting file selection"
    if ! gui_file_selection; then
        show_gui_info "No files or directory selected. Exiting."
        return 1
    fi

    [ "$debug_mode" = "true" ] && echo "DEBUG: File selection completed"
    [ "$debug_mode" = "true" ] && echo "DEBUG: Selection type: $SELECTION_TYPE"
    [ "$debug_mode" = "true" ] && echo "DEBUG: Selected files/dirs: ${SELECTED_FILES[*]}"

    # Configuration dialog
    [ "$debug_mode" = "true" ] && echo "DEBUG: Starting configuration dialog"
    if ! gui_configuration_dialog; then
        show_gui_info "Configuration cancelled."
        return 1
    fi

    [ "$debug_mode" = "true" ] && echo "DEBUG: Configuration completed"

    # Count total files for progress
    [ "$debug_mode" = "true" ] && echo "DEBUG: Counting files for progress tracking..."
    local total_files=0
    if [ "$SELECTION_TYPE" = "files" ]; then
        total_files=${#SELECTED_FILES[@]}
        [ "$debug_mode" = "true" ] && echo "DEBUG: Individual files mode - $total_files files selected"
    else
        # Count files in directory using a more reliable method
        [ "$debug_mode" = "true" ] && echo "DEBUG: Directory mode - scanning ${SELECTED_FILES[0]}"
        echo "Scanning directory for files..."
        total_files=0
        while IFS= read -r -d '' file; do
            total_files=$((total_files + 1))
            [ "$debug_mode" = "true" ] && echo "DEBUG: Found file #$total_files: $(basename "$file")"
        done < <(find_all_files "${SELECTED_FILES[0]}")
        [ "$debug_mode" = "true" ] && echo "DEBUG: Directory scan complete - found $total_files files"
    fi

    if [ "$total_files" -eq 0 ]; then
        show_gui_info "No supported files found to process."
        return 1
    fi

    echo "Found $total_files files to process"
    [ "$debug_mode" = "true" ] && echo "DEBUG: Total files to process: $total_files"

    # Confirmation dialog with preview
    local preview_text="Ready to process $total_files file(s)\n\n"
    preview_text+="Settings:\n"
    [ "$clean_filenames" = "true" ] && preview_text+="• Clean filenames: Replace dots with spaces\n"
    [ "$replace_underscores" = "true" ] && preview_text+="• Replace underscores with spaces\n"
    [ "$capitalize_filenames" = "true" ] && preview_text+="• Capitalize filenames\n"
    [ "$rename_to_m4v" = "true" ] && preview_text+="• Rename video extensions to M4V\n"
    [ "$backups" = "true" ] && preview_text+="• Create backups: Yes\n"
    [ "$recursive" = "true" ] && preview_text+="• Recursive processing: Yes\n"
    [ "$rm_metadata_files" = "true" ] && preview_text+="• Remove metadata files: Yes\n"
    [ "$conv_oldfileformats" = "true" ] && preview_text+="• Convert old formats to MP4: Yes\n"
    [ "$use_handbrake_settings" = "true" ] && preview_text+="• HandBrake compression: Yes\n"
    [ "$process_images" = "true" ] && preview_text+="• Image processing: Yes (format: $image_format)\n"
    [ "$audio_output_format" != "mp3" ] && preview_text+="• Audio format: $audio_output_format\n"
    preview_text+="\nProceed with processing?"

    [ "$debug_mode" = "true" ] && echo "DEBUG: Showing confirmation dialog"

    case "$gui_tool" in
        zenity)
            if ! zenity --question --title="Confirm Processing" --text="$preview_text" --width=500 --height=400 2>/dev/null; then
                return 0
            fi
            ;;
        kdialog)
            if ! kdialog --yesno "$preview_text" 2>/dev/null; then
                return 0
            fi
            ;;
        yad)
            if ! yad --question --title="Confirm Processing" --text="$preview_text" --width=500 --height=400 2>/dev/null; then
                return 0
            fi
            ;;
    esac

    [ "$debug_mode" = "true" ] && echo "DEBUG: User confirmed processing"

    # Start progress window
    [ "$debug_mode" = "true" ] && echo "DEBUG: About to start progress window for $total_files files"
    gui_progress_window "Processing Files" "$total_files"
    local current_count=0

    echo "Starting file processing..."
    [ "$debug_mode" = "true" ] && echo "DEBUG: Starting file processing loop..."
    [ "$debug_mode" = "true" ] && echo "DEBUG: Selection type: $SELECTION_TYPE"
    [ "$debug_mode" = "true" ] && echo "DEBUG: Selected files: ${SELECTED_FILES[*]}"

    # Process files
    if [ "$SELECTION_TYPE" = "files" ]; then
        [ "$debug_mode" = "true" ] && echo "DEBUG: Processing individual files mode"
        # Process individual files
        for file in "${SELECTED_FILES[@]}"; do
            [ "$debug_mode" = "true" ] && echo "DEBUG: Processing file: $file"
            if [ -f "$file" ]; then
                current_count=$((current_count + 1))
                update_progress "$current_count" "$total_files" "$file"
                process_single_file "$file"
            else
                echo "WARNING: File not found: $file"
            fi
        done
    else
        [ "$debug_mode" = "true" ] && echo "DEBUG: Processing directory mode"
        # Process directory
        local target_dir="${SELECTED_FILES[0]}"
        [ "$debug_mode" = "true" ] && echo "DEBUG: Target directory: $target_dir"

        # Clean up directory metadata first
        cleanup_directory_metadata "$target_dir"

        # Process all files with progress updates
        [ "$debug_mode" = "true" ] && echo "DEBUG: Starting find command..."
        while IFS= read -r -d '' file; do
            [ "$debug_mode" = "true" ] && echo "DEBUG: Found file for processing: $file"
            current_count=$((current_count + 1))
            update_progress "$current_count" "$total_files" "$file"
            process_single_file "$file"

            # Add a small delay to make progress visible
            sleep 0.1
        done < <(find_all_files "$target_dir")

        [ "$debug_mode" = "true" ] && echo "DEBUG: Finished processing directory files"
    fi

    echo "File processing complete! Processed $current_count files."
    [ "$debug_mode" = "true" ] && echo "DEBUG: File processing complete, processed $current_count files"

    # Complete progress
    update_progress "$total_files" "$total_files" "Complete!"
    sleep 2
    close_progress

    [ "$debug_mode" = "true" ] && echo "DEBUG: About to show results dialog"

    # Show results
    show_results_dialog

    return 0
}

# Import all the other functions from the original script
# (All the existing functions for processing files, metadata removal, etc.)
# ... [Previous functions remain the same] ...

# Clean filename function
clean_filename() {
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

    # Handle M4V renaming - do this FIRST before other processing
    if [ "$rename_to_m4v" = true ]; then
        local old_extension="${extension,,}" # Convert to lowercase
        case "$old_extension" in
            mp4|m4v|mov|avi|mkv)
                if [ "$extension" != "m4v" ]; then
                    extension="m4v"
                    changed=true
                    echo "DEBUG: Will rename extension from .$old_extension to .m4v"
                fi
                ;;
        esac
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

    # Handle M4V renaming
    if [ "$rename_to_m4v" = true ]; then
        case "$extension" in
            mp4|m4v|mov)
                extension="m4v"
                changed=true
                ;;
        esac
    fi

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
            echo "→ Renaming file: $(basename "$file") -> $(basename "$new_path")"
            if mv "$file" "$new_path"; then
                echo "✓ Successfully renamed: $(basename "$file") -> $(basename "$new_path")"
                if [ "$verbose" = "true" ]; then
                    echo "DEBUG: clean_filename output: '$new_path'"
                fi
                echo "$new_path"
                return 0
            else
                echo "✗ Failed to rename: $file"
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

# Include all other necessary functions from the original script...
# (backup_file, is_file_processed, log_processed_file, etc.)

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

    # Increment counters
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
        jpg|jpeg|png|gif|bmp|tiff|webp|tga|dds|dxt|pcx|psd)
            image_files_processed=$((image_files_processed+1))
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
}

cleanup_directory_metadata() {
    local dir="$1"
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

    # Update global counters
    metadata_files_removed=$((metadata_files_removed + nfo_count))
    thumbnails_removed=$((thumbnails_removed + thumb_count))
}

process_mp3() {
    local file="$1"
    local backup_dir="${2:-./backups}"

    if is_file_processed "$file"; then
        echo "Skipping already processed MP3 file: $file"
        files_skipped=$((files_skipped + 1))
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
        return 0
    else
        echo "✗ Failed to process MP3 with exiftool: $file"
        files_failed=$((files_failed + 1))
        local temp_file="${file%.*}_stripped.mp3"
        if ffmpeg -y -nostdin -i "$file" -c:a copy -map_metadata -1 "$temp_file"; then
            mv "$temp_file" "$file"
            echo "✓ Processed MP3 with ffmpeg: $file"
            log_processed_file "$file" "processed" "mp3"
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
        files_skipped=$((files_skipped + 1))
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
            audio_codec="aac"
            output_file="${file%.*}.m4a"
            ;;
        *)
            audio_codec="libmp3lame"
            output_file="${file%.*}.mp3"
            ;;
    esac

    if [ "$input_format" = "$audio_output_format" ]; then
        echo "Input and output formats are the same. Just removing metadata..."
        if exiftool -overwrite_original -All= "$file"; then
            echo "✓ Removed metadata from $input_format file: $file"
            log_processed_file "$file" "processed" "$input_format"
            return 0
        else
            temp_file="${file%.*}_stripped.$input_format"
            if ffmpeg -y -nostdin -i "$file" -c:a copy -map_metadata -1 "$temp_file"; then
                mv "$temp_file" "$file"
                echo "✓ Removed metadata with ffmpeg: $file"
                log_processed_file "$file" "processed" "$input_format"
                return 0
            fi
        fi
    fi

    if ffmpeg -y -nostdin -i "$file" -vn -ar 44100 -ac 2 -c:a "$audio_codec" -b:a "$bitrate" -map_metadata -1 "$output_file"; then
        if [ "$backups" = "false" ]; then
            rm "$file"
        fi
        echo "✓ Converted $input_format to $audio_output_format: $output_file"
        log_processed_file "$output_file" "processed" "$audio_output_format"
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
        files_skipped=$((files_skipped + 1))
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

    if [ ! -f "$file" ]; then
        echo "✗ Error: File not found: $file"
        files_failed=$((files_failed + 1))
        return 1
    fi

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would strip metadata from: $file"
        return 0
    fi

    backup_file "$file" "$backup_dir"
    file_type=$(detect_file_type "$file")

    # Handle both old renameext and new rename_to_m4v options
    if [ "$renameext" = "true" ] || [ "$rename_to_m4v" = "true" ]; then
        case "$file_type" in
            mp4|m4v|mov)
                new_name="${file%.*}.m4v"
                if [ "$file" != "$new_name" ]; then
                    mv "$file" "$new_name"
                    file="$new_name"
                    echo "Renamed to M4V: $file"
                fi
                ;;
        esac
    fi

    remove_assoc_metadata_files "$file"

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
    echo "Processing MKV: $file"

    if [ "$dry_run" = "true" ]; then
        echo "[DRY RUN] Would process MKV: $file"
        return 0
    fi

    if [ "$renameext" = "true" ] || [ "$rename_to_m4v" = "true" ]; then
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

# Additional utility functions

handle_error() {
    local error_code=$1
    local error_message=$2
    local operation=$3
    local file=$4

    echo -e "Error (code $error_code) during $operation: $error_message" >&2
    echo -e "Failed to process: $file" >&2
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

check_for_updates() {
    echo "Checking for script updates..."
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s https://github.com/X-Seti/stripmeta/main/version.txt)
        if [ -n "$latest_version" ] && [ "$latest_version" != "$SCRIPT_VERSION" ]; then
            echo -e "A new version ($latest_version) is available! Current version: $SCRIPT_VERSION\nVisit https://github.com/X-Seti/stripmeta to update"
        else
            echo "You are running the latest version: $SCRIPT_VERSION"
        fi
    else
        echo "curl not found, cannot check for updates"
    fi
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
    Standard: jpg, jpeg, png, gif, bmp
    Professional: tiff, tif, psd
    Web: webp
    Game: tga, dds, dxt, pcx
    Legacy: Various game and specialty formats

PLAYLIST FORMATS:
    m3u (basic playlist support)

OUTPUT FORMATS:
    Video: mp4 (H.264), mkv (H.265 with HandBrake)
    Audio: mp3, flac, ogg, wav, aac, m4a
    Images: jpg, png, gif, bmp, tiff, webp

METADATA REMOVAL:
    - EXIF data from media files and images
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
    echo "rename_to_m4v=$rename_to_m4v" >> "$config_file"
    echo "backups=$backups" >> "$config_file"
    echo "verbose=$verbose" >> "$config_file"
    echo "recursive=$recursive" >> "$config_file"
    echo "convert_to_mp4=$convert_to_mp4" >> "$config_file"
    echo "conv_oldfileformats=$conv_oldfileformats" >> "$config_file"
    echo "use_handbrake_settings=$use_handbrake_settings" >> "$config_file"
    echo "rm_metadata_files=$rm_metadata_files" >> "$config_file"
    echo "process_images=$process_images" >> "$config_file"
    echo "image_format=\"$image_format\"" >> "$config_file"
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
    echo "last_rename_to_m4v=$rename_to_m4v" >> "$config_file"
    echo "last_backups=$backups" >> "$config_file"
    echo "last_recursive=$recursive" >> "$config_file"
    echo "last_convert_to_mp4=$convert_to_mp4" >> "$config_file"
    echo "last_conv_oldfileformats=$conv_oldfileformats" >> "$config_file"
    echo "last_use_handbrake_settings=$use_handbrake_settings" >> "$config_file"
    echo "last_rm_metadata_files=$rm_metadata_files" >> "$config_file"
    echo "last_process_images=$process_images" >> "$config_file"
    echo "last_image_format=\"$image_format\"" >> "$config_file"
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
        [ -z "$rename_to_m4v" ] && rename_to_m4v=${last_rename_to_m4v:-false}
        [ -z "$backups" ] && backups=${last_backups:-false}
        [ -z "$recursive" ] && recursive=${last_recursive:-false}
        [ -z "$convert_to_mp4" ] && convert_to_mp4=${last_convert_to_mp4:-false}
        [ -z "$conv_oldfileformats" ] && conv_oldfileformats=${last_conv_oldfileformats:-false}
        [ -z "$use_handbrake_settings" ] && use_handbrake_settings=${last_use_handbrake_settings:-false}
        [ -z "$rm_metadata_files" ] && rm_metadata_files=${last_rm_metadata_files:-false}
        [ -z "$process_images" ] && process_images=${last_process_images:-false}
        [ -z "$image_format" ] && image_format=${last_image_format:-"jpg"}
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
        jpg|jpeg|png|gif|bmp|tiff|webp|tga|dds|dxt|pcx|psd)
            # Check image metadata with identify
            if command -v identify >/dev/null 2>&1; then
                identify -verbose "$file" > "$temp_output"
                if grep -i -E "(exif|date|camera|gps|software)" "$temp_output"; then
                    echo "WARNING: Some image metadata may remain."
                    rm "$temp_output"
                    return 1
                else
                    [ "$verbose" = "true" ] && echo "OK"
                    rm "$temp_output"
                    return 0
                fi
            else
                [ "$verbose" = "true" ] && echo "Skipped (identify not available)"
                rm "$temp_output"
                return 2
            fi
            ;;
    esac

    rm "$temp_output"
    return 0
}

# Enhanced terminal interactive mode
run_interactive_mode() {
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
                    while IFS= read -r -d '' file; do
                        process_single_file "$file"
                    done < <(find_all_files ".")
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

    if [ "$rename_to_m4v" = false ]; then
        read -p "Rename video extensions specifically to M4V? [y/N]: " m4v_response
        if [[ "$m4v_response" =~ ^[Yy]$ ]]; then
            rename_to_m4v=true
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

    echo -e "\n== Image Processing Options =="
    if [ "$process_images" = false ]; then
        read -p "Process image files? [y/N]: " image_response
        if [[ "$image_response" =~ ^[Yy]$ ]]; then
            process_images=true
            echo -e "\nChoose image output format:\n1) JPG (default - widely compatible)\n2) PNG (lossless compression)\n3) GIF (animations)\n4) BMP (uncompressed)\n5) TIFF (professional)\n6) WebP (modern web format)"
            read -p "Select format [1-6] (default: 1): " img_format_choice
            case "$img_format_choice" in
            2) image_format="png" ;;
            3) image_format="gif" ;;
            4) image_format="bmp" ;;
            5) image_format="tiff" ;;
            6) image_format="webp" ;;
            *) image_format="jpg" ;; # Default or invalid input
            esac
            echo "Selected image output format: $image_format"
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
    read -p "Process all video, audio, and image files, Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled - Press Enter to exit.."
        read
        exit 0
    fi

    cleanup_directory_metadata "."
    while IFS= read -r -d '' file; do
        process_single_file "$file"
    done < <(find_all_files ".")
    show_stats

    echo "Processing complete. Press Enter to exit..."
    read
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

show_stats() {
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
    if [ "$image_files_processed" -gt 0 ]; then
        echo "  Image files: $image_files_processed"
    fi
    if [ "$other_files_processed" -gt 0 ]; then
        echo "  Other files: $other_files_processed"
    fi
    echo "==========================================="
}

show_help() {
    cat << 'EOF'
StripMeta GUI - Media File Metadata Remover & Processor with Complete Graphical Interface

USAGE:
    ./stripmeta-gui.sh [OPTIONS] [FILES/DIRECTORIES...]
    ./stripmeta-gui.sh [OPTIONS]                    # Interactive mode
    ./stripmeta-gui.sh --gui                        # GUI mode (default when double-clicked)

DESCRIPTION:
    Advanced media file processor with complete GUI interface.
    Removes metadata, cleans filenames, converts formats, processes images, and organizes media collections.

    When double-clicked from desktop, automatically launches GUI mode if
    zenity, kdialog, or yad is available, otherwise opens in terminal.

SUPPORTED FORMATS:
    Video: mp4, mkv, avi, mpg, mpeg, m4v, flv, mov, webm, 3gp, wmv, ts, mts, m2ts, vob
    Audio: mp3, flac, wav, ogg, aac, m4a, wma, opus, amr, aiff, iff, 8svx, au
    Images: jpg, jpeg, png, gif, bmp, tiff, webp, tga, dds, dxt, pcx, psd
    Other: m3u (playlists)

NEW GUI FEATURES:
    ✓ Complete graphical interface for all operations
    ✓ Visual file and directory selection with file browser
    ✓ Organized configuration dialogs with checkboxes
    ✓ Real-time progress tracking with activity log
    ✓ Image processing support with format conversion
    ✓ Enhanced results display with comprehensive statistics
    ✓ Cross-platform support (GNOME, KDE, XFCE)

COMMAND LINE OPTIONS:
    -h, --help                      Show this help message
    --gui                           Force GUI mode (requires zenity/kdialog/yad)
    --version                       Display script version and dependency status
    --formats                       Show supported file formats
    --check-update                  Check for script updates
    --dry-run                       Show what would be done without making changes
    --verbose                       Enable detailed debug output

TROUBLESHOOTING:
    Enable debug mode for detailed troubleshooting output:

    Method 1: Set environment variable
    export STRIPMETA_DEBUG=1
    ./stripmeta-gui.sh

    Method 2: Run from terminal (automatically enables debug)
    ./stripmeta-gui.sh --gui

    Debug mode shows detailed progress and helps identify issues with:
    • File selection and scanning
    • GUI dialog interactions
    • Progress window creation
    • File processing loops

IMAGE PROCESSING:
    --process-images                Enable image processing
    --image-format FORMAT           Output format: jpg, png, gif, bmp, tiff, webp

FILENAME PROCESSING:
    --clean-filenames               Replace dots with spaces in filenames
    --replace-underscores           Replace underscores with spaces
    --capitalize                    Capitalize words in filenames
    --rename                        Change video extensions to m4v
    --rename-to-m4v                 Specifically rename to M4V format

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
    Images: ImageMagick (convert, identify)
    GUI Mode: zenity (GNOME) OR kdialog (KDE) OR yad (advanced)
    Optional: curl (updates), numfmt (formatting), ionice (performance)

INSTALLATION:
    Ubuntu/Debian: sudo apt install exiftool mkvtoolnix-cli coreutils ffmpeg zenity imagemagick
    Arch Linux: sudo pacman -S perl-image-exiftool mkvtoolnix-cli coreutils ffmpeg zenity imagemagick
    Fedora: sudo dnf install perl-Image-ExifTool mkvtoolnix coreutils ffmpeg zenity ImageMagick

EXAMPLES:
    # GUI mode (automatic when double-clicked)
    ./stripmeta-gui.sh --gui

    # Interactive terminal mode
    ./stripmeta-gui.sh

    # Process specific files
    ./stripmeta-gui.sh "Movie File.mkv" "Song.mp3" "Photo.jpg"

    # Process directory recursively with backups and image processing
    ./stripmeta-gui.sh --recursive --backups --process-images "/path/to/media"

    # Clean filenames and remove metadata files
    ./stripmeta-gui.sh --clean-filenames --remove-metadata-files --rename-to-m4v

    # Convert audio to FLAC with HandBrake video compression and image processing
    ./stripmeta-gui.sh --audio-format flac --handbrake --process-images --image-format png

    # Preview mode to see what would happen
    ./stripmeta-gui.sh --dry-run --verbose "/media/folder"

CONFIGURATION:
    Settings can be saved to ~/.stripmeta-config for automatic loading.
    Use the interactive mode to configure and save your preferences.

LOGS:
    Processing log: .processed_files.log
    Error log: .processed_files_errors.log

PROJECT:
    StripMeta GUI v2.1.0 - Advanced Media File Processor with Complete GUI
    For updates and documentation: https://github.com/X-Seti/stripmeta
EOF
}

# Check if script is launched directly (double-clicked)
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
                    xterm -e bash -c "cd $(printf '%q' "$(pwd)") && $(printf '%q' "$0")$escaped_args; exec bash"
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
        clean_filenames=true
        replace_underscores=true
        capitalize_filenames=false
        renameext=true
        backups=true
        rm_metadata_files=true
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
            --image-format)
                if [[ -n "$2" && "$2" =~ ^(jpg|jpeg|png|gif|bmp|tiff|webp)$ ]]; then
                    image_format="$2"
                    shift 2
                else
                    echo "Error: Invalid image format. Supported formats: jpg, jpeg, png, gif, bmp, tiff, webp"
                    exit 1
                fi
                ;;
            --process-images)
                process_images=true
                shift
                ;;
            --version)
                echo "StripMeta GUI - Advanced Media File Processor"
                echo "Version: $SCRIPT_VERSION"
                echo ""
                echo "New Features:"
                echo "✓ Complete Graphical User Interface (GUI Mode)"
                echo "✓ Visual File and Directory Selection"
                echo "✓ Image Processing Support (JPG, PNG, DXT, TGA, etc.)"
                echo "✓ Real-time Progress Tracking"
                echo "✓ Enhanced Format Support"
                echo ""
                echo "Capabilities:"
                echo "✓ Command Line Interface (CLI Mode)"
                echo "✓ Interactive Terminal Mode"
                echo "✓ 25+ Video Formats • 15+ Audio Formats • 12+ Image Formats"
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
            --rename-to-m4v)
                rename_to_m4v=true
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
            --test-rename)
                # Test mode to verify M4V renaming is working
                echo "=== Testing M4V Rename Functionality ==="
                rename_to_m4v=true
                dry_run=true

                if [ -n "$2" ]; then
                    test_file="$2"
                    if [ -f "$test_file" ]; then
                        echo "Testing with file: $test_file"
                        echo "Original filename: $(basename "$test_file")"
                        test_result=$(clean_filename "$test_file")
                        echo "Result filename: $(basename "$test_result")"
                    else
                        echo "Test file not found: $test_file"
                    fi
                    shift 2
                else
                    echo "Usage: $0 --test-rename /path/to/test/file.mp4"
                    exit 1
                fi
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    # If no command line arguments, start GUI mode or interactive mode
    if [ $# -eq 0 ] && [ "$is_drag_drop" = false ]; then
        # Try GUI mode first
        if [ "$(check_gui_tools)" != "none" ]; then
            run_gui_mode
            exit $?
        else
            echo "GUI tools not available. Running in interactive terminal mode."
            run_interactive_mode
            exit $?
        fi
    else
        # COMMAND LINE ARGUMENTS PROVIDED - PROCESS INDIVIDUAL FILES
        for path in "$@"; do
            if [ -f "$path" ]; then
                cleanup_directory_metadata "$(dirname "$path")"
                process_single_file "$path"
            elif [ -d "$path" ]; then
                cleanup_directory_metadata "$path"
                echo "Processing files in directory: $path"
                while IFS= read -r -d '' file; do
                    process_single_file "$file"
                done < <(find_all_files "$path")
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
