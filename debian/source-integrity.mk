# Build-time source-package integrity checks (Closes: #1130335)
#
# Modifying source-package files (debian/control, debian/watch, ...) during
# the build is forbidden by Debian policy and breaks reproducibility. The
# substitution loop in stamps/preconfigure rewrites a handful of
# tracked-and-shipped files in place; the recipes below snapshot them
# beforehand and fail the build if they diverge from the committed copy.
#
# apt.llvm.org snapshot builds bypass the failure because the rendered
# output legitimately differs between snapshots.
#
# Requires: $(LLVM_VERSION_SNAPSHOT) defined by the including makefile.

# apt.llvm.org snapshot builds are detected from the version string:
# they always carry the "~++" snapshot marker (e.g. 1:22~++20251023025710-1~exp4).
APT_LLVM_ORG := $(shell echo $(LLVM_VERSION_SNAPSHOT) | grep -q "~++" && echo yes || echo no)

# Files that are tracked in git AND kept by override_dh_auto_clean (i.e.
# shipped in the source package) AND rewritten by the .in substitution loop.
GENERATED_TRACKED_FILES := debian/control debian/watch debian/packages.ocaml debian/packages.libclc

# Snapshot tracked files before the substitution loop runs.
# Use as a single-line recipe step: $(snapshot_generated_tracked_files)
define snapshot_generated_tracked_files
for f in $(GENERATED_TRACKED_FILES); do cp -p $$f $$f.orig; done
endef

# Verify that no tracked source-package file was modified during the build,
# unless this is an apt.llvm.org snapshot build.
# Use as a single-line recipe step: $(verify_generated_tracked_files)
define verify_generated_tracked_files
rc=0; \
for f in $(GENERATED_TRACKED_FILES); do \
	if cmp -s $$f.orig $$f; then \
		rm -f $$f.orig; \
	elif test "$(APT_LLVM_ORG)" = "yes"; then \
		echo "apt.llvm.org snapshot build: $$f regenerated"; \
		diff -u $$f.orig $$f || true; \
		rm -f $$f.orig; \
	else \
		echo ""; \
		echo "ERROR: $$f was regenerated during the build."; \
		echo "Modifying $$f during the build is forbidden by Debian"; \
		echo "policy. Please refresh it before upload (e.g. via"; \
		echo "'debian/rules debian/control' on a clean tree) and commit"; \
		echo "the result."; \
		echo ""; \
		diff -u $$f.orig $$f || true; \
		mv $$f.orig $$f; \
		rc=1; \
	fi; \
done; \
exit $$rc
endef
