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

ext_mod_dir := $(PRODUCT_KERNEL_OUTPUT)/extmods/$(LOCAL_MODULE)
ext_mod_file := $(ext_mod_dir)/.sentinel

ifneq ($(firstword $(LOCAL_KCONFIG_OVERRIDE_FILES)),)
# As the module has some extra CONFIG parameters, a new
# .config file must be created and used during build.

local_config_files := $(addprefix $(LOCAL_MODULE_PATH)/,$(LOCAL_KCONFIG_OVERRIDE_FILES))

ext_cfg_file :=	$(ext_mod_dir)/.config

$(ext_cfg_file): $(local_config_files)
	$(hide) mkdir -p $(@D)
	$(hide) cat $^ > $@

$(ext_mod_file): $(ext_cfg_file)
$(ext_mod_file): PRIVATE_CONFIG_PATH:=KCONFIG_CONFIG=$(ext_cfg_file)

else
# Use the unmodified kernel config file
$(ext_mod_file): PRIVATE_CONFIG_PATH:=
endif

ifeq ($(LOCAL_C_INCLUDES),)
$(ext_mod_file): PRIVATE_KERNEL_MODULE_INCLUDES :=
else
$(ext_mod_file): PRIVATE_KERNEL_MODULE_INCLUDES := KCPPFLAGS="$(addprefix -I,$(abspath $(LOCAL_C_INCLUDES)))"
endif

# Define build of this module here, separately,
# to ensure it gets the appropriate config file.
# FIXME Workaround due to lack of simultaneous support of M= and O=; copy the
# source into an intermediate directory and compile it there, preserving
# timestamps so code is only rebuilt if it changes.
$(ext_mod_file): private_src_dir:=$(LOCAL_MODULE_PATH)
$(ext_mod_file): $(INSTALLED_KERNEL_TARGET) FORCE
	$(hide) mkdir -p $(@D)
	$(hide) $(ACP) -rtf $(private_src_dir)/* $(@D)
	$(mk_kernel) M=$(@D) $(PRIVATE_KERNEL_MODULE_INCLUDES) modules
	touch $@

# Add module to list of modules to install. This must
# be done in one place in a for loop, as the
# install modifies common files.
EXTERNAL_KERNEL_MODULES_TO_INSTALL += $(ext_mod_file)

gpl_license_file := $(call find-parent-file,$(LOCAL_PATH),MODULE_LICENSE*_GPL* MODULE_LICENSE*_MPL* MODULE_LICENSE*_LGPL*)
ifneq ($(gpl_license_file),)
  LOCAL_MODULE_TAGS += gnu
  ALL_GPL_KERNEL_MODULE_LICENSE_FILES := $(sort $(ALL_GPL_KERNEL_MODULE_LICENSE_FILES) $(gpl_license_file))
endif

endif
