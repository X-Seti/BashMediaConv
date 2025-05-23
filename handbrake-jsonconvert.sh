#!/bin/bash

# Handbrake preset JSON to ffmpeg convertion - X-Seti (Mooheda)
# Usage: ./hb-ffmpeg-conv.sh [input_json_file] [options]
#  hbpreset.json -r [this will search and convert any media file]
#

set -e

VERSION="0.5"
# Default values
RECURSIVE=false
EXECUTE=false
MEDIA_EXTENSIONS=("mp4" "mkv" "avi" "mov" "wmv" "flv" "webm" "m4v" "mpg" "mpeg" "ts")
DRY_RUN=false
SHOW_PRESET_ONLY=false
MEDIA_DIR=""
OUTPUT_DIR=""
IGNORE_FLAG=".noconvert"
FORCE_M4V=false

# Function to display usage
show_usage() {
    echo "Usage: $0 [input_json_file] [options]" >&2
    echo "Options:" >&2
    echo "  -r, --recursive    Process media files recursively in subdirectories" >&2
    echo "  -e, --execute      Execute the generated ffmpeg commands" >&2
    echo "  -d, --dry-run      Show what would be done without actually doing it" >&2
    echo "  -p, --show-preset  Show only the ffmpeg equivalent of the preset" >&2
    echo "  -i, --input-dir    Specify input directory (default: same as JSON file)" >&2
    echo "  -o, --output-dir   Specify output directory (default: input_dir/converted)" >&2
    echo "  -m, --force-m4v    Force output extension to .m4v regardless of container" >&2
    echo "  --ignore-flag=X    Set custom ignore flag file (default: .noconvert)" >&2
    echo "  -v, --version      Show version ">&2
    echo "  -h, --help         Show this help message" >&2
    echo "" >&2
    echo "Special Features:" >&2
    echo "  - Files will be skipped if a '$IGNORE_FLAG' file exists in the same directory" >&2
    echo "  - Use -m/--force-m4v to output all files with .m4v extension" >&2
    exit 1
}

# Parse command line arguments
if [ $# -lt 1 ]; then
    show_usage
fi

# First argument should be the JSON file
JSON_FILE="$1"
shift

# Check for options
while [ "$#" -gt 0 ]; do
    case "$1" in
        -r|--recursive) RECURSIVE=true ;;
        -e|--execute) EXECUTE=true ;;
        -d|--dry-run) DRY_RUN=true ;;
        -p|--show-preset) SHOW_PRESET_ONLY=true ;;
        -m|--force-m4v) FORCE_M4V=true ;;
        -i|--input-dir)
            shift
            MEDIA_DIR="$1" ;;
        -o|--output-dir)
            shift
            OUTPUT_DIR="$1" ;;
        --ignore-flag=*)
            IGNORE_FLAG="${1#*=}" ;;
        -v|--version) show_versopm ;;
        -h|--help) show_usage ;;
        *) echo "Unknown option: $1" >&2; show_usage ;;
    esac
    shift
done

# Check if JSON file exists
if [ ! -f "$JSON_FILE" ]; then
    echo "Error: JSON file '$JSON_FILE' does not exist." >&2
    exit 1
fi

# Set default directory paths if not specified
if [ -z "$MEDIA_DIR" ]; then
    MEDIA_DIR=$(dirname "$(realpath "$JSON_FILE")")
    echo "Using media directory: $MEDIA_DIR"
fi

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$MEDIA_DIR/converted"
    echo "Using output directory: $OUTPUT_DIR"
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq." >&2
    exit 1
fi

# Extract relevant settings from JSON
PRESET_NAME=$(jq -r '.PresetList[0].PresetName' "$JSON_FILE")
VIDEO_ENCODER=$(jq -r '.PresetList[0].VideoEncoder' "$JSON_FILE")
VIDEO_BITRATE=$(jq -r '.PresetList[0].VideoAvgBitrate' "$JSON_FILE")
VIDEO_PRESET=$(jq -r '.PresetList[0].VideoPreset' "$JSON_FILE")
VIDEO_PROFILE=$(jq -r '.PresetList[0].VideoProfile' "$JSON_FILE")
VIDEO_FRAMERATE=$(jq -r '.PresetList[0].VideoFramerate' "$JSON_FILE")
VIDEO_QUALITY=$(jq -r '.PresetList[0].VideoQualitySlider' "$JSON_FILE")
VIDEO_QUALITY_TYPE=$(jq -r '.PresetList[0].VideoQualityType' "$JSON_FILE")
VIDEO_MULTIPASS=$(jq -r '.PresetList[0].VideoMultiPass' "$JSON_FILE" 2>/dev/null || echo "false")
PICTURE_WIDTH=$(jq -r '.PresetList[0].PictureWidth' "$JSON_FILE")
PICTURE_HEIGHT=$(jq -r '.PresetList[0].PictureHeight' "$JSON_FILE")
AUDIO_ENCODER=$(jq -r '.PresetList[0].AudioList[0].AudioEncoder' "$JSON_FILE")
AUDIO_BITRATE=$(jq -r '.PresetList[0].AudioList[0].AudioBitrate' "$JSON_FILE")
AUDIO_MIXDOWN=$(jq -r '.PresetList[0].AudioList[0].AudioMixdown' "$JSON_FILE")
CONTAINER=$(jq -r '.PresetList[0].FileFormat' "$JSON_FILE")

# Convert video encoder name
if [ "$VIDEO_ENCODER" = "x265" ]; then
    FFMPEG_VCODEC="libx265"
elif [ "$VIDEO_ENCODER" = "x264" ]; then
    FFMPEG_VCODEC="libx264"
else
    FFMPEG_VCODEC="$VIDEO_ENCODER"
fi

# Convert audio encoder name
if [[ "$AUDIO_ENCODER" == "copy:"* ]]; then
    AUDIO_CODEC=$(echo "$AUDIO_ENCODER" | cut -d':' -f2)
    FFMPEG_ACODEC="-c:a copy"
else
    FFMPEG_ACODEC="-c:a aac -b:a ${AUDIO_BITRATE}k"
fi

# Handle audio mixdown
if [ "$AUDIO_MIXDOWN" = "5point1" ]; then
    FFMPEG_AUDIO_CHANNELS="-ac 6"
elif [ "$AUDIO_MIXDOWN" = "stereo" ]; then
    FFMPEG_AUDIO_CHANNELS="-ac 2"
elif [ "$AUDIO_MIXDOWN" = "mono" ]; then
    FFMPEG_AUDIO_CHANNELS="-ac 1"
else
    FFMPEG_AUDIO_CHANNELS=""
fi

# Video quality settings
if [ "$VIDEO_QUALITY_TYPE" = "2" ]; then
    # Convert Handbrake CRF value to ffmpeg
    FFMPEG_QUALITY="-crf $VIDEO_QUALITY"
else
    FFMPEG_QUALITY="-b:v ${VIDEO_BITRATE}k"
fi

# Convert container format
if [ "$CONTAINER" = "av_mkv" ]; then
    OUTPUT_FORMAT="mkv"
elif [ "$CONTAINER" = "av_mp4" ]; then
    OUTPUT_FORMAT="mp4"
else
    OUTPUT_FORMAT="mkv"  # Default to MKV
fi

# Override output format if force m4v is enabled
if [ "$FORCE_M4V" = "true" ]; then
    OUTPUT_FORMAT="m4v"
    echo "Forcing output extension to .m4v"
fi

# Function to show the preset's FFmpeg equivalent
show_preset() {
    echo "============================================"
    echo "Handbrake Preset: $PRESET_NAME"
    echo "FFmpeg Equivalent Parameters:"
    echo "============================================"
    echo "Video codec:      -c:v $FFMPEG_VCODEC"
    echo "Quality:          $FFMPEG_QUALITY"
    echo "Preset:           -preset $VIDEO_PRESET"

    if [ "$VIDEO_FRAMERATE" != "auto" ] && [ -n "$VIDEO_FRAMERATE" ]; then
        echo "Framerate:        -r $VIDEO_FRAMERATE"
    fi

    echo "Resolution:       -s ${PICTURE_WIDTH}x${PICTURE_HEIGHT}"
    echo "Audio:            $FFMPEG_ACODEC $FFMPEG_AUDIO_CHANNELS"

    if [ "$VIDEO_PROFILE" != "auto" ] && [ -n "$VIDEO_PROFILE" ]; then
        echo "Profile:          -profile:v $VIDEO_PROFILE"
    fi

    echo "Output format:    $OUTPUT_FORMAT"

    if [ "$VIDEO_MULTIPASS" = "true" ] && [ "$VIDEO_QUALITY_TYPE" != "2" ]; then
        echo "Multipass:        Enabled (two-pass encoding)"
    else
        echo "Multipass:        Disabled (single-pass encoding)"
    fi
    echo "============================================"
    echo "Example usage:"
    echo "ffmpeg -i input.mp4 -c:v $FFMPEG_VCODEC $FFMPEG_QUALITY -preset $VIDEO_PRESET -s ${PICTURE_WIDTH}x${PICTURE_HEIGHT} $FFMPEG_ACODEC $FFMPEG_AUDIO_CHANNELS output.$OUTPUT_FORMAT"
    echo "============================================"
}

# Show preset only if requested
if [ "$SHOW_PRESET_ONLY" = "true" ]; then
    show_preset
    exit 0
fi

# Create output directory if it doesn't exist and not in dry run mode
if [ ! -d "$OUTPUT_DIR" ] && [ "$DRY_RUN" = "false" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Function to check if a file should be ignored
should_ignore_file() {
    local dir_path=$(dirname "$1")
    if [ -f "$dir_path/$IGNORE_FLAG" ]; then
        return 0  # True, should ignore
    fi
    return 1  # False, should not ignore
}

# Function to build ffmpeg command for a single file
build_ffmpeg_command() {
    local input_file="$1"
    local output_file="$2"

    # Base command
    local cmd="ffmpeg -i \"$input_file\" -c:v $FFMPEG_VCODEC $FFMPEG_QUALITY -preset $VIDEO_PRESET"

    # Add framerate if specified
    if [ "$VIDEO_FRAMERATE" != "auto" ] && [ -n "$VIDEO_FRAMERATE" ]; then
        cmd="$cmd -r $VIDEO_FRAMERATE"
    fi

    # Add resolution
    cmd="$cmd -s ${PICTURE_WIDTH}x${PICTURE_HEIGHT}"

    # Add audio settings
    cmd="$cmd $FFMPEG_ACODEC $FFMPEG_AUDIO_CHANNELS"

    # Add profile if specified
    if [ "$VIDEO_PROFILE" != "auto" ] && [ -n "$VIDEO_PROFILE" ]; then
        cmd="$cmd -profile:v $VIDEO_PROFILE"
    fi

    # Add multipass settings
    if [ "$VIDEO_MULTIPASS" = "true" ] && [ "$VIDEO_QUALITY_TYPE" != "2" ]; then
        # First pass
        local pass1="$cmd -pass 1 -f null /dev/null"
        # Second pass
        local pass2="$cmd -pass 2 \"$output_file\""

        # Combine commands
        cmd="$pass1 && $pass2"
    else
        cmd="$cmd \"$output_file\""
    fi

    echo "$cmd"
}

# Function to process a media file
process_file() {
    local input_file="$1"
    local rel_path="${input_file#$MEDIA_DIR/}"
    local output_subdir=$(dirname "$OUTPUT_DIR/$rel_path")
    local filename=$(basename "$input_file")
    local basename="${filename%.*}"
    local output_file="$output_subdir/$basename.$OUTPUT_FORMAT"

    # Skip processing the JSON file itself
    if [ "$input_file" = "$(realpath "$JSON_FILE")" ]; then
        return
    fi

    # Check if file should be ignored
    if should_ignore_file "$input_file"; then
        echo "Skipping: $input_file (ignore flag found)"
        return
    fi

    # Create output subdirectory if needed
    if [ ! -d "$output_subdir" ]; then
        if [ "$DRY_RUN" = "false" ]; then
            mkdir -p "$output_subdir"
        else
            echo "[DRY RUN] Would create directory: $output_subdir"
        fi
    fi

    # Build ffmpeg command
    local ffmpeg_cmd=$(build_ffmpeg_command "$input_file" "$output_file")

    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY RUN] Would execute:"
        echo "$ffmpeg_cmd"
    elif [ "$EXECUTE" = "true" ]; then
        echo "Processing: $input_file"
        echo "Output: $output_file"
        echo "Command: $ffmpeg_cmd"
        eval "$ffmpeg_cmd"
    else
        echo "Generated command for $input_file:"
        echo "$ffmpeg_cmd"
    fi
}

# Build file extension pattern for find command
extension_pattern=""
for ext in "${MEDIA_EXTENSIONS[@]}"; do
    if [ -z "$extension_pattern" ]; then
        extension_pattern="-name \"*.$ext\""
    else
        extension_pattern="$extension_pattern -o -name \"*.$ext\""
    fi
done

# Find and process media files
echo "Searching for media files in $MEDIA_DIR"
echo "Files with the '$IGNORE_FLAG' file in their directory will be skipped"

if [ "$RECURSIVE" = "true" ]; then
    echo "Recursive search enabled"
    media_files=$(eval "find \"$MEDIA_DIR\" -type f \( $extension_pattern \)")
else
    echo "Non-recursive search"
    media_files=$(eval "find \"$MEDIA_DIR\" -maxdepth 1 -type f \( $extension_pattern \)")
fi

# Process each file
file_count=0
skipped_count=0
for file in $media_files; do
    if should_ignore_file "$file"; then
        echo "Skipping: $file (ignore flag found)"
        skipped_count=$((skipped_count + 1))
    else
        process_file "$file"
        file_count=$((file_count + 1))
    fi
done

echo "Processed $file_count files, skipped $skipped_count files"

if [ "$file_count" -eq 0 ] && [ "$skipped_count" -eq 0 ]; then
    echo "No media files found in the specified directory."
fi
