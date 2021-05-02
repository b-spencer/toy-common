#******************************************************************************
# We may as well even do things right for toy programs.
#
# all:   build everything, including tests.
# tests: build the tests (if any)
# test   build and run the tests (if any)
#
# Variables:
#
#   DEBUG=1      Enable -ggdb3 and disable optimizations.
#   SANITIZE=x   Enable -fsanitize=x for the compiler and linker.
#
# If you have a directory named "test/", this assumes all the sources inside are
# tests using Boost UT.  Use $(TEST_OMIT_OBJS) to specify which file has your
# main() so you can filter it out of the tests.
#
# If you need additional (system) libraries linked in, set $(LIBS) to the bare
# library names in your Makefile.
#
# Yes, this does in-source-tree builds, but it was supposed to be very simple.
# And one day long ago, it was.

__THIS_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

# Use bash everywhere.
export SHELL := /bin/bash

# The default goal is always "all".
.DEFAULT_GOAL := all

# Delete targets on error, globally.
.DELETE_ON_ERROR:

# Disable all the (useless, in-the-way) default rules.  We'll write all the
# rules ourselves.
.SUFFIXES:
%: %,v
%: RCS/%,v
%: RCS/%
%: s.%
%: SCCS/s.%

#------------------------------------------------------------------------------
# Compiler setup.

# What version of clang do we use?
CLANG_VERSION := 11

# The tools we need.
CC := clang-$(CLANG_VERSION)
CXX := clang++-$(CLANG_VERSION)
LD := clang++-$(CLANG_VERSION)
AR := llvm-ar-$(CLANG_VERSION)
NM := llvm-nm-$(CLANG_VERSION)
RANLIB := llvm-ranlib-$(CLANG_VERSION)

# Debug flag
DEBUG_FLAGS := -ggdb3

# Debug or release?
C_CXX_FLAGS := -Wall -Wextra -Werror $(DEBUG_FLAGS)
ifeq ($(DEBUG),)
  C_CXX_FLAGS += -O3 -ffast-math -march=native -mtune=native -DNDEBUG -flto
endif

# Sanitize?
C_CXX_LD_FLAGS :=
ifneq ($(SANITIZE),)
  C_CXX_LD_FLAGS += -fsanitize=$(SANITIZE)
endif

# C++ standard version and library?
STD_VER_FLAGS := -std=c++20
STD_LIB_FLAGS := -stdlib=libc++

# Apply flags to each tool.
CFLAGS := $(C_CXX_FLAGS) $(C_CXX_LD_FLAGS)
CXXFLAGS := $(C_CXX_FLAGS) $(C_CXX_LD_FLAGS) $(STD_VER_FLAGS) $(STD_LIB_FLAGS)
LDFLAGS := $(DEBUG_FLAGS) $(C_CXX_LD_FLAGS) -fuse-ld=lld -flto $(STD_VER_FLAGS) $(STD_LIB_FLAGS)

# Add libraries.
LDFLAGS += $(addprefix -l,$(LIBS))

# Verbose or terse output?
hide := $(if $(V),,@)
emit = $(info [$1] $2)

# Should things depend on the makefiles themselves?
MAKEFILE_DEPS := $(if $(NMD),,$(MAKEFILE_LIST))

# If they didn't set $(OBJS) explicitly, assume all .cc files make .o.
ifeq ($(OBJS),)
  OBJS := $(patsubst %.cc,%.o,$(wildcard *.cc))
endif

#------------------------------------------------------------------------------
# Test Setup

# Include the ut library.
TEST_CXXFLAGS := -I../common/ut/include/

# Define which $(OBJS) to omit from tests.  Default to main.o.
TEST_OMIT_OBJS := main.o

#------------------------------------------------------------------------------
# Google Benchmark

# Where things are.
BENCHMARK_DIR := ../common/benchmark
BENCHMARK_INCLUDE := $(BENCHMARK_DIR)/include
BENCHMARK_LIB := $(BENCHMARK_DIR)/build/src/libbenchmark.a

# Include the benchmark library.
BENCHMARK_CXXFLAGS := -I$(BENCHMARK_INCLUDE)

# We need pthread for this.
bench/bench: LDFLAGS := $(LDFLAGS) -pthread

# As per the online instructions.
$(BENCHMARK_LIB): $(MAKEFILE_DEPS)
	$(call emit,cmake,benchmark library (slow))
	$(hide) rm -rf $(BENCHMARK_DIR)/build
	$(hide) cd $(BENCHMARK_DIR) \
	  && cmake \
	       -DBENCHMARK_ENABLE_GTEST_TESTS=OFF \
	       -DBENCHMARK_ENABLE_LTO=true \
	       -DCMAKE_BUILD_TYPE=Release \
	       -DCMAKE_CXX_COMPILER=$(CXX) \
	       -DCMAKE_CXX_FLAGS='$(STD_LIB_FLAGS)' \
	       -DCMAKE_EXE_LINKER_FLAGS='$(STD_LIB_FLAGS)' \
	       -DLLVMAR_EXECUTABLE=/usr/bin/$(AR) \
	       -DLLVMNM_EXECUTABLE=/usr/bin/$(NM) \
	       -DLLVMRANLIB_EXECUTABLE=/usr/bin/$(RANLIB) \
	       -S . \
	       -B "build" \
	  >/dev/null
	+$(hide) cd $(BENCHMARK_DIR) \
	  && $(if $(V),VERBOSE=1) cmake \
	    --build "build" \
	    --config Release \
	    --target benchmark \
	  >/dev/null

#------------------------------------------------------------------------------
# Simple rules for simple programs.  Well, it used to be simple.

# How to make dependencies at the same time as compilation.
DEPFLAGS = -MT $@ -MMD -MP -MF $@.d

%.o: %.c $(MAKEFILE_DEPS)
	$(call emit,$(CC),$<)
	$(hide) rm -f $@.d
	$(hide) $(CC) $(CFLAGS) $(DEPFLAGS) -o $@ -c $<
	$(hide) touch $@.d

%.o: %.cc $(MAKEFILE_DEPS)
	$(call emit,$(CXX),$<)
	$(hide) rm -f $@.d
	$(hide) $(CXX) $(CXXFLAGS) $(DEPFLAGS) -o $@ -c $<
	$(hide) touch $@.d

prog: $(MAKEFILE_DEPS) $(OBJS)
	$(call emit,link,$@)
	$(hide) $(LD) -o $@ $(filter %.o %.a,$^) $(LDFLAGS)

# Tests need some extras.
test/%.o: CXXFLAGS := $(CXXFLAGS) $(TEST_CXXFLAGS)

# The test_main.o lives in a special place.
test/test_main.o: $(__THIS_DIR)/../test-main/test_main.cc $(MAKEFILE_DEPS)
	$(call emit,$(CXX),$@)
	$(hide) $(CXX) $(CXXFLAGS) -o $@ -c $<

# How to built the test binary.
test/tests: \
  $(MAKEFILE_DEPS) \
  $(filter-out $(TEST_OMIT_OBJS),$(OBJS)) \
  test/test_main.o \
  $(patsubst %.cc,%.o,$(wildcard test/*.cc))
	$(call emit,link,$@)
	$(hide) $(LD) -o $@ $(filter %.o %.a,$^) $(LDFLAGS)

# Benchmarks need some extras.
bench/%.o: CXXFLAGS := $(CXXFLAGS) $(BENCHMARK_CXXFLAGS)

# How to built the benchmark binary.
bench/bench: \
  $(MAKEFILE_DEPS) \
  $(BENCHMARK_LIB) \
  $(filter-out $(TEST_OMIT_OBJS),$(OBJS)) \
  $(patsubst %.cc,%.o,$(wildcard bench/*.cc))
	$(call emit,link,$@)
	$(hide) $(LD) -o $@ $(filter %.o %.a,$^) $(LDFLAGS)

# Build everything.
.PHONY: all
all: \
  prog \
  $(if $(wildcard test/),test/tests) \
  $(if $(wildcard bench/),bench/bench)

# Run the tests.
.PHONY: test
test: test/tests
	$(call emit,$@,$<)
	$(hide) ./test/tests

# Run the benchmarks.
.PHONY: bench
bench: bench/bench
	$(call emit,$@,$<)
	$(hide) ./bench/bench

# Clean everything.
.PHONY: clean
clean:
	$(call emit,$@)
	-$(hide) rm -f *.o *.d prog test/{tests,*.o,*.d} bench/{bench,*.o,*.d}

.PHONY: pristine
pristine: clean
	$(call emit,$@)
	-$(hide) rm -rf $(BENCHMARK_DIR)/build

# Include dependencies.
include $(wildcard *.d test/*.d bench/*.d)

#******************************************************************************
