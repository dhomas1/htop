### NCURSES ###
_build_ncurses() {
local VERSION="6.4"  # Updated to newer version with better optimizations
local FOLDER="ncurses-${VERSION}"
local FILE="${FOLDER}.tar.gz"
local URL="http://ftp.gnu.org/gnu/ncurses/${FILE}"

_download_tgz "${FILE}" "${URL}" "${FOLDER}"
pushd target/"${FOLDER}"

# Optimized configure flags for resource-constrained devices
./configure --host="${HOST}" --prefix="${DEPS}" \
  --libdir="${DEST}/lib" --datadir="${DEST}/share" \
  --with-shared --enable-rpath --enable-widec --with-termlib=tinfo \
  --disable-database --disable-db-install \
  --without-ada --without-cxx --without-cxx-binding \
  --without-manpages --without-progs --without-tests \
  --disable-echo --disable-getcap --disable-hard-tabs \
  --disable-leaks --disable-macros --disable-overwrite \
  --enable-const --enable-ext-colors --enable-ext-mouse \
  --with-fallbacks=linux,screen,vt100,xterm \
  --without-debug --without-profile \
  --enable-pc-files=no

# Use fewer parallel jobs to reduce memory pressure
make -j2
make install
# Remove static libraries and unnecessary files
rm -v "${DEST}/lib"/*.a
rm -rf "${DEST}/share/terminfo" 2>/dev/null || true
rm -rf "${DEST}/share/tabset" 2>/dev/null || true
popd
}

### HTOP ###
_build_htop() {
local VERSION="3.4.1"  # Keep stable version that works well
local FOLDER="htop-${VERSION}"
local FILE="${FOLDER}.tar.xz"
local URL="https://github.com/htop-dev/htop/releases/download/${VERSION}/${FILE}"

_download_xz "${FILE}" "${URL}" "${FOLDER}"
pushd target/"${FOLDER}"

# Enhanced configure with optimizations for embedded systems
CPPFLAGS="${CPPFLAGS} -DNDEBUG" \
CFLAGS="${CFLAGS} -ffunction-sections -fdata-sections -fno-unwind-tables -fno-asynchronous-unwind-tables" \
LDFLAGS="${LDFLAGS} -Wl,--gc-sections -Wl,--strip-all" \
./configure --host="${HOST}" --prefix="${DEST}" \
  --mandir="${DEST}/man" \
  --enable-unicode \
  --disable-sensors --disable-capabilities \
  --disable-delayacct --disable-openvz --disable-vserver \
  --disable-ancient-vserver --disable-hwloc \
  ac_cv_func_malloc_0_nonnull=yes \
  ac_cv_func_realloc_0_nonnull=yes \
  ac_cv_file__proc_stat=yes \
  ac_cv_file__proc_meminfo=yes

make -j1  # Single job for stability
make install-strip  # Use install-strip to automatically strip symbols
# Remove man pages to save space
rm -rf "${DEST}/man" 2>/dev/null || true
popd
}

_build() {
  # Check available resources before building
  echo "Available memory: $(free -h | awk '/^Mem:/ {print $7}')"
  echo "Available disk space: $(df -h . | awk 'NR==2 {print $4}')"
  
  _build_ncurses
  _build_htop
  _package
}
