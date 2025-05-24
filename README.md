# StripMeta GUI - Advanced Media File Processor (X-Seti)

<div align="center">

*Remove metadata • Convert formats • Clean filenames • Process images*

</div>

## ✨ Features

### 🎬 **Media Processing**
- **25+ Video Formats**: MP4, MKV, AVI, MOV, FLV, WebM, 3GP, WMV, and more
- **15+ Audio Formats**: MP3, FLAC, WAV, OGG, AAC, M4A, Opus, and more
- **Image Processing**: JPG, PNG, GIF, BMP, TIFF, DXT, TGA, and game formats
- **Metadata Removal**: Complete EXIF, ID3, and embedded data cleanup
- **Format Conversion**: Modern codec support with quality presets

### 🖥️ **User Interface** -- coming soon (stripmeta-gui) version
- **Full GUI Mode**: Intuitive graphical interface for all operations
- **File Browser**: Visual file and folder selection
- **Real-time Progress**: Live processing updates with activity log
- **Cross-platform**: Support for GNOME, KDE, XFCE desktop environments
- **Drag & Drop**: Direct file processing from file manager

### 🔧 **Advanced Options**
- **Filename Cleaning**: Replace dots/underscores, capitalize words
- **Batch Processing**: Recursive directory processing
- **Backup System**: Automatic file backups before processing
- **HandBrake Integration**: Professional video compression settings
- **Parallel Processing**: Multi-threaded operations for speed

## 🚀 Quick Start

### Installation

#### Ubuntu/Debian
```bash
sudo apt update
sudo apt install exiftool mkvtoolnix-cli coreutils ffmpeg zenity imagemagick
```

#### Arch Linux
```bash
sudo pacman -S perl-image-exiftool mkvtoolnix-cli coreutils ffmpeg zenity imagemagick
```

#### Fedora
```bash
sudo dnf install perl-Image-ExifTool mkvtoolnix coreutils ffmpeg zenity ImageMagick
```

### Usage

#### GUI Mode (Recommended)
```bash
# Make executable
chmod +x stripmeta-gui.sh

# Double-click from file manager OR run:
./stripmeta-gui.sh --gui
```

#### Command Line
```bash
# Process specific files
./stripmeta-gui.sh "Movie File.mkv" "Song.mp3"

# Process directory recursively
./stripmeta-gui.sh --recursive --backups "/path/to/media"

# Interactive terminal mode
./stripmeta-gui.sh
```

## 📋 Supported Formats

### 🎥 Video Formats
| Format | Extension | Processing | Conversion |
|--------|-----------|------------|------------|
| MP4 | `.mp4` | ✅ Metadata removal | ✅ Output format |
| MKV | `.mkv` | ✅ Advanced processing | ✅ HandBrake support |
| AVI | `.avi` | ✅ Legacy support | ✅ Convert to MP4 |
| MOV | `.mov` | ✅ QuickTime | ✅ Convert to MP4 |
| WebM | `.webm` | ✅ Modern web | ✅ Maintain quality |
| FLV | `.flv` | ✅ Flash video | ✅ Convert to MP4 |

### 🎵 Audio Formats
| Format | Extension | Quality | Compression |
|--------|-----------|---------|-------------|
| MP3 | `.mp3` | Lossy | 192k default |
| FLAC | `.flac` | Lossless | Best quality |
| WAV | `.wav` | Uncompressed | Large files |
| OGG | `.ogg` | Open source | Good quality |
| AAC | `.aac` | Modern lossy | Efficient |
| Opus | `.opus` | Latest codec | Low bitrate |

### 🖼️ Image Formats
| Category | Extensions | Support Level |
|----------|------------|---------------|
| **Standard** | JPG, PNG, GIF, BMP | ✅ Full support |
| **Professional** | TIFF, PSD, RAW | ✅ Metadata removal |
| **Game Formats** | DXT, TGA, DDS | ✅ Conversion support |
| **Legacy** | PCX, IFF, 8SVX | ✅ Basic processing |

## 🎛️ GUI Interface Guide

### Main Configuration Window
The GUI provides organized sections for easy configuration:

#### **📁 File Selection**
- **Directory Mode**: Process entire folders
- **File Mode**: Select specific files
- **Recursive**: Include subdirectories

#### **🔧 Processing Options**
- ☑️ **Clean Filenames**: Replace dots with spaces
- ☑️ **Replace Underscores**: Convert underscores to spaces
- ☑️ **Capitalize**: Proper case formatting
- ☑️ **Rename Extensions**: Change to .m4v format

#### **🎬 Video Settings**
- **Metadata Only**: Basic cleaning
- **Convert Old Formats**: AVI/MPG/FLV → MP4
- **HandBrake Compression**: Professional quality

#### **🎵 Audio Settings**
- **Format Selection**: MP3, FLAC, OGG, WAV, AAC, M4A
- **Quality Presets**: Optimized bitrates per format
- **Conversion Options**: Modern codec support

#### **🛡️ Safety Options**
- ☑️ **Create Backups**: Save original files
- ☑️ **Remove Metadata Files**: Clean .nfo and thumbnails
- **Backup Directory**: Custom backup location

### Progress Window
Real-time processing display with:
- **File Counter**: Current/Total files
- **Progress Bar**: Visual completion status
- **Activity Log**: Current file being processed
- **Statistics**: Success/failure counts

## 🔧 Advanced Usage

### Command Line Options

#### Processing Modes
```bash
--gui                    # Force GUI mode
--dry-run               # Preview mode (no changes)
--verbose               # Detailed output
--recursive             # Process subdirectories
```

#### Filename Options
```bash
--clean-filenames       # Replace dots with spaces
--replace-underscores   # Replace underscores with spaces
--capitalize           # Capitalize words
--rename               # Change extensions to m4v
```

#### Conversion Options
```bash
--audio-format FORMAT   # mp3, flac, ogg, wav, aac, m4a
--conv-oldfileformats  # Convert AVI/MPG/FLV to MP4
--handbrake            # Use HandBrake compression
```

#### Safety & Performance
```bash
--backups              # Create backup copies
--backup-dir DIR       # Custom backup directory
--parallel             # Enable parallel processing
--max-jobs N           # Parallel job limit
```

### Configuration Files

#### Save Settings
The script can save your preferences:
- **System Config**: `~/.stripmeta-config`
- **Last Run**: `~/.stripmeta-lastrun`
- **Processing Log**: `.processed_files.log`

#### Example Config
```bash
# ~/.stripmeta-config
clean_filenames=true
replace_underscores=true
backups=true
recursive=false
audio_output_format="flac"
use_handbrake_settings=true
```

## 🛠️ Dependencies

### Required
| Package | Purpose | Installation |
|---------|---------|--------------|
| **exiftool** | Metadata removal | `apt install exiftool` |
| **mkvpropedit** | MKV processing | `apt install mkvtoolnix-cli` |
| **ffmpeg** | Media conversion | `apt install ffmpeg` |
| **sha256sum** | File verification | `apt install coreutils` |

### GUI Support
| Package | Desktop | Installation |
|---------|---------|--------------|
| **zenity** | GNOME/Unity | `apt install zenity` |
| **kdialog** | KDE/Plasma | `apt install kdialog` |
| **yad** | Advanced dialogs | `apt install yad` |

### Optional
| Package | Feature | Installation |
|---------|---------|--------------|
| **ImageMagick** | Image processing | `apt install imagemagick` |
| **curl** | Update checking | `apt install curl` |
| **ionice** | I/O optimization | `apt install util-linux` |

## 📊 Performance

### Benchmarks
- **Video Processing**: ~5-10 files/minute (depends on size)
- **Audio Conversion**: ~20-30 files/minute
- **Metadata Removal**: ~50+ files/minute
- **Parallel Mode**: 2-4x speed improvement

### Optimization Tips
1. **Enable Parallel Processing**: Use `--parallel` for multiple files
2. **SSD Storage**: Faster I/O improves performance significantly
3. **Backup Location**: Use separate drive for backups
4. **Memory**: 8GB+ RAM recommended for large files

## 🐛 Troubleshooting

### Common Issues

#### GUI Not Starting
```bash
# Install GUI dependencies
sudo apt install zenity  # For GNOME
sudo apt install kdialog # For KDE
sudo apt install yad     # Advanced option
```

#### File Selection Issues
- Ensure files have proper permissions
- Check file path contains no special characters
- Use absolute paths for complex directory structures

#### Conversion Failures
- Verify ffmpeg installation: `ffmpeg -version`
- Check available codecs: `ffmpeg -codecs`
- Ensure sufficient disk space

#### Permission Errors
```bash
# Fix script permissions
chmod +x stripmeta-gui.sh

# Fix file permissions
sudo chown -R $USER:$USER /path/to/media/
```

### Debug Mode
```bash
# Enable verbose logging
./stripmeta-gui.sh --verbose --dry-run

# Check processing log
tail -f .processed_files.log
```

## 📝 Changelog

### Version 2.0.0 (2025-05-24)
- ✨ **New**: Complete GUI redesign with visual file selection
- ✨ **New**: Image processing support (JPG, PNG, DXT, TGA)
- ✨ **New**: Real-time progress tracking with activity log
- 🔧 **Fixed**: File browser selection issues
- 🔧 **Fixed**: Missing rename to m4v option in GUI
- ⚡ **Improved**: Parallel processing support
- ⚡ **Improved**: Cross-platform compatibility

### Version 1.0.0
- 🎉 Initial release
- 🎬 Video/audio metadata removal
- 🎨 Basic GUI interface
- 📁 Directory processing

## 🤝 Contributing

We welcome contributions! Please see our guidelines:

1. **Fork** the repository
2. **Create** a feature branch
3. **Test** your changes thoroughly
4. **Submit** a pull request

### Development Setup
```bash
git clone https://github.com/X-Seti/stripmeta.git
cd stripmeta
chmod +x stripmeta-gui.sh
./stripmeta-gui.sh --version
```

## 📄 License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **ExifTool** by Phil Harvey - Metadata processing
- **FFmpeg Team** - Media conversion
- **MKVToolNix** - Matroska processing
- **ImageMagick** - Image processing

--

<div align="center">

**Made with ❤️ for the open source community**

[⭐ Star this project](https://github.com/X-Seti/stripmeta) • [🐛 Report issues](https://github.com/X-Seti/stripmeta/issues) • [📖 Documentation](https://github.com/X-Seti/stripmeta/wiki)

</div>
