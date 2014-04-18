BUILD := build
BUILT := $(BUILD)/built
CMAKE_FLAGS := -G Ninja -DCMAKE_BUILD_TYPE:STRING=Debug -DCMAKE_INSTALL_PREFIX:PATH=$(shell pwd)/$(BUILT)
LLVM_VERSION := 3.2
CMAKE := cmake

ifeq ($(shell uname -s),Darwin)
        LIBEXT := dylib
else
        LIBEXT := so
endif

# Automatically use a binary called "ninja-build", if it's available. Some
# package managers call it this to avoid naming conflicts.
ifeq ($(shell which ninja-build >/dev/null 2>&1 ; echo $$?),0)
	NINJA := ninja-build
else
	NINJA := ninja
endif

# LLVM 3.2 has some trouble building against libc++, which seems to be the
# default standard library on recent OS X dev tools. Presumably this is fixed
# in later versions of LLVM, but for now, we force the compiler to use GNU
# libstdc++.
ifeq ($(LLVM_VERSION),3.2)
ifneq ($(shell c++ --version | grep clang),)
	CMAKE_FLAGS += '-DCMAKE_CXX_FLAGS:STRING=-stdlib=libstdc++ -std=gnu++98'
endif
endif


# Actually building stuff.

.PHONY: accept llvm

accept: check_cmake check_ninja
	mkdir -p $(BUILD)/enerc
	cd $(BUILD)/enerc ; $(CMAKE) $(CMAKE_FLAGS) ../..
	cd $(BUILD)/enerc ; $(NINJA) install

llvm: llvm/CMakeLists.txt llvm/tools/clang check_cmake check_ninja
	mkdir -p $(BUILD)/llvm
	cd $(BUILD)/llvm ; $(CMAKE) $(CMAKE_FLAGS) ../../llvm
	cd $(BUILD)/llvm ; $(NINJA) install


# Convenience targets.

.PHONY: setup test clean

setup: llvm accept

test:
	$(BUILT)/bin/llvm-lit -v test

clean:
	rm -rf $(BUILD)


# Fetching and extracting LLVM.

.INTERMEDIATE: llvm-$(LLVM_VERSION).src.tar.gz
llvm-$(LLVM_VERSION).src.tar.gz:
	curl -O http://llvm.org/releases/$(LLVM_VERSION)/$@

llvm/CMakeLists.txt: llvm-$(LLVM_VERSION).src.tar.gz
	tar -xf $<
	mv llvm-$(LLVM_VERSION).src llvm

# Symlink our modified Clang source into the LLVM tree. This way, building the
# "llvm" directory will build both LLVM and Clang. (In fact, this is the only
# way to build Clang at all as far as I know.)
llvm/tools/clang: llvm/CMakeLists.txt
	cd llvm/tools ; ln -s ../../clang .


# Friendly error messages when tools don't exist.

.PHONY: check_cmake check_ninja

check_cmake:
	@if ! $(CMAKE) --version > /dev/null ; then \
		echo "Please install CMake to build LLVM and ACCEPT."; \
		echo "http://www.cmake.org"; \
		exit 2; \
	else true; fi

check_ninja:
	@if ! $(NINJA) --version > /dev/null ; then \
		echo "Please install Ninja to build LLVM and ACCEPT."; \
		echo "http://martine.github.io/ninja/"; \
		exit 2; \
	else true; fi


# Documentation.

.PHONY: docs cleandocs deploydocs

docs:
	mkdocs build

cleandocs:
	rm -rf site

# Upload the documentation to the Web server.
CSEHOST := bicycle.cs.washington.edu
CSEPATH := /cse/www2/sampa/accept
deploydocs: cleandocs docs
	rsync --compress --recursive --checksum --itemize-changes --delete -e ssh site/ $(CSEHOST):$(CSEPATH)
	ssh $(CSEHOST) "echo -e 'authtype csenetid\\nrequire valid-user' > $(CSEPATH)/.htaccess"
