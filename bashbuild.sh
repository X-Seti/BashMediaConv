#!/bin/bash
# X-Seti - June24 - Multi-Architecture Shell Script Compiler
# Compiles shell scripts for different CPU architectures
# Supports modern, legacy, embedded, and historical architectures
# Version: 1.0 - Complete architecture coverage

SCRIPT_VERSION="1.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_AUTH="X-Seti - June24"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global flags
VERBOSE=false
SHOW_DETAILS=false
DRY_RUN=false
FORCE_COMPILE=false

# Comprehensive architecture database
declare -A arch_info=(
    # === MODERN DESKTOP/SERVER ARCHITECTURES ===
    ["amd64"]="AMD/Intel 64-bit (modern PC/server):x86_64-linux-gnu:amd64:desktop"
    ["x86_64"]="Intel/AMD 64-bit (alias for amd64):x86_64-linux-gnu:amd64:desktop"
    ["i386"]="Intel 32-bit (legacy PC):i686-linux-gnu:i386:desktop"
    ["i686"]="Intel 32-bit (alias for i386):i686-linux-gnu:i386:desktop"

    # === ARM ARCHITECTURES (MOBILE/EMBEDDED) ===
    ["arm64"]="ARM 64-bit (Apple M1/M2, RPi4+, Android):aarch64-linux-gnu:arm64:mobile"
    ["aarch64"]="ARM 64-bit (alias for arm64):aarch64-linux-gnu:arm64:mobile"
    ["armhf"]="ARM 32-bit hard-float (Raspberry Pi 2/3):arm-linux-gnueabihf:armhf:embedded"
    ["armel"]="ARM 32-bit soft-float (older ARM devices):arm-linux-gnueabi:armel:embedded"
    ["armv7"]="ARM v7 (modern 32-bit ARM):arm-linux-gnueabihf:armv7:embedded"
    ["armv6"]="ARM v6 (Raspberry Pi 1, Zero):arm-linux-gnueabi:armv6:embedded"

    # === NETWORK/ROUTER ARCHITECTURES ===
    ["mips"]="MIPS big-endian (routers, industrial):mips-linux-gnu:mips:network"
    ["mipsel"]="MIPS little-endian (some routers, PlayStation):mipsel-linux-gnu:mipsel:network"
    ["mips64"]="MIPS 64-bit big-endian (high-end routers):mips64-linux-gnu:mips64:network"
    ["mips64el"]="MIPS 64-bit little-endian:mips64el-linux-gnu:mips64el:network"

    # === SERVER/WORKSTATION ARCHITECTURES ===
    ["ppc64"]="PowerPC 64-bit (IBM servers, old Mac G5):powerpc64-linux-gnu:ppc64:server"
    ["ppc64le"]="PowerPC 64-bit LE (modern IBM POWER):powerpc64le-linux-gnu:ppc64le:server"
    ["ppc"]="PowerPC 32-bit (old Mac, embedded):powerpc-linux-gnu:ppc:server"
    ["s390x"]="IBM System z (mainframes):s390x-linux-gnu:s390x:server"
    ["sparc64"]="SPARC 64-bit (Sun workstations):sparc64-linux-gnu:sparc64:server"
    ["sparc"]="SPARC 32-bit (older Sun systems):sparc-linux-gnu:sparc:server"

    # === EMERGING/ACADEMIC ARCHITECTURES ===
    ["riscv64"]="RISC-V 64-bit (open-source, research):riscv64-linux-gnu:riscv64:emerging"
    ["riscv32"]="RISC-V 32-bit (embedded, IoT):riscv32-linux-gnu:riscv32:emerging"

    # === HISTORICAL/RETRO ARCHITECTURES ===
    ["m68k"]="Motorola 68000 (Amiga, Atari ST, early Mac):m68k-linux-gnu:m68k:retro"
    ["alpha"]="DEC Alpha (old workstations):alpha-linux-gnu:alpha:retro"
    ["hppa"]="HP PA-RISC (HP workstations):hppa-linux-gnu:hppa:retro"
    ["sh4"]="SuperH (Dreamcast, embedded):sh4-linux-gnu:sh4:retro"
    ["vax"]="DEC VAX (historical minicomputers):vax-linux-gnu:vax:retro"

    # === EMBEDDED/MICROCONTROLLER ===
    ["avr"]="AVR microcontrollers (Arduino):avr:avr:micro"
    ["xtensa"]="Xtensa (ESP32, ESP8266):xtensa-esp32-elf:xtensa:micro"

    # === EXOTIC/SPECIALIZED ===
    ["ia64"]="Intel Itanium (discontinued):ia64-linux-gnu:ia64:exotic"
    ["nios2"]="Altera Nios II (FPGA soft-core):nios2-linux-gnu:nios2:exotic"
    ["or1k"]="OpenRISC (open-source processor):or1k-linux-gnu:or1k:exotic"
    ["arc"]="ARC processors (embedded):arc-linux-gnu:arc:exotic"
    ["c6x"]="TI C6000 DSP:c6x-linux-gnu:c6x:exotic"
    ["hexagon"]="Qualcomm Hexagon DSP:hexagon-linux-gnu:hexagon:exotic"
)

# Gaming console architectures for reference
declare -A console_info=(
    ["nes"]="Nintendo NES (6502 - 8-bit, no modern support)"
    ["snes"]="Super Nintendo (65816 - 16-bit, no modern support)"
    ["genesis"]="Sega Genesis (Motorola 68000 - use m68k)"
    ["n64"]="Nintendo 64 (MIPS - use mips/mipsel)"
    ["psx"]="PlayStation 1 (MIPS - use mipsel)"
    ["ps2"]="PlayStation 2 (MIPS - use mipsel)"
    ["dreamcast"]="Sega Dreamcast (SuperH - use sh4)"
    ["gamecube"]="Nintendo GameCube (PowerPC - use ppc)"
    ["xbox"]="Original Xbox (Intel x86 - use i386)"
    ["xbox360"]="Xbox 360 (PowerPC - use ppc64)"
    ["ps3"]="PlayStation 3 (PowerPC Cell - use ppc64)"
    ["wii"]="Nintendo Wii (PowerPC - use ppc)"
    ["switch"]="Nintendo Switch (ARM64 - use arm64)"
    ["ps4"]="PlayStation 4 (AMD64 - use amd64)"
    ["ps5"]="PlayStation 5 (AMD64 - use amd64)"
    ["xboxone"]="Xbox One (AMD64 - use amd64)"
    ["steamdeck"]="Steam Deck (AMD64 - use amd64)"
)

# Helper functions
print_colored() {
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${NC}"
}

print_header() {
    print_colored "$CYAN" "╔══════════════════════════════════════════════════════════════╗"
    print_colored "$CYAN" "║          Multi-Architecture Shell  Script Compiler           ║"
    print_colored "$CYAN" "║                      Version $SCRIPT_VERSION - $SCRIPT_AUTH           ║"
    print_colored "$CYAN" "╚══════════════════════════════════════════════════════════════╝"
}

show_usage() {
    print_header
    echo ""
    print_colored "$WHITE" "Usage: $SCRIPT_NAME <script.sh> [architecture] [options]"
    echo ""
    print_colored "$YELLOW" "ARCHITECTURE OPTIONS:"
    echo "  auto        - Auto-detect current architecture (default)"
    echo "  all         - Compile for all supported architectures"
    echo "  modern      - Compile for modern architectures only"
    echo "  embedded    - Compile for embedded/ARM architectures"
    echo "  retro       - Compile for historical/retro architectures"
    echo "  <specific>  - Compile for specific architecture (see --list)"
    echo ""
    print_colored "$YELLOW" "GENERAL OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  -l, --list     List all supported architectures"
    echo "  -v, --verbose  Show detailed compilation output"
    echo "  -d, --details  Show architecture details and history"
    echo "  -n, --dry-run  Show what would be compiled without doing it"
    echo "  -f, --force    Force compilation even if cross-compiler missing"
    echo "  --version      Show script version"
    echo "  --consoles     Show gaming console architecture mappings"
    echo ""
    print_colored "$YELLOW" "EXAMPLES:"
    echo "  $SCRIPT_NAME script.sh                    # Auto-detect architecture"
    echo "  $SCRIPT_NAME script.sh arm64              # Compile for ARM64"
    echo "  $SCRIPT_NAME script.sh all --verbose      # Compile for all with details"
    echo "  $SCRIPT_NAME script.sh modern             # Modern architectures only"
    echo "  $SCRIPT_NAME script.sh --list             # Show all supported archs"
    echo "  $SCRIPT_NAME script.sh retro --details    # Retro archs with history"
}

list_architectures() {
    local filter="${1:-all}"
    local show_details="${2:-false}"

    print_colored "$CYAN" "🏗️  Supported Architectures ($filter):"
    echo ""

    # Group architectures by category
    declare -A categories=(
        ["desktop"]="💻 Desktop/Server Architectures"
        ["mobile"]="📱 Mobile/ARM Architectures"
        ["embedded"]="🔧 Embedded/ARM Architectures"
        ["network"]="📡 Network/Router Architectures"
        ["server"]="🏢 Server/Workstation Architectures"
        ["emerging"]="🚀 Emerging/Academic Architectures"
        ["retro"]="🕰️  Historical/Retro Architectures"
        ["micro"]="⚡ Microcontroller Architectures"
        ["exotic"]="🦄 Exotic/Specialized Architectures"
    )

    for category in desktop mobile embedded network server emerging retro micro exotic; do
        local found_any=false
        local category_output=""

        for arch in $(printf '%s\n' "${!arch_info[@]}" | sort); do
            local info="${arch_info[$arch]}"
            IFS=':' read -r description gcc_prefix file_suffix arch_category <<< "$info"

            # Skip if filtering and category doesn't match
            if [[ "$filter" != "all" ]]; then
                case "$filter" in
                    "modern") [[ "$arch_category" =~ ^(desktop|mobile)$ ]] || continue ;;
                    "embedded") [[ "$arch_category" =~ ^(embedded|micro)$ ]] || continue ;;
                    "retro") [[ "$arch_category" = "retro" ]] || continue ;;
                    *) [[ "$arch_category" = "$filter" ]] || continue ;;
                esac
            fi

            if [[ "$arch_category" = "$category" ]]; then
                if ! $found_any; then
                    category_output="${categories[$category]}\n"
                    found_any=true
                fi

                # Check if compiler is available
                local status="❌"
                local compiler_note=""
                if command -v "${gcc_prefix}-gcc" >/dev/null 2>&1; then
                    status="✅"
                elif [[ "$gcc_prefix" = "avr" ]] && command -v "avr-gcc" >/dev/null 2>&1; then
                    status="✅"
                elif command -v "gcc" >/dev/null 2>&1 && [[ "$arch_category" = "desktop" ]]; then
                    status="🔶"
                    compiler_note=" (native)"
                fi

                category_output+="  $status $arch$compiler_note\n"
                if $show_details; then
                    category_output+="      $description\n"
                    category_output+="      Prefix: $gcc_prefix\n"
                fi
            fi
        done

        if $found_any; then
            echo -e "$category_output"
        fi
    done

    echo ""
    print_colored "$YELLOW" "Legend:"
    echo "  ✅ Cross-compiler available"
    echo "  🔶 Native compiler (may work for compatible architectures)"
    echo "  ❌ Cross-compiler not installed"
}

show_console_mappings() {
    print_colored "$CYAN" "🎮 Gaming Console Architecture Mappings:"
    echo ""

    declare -A console_eras=(
        ["8-bit"]="nes snes"
        ["16-bit"]="genesis"
        ["32-bit"]="psx n64 dreamcast"
        ["128-bit"]="ps2 gamecube xbox"
        ["HD Era"]="xbox360 ps3 wii"
        ["Modern"]="switch ps4 ps5 xboxone steamdeck"
    )

    for era in "8-bit" "16-bit" "32-bit" "128-bit" "HD Era" "Modern"; do
        print_colored "$WHITE" "$era Era:"
        for console in ${console_eras[$era]}; do
            if [[ -n "${console_info[$console]}" ]]; then
                echo "  🎮 $console: ${console_info[$console]}"
            fi
        done
        echo ""
    done
}

detect_architecture() {
    local detected_arch=$(uname -m)
    local os_type=$(uname -s)

    case "$detected_arch" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l)         echo "armhf" ;;
        armv6l)         echo "armv6" ;;
        i686|i386)      echo "i386" ;;
        mips)           echo "mips" ;;
        mipsel)         echo "mipsel" ;;
        mips64)         echo "mips64" ;;
        mips64el)       echo "mips64el" ;;
        ppc64)          echo "ppc64" ;;
        ppc64le)        echo "ppc64le" ;;
        ppc)            echo "ppc" ;;
        s390x)          echo "s390x" ;;
        sparc64)        echo "sparc64" ;;
        sparc)          echo "sparc" ;;
        riscv64)        echo "riscv64" ;;
        alpha)          echo "alpha" ;;
        ia64)           echo "ia64" ;;
        m68k)           echo "m68k" ;;
        sh4)            echo "sh4" ;;
        *)              echo "unknown" ;;
    esac
}

compile_for_architecture() {
    local target_arch="$1"
    local input_file="$2"
    local force="$3"

    # Get architecture info
    local info="${arch_info[$target_arch]}"
    if [[ -z "$info" ]]; then
        print_colored "$RED" "❌ Error: Unsupported architecture '$target_arch'"
        return 1
    fi

    IFS=':' read -r description gcc_prefix file_suffix arch_category <<< "$info"

    # Generate output filename
    local base_name="${input_file%.*}"
    local out_file="${base_name}_${file_suffix}.bin"

    print_colored "$BLUE" "🔨 Compiling for $description..."
    echo "   Input:    $input_file"
    echo "   Output:   $out_file"
    echo "   Category: $arch_category"
    echo "   Prefix:   $gcc_prefix"

    if $DRY_RUN; then
        print_colored "$YELLOW" "   [DRY RUN] Would compile here"
        return 0
    fi

    # Check for cross-compiler
    local cc_cmd=""
    local compiler_found=false

    # Special cases for certain architectures
    case "$gcc_prefix" in
        "avr")
            if command -v "avr-gcc" >/dev/null 2>&1; then
                cc_cmd="CC=avr-gcc"
                compiler_found=true
            fi
            ;;
        "xtensa-esp32-elf")
            if command -v "xtensa-esp32-elf-gcc" >/dev/null 2>&1; then
                cc_cmd="CC=xtensa-esp32-elf-gcc"
                compiler_found=true
            fi
            ;;
        *)
            if command -v "${gcc_prefix}-gcc" >/dev/null 2>&1; then
                cc_cmd="CC=${gcc_prefix}-gcc"
                compiler_found=true
            elif command -v "gcc" >/dev/null 2>&1; then
                # Use native compiler for compatible architectures
                local native_arch=$(detect_architecture)
                if [[ "$target_arch" = "$native_arch" ]] ||
                   [[ "$target_arch" = "amd64" && "$native_arch" = "x86_64" ]] ||
                   [[ "$target_arch" = "x86_64" && "$native_arch" = "amd64" ]]; then
                    cc_cmd="CC=gcc"
                    compiler_found=true
                    print_colored "$YELLOW" "   Using native compiler (compatible architecture)"
                fi
            fi
            ;;
    esac

    if ! $compiler_found; then
        if $force; then
            print_colored "$YELLOW" "   ⚠️  Compiler not found, forcing with default"
            cc_cmd=""
        else
            print_colored "$RED" "   ❌ Cross-compiler '${gcc_prefix}-gcc' not found"
            print_colored "$YELLOW" "   💡 Install with: sudo apt install gcc-${gcc_prefix/-linux-gnu/}"
            print_colored "$YELLOW" "   💡 Or use --force to attempt with default compiler"
            return 1
        fi
    else
        print_colored "$GREEN" "   ✅ Using: ${cc_cmd#CC=}"
    fi

    # Compile with shc
    local shc_cmd="env $cc_cmd shc -f \"$input_file\" -o \"$out_file\""

    if $VERBOSE; then
        print_colored "$CYAN" "   Executing: $shc_cmd"
    fi

    if eval "$shc_cmd" 2>/dev/null; then
        # Get file info
        local file_size=$(du -h "$out_file" 2>/dev/null | cut -f1 || echo "unknown")
        print_colored "$GREEN" "   ✅ Success: $out_file ($file_size)"

        # Show file architecture if possible
        if command -v file >/dev/null 2>&1; then
            local file_arch=$(file "$out_file" 2>/dev/null)
            if $VERBOSE; then
                echo "   📋 Details: $file_arch"
            fi
        fi

        return 0
    else
        print_colored "$RED" "   ❌ Compilation failed"
        return 1
    fi
}

compile_multiple() {
    local input_file="$1"
    local arch_set="$2"

    local architectures=()

    case "$arch_set" in
        "all")
            # All architectures except aliases
            for arch in "${!arch_info[@]}"; do
                case "$arch" in
                    aarch64|x86_64|i686|armv7|armv6) continue ;;  # Skip aliases
                    *) architectures+=("$arch") ;;
                esac
            done
            ;;
        "modern")
            architectures=("amd64" "arm64" "i386")
            ;;
        "embedded")
            architectures=("armhf" "armel" "mips" "mipsel" "avr" "xtensa")
            ;;
        "retro")
            architectures=("m68k" "alpha" "hppa" "sh4" "vax" "ppc")
            ;;
        *)
            echo "Unknown architecture set: $arch_set"
            return 1
            ;;
    esac

    print_colored "$CYAN" "🏭 Compiling for architecture set: $arch_set"
    echo "   Targets: ${architectures[*]}"
    echo ""

    local success_count=0
    local total_count=${#architectures[@]}

    for arch in "${architectures[@]}"; do
        if compile_for_architecture "$arch" "$input_file" "$FORCE_COMPILE"; then
            success_count=$((success_count + 1))
        fi
        echo ""
    done

    print_colored "$CYAN" "📊 Compilation Summary:"
    print_colored "$GREEN" "   ✅ Successful: $success_count"
    print_colored "$RED" "   ❌ Failed: $((total_count - success_count))"
    print_colored "$BLUE" "   📈 Success Rate: $(( success_count * 100 / total_count ))%"
}

install_cross_compilers() {
    print_colored "$CYAN" "🛠️  Cross-Compiler Installation Guide:"
    echo ""

    print_colored "$WHITE" "Ubuntu/Debian:"
    echo "  sudo apt update"
    echo "  sudo apt install build-essential"
    echo "  # ARM architectures:"
    echo "  sudo apt install gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi"
    echo "  # Historical architectures:"
    echo "  sudo apt install gcc-m68k-linux-gnu gcc-alpha-linux-gnu"
    echo "  # MIPS architectures:"
    echo "  sudo apt install gcc-mips-linux-gnu gcc-mipsel-linux-gnu"
    echo "  # PowerPC:"
    echo "  sudo apt install gcc-powerpc64-linux-gnu gcc-powerpc64le-linux-gnu"
    echo "  # Microcontrollers:"
    echo "  sudo apt install gcc-avr avr-libc"
    echo ""

    print_colored "$WHITE" "RHEL/CentOS/Fedora:"
    echo "  sudo dnf groupinstall 'Development Tools'"
    echo "  sudo dnf install gcc-aarch64-linux-gnu gcc-arm-linux-gnu"
    echo ""

    print_colored "$WHITE" "macOS:"
    echo "  brew install shc"
    echo "  # Limited cross-compilation support on macOS"
    echo ""

    print_colored "$WHITE" "Arch Linux:"
    echo "  sudo pacman -S base-devel"
    echo "  # Use AUR for cross-compilers:"
    echo "  yay -S aarch64-linux-gnu-gcc arm-linux-gnueabihf-gcc"
}

check_dependencies() {
    print_colored "$CYAN" "🔍 Checking dependencies..."

    local missing_deps=()

    # Check for shc
    if ! command -v shc >/dev/null 2>&1; then
        missing_deps+=("shc")
    else
        print_colored "$GREEN" "   ✅ shc (Shell Compiler) found"
    fi

    # Check for basic build tools
    if ! command -v gcc >/dev/null 2>&1; then
        missing_deps+=("gcc")
    else
        print_colored "$GREEN" "   ✅ gcc (GNU Compiler Collection) found"
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_colored "$RED" "❌ Missing dependencies: ${missing_deps[*]}"
        echo ""
        install_cross_compilers
        return 1
    fi

    return 0
}

# Main script logic
main() {
    local input_file=""
    local target_arch="auto"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--list)
                list_architectures "all" false
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--details)
                SHOW_DETAILS=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_COMPILE=true
                shift
                ;;
            --version)
                echo "Multi-Architecture Shell Script Compiler v$SCRIPT_VERSION"
                exit 0
                ;;
            --consoles)
                show_console_mappings
                exit 0
                ;;
            --install-help)
                install_cross_compilers
                exit 0
                ;;
            --check)
                check_dependencies
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$input_file" ]]; then
                    input_file="$1"
                elif [[ -z "$target_arch" ]] || [[ "$target_arch" = "auto" ]]; then
                    target_arch="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "$input_file" ]]; then
        print_colored "$RED" "❌ Error: No input file specified"
        show_usage
        exit 1
    fi

    if [[ ! -f "$input_file" ]]; then
        print_colored "$RED" "❌ Error: Input file '$input_file' not found"
        exit 1
    fi

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Show details if requested
    if $SHOW_DETAILS; then
        list_architectures "$target_arch" true
        echo ""
    fi

    print_colored "$GREEN" "📄 Input file: $input_file"

    # Handle different compilation modes
    case "$target_arch" in
        "auto")
            local detected=$(detect_architecture)
            if [[ "$detected" = "unknown" ]]; then
                print_colored "$RED" "❌ Could not auto-detect architecture"
                print_colored "$BLUE" "🔍 Detected: $(uname -m) on $(uname -s)"
                print_colored "$YELLOW" "💡 Please specify architecture manually"
                exit 1
            fi
            print_colored "$BLUE" "🔍 Auto-detected: $detected"
            compile_for_architecture "$detected" "$input_file" "$FORCE_COMPILE"
            ;;
        "all"|"modern"|"embedded"|"retro")
            compile_multiple "$input_file" "$target_arch"
            ;;
        *)
            compile_for_architecture "$target_arch" "$input_file" "$FORCE_COMPILE"
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
