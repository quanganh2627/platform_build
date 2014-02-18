#
# Copyright (C) 2013 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


# Defines how to build a Linux external kernel module

LOCAL_MODULE := $(strip $(LOCAL_MODULE))

# The source tree currently has at least one kernel tree which contains
# symlinks to external drivers. This leads to the Android.mk
# files in those directories being read more than once. Thus an
# exclusion guard is needed.
ifeq ($($(LOCAL_MODULE)_EXCLUSION_GUARD),)
$(LOCAL_MODULE)_EXCLUSION_GUARD := true

# Contains flags sent to the C pre-preprocessor when building the module.
# Used to add definitions and header file paths.
PRIVATE_KCPPFLAGS :=
PRIVATE_CONFIG_FLAGS :=

LOCAL_MODULE_CLASS := EXTERNAL_KERNEL_MODULE
# Prevent build system from defining standard install rules
LOCAL_UNINSTALLABLE_MODULE := true
LOCAL_BUILT_MODULE_STEM := .sentinel

include build/core/base_rules.mk

ext_mod_file := $(LOCAL_BUILT_MODULE)

ifneq ($(firstword $(LOCAL_KCONFIG_OVERRIDE_FILES)),)
# As the module has some extra CONFIG parameters, these must
# be made available to the module's Makefile and C code

local_config_files := $(addprefix $(LOCAL_MODULE_PATH)/,$(LOCAL_KCONFIG_OVERRIDE_FILES))
local_config_files_full_path := $(realpath $(local_config_files))
ifneq ($(words $(local_config_files)),$(words $(local_config_files_full_path)))
$(info Error building external module $(LOCAL_MODULE): some of the config files specified do not exist)
$(info Specified files: $(local_config_files))
$(info Found files: $(local_config_files_full_path))
$(error exiting...)
endif

# Extract the extra CONFIG parameters from their file(s) to a make variable
PRIVATE_CONFIG_FLAGS := $(shell cat $(local_config_files_full_path))

# Create a target-specific version of PRIVATE_CONFIG_FLAGS,
# as extmods included after this one will overwrite the global version.
$(ext_mod_file): PRIVATE_CONFIG_FLAGS := $(PRIVATE_CONFIG_FLAGS)

# Make the extra CONFIG parameters available to the C source code
PRIVATE_KCPPFLAGS += $(addprefix -D,$(PRIVATE_CONFIG_FLAGS))

endif

ifneq ($(LOCAL_C_INCLUDES),)
PRIVATE_KCPPFLAGS += $(addprefix -I,$(abspath $(LOCAL_C_INCLUDES)))
endif
ifeq ($(PRIVATE_KCPPFLAGS),)
$(ext_mod_file): PRIVATE_KERNEL_MODULE_CPPFLAGS :=
else
$(ext_mod_file): PRIVATE_KERNEL_MODULE_CPPFLAGS := KCPPFLAGS="$(PRIVATE_KCPPFLAGS)"
endif

# Define the module's build rule.
# FIXME Workaround due to lack of simultaneous support of M= and O=; copy the
# source into an intermediate directory and compile it there, preserving
# timestamps so code is only rebuilt if it changes.
$(ext_mod_file): private_src_dir:=$(LOCAL_MODULE_PATH)
$(ext_mod_file): $(INSTALLED_KERNEL_TARGET) FORCE | $(ACP)
	@echo Building external kernel module in $(@D)
	$(hide) mkdir -p $(@D)
	$(hide) $(ACP) -rtf $(private_src_dir)/* $(@D)
	$(hide) find $(@D) -name Android.mk | xargs rm -f
	$(mk_kernel) M=$(CURDIR)/$(@D) $(PRIVATE_KERNEL_MODULE_CPPFLAGS) $(PRIVATE_CONFIG_FLAGS) modules
	$(hide) touch $@

# Add module to list of modules to install. This must
# be done in one place in a for loop, as the
# install modifies common files.
EXTERNAL_KERNEL_MODULES_TO_INSTALL += $(LOCAL_MODULE)

gpl_license_file := $(call find-parent-file,$(LOCAL_PATH),MODULE_LICENSE*_GPL* MODULE_LICENSE*_MPL* MODULE_LICENSE*_LGPL*)
ifneq ($(gpl_license_file),)
  LOCAL_MODULE_TAGS += gnu
  ALL_GPL_KERNEL_MODULE_LICENSE_FILES := $(sort $(ALL_GPL_KERNEL_MODULE_LICENSE_FILES) $(gpl_license_file))
endif

endif
