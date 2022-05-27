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
CLANG_VERSION := 14

# The tools we need.
CC := clang-$(CLANG_VERSION)
CXX := clang++-$(CLANG_VERSION)
LD := clang++-$(CLANG_VERSION)
# The benchmark rule needs these :(
AR := llvm-ar-$(CLANG_VERSION)
NM := llvm-nm-$(CLANG_VERSION)
RANLIB := llvm-ranlib-$(CLANG_VERSION)

# Debug flag
DEBUG_FLAGS := -ggdb3

# Debug or release?
C_CXX_FLAGS := -Wall -Wextra -Werror $(DEBUG_FLAGS)
ifeq ($(DEBUG),)
  C_CXX_FLAGS += -O3 -ffast-math -march=native -mtune=native -DNDEBUG
endif

# Flags common to both compilers and the linker.
C_CXX_LD_FLAGS := -flto

# Sanitize?
ifneq ($(SANITIZE),)
  C_CXX_LD_FLAGS += -fsanitize=$(SANITIZE)
endif

# C++ standard version and library?
STD_VER_FLAGS := -std=c++20
STD_LIB_FLAGS := -stdlib=libc++

# Apply flags to each tool.
CFLAGS := $(C_CXX_FLAGS) $(C_CXX_LD_FLAGS)
CXXFLAGS := $(C_CXX_FLAGS) $(C_CXX_LD_FLAGS) $(STD_VER_FLAGS) $(STD_LIB_FLAGS)
LDFLAGS := $(DEBUG_FLAGS) $(C_CXX_LD_FLAGS) -fuse-ld=lld $(STD_VER_FLAGS) $(STD_LIB_FLAGS)

# Add libraries.
LDFLAGS += $(addprefix -l,$(LIBS))

# Verbose or terse output?
hide := $(if $(V),,@)
emit = $(info [$1] $2)

# Should things depend on the makefiles themselves?
MAKEFILE_DEPS := $(if $(NMD),,$(MAKEFILE_LIST))

# Find _all_ objects that we might want to compile.
OBJS := $(patsubst src/%,obj/%,$(patsubst %.cc,%.o,$(shell find src/ -name '*.cc')))

# The special test_main.o object's source lives outside of src/, so add it to
# $(OBJS) manually.
TEST_OBJS_MAIN := obj/test/test_main.o
OBJS += $(TEST_OBJS_MAIN)

# What are the dependencies of all those objects?
DEPS := $(patsubst %,%.d,$(OBJS))

# Which of those $(OBJS) are normal program objects?
PROG_OBJS := $(foreach obj,$(OBJS),$(if $(findstring /test/,$(obj)),,$(obj)))

#------------------------------------------------------------------------------
# Test Setup

# Include the ut library.
TEST_CXXFLAGS := -Icommon/ut/include/

# Which of those $(OBJS) are exclusively test objects?
TEST_OBJS := $(foreach obj,$(OBJS),$(if $(findstring /test/,$(obj)),$(obj)))

# Define which $(PROG_OBJS) to omit when we link bin/tests.
TEST_OMIT_PROG_OBJS := obj/main.o

#------------------------------------------------------------------------------
# Google Benchmark

# Where things are.
BENCHMARK_DIR := common/benchmark
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
# Object rules.

# How to make dependencies at the same time as compilation.
DEPFLAGS = -MT $@ -MMD -MP -MF $@.d

# Rules to make the parent directory of each $(OBJS) (and bin/).
$(foreach obj,$(OBJS),$(eval $(obj): | $(dir $(obj))))
$(foreach parent,bin $(sort $(dir $(OBJS))),$(eval $(parent):; mkdir -p $$@))

obj/%.o: src/%.c $(MAKEFILE_DEPS)
	$(call emit,$(CC),$<)
	$(hide) rm -f $@.d
	$(hide) $(CC) $(CFLAGS) $(DEPFLAGS) -o $@ -c $<
	$(hide) touch $@.d

obj/%.o: src/%.cc $(MAKEFILE_DEPS)
	$(call emit,$(CXX),$<)
	$(hide) rm -f $@.d
	$(hide) $(CXX) $(CXXFLAGS) $(DEPFLAGS) -o $@ -c $<
	$(hide) touch $@.d

# Test objects need to be compiled with extra flags.
$(TEST_OBJS): CXXFLAGS := $(CXXFLAGS) $(TEST_CXXFLAGS)

# The test_main.o lives in a special place.
$(TEST_OBJS_MAIN): common/test-main/test_main.cc $(MAKEFILE_DEPS)
	$(call emit,$(CXX),$<)
	$(hide) rm -f $@.d
	$(hide) $(CXX) $(CXXFLAGS) $(DEPFLAGS) -o $@ -c $<
	$(hide) touch $@.d

#------------------------------------------------------------------------------
# Binary rules.

bin/%: $(MAKEFILE_DEPS) | bin
	$(call emit,link,$@)
	$(hide) $(LD) -o $@ $(filter %.o %.a,$^) $(LDFLAGS)

# The normal program depends on the non-test $(OBJS).
bin/prog: $(PROG_OBJS)

# How to built the test binary.
bin/tests: $(filter-out $(TEST_OMIT_PROG_OBJS),$(PROG_OBJS)) $(TEST_OBJS)

# Benchmarks need some extras.
# TODO: bench/%.o: CXXFLAGS := $(CXXFLAGS) $(BENCHMARK_CXXFLAGS)

# How to built the benchmark binary.
bin/bench: \
  $(MAKEFILE_DEPS) \
  $(BENCHMARK_LIB) \
  $(PROG_OBJS) \
  $(patsubst %.cc,%.o,$(wildcard bench/*.cc))
	$(call emit,link,$@)
	$(hide) $(LD) -o $@ $(filter %.o %.a,$^) $(LDFLAGS)

#------------------------------------------------------------------------------
# Special targets.

# Build everything.
.PHONY: all
all: \
  bin/prog \
  $(if $(wildcard src/test/),bin/tests) \
  $(if $(wildcard src/bench/),bin/bench)

# Run the tests.
.PHONY: test
test: bin/tests
	$(call emit,$@,$<)
	$(hide) ./bin/tests

# Run the benchmarks.
.PHONY: bench
bench: bin/bench
	$(call emit,$@,$<)
	$(hide) ./bin/bench

# Clean everything.
.PHONY: clean
clean:
	$(call emit,$@)
	-$(hide) rm -rf bin/ obj/ 

.PHONY: pristine
pristine: clean
	$(call emit,$@)
	-$(hide) rm -rf $(BENCHMARK_DIR)/build

# Include dependencies.
include $(wildcard $(DEPS))

#******************************************************************************
