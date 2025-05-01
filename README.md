# StripMeta Tool Documentation

## Overview
StripMeta is a powerful bash script for removing metadata from various media files (video and audio) and performing additional file processing tasks. It's designed to help you clean up your media library by stripping privacy-revealing metadata, converting file formats, cleaning up filenames, and more.

**Version**: 1.9.0 (April 25, 2025)  
**Author**: Moocow Mooheda

## Dependencies
The script requires the following external tools:
- `exiftool` - For metadata removal
- `mkvpropedit` - For MKV file processing
- `sha256sum` - For file checksumming
- `ffmpeg` - For file conversion and processing

## Core Features

### Metadata Removal
- Strips all metadata from various file formats (MP4, MP3, MKV, etc.)
- Removes identifying information like geolocation, creation dates, camera info
- Uses specialized techniques for different file formats
- Verifies metadata removal

### File Type Support
- **Video**: MP4, M4V, MKV, AVI, MPG, MPEG, FLV, MOV
- **Audio**: MP3, WAV, OGG, FLAC, AAC, M4A, IFF, 8SVX, M3V, AUD
- **Playlists**: M3U

### Filename Cleaning
- Replace dots with spaces in filenames
- Replace underscores with spaces
- Capitalize words in filenames
- Remove/replace problematic characters
- Standardize file extensions

### Format Conversion
- Convert older video formats (AVI, MPG, FLV, MOV) to MP4
- Convert between audio formats with configurable settings
- Apply HandBrake-like quality settings for video conversion

### Additional Cleanup
- Remove associated metadata files (.nfo files)
- Remove thumbnail images
- Log processed files to prevent duplicate processing

## Usage Modes

### Interactive Mode
Run the script without arguments to enter interactive mode, which will:
1. Present a menu of options
2. Allow you to select processing preferences
3. Save your configuration for future use
4. Process files in the current directory

### Command Line Mode
Pass specific options and file/directory paths as arguments:
```bash
./stripmeta-wip.sh [OPTIONS] [FILE/DIRECTORY]
```

### Drag and Drop Mode
Simply drag files or folders onto the script in your file manager to process them with a predetermined set of options:
- Clean filenames (dots to spaces)
- Replace underscores with spaces
- Rename video files to the configured extension
- Create backups
- Remove metadata files

## Command Line Options

### File Handling
- `--clean-filenames` - Replace dots with spaces in filenames
- `--replace-underscores` - Replace underscores with spaces
- `--capitalize` - Capitalize words in filenames
- `--rename` - Rename video file extensions to configured format (default: m4v)

### Processing Options
- `--recursive` - Process files in all subdirectories
- `--convert-avi-mpg-flv-mov` / `--conv-oldfileformats` - Convert older formats to MP4
- `--handbrake` - Use HandBrake-like quality settings for conversion
- `--remove-metadata-files` - Remove .nfo and thumbnail files
- `--audio-format [format]` - Set output format for audio files (mp3, flac, ogg, wav, aac, m4a)

### Performance
- `--parallel` - Enable parallel processing
- `--max-jobs N` - Set maximum number of parallel jobs

### Backup Options
- `--backups` - Create backups of original files
- `--backup-dir [directory]` - Set custom backup directory (default: ./backups)

### Other Options
- `--dry-run` - Show what would be done without making changes
- `--verbose` - Show detailed processing information
- `--check-update` - Check for script updates
- `--version` - Display script version
- `--reset-log` - Reset the processing log

## Configuration
The script supports saving your configuration for future use:
- Saved to `~/.stripmeta-config`
- Last run settings saved to `~/.stripmeta-lastrun`
- Settings can be reloaded automatically

## Advanced Features

### Parallel Processing
- Process multiple files simultaneously for better performance
- Configure maximum number of parallel jobs
- Improved I/O performance settings

### Log Management
- Tracks processed files to prevent duplicate processing
- Automatic log rotation when logs get too large
- Detailed error logging

### Error Handling
- Detects and reports processing errors
- Recovery mechanisms for failed operations
- File integrity verification

### Terminal Auto-Detection
- Automatically opens in a terminal window if executed from a file manager
- Compatible with multiple desktop environments (GNOME, KDE, XFCE)

## Examples

### Basic Usage
```bash
# Run in interactive mode
./stripmeta-wip.sh

# Process a single file
./stripmeta-wip.sh video.mp4

# Process an entire directory
./stripmeta-wip.sh --recursive /path/to/media/folder
```

### Common Use Cases
```bash
# Clean filenames and convert all older formats to MP4
./stripmeta-wip.sh --clean-filenames --conv-oldfileformats /path/to/folder

# Strip metadata with no conversion, create backups
./stripmeta-wip.sh --backups --backup-dir /path/to/backups /path/to/media

# Clean all filenames and convert audio to FLAC
./stripmeta-wip.sh --clean-filenames --replace-underscores --capitalize --audio-format flac /path/to/music
```

## Best Practices
1. Run with `--dry-run` first to see what changes would be made
2. Use `--backups` for important files until you're comfortable with the results
3. Consider using `--recursive` with caution on large directories
4. Use the appropriate audio format for your needs (mp3 for compatibility, flac for quality)
5. Check the logs periodically to ensure proper processing

## Troubleshooting
- If a file fails to process, try running with `--verbose` to see detailed errors
- Ensure all dependencies are installed and up-to-date
- Check file permissions if you encounter access issues
- For corrupted files, try processing them individually

## Known Limitations
- Some proprietary formats may retain certain metadata
- Very large files may require more memory for processing
- Some older or exotic file formats might not be fully supported

---

For updates and more information, please check the project repository.
