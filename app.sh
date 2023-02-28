### NCURSES ###
_build_ncurses() {
local VERSION="6.4"
local FOLDER="ncurses-${VERSION}"
local FILE="${FOLDER}.tar.gz"
local URL="http://ftp.gnu.org/gnu/ncurses/${FILE}"

_download_tgz "${FILE}" "${URL}" "${FOLDER}"
pushd target/"${FOLDER}"

# htop's configure script explicitly looks for libtinfo, which, it seems, is
# now included as part of libncurses(w) by default. in lieu of fixing what
# appears to be an "upstream" problem with htop, we avoid linking errors by
# specifying the --with-termlib=tinfo arg to build tinfo as a separate library
# named 'libtinfo'.
#
# note that without specifying the name, tinfo will get built as 'libtinfow'
# (due to the --enable-widec argument) which again trips's up htop's configure
# script, which is still looking for libtinfo. :-/
#
# another workaround for this mess would be to not include the --with-termlib
# arg and just symlink libtinfo to libncursesw. however, building the separate
# library feels (slightly) more appropriate.
#
./configure --host="${HOST}" --prefix="${DEPS}" \
  --libdir="${DEST}/lib" --datadir="${DEST}/share" \
  --with-shared --enable-rpath --enable-widec --with-termlib=tinfo
make
make install
rm -v "${DEST}/lib"/*.a
popd
}

### HTOP ###
_build_htop() {
local VERSION="3.2.2"
local FOLDER="htop-${VERSION}"
local FILE="${FOLDER}.tar.xz"
local URL="https://github.com/htop-dev/htop/releases/download/${VERSION}/${FILE}"

_download_xz "${FILE}" "${URL}" "${FOLDER}"
pushd target/"${FOLDER}"
./configure --host="${HOST}" --prefix="${DEST}" \
  --mandir="${DEST}/man" \
  --enable-unicode \
  ac_cv_func_malloc_0_nonnull=yes \
  ac_cv_func_realloc_0_nonnull=yes \
  ac_cv_file__proc_stat=yes \
  ac_cv_file__proc_meminfo=yes
make
make install
popd
}

_build() {
  _build_ncurses
  _build_htop
  _package
}
