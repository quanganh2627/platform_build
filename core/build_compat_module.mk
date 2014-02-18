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

# Defines how to build a Linux compat kernel module
#
# The procedure for building compat (=backported) modules is
# something of a mix between building the kernel and building
# external modules. The source exists outside the kernel tree,
# like an external module, but the module is built by invoking
# the entire kernel build, weaving the Kconfig files of
# the module into the kernel Kconfig tree.
#
# The config stage requires the kernel .config file to be
# present, in the kernel's output tree.
#
# The build stage only depends on its config stage
# The install stage depends on the kernel and external modules
# being installed. It has the same parallellism issue as
# the external modules; if more than one module is
# run in parallell, they will try to write the same
# modules.dep file.
#
# Compat modules also need to rename some of the installed
# .ko files, with subsequent need to massage the modules.dep
# and modules.alias files.
#
# The make variables set by the caller are:
#  LOCAL_MODULE - name of the module
#    Used for defining unique make rules and useful printouts
#  LOCAL_PATH
#    Path to module, relative to root build dir
#  LOCAL_KERNEL_COMPAT_DEFCONFIG
#    Name of the module-local defconfig file used to configure
#    the compat build. The full name passed to the kernel makefile
#    is defconfig-$(LOCAL_KERNEL_COMPAT_DEFCONFIG)
#  COMPAT_PRIVATE_$(LOCAL_MODULE)_PREINSTALL:
#  COMPAT_PRIVATE_$(LOCAL_MODULE)_POSTINSTALL:
#    Defines a set of commands that will be run before/after the 
#    module is installed.
#    This macro should be defined using define/endef, to ensure
#    that it uses deferred evaluation. And yes, the macro may
#    contain multiple lines.
#    Two parameters may be used inside the commands
#    $(1): Path to where module is installed
#    $(2): Path to where the module is built from 
#
# To include the module in the build, the module name must also
# be added to PRODUCT_PACKAGES in one of the product definition
# files (BoardConfig.mk, product.mk, etc).


LOCAL_MODULE_CLASS := COMPAT_KERNEL_MODULE
# Prevent Android from defining install rules. For compat modules
# the installation is handled by the Linux build system
LOCAL_UNINSTALLABLE_MODULE := true
# Ensure that LOCAL_BUILT_MODULE defines a file, not a directory.
# This is needed to be able to execute 'make <module>'
# from the command line, as base_rules.mk defines a dependency
# between LOCAL_MODULE and LOCAL_BUILT_MODULE.
LOCAL_BUILT_MODULE_STEM := .sentinel

include build/core/base_rules.mk

compat_mod_file := $(LOCAL_BUILT_MODULE)
compat_cfg_file := $(dir $(LOCAL_BUILT_MODULE))/.config

# The compat module .config is based on the kernel config.
# The .config file is only updated if actually changed. This is done to
# prevent backport-include/backport/autoconf.h from being rebuilt each time,
# as that will force a rebuild of all files in the compat module.
# (The normal kernel behavior is to filter out dependencies to autoconf.h and instead
#  use dependencies to files created in include/config, one for each config option.
#  Unfortunately this does not work for the compat module's version of autoconf.h.)
$(compat_cfg_file): PRIVATE_KERNEL_DEFCONFIG := $(LOCAL_KERNEL_COMPAT_DEFCONFIG)
$(compat_cfg_file): PRIVATE_MODULE := $(LOCAL_MODULE)
$(compat_cfg_file): private_src_dir:=$(LOCAL_PATH)
$(compat_cfg_file): $(PRODUCT_KERNEL_OUTPUT)/.config FORCE | $(ACP)
	@echo Configuring kernel compat module $(PRIVATE_MODULE) with defconfig-$(PRIVATE_KERNEL_DEFCONFIG)
	$(hide) mkdir -p $(@D)
	$(hide) cp -ru $(private_src_dir)/. $(@D)/
	$(hide) find $(@D) -name Android.mk | xargs rm -f
	$(mk_kernel_base) -C $(@D) KLIB_BUILD=$(PRODUCT_KERNEL_OUTPUT) KCONFIG_CONFIG=$(@F).tmp defconfig-$(PRIVATE_KERNEL_DEFCONFIG)
	$(hide) cmp --quiet $@.tmp $@ || { $(ACP) -f $@.tmp $@ && echo ".config changed, updating."; }


# Define build of this module here, separately,
# to ensure it gets the appropriate config file.
$(compat_mod_file): PRIVATE_MODULE := $(LOCAL_MODULE)
# Testing a few parallel builds indicate that the kernel needs to be built before building
# compat modules.
$(compat_mod_file): $(INSTALLED_KERNEL_TARGET)
$(compat_mod_file): $(compat_cfg_file) FORCE
	@echo Building kernel compat module $(PRIVATE_MODULE) in $(@D)
	$(mk_kernel_base) -C $(@D) KLIB_BUILD=$(PRODUCT_KERNEL_OUTPUT)
	$(hide) touch $@


# Define a couple of utility make targets for debugging
.PHONY: config_$(LOCAL_MODULE) build_$(LOCAL_MODULE)
config_$(LOCAL_MODULE): $(compat_cfg_file)
build_$(LOCAL_MODULE): $(compat_mod_file)

# Add module to list of modules to install. This must
# be done in one place in a for loop, as the
# install modifies common files.
EXTERNAL_KERNEL_COMPAT_MODULES_TO_INSTALL += $(LOCAL_MODULE)


gpl_license_file := $(call find-parent-file,$(LOCAL_PATH),MODULE_LICENSE*_GPL* MODULE_LICENSE*_MPL* MODULE_LICENSE*_LGPL*)
ifneq ($(gpl_license_file),)
  LOCAL_MODULE_TAGS += gnu
  ALL_GPL_KERNEL_MODULE_LICENSE_FILES := $(sort $(ALL_GPL_KERNEL_MODULE_LICENSE_FILES) $(gpl_license_file))
endif
