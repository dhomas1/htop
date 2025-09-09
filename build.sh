#!/usr/bin/env bash

### bash best practices ###
set -o errexit
set -o nounset  
set -o pipefail
shopt -s expand_aliases

# Only enable xtrace if DEBUG is set to reduce log overhead
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -o xtrace
fi

### logfile (optimized for space) ###
timestamp="$(date +%Y%m%d_%H%M%S)"  # Shorter timestamp format
logfile="build_${timestamp}.log"    # Shorter filename
echo "${0##*/} ${*}" > "${logfile}"  # Only log basename and args

# Only tee to logfile if not in quiet mode
if [[ "${QUIET:-0}" != "1" ]]; then
    exec 1> >(tee -a "${logfile}")
    exec 2> >(tee -a "${logfile}" >&2)
fi

### environment setup ###
. crosscompile.sh
export NAME="$(basename "${PWD}")"
export DEST="${BUILD_DEST:-/mnt/DroboFS/Shares/DroboApps/${NAME}}"
export DEPS="${PWD}/target/install"

# Optimized compiler flags for size and embedded systems
export CFLAGS="${CFLAGS:-} -Os -fPIC -ffunction-sections -fdata-sections -fno-unwind-tables -fno-asynchronous-unwind-tables"
export CXXFLAGS="${CXXFLAGS:-} ${CFLAGS}"
export CPPFLAGS="-I${DEPS}/include -DNDEBUG"
export LDFLAGS="${LDFLAGS:-} -Wl,-rpath,${DEST}/lib -L${DEST}/lib -Wl,--gc-sections -Wl,--as-needed"

# Reduce parallel jobs for memory-constrained systems and cross-compilation stability
MAKE_JOBS="${MAKE_JOBS:-1}"  # Single job by default for stability
alias make="make -j${MAKE_JOBS}"

### optimized support functions ###
# Unified download function to reduce code duplication
_download_and_extract() {
    local file="$1"
    local url="$2" 
    local folder="$3"
    local extract_cmd="$4"
    
    [[ ! -d "download" ]] && mkdir -p "download"
    [[ ! -d "target" ]]   && mkdir -p "target"
    
    # Only download if file doesn't exist or is corrupted
    if [[ ! -f "download/${file}" ]] || ! ${extract_cmd} "download/${file}" -t &>/dev/null; then
        echo "Downloading ${file}..."
        wget -q --show-progress -O "download/${file}" "${url}"
    fi
    
    # Clean extraction with better error handling
    if [[ -d "target/${folder}" ]]; then
        echo "Removing existing ${folder}..."
        rm -rf "target/${folder}"
    fi
    
    echo "Extracting ${file}..."
    ${extract_cmd} "download/${file}" -C target
}

# Optimized download functions using the unified approach
_download_tar() {
    _download_and_extract "$1" "$2" "$3" "tar -xf"
}

_download_tgz() {
    _download_and_extract "$1" "$2" "$3" "tar -zxf"
}

_download_bz2() {
    _download_and_extract "$1" "$2" "$3" "tar -jxf"
}

_download_xz() {
    _download_and_extract "$1" "$2" "$3" "tar -Jxf"
}

_download_zip() {
    [[ ! -d "download" ]] && mkdir -p "download"
    [[ ! -d "target" ]]   && mkdir -p "target"
    
    if [[ ! -f "download/$1" ]] || ! unzip -t "download/$1" &>/dev/null; then
        wget -q --show-progress -O "download/$1" "$2"
    fi
    
    [[ -d "target/$3" ]] && rm -rf "target/$3"
    unzip -q "download/$1" -d target
}

# Optimized git clone
_download_git() {
    [[ ! -d "target" ]] && mkdir -p "target"
    [[ -d "target/$2" ]] && rm -rf "target/$2"
    git clone --branch "$1" --single-branch --depth 1 "$3" "target/$2" --quiet
}

# Simple file downloads
_download_file() {
    [[ ! -d "download" ]] && mkdir -p "download"
    [[ ! -f "download/$1" ]] && wget -q --show-progress -O "download/$1" "$2"
}

_download_file_in_folder() {
    [[ ! -d "download/$3" ]] && mkdir -p "download/$3"
    [[ ! -f "download/$3/$1" ]] && wget -q --show-progress -O "download/$3/$1" "$2"
}

# Enhanced app download
_download_app() {
    _download_and_extract "$1" "$2" "$3" "tar -zxf"
}

# Optimized package creation with better compression
_create_tgz() {
    local FILE="${PWD}/${NAME}.tgz"
    
    [[ -f "${FILE}" ]] && rm -v "${FILE}"
    
    pushd "${DEST}"
    # Use higher compression and exclude unnecessary files
    tar --create --numeric-owner --owner=0 --group=0 \
        --gzip --file "${FILE}" \
        --exclude="*.la" --exclude="pkgconfig" --exclude="*.pc" \
        --exclude="share/info" --exclude="share/doc" \
        --exclude="include" --exclude="share/man" \
        *
    popd
    
    echo "Created package: ${FILE} ($(du -h "${FILE}" | cut -f1))"
}

# Enhanced packaging with size optimization
_package() {
    mkdir -p "${DEST}"
    [[ -d "src/dest" ]] && cp -afR src/dest/* "${DEST}"/
    
    # Remove development files and reduce size
    find "${DEST}" -name "._*" -delete
    find "${DEST}" -name "*.la" -delete 2>/dev/null || true
    find "${DEST}" -name "*.pc" -delete 2>/dev/null || true
    find "${DEST}" -path "*/include/*" -delete 2>/dev/null || true
    find "${DEST}" -path "*/share/man/*" -delete 2>/dev/null || true
    find "${DEST}" -path "*/share/doc/*" -delete 2>/dev/null || true
    find "${DEST}" -path "*/share/info/*" -delete 2>/dev/null || true
    
    # Strip binaries if strip is available
    if command -v "${HOST}-strip" >/dev/null 2>&1; then
        echo "Stripping binaries..."
        find "${DEST}" -type f -executable -exec "${HOST}-strip" --strip-unneeded {} \; 2>/dev/null || true
    fi
    
    _create_tgz
}

# Enhanced clean functions
_clean() {
    echo "Cleaning build artifacts..."
    rm -rf "${DEPS}" "${DEST}" target/*
    # Clean up any core dumps or temporary files
    find . -name "core*" -o -name "*.tmp" -delete 2>/dev/null || true
}

_dist_clean() {
    echo "Performing distribution clean..."
    _clean
    rm -f logfile* build_*.log
    rm -rf download/*
    # Clean git cache if exists
    [[ -d ".git" ]] && git clean -fdx 2>/dev/null || true
}

### Memory monitoring ###
_check_resources() {
    local available_mem=$(free -m | awk '/^Mem:/ {print $7}')
    local available_disk=$(df -m . | awk 'NR==2 {print $4}')
    
    echo "Available memory: ${available_mem}MB"
    echo "Available disk: ${available_disk}MB"
    
    if (( available_mem < 100 )); then
        echo "WARNING: Low memory detected. Consider reducing MAKE_JOBS."
    fi
    
    if (( available_disk < 500 )); then
        echo "WARNING: Low disk space. Build may fail."
    fi
}

### application-specific functions ###
. app.sh

# Show resource status before building
_check_resources

# Enhanced command processing
if [[ -n "${1:-}" ]]; then
    while [[ -n "${1:-}" ]]; do
        case "${1}" in
            clean|distclean|all|package)
                "_${1/_/-}" ;;
            check)
                _check_resources ;;
            *)
                if declare -f "_build_${1}" >/dev/null 2>&1; then
                    "_build_${1}"
                else
                    echo "Unknown target: ${1}" >&2
                    exit 1
                fi ;;
        esac
        shift
    done
else
    _build
fi
