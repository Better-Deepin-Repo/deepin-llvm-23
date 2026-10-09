# Cross-compilation rules for the wasm32/wasm64 and mingw-w64 compiler-rt
# / libcxx targets, plus the stamps/debian-{wasm,mingw}-build aggregators.
#
# Reads (from the including makefile): CMAKE_BIN, DISTRO, LDFLAGS,
# LIBCXX_WASM_ENABLE, LLVM_DIR, LLVM_VERSION, NJOBS, SCCACHE_CMAKE,
# STAGE_2_BIN_DIR, STAGE_2_CFLAGS, STAGE_2_CXXFLAGS, STAGE_2_LDFLAGS,
# STAGE_2_LIB_DIR, TIME_COMMAND, VERBOSE, opt_flags.

# Remove some new flags introduced by dpkg 1.23.0;
STAGE_2_WASM_CFLAGS := $(filter-out -march=% -mfpu=% -fcf-protection% -mbranch-protection% -mcmodel=%, $(STAGE_2_CFLAGS))
STAGE_2_WASM_CXXFLAGS := $(filter-out -march=% -mfpu=% -fcf-protection% -mbranch-protection% -mcmodel=%, $(STAGE_2_CXXFLAGS))

build-mingw/compiler-rt-%: cpu = $(@:build-mingw/compiler-rt-%=%)
build-mingw/compiler-rt-%: stamps/debian-full-build
	@echo "Building compiler-rt for $(cpu)-w64-windows-gnu"
	@echo "Using cmake: $(CMAKE_BIN)"
	mkdir -p "$@"
	$(CMAKE_BIN) -B "$@" -S compiler-rt/lib/builtins/ \
		-G Ninja \
		$(SCCACHE_CMAKE) \
		-DCMAKE_SYSTEM_NAME=Windows \
		-DCMAKE_SYSROOT=/usr/share/mingw-w64 \
		-DCMAKE_C_COMPILER_TARGET=$(cpu)-w64-windows-gnu \
		-DCMAKE_CXX_COMPILER_TARGET=$(cpu)-w64-windows-gnu \
		-DCMAKE_ASM_COMPILER_TARGET=$(cpu)-w64-windows-gnu \
		-DCMAKE_C_COMPILER=$(STAGE_2_BIN_DIR)/clang \
		-DCMAKE_CXX_COMPILER=$(STAGE_2_BIN_DIR)/clang++ \
		-DCMAKE_C_FLAGS="$(opt_flags)" \
		-DCMAKE_CXX_FLAGS="$(opt_flags)" \
		-DCMAKE_SHARED_LINKER_FLAGS="$(STAGE_2_LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_MODULE_LINKER_FLAGS="$(STAGE_2_LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_EXE_LINKER_FLAGS="$(STAGE_2_LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_INSTALL_PREFIX=/$(LLVM_DIR)/lib/clang/$(LLVM_VERSION) \
		-DCMAKE_INSTALL_DATADIR=lib \
		-DCMAKE_INSTALL_INCLUDEDIR=include \
		-DLLVM_CMAKE_DIR=$(STAGE_2_BIN_DIR)/../ \
		-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
		-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
		-DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=OFF \
		-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
		-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
		-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
	$(TIME_COMMAND) ninja -C "$@" -j $(NJOBS) $(VERBOSE)

build-wasm/compiler-rt-%: cpu = $(@:build-wasm/compiler-rt-%=%)
build-wasm/compiler-rt-%: stamps/debian-full-build
	@echo "Building compiler-rt for $(cpu)"
	@echo "Using cmake: $(CMAKE_BIN)"
	mkdir -p "$@"
	sed -i -e 's/^\(cmake_policy(VERSION .*\.\.\.\).*/\13.29)/' build-llvm/tools/clang/stage2-bins/lib/cmake/llvm/LLVMExports.cmake
	sed -i -e 's/^\(cmake_policy(VERSION .*\.\.\.\).*/\13.29)/' build-llvm/tools/clang/stage2-bins/lib/cmake/llvm/LLVMBuildTreeOnlyTargets.cmake
	$(CMAKE_BIN) -B "$@" -S compiler-rt/lib/builtins/ \
		-G Ninja \
		$(SCCACHE_CMAKE) \
		-DCMAKE_SYSTEM_NAME=Generic \
		-DCMAKE_C_COMPILER_TARGET=$(cpu)-unknown-unknown \
		-DCMAKE_CXX_COMPILER_TARGET=$(cpu)-unknown-unknown \
		-DCMAKE_ASM_COMPILER_TARGET=$(cpu)-unknown-unknown \
		-DCMAKE_C_COMPILER=$(STAGE_2_BIN_DIR)/clang \
		-DCMAKE_CXX_COMPILER=$(STAGE_2_BIN_DIR)/clang++ \
		-DCMAKE_C_FLAGS="$(opt_flags) $(STAGE_2_WASM_CFLAGS)" \
		-DCMAKE_CXX_FLAGS="$(opt_flags) $(STAGE_2_WASM_CXXFLAGS)" \
		-DCMAKE_SHARED_LINKER_FLAGS="$(STAGE_2_LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_MODULE_LINKER_FLAGS="$(STAGE_2_LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_EXE_LINKER_FLAGS="$(STAGE_2_LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_INSTALL_PREFIX=/$(LLVM_DIR)/lib/clang/$(LLVM_VERSION) \
		-DCMAKE_INSTALL_DATADIR=lib \
		-DCMAKE_INSTALL_INCLUDEDIR=include \
		-DLLVM_CMAKE_DIR=$(STAGE_2_BIN_DIR)/../ \
		-DCOMPILER_RT_STANDALONE_BUILD=ON \
		-DCOMPILER_RT_BAREMETAL_BUILD=ON \
		-DCOMPILER_RT_INCLUDE_TESTS=OFF \
		-DCOMPILER_RT_USE_LIBCXX=OFF \
		-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
		-DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=$(cpu)-unknown-unknown \
		-DCOMPILER_RT_OS_DIR=wasi
	$(TIME_COMMAND) ninja -C "$@" -j $(NJOBS) $(VERBOSE)

ifeq ($(LIBCXX_WASM_ENABLE), no)
build-wasm/libcxx-%-wasi: build-wasm/compiler-rt-%
	@echo "Skipping libcxx-*-wasi on this distro $(DISTRO)"
else
build-wasm/libcxx-%-wasi: cpu = $(@:build-wasm/libcxx-%-wasi=%)
build-wasm/libcxx-%-wasi: build-wasm/compiler-rt-%
	@echo "Building libcxx for $(cpu)"
	@echo "Using cmake: $(CMAKE_BIN)"

	# We need a functioning clang, which in turn requires a linker. We
	# patch clang to use a versioned wasm-ld (cf. wasm-ld-path.diff), so
	# create wasm-ld-$(LLVM_VERSION) in the stage2 bin dir manually.
	cp $(STAGE_2_BIN_DIR)/wasm-ld $(STAGE_2_BIN_DIR)/wasm-ld-$(LLVM_VERSION)

	# We need a wasm compiler-rt. Depend on the make target that builds it,
	# and manually copy it to the stage2 lib dir from there
	mkdir -p \
	   $(STAGE_2_LIB_DIR)/clang/$(LLVM_VERSION)/lib/wasi/
	cp build-wasm/compiler-rt-$(cpu)/lib/wasi/libclang_rt.builtins-$(cpu).a \
	   $(STAGE_2_LIB_DIR)/clang/$(LLVM_VERSION)/lib/wasi/

	# Notes:
	# - Uses $(LDFLAGS) instead of $(STAGE_2_LDFLAGS), because wasm-ld does not
	#   support --build-id yet. Upstream is working on it, cf. D107662.
	# - Pass -fno-stack-protector to disable -fstack-protector-strong that is
	#   passed by default, as this is not supported yet in WebAssembly, cf.
	#   https://github.com/WebAssembly/wasi-libc/issues/157
	# - Use llvm-ar and llvm-ranlib, as binutils does not currently support
	#   WebAssembly and creates invalid indexes.
	# - Use LLVM_LIBDIR_SUFFIX to install to /usr/lib/wasm32-wasi. To be
	#   replaced by CMAKE_INSTALL_LIBDIR=lib/$(cpu)-wasi when D130586
	#   ships.
	mkdir -p "$@"
	$(CMAKE_BIN) -B "$@" -S runtimes \
		-G Ninja \
		$(SCCACHE_CMAKE) \
		-DCMAKE_C_COMPILER_WORKS=ON \
		-DCMAKE_CXX_COMPILER_WORKS=ON \
		-DLLVM_COMPILER_CHECKED=ON \
		-DCMAKE_C_COMPILER_TARGET=$(cpu)-unknown-wasi \
		-DCMAKE_CXX_COMPILER_TARGET=$(cpu)-unknown-wasi \
		-DCMAKE_ASM_COMPILER_TARGET=$(cpu)-unknown-wasi \
		-DCMAKE_C_COMPILER=$(STAGE_2_BIN_DIR)/clang \
		-DCMAKE_CXX_COMPILER=$(STAGE_2_BIN_DIR)/clang++ \
		-DCMAKE_AR=$(STAGE_2_BIN_DIR)/llvm-ar \
		-DCMAKE_RANLIB=$(STAGE_2_BIN_DIR)/llvm-ranlib \
		-DCMAKE_C_FLAGS="$(opt_flags) $(STAGE_2_WASM_CFLAGS) -fno-stack-protector" \
		-DCMAKE_CXX_FLAGS="$(opt_flags) $(STAGE_2_WASM_CXXFLAGS) -fno-stack-protector" \
		-DCMAKE_SHARED_LINKER_FLAGS="$(LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_MODULE_LINKER_FLAGS="$(LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_EXE_LINKER_FLAGS="$(LDFLAGS) -L$(STAGE_2_LIB_DIR)" \
		-DCMAKE_INSTALL_PREFIX=/$(LLVM_DIR) \
		-DCMAKE_INSTALL_INCLUDEDIR=include/$(cpu)-wasi \
		-DLLVM_LIBDIR_SUFFIX=/$(cpu)-wasi \
		-DLLVM_CONFIG=$(STAGE_2_BIN_DIR)/llvm-config \
		-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
		-DLIBCXX_USE_COMPILER_RT=ON \
		-DLIBCXXABI_USE_COMPILER_RT=ON \
		-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
		-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
		-DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=OFF \
		-DCMAKE_BUILD_TYPE=RelWithDebugInfo \
		-DLIBCXX_CXX_ABI=libcxxabi \
		-DLIBCXX_ABI_VERSION=2 \
		-DLIBCXX_HAS_MUSL_LIBC:BOOL=ON \
		-DLIBCXX_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY:BOOL=OFF \
		-DLIBCXX_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXX_ENABLE_FILESYSTEM:BOOL=OFF \
		-DLIBCXX_ENABLE_THREADS:BOOL=OFF \
		-DLIBCXX_HAS_PTHREAD_API:BOOL=OFF \
		-DLIBCXX_HAS_EXTERNAL_THREAD_API:BOOL=OFF \
		-DLIBCXX_BUILD_EXTERNAL_THREAD_LIBRARY:BOOL=OFF \
		-DLIBCXXABI_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXXABI_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXXABI_SILENT_TERMINATE:BOOL=ON \
		-DLIBCXXABI_ENABLE_THREADS:BOOL=OFF \
		-DLIBCXXABI_HAS_PTHREAD_API:BOOL=OFF \
		-DLIBCXXABI_HAS_EXTERNAL_THREAD_API:BOOL=OFF \
		-DLIBCXXABI_BUILD_EXTERNAL_THREAD_LIBRARY:BOOL=OFF \
		-DLIBCXXABI_USE_LLVM_UNWINDER:BOOL=OFF
	$(TIME_COMMAND) ninja -C "$@" -j $(NJOBS) $(VERBOSE)
endif

# Build compiler-rt for wasm32 and wasm64. Build libcxx only for wasm32, as
# libcxx requires wasi-libc, which only exists for wasm32 right now.
stamps/debian-wasm-build: \
  build-wasm/compiler-rt-wasm32 \
  build-wasm/libcxx-wasm32-wasi \
  build-wasm/compiler-rt-wasm64
	touch $@

# Build compiler-rt for mingw/w64.
stamps/debian-mingw-build: \
  build-mingw/compiler-rt-x86_64 \
  build-mingw/compiler-rt-i686 \
  build-mingw/compiler-rt-armv7 \
  build-mingw/compiler-rt-aarch64
	touch $@
