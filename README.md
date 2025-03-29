# Video File Metadata Stripper

**Version:** 1.4.1  
**Author:** Moocow Mooheda  
**Date:** March 25, 2025

## Overview

This script removes metadata from video files, helping to ensure privacy and clean up media files. It supports various video formats, including MP4, MKV, AVI, MPG, MPEG, FLV, MOV, and M4V files.

## Dependencies

The script requires the following tools to be installed:
- `exiftool` - For metadata removal
- `mkvpropedit` - For processing MKV files
- `sha256sum` - For file tracking
- `ffmpeg` - For video conversion

## Features

- Removes metadata from video files
- Cleans filenames (replaces dots with spaces)
- Renames file extensions (e.g., to .m4v)
- Creates backups of original files
- Converts older formats to MP4
- Removes associated metadata files (.nfo and thumbnail files)
- Processes files recursively
- Tracks processed files to avoid redundant processing

## Usage

### Basic Usage

Run the script without arguments to use the interactive mode:

```bash
./stripmeta-new.sh
```

The script will prompt you with options for:
- Cleaning filenames
- Renaming file extensions
- Converting to MP4
- Converting specific old format files
- Creating backups
- Removing metadata files
- Processing recursively

### Command Line Options

```bash
./stripmeta-new.sh [options] [file/directory paths...]
```

#### Available Options:

- `--version`: Display the script version
- `--dry-run`: Show what would be done without making changes
- `--verbose`: Show detailed information
- `--backups`: Create backups of original files
- `--backup-dir <path>`: Specify custom backup directory (default: ./backups)
- `--clean-filenames`: Replace dots with spaces in filenames
- `--rename`: Rename processed files to .m4v extension
- `--recursive`: Process files in subdirectories
- `--convert-to-mp4`: Convert all supported video files to MP4
- `--conv-oldfileformats`: Convert only older formats (AVI, MPG, FLV, MOV, MPEG) to MP4
- `--remove-metadata-files`: Remove associated .nfo and thumbnail files
- `--reset-log`: Reset the processing log file

### Drag and Drop

You can also drag and drop files or folders onto the script. In drag-and-drop mode, the following options are automatically enabled:
- Clean filenames
- Rename to .m4v
- Create backups
- Remove metadata files

## Functions Explained

### Main Functions

1. **`main()`**: Coordinates the entire script operation, processes command-line arguments, and handles user interaction.

2. **`process_files()`**: Finds and processes video files in a directory.

3. **`strip_metadata()`**: Removes metadata from video files based on their type.

4. **`process_mkv()`**: Specifically handles MKV files using mkvpropedit.

5. **`convert_to_mp4()`**: Converts video files to MP4 format using ffmpeg.

### Helper Functions

1. **`check_dependencies()`**: Ensures all required tools are installed.

2. **`clean_filename()`**: Replaces dots with spaces in filenames.

3. **`backup_file()`**: Creates backups of files before processing.

4. **`detect_file_type()`**: Determines file type based on extension.

5. **`re_assoc_metadata_files()`**: Removes associated .nfo and thumbnail files.

6. **`is_file_processed()`**: Checks if a file has been processed previously.

7. **`log_processed_file()`**: Records processed files to avoid redundant processing.

8. **`set_drag_drop_defaults()`**: Configures settings for drag and drop mode.

## File Tracking

The script maintains a log file (`.processed_files.log`) that records the SHA256 hash and absolute path of processed files. This prevents re-processing the same files multiple times.

## Supported File Types

- **MP4, M4V, MKV**: Processed directly with respective tools
- **AVI**: Processed using ffmpeg
- **MPG, MPEG, FLV, MOV**: Processed with exiftool and can be converted to MP4

## Notes

- The script creates a backup directory (`./backups` by default) when the backup option is enabled
- The script will automatically launch in a terminal window if run from a file manager
- Processing large files or directories may take time, especially when converting formats

## Examples

Process a single file:
```bash
./stripmeta-new.sh myvideo.mkv
```

Process all videos in a directory recursively:
```bash
./stripmeta-new.sh --recursive /path/to/videos
```

Process and convert older format videos:
```bash
./stripmeta-new.sh --conv-oldfileformats myvideo.avi
```
