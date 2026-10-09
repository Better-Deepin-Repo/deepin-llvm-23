# Test rules. Defines override_dh_auto_test, gated on RUN_TEST=yes.
#
# Reads (from the including makefile): RUN_TEST, DEB_HOST_ARCH, VERBOSE,
# TARGET_BUILD, TARGET_BUILD_STAGE2, LLD_ENABLE, LLDB_DISABLE_ARCHS,
# DEB_BUILD_OPTIONS, CODECOVERAGE.

ifeq (${RUN_TEST},yes)
# List of the archs we know we have 100 % tests working
ARCH_LLVM_TEST_OK := i386 amd64

override_dh_auto_test:
	echo "Running tests: $(RUN_TEST)"
# LLVM tests
ifneq (,$(findstring $(DEB_HOST_ARCH),$(ARCH_LLVM_TEST_OK)))
# logs the output to check-llvm_build_log.txt for validation through autopkgtest
	mkdir -p reports
	ninja $(VERBOSE) -C $(TARGET_BUILD) stage2-check-llvm 2>&1 | tee reports/check-llvm_build_log.txt
else
	ninja $(VERBOSE) -C $(TARGET_BUILD) stage2-check-llvm || true
endif

# Clang tests
	ninja $(VERBOSE) -C $(TARGET_BUILD) stage2-check-clang || true

# Clang extra tests (ex: clang-tidy)
	ninja $(VERBOSE) -C $(TARGET_BUILD_STAGE2) check-clang-tools || true

# LLD tests
ifeq (${LLD_ENABLE},yes)
	ninja $(VERBOSE) -C $(TARGET_BUILD_STAGE2) check-lld || true
endif

# Sanitizer
	ninja $(VERBOSE) -C $(TARGET_BUILD_STAGE2) check-sanitizer || true

# Libcxx
	ninja $(VERBOSE) -C $(TARGET_BUILD_STAGE2) check-libcxx || true

# Libc
	ninja $(VERBOSE) -C $(TARGET_BUILD_STAGE2) check-libc || true

# Libcxxabi
	ninja $(VERBOSE) -C $(TARGET_BUILD_STAGE2) check-libcxxabi || true

# MLIR
ifeq (,$(filter $(DEB_HOST_ARCH), armel armhf i386 x32))
# Do not run MLIR test on i386 because of
# https://github.com/llvm/llvm-project/issues/58357
	ninja $(VERBOSE) -C $(TARGET_BUILD_STAGE2) check-mlir || true
endif

# Libclc tests now run as part of the stage-2 runtimes build; nothing to do here.

# LLDB tests
ifeq (,$(filter $(DEB_HOST_ARCH), $(LLDB_DISABLE_ARCHS) armhf armel))
ifneq (,$(filter codecoverage,$(DEB_BUILD_OPTIONS)))
# Create a symlink to run the testsuite: see https://bugs.archlinux.org/task/50759
	cd $(TARGET_BUILD)/lib/python*/*-packages/; \
		if test ! -e _lldb.so; then \
			ln -s lldb/_lldb.so; \
		fi
	if test "$(CODECOVERAGE)" = "no"; then \
	LD_LIBRARY_PATH=$$LD_LIBRARY_PATH:$(CURDIR)/$(TARGET_BUILD)/lib/ ninja $(VERBOSE) -C $(TARGET_BUILD) check-lldb || true; \
	fi
	# remove the workaround
	rm $(TARGET_BUILD)/lib/python*/*-packages/_lldb.so
endif
endif

# Polly tests
#ifeq (${POLLY_ENABLE},yes)
#	ninja -C $(TARGET_BUILD) check-polly || true
#endif

# Managed by debian build system
	rm -f $(TARGET_BUILD)/lib/python*/*-packages/lldb/_lldb.so

# The compression of the code coverage report is done in the
# hook B21GetCoverageResults on the server
	if test "$(CODECOVERAGE)" = "yes"; then \
		REPORT=reports/llvm-toolchain.info; \
		mkdir -p reports/; \
		lcov --directory $(TARGET_BUILD)/ --capture --ignore-errors source --output-file $$REPORT; \
		lcov --remove $$REPORT "/usr*" -o $$REPORT; \
		genhtml -o reports/coverage --show-details --highlight --legend $$REPORT; \
		chmod 0755 `find reports/coverage -type d`; \
		chmod 0644 `find reports/coverage -type f`; \
	fi
else
override_dh_auto_test:
	@echo "Skipping tests"
endif
