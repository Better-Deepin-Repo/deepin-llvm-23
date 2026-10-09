#!/bin/bash
# Unpack the freshest .orig.tar.xz produced by debian/orig-tar.sh, copy the
# packaging over it and rebase the quilt patch series on top of it.
# Patches refreshed on the way are copied back to the packaging branch.
#
# The branch (23, snapshot, ...) and the LLVM major version are deduced from
# the location of this script and from debian/changelog: nothing to update
# when a new branch is created, just symlink it:
#   ln -s 23/debian/unpack.sh unpack-23.sh
#
# Usage:
#   bash unpack-23.sh            # rebase the series of branch 23
#   bash unpack.sh               # same, for whichever branch holds this file
#
# Options / environment:
#   -f, --force        remove an already extracted directory without asking
#   -n, --dry-run      only show what would be unpacked, then stop
#   TARBALL=<file>     use this tarball instead of the newest matching one
#   MAJOR_VERSION=<n>  override the LLVM major version check
#   MAX_ATTEMPTS=<n>   maximum patch rebase rounds (default: 20)

set -euo pipefail

die() { echo "E: $*" >&2; exit 1; }
info() { echo "I: $*"; }
warn() { echo "W: $*" >&2; }

FORCE=""
DRY_RUN=""
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) sed -ne '2,/^$/s/^# \?//p' "$0"; exit 0 ;;
        *) die "unknown argument: $arg (see --help)" ;;
    esac
done

for cmd in quilt tar xz dpkg-parsechangelog; do
    command -v "$cmd" > /dev/null || die "missing required command: $cmd"
done

# This script lives in <branches>/<ORIG_VERSION>/debian/ and is usually called
# through a symlink from <branches>/unpack-<ORIG_VERSION>.sh: resolve it.
SELF=$(readlink -f "$0")
BRANCH_DIR=$(dirname "$(dirname "$SELF")")
ORIG_VERSION=$(basename "$BRANCH_DIR")
BASE_DIR=$(dirname "$BRANCH_DIR")

test -d "$BRANCH_DIR/debian/patches" || die "no patch series in $BRANCH_DIR/debian/patches"
test -f "$BRANCH_DIR/debian/changelog" || die "no changelog in $BRANCH_DIR/debian"

# The major version comes from the changelog, so it cannot drift out of sync
# with the packaging the way a hardcoded variable does.
if test -z "${MAJOR_VERSION:-}"; then
    MAJOR_VERSION=$(dpkg-parsechangelog -l "$BRANCH_DIR/debian/changelog" \
        | sed -rne "s,^Version: 1:([0-9]+).*,\1,p")
fi
test -n "$MAJOR_VERSION" || die "could not detect the major version from $BRANCH_DIR/debian/changelog"

info "Branch: $ORIG_VERSION / LLVM major version: $MAJOR_VERSION"
cd "$BASE_DIR"

# --- Locate the tarball -----------------------------------------------------
if test -n "${TARBALL:-}"; then
    LLVM_ARCHIVE=$TARBALL
    test -f "$LLVM_ARCHIVE" || die "$LLVM_ARCHIVE does not exist"
else
    # Newest by modification time: that is the one orig-tar.sh just created.
    # (Sorting the names lies as soon as the timestamp scheme changes.)
    LLVM_ARCHIVE=$(ls -1t -- "llvm-toolchain-${ORIG_VERSION}_${MAJOR_VERSION}"*~+*.orig.tar.xz 2>/dev/null | head -1 || true)
    test -n "$LLVM_ARCHIVE" \
        || die "no llvm-toolchain-${ORIG_VERSION}_${MAJOR_VERSION}*~+*.orig.tar.xz found in $BASE_DIR -- run $ORIG_VERSION/debian/orig-tar.sh first"
fi

SRC_DIR=$(basename "$LLVM_ARCHIVE" .orig.tar.xz)
info "Tarball: $LLVM_ARCHIVE ($(date -r "$LLVM_ARCHIVE" '+%F %T'), $(du -h "$LLVM_ARCHIVE" | cut -f1))"
info "Source directory: $SRC_DIR"
test -n "$DRY_RUN" && exit 0

# A truncated tarball (interrupted creation or download) otherwise fails much
# later, in ways that look like a patch conflict.
info "Checking the integrity of the tarball"
xz -t "$LLVM_ARCHIVE" || die "$LLVM_ARCHIVE is corrupted or incomplete"

# --- Extract ----------------------------------------------------------------
if test -d "$SRC_DIR"; then
    if test -n "$FORCE"; then
        info "Removing the existing $SRC_DIR"
        rm -rf "$SRC_DIR"
    elif test -t 0; then
        read -r -p "$SRC_DIR already exists. Remove it and start over? [y/N] " answer
        case "$answer" in
            [yY]*) rm -rf "$SRC_DIR" ;;
            *) die "aborting, use --force to overwrite" ;;
        esac
    else
        die "$SRC_DIR already exists (use --force to overwrite)"
    fi
fi

info "Unpacking $LLVM_ARCHIVE"
tar Jxf "$LLVM_ARCHIVE"
test -d "$SRC_DIR" || die "the tarball did not contain the expected directory $SRC_DIR"

cd "$SRC_DIR"

# --- Sanity check the upstream version --------------------------------------
VERSION_CMAKE=cmake/Modules/LLVMVersion.cmake
test -f "$VERSION_CMAKE" || die "$VERSION_CMAKE not found: unexpected tarball layout"
VER_FOUND=$(grep "LLVM_VERSION_MAJOR " "$VERSION_CMAKE" | awk '{print $2}' | cut -d\) -f1)
case "$VER_FOUND" in
    "$MAJOR_VERSION"|"$MAJOR_VERSION".0.0|"$MAJOR_VERSION".0.0git|"$MAJOR_VERSION"git) ;;
    *)
        echo "Mismatch of version"
        echo "Expected $MAJOR_VERSION / Found $VER_FOUND"
        die "the tarball does not match $BRANCH_DIR/debian/changelog"
        ;;
esac

# --- Copy the packaging -----------------------------------------------------
cp -R "$BRANCH_DIR/debian" .
test -f debian/patches/series || die "debian/patches/series is missing"

export QUILT_PATCHES=debian/patches/
# We grep quilt/patch output below: keep it in English whatever the locale is.
export LC_ALL=C LANGUAGE=C
PATCHES_SRC="$BRANCH_DIR/debian/patches"

# quilt prints patch names prefixed with $QUILT_PATCHES; we want the name as
# it appears in debian/patches/series.
patch_name() { local p=${1#debian/patches/}; echo "${p#/}"; }
# quilt applied/unapplied exit non-zero when the list is empty: never let that
# abort the script (set -e / pipefail).
count_applied() { { quilt applied 2>/dev/null || true; } | grep -c . || true; }
count_unapplied() { { quilt unapplied 2>/dev/null || true; } | grep -c . || true; }
sync_patch() {
    # Copy a refreshed patch back to the packaging branch
    local patch=$1
    mkdir -p "$(dirname "$PATCHES_SRC/$patch")"
    cp -a "debian/patches/$patch" "$PATCHES_SRC/$patch"
    info "Refreshed patch copied back: $patch"
}

MAX_ATTEMPTS=${MAX_ATTEMPTS:-20}
REFRESHED=()
attempt=0
status=fail

while test "$attempt" -lt "$MAX_ATTEMPTS"; do
    attempt=$((attempt + 1))
    before=$(count_applied)

    # Apply everything we can, without any fuzz
    if output=$(quilt push -a --fuzz=0 2>&1); then
        echo "$output"
        status=ok
        break
    fi
    echo "$output"

    if echo "$output" | grep -q "File series fully applied"; then
        status=ok
        break
    fi

    failing=$(patch_name "$(quilt next 2>/dev/null || true)")
    test -n "$failing" || die "quilt push failed but no patch is pending, giving up"
    info "Attempt $attempt/$MAX_ATTEMPTS: $failing does not apply cleanly, retrying with fuzz"

    if output=$(quilt push 2>&1); then
        echo "$output"
        if echo "$output" | grep -q "with fuzz"; then
            info "Fuzz detected in $failing, refreshing it"
            quilt refresh
            sync_patch "$(patch_name "$(quilt top)")"
            REFRESHED+=("$failing")
        fi
    else
        echo "$output"
        echo
        echo "=================================================================="
        echo " $failing does not apply, even with fuzz."
        echo " Rejected hunks:"
        find . -name '*.rej' -newermt '-10 minutes' -printf '   %p\n' 2>/dev/null || true
        echo
        echo " Fix it by hand:"
        echo "   cd $(pwd)"
        echo "   export QUILT_PATCHES=$QUILT_PATCHES"
        echo "   quilt push -f && \$EDITOR <the files> && quilt refresh"
        echo "   cp -a debian/patches/$failing $PATCHES_SRC/$failing"
        echo " then re-run this script, or continue with: quilt push -a"
        echo "=================================================================="
        status=conflict
        break
    fi

    if test "$(count_applied)" -le "$before"; then
        warn "no progress made during this round, stopping"
        status=stuck
        break
    fi
done

echo
if test ${#REFRESHED[@]} -gt 0; then
    info "${#REFRESHED[@]} patch(es) refreshed and copied back to $ORIG_VERSION/debian/patches:"
    printf '   %s\n' "${REFRESHED[@]}"
    info "Review them with: git -C $BRANCH_DIR diff"
fi

case "$status" in
    ok)
        remaining=$(count_unapplied)
        if test "$remaining" -ne 0; then
            warn "$remaining patch(es) are still unapplied:"
            quilt unapplied
            exit 1
        fi
        info "All $(count_applied) patches applied successfully in $BASE_DIR/$SRC_DIR"
        ;;
    conflict) die "patch series rebase stopped on a conflict (see above)" ;;
    stuck)    die "patch series rebase made no progress, manual intervention needed" ;;
    *)        die "reached the maximum of $MAX_ATTEMPTS attempts without applying the whole series" ;;
esac
