#
# Copyright (C) 2009 The Android-x86 Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#

ifneq ($(strip $(TARGET_NO_KERNEL)),true)

# use_prebuilt_kernel is the variable used for determining if we will be using
# prebuilt kernel components or build kernel from source, in the code that
# follows below.
use_prebuilt_kernel :=

# kernel_prebuilt_* variables will hold the full paths to the kernel artifacts,
# if they exist, otherwise they will have empty values. The exact file name is
# being determined by keeping the file name base of the corresponding targets,
# then using the wildcard function to actually see if these files exist in the
# TARGET_PREBUILT_KERNEL_DIR directory, which is usually set in a
# BoardConfig.mk file.
kernel_prebuilt_image  := $(wildcard $(TARGET_PREBUILT_KERNEL_DIR)/$(notdir $(INSTALLED_KERNEL_TARGET)))
kernel_prebuilt_sysmap := $(wildcard $(TARGET_PREBUILT_KERNEL_DIR)/$(notdir $(INSTALLED_SYSTEM_MAP)))
kernel_prebuilt_mods   := $(wildcard $(TARGET_PREBUILT_KERNEL_DIR)/$(notdir $(INSTALLED_MODULES_TARGET)))
kernel_prebuilt_fw     := $(wildcard $(TARGET_PREBUILT_KERNEL_DIR)/$(notdir $(INSTALLED_KERNELFW_TARGET)))

# The kernel image and the System.map files are mandatory for considering that
# we have a full prebuilt kernel. So, both the above set variables are actually
# pointing to existing files, then we can consider using prebuilt kernels.
ifneq ($(and $(kernel_prebuilt_image),$(kernel_prebuilt_sysmap)),)
$(info KERNEL: Kernel prebuilt image and system map are available)

# We have all the ingredients necessary for prebuilt kernels, but we make sure
# that the user didn't set the BUILD_KERNEL variable, in which case we will be
# forcing the kernel build from source.
ifeq ($(BUILD_KERNEL),)
$(info KERNEL: BUILD_KERNEL is not set, will not force kernel source build)

# Under this condition, we set use_prebuilt_kernel to true, which means that we
# will be using prebuilt kernels below.
use_prebuilt_kernel := true
$(info KERNEL: Will use prebuilt kernel)
else # BUILD_KERNEL != null
# This is the case where users force kernel build from source.
$(info KERNEL: BUILD_KERNEL is set to a non-null value. Will not use prebuilt kernels)
endif
else # kernel prebuilt mandatory ingredients are not available
$(info KERNEL: Kernel prebuilt image and/or system map are not available. Will not use prebuilt kernels)
endif

ifneq ($(use_prebuilt_kernel),true)

$(info Building kernel from source)
ifeq ($(TARGET_ARCH),x86)
KERNEL_TARGET := bzImage
TARGET_KERNEL_CONFIG ?= android-x86_defconfig
endif
ifeq ($(TARGET_ARCH),arm)
KERNEL_TARGET := zImage
TARGET_KERNEL_CONFIG ?= goldfish_defconfig
endif

TARGET_KERNEL_SOURCE ?= kernel
TARGET_KERNEL_EXTRA_CFLAGS = -fno-pic


KBUILD_OUTPUT := $(CURDIR)/$(TARGET_OUT_INTERMEDIATES)/kernel

# Leading "+" gives child Make access to the jobserver.
# gzip hack necessary to get the kernel to compress the
# bzImage with minigzip instead of host gzip, so that the
# newer verion of deflate algorithn inside zlib is used.
# This is needed by OTA applypatch, which makes much larger
# binary diffs of compressed data if the deflate versions
# are out of alignment.
mk_kernel := + $(hide) PATH=$(CURDIR)/build/tools/gzip_hack/:$(PATH) $(MAKE) -C $(TARGET_KERNEL_SOURCE)  O=$(KBUILD_OUTPUT) ARCH=$(TARGET_ARCH) $(if $(SHOW_COMMANDS),V=1) KCFLAGS=$(TARGET_KERNEL_EXTRA_CFLAGS)
ifneq ($(TARGET_TOOLS_PREFIX),)
ifneq ($(USE_CCACHE),)
mk_kernel += CROSS_COMPILE="$(CCACHE_BIN) $(CURDIR)/$(TARGET_TOOLS_PREFIX)"
else
mk_kernel += CROSS_COMPILE=$(CURDIR)/$(TARGET_TOOLS_PREFIX)
endif
endif

ifneq ($(wildcard $(TARGET_KERNEL_SOURCE)/arch/$(TARGET_ARCH)/configs/$(TARGET_KERNEL_CONFIG)),)
KERNEL_CONFIG_FILE := $(TARGET_KERNEL_SOURCE)/arch/$(TARGET_ARCH)/configs/$(TARGET_KERNEL_CONFIG)
else
KERNEL_CONFIG_FILE := $(TARGET_KERNEL_CONFIG)
endif

MOD_ENABLED = $(shell grep ^CONFIG_MODULES=y $(KERNEL_CONFIG_FILE))
FIRMWARE_ENABLED = $(shell grep ^CONFIG_FIRMWARE_IN_KERNEL=y $(KERNEL_CONFIG_FILE))

# I understand Android build system discourage to use submake,
# but I don't want to write a complex Android.mk to build kernel.
# This is the simplest way I can think.
KERNEL_DOTCONFIG_FILE := $(KBUILD_OUTPUT)/.config
$(KERNEL_DOTCONFIG_FILE): $(KERNEL_CONFIG_FILE) | $(ACP)
	$(copy-file-to-new-target)

BUILT_KERNEL_TARGET := $(KBUILD_OUTPUT)/arch/$(TARGET_ARCH)/boot/$(KERNEL_TARGET)

# Declared .PHONY to force a rebuild each time. We can't tell if the kernel
# sources have changed from this context
.PHONY : $(INSTALLED_KERNEL_TARGET)

$(INSTALLED_KERNEL_TARGET): $(KERNEL_DOTCONFIG_FILE) $(MINIGZIP) | $(ACP)
	$(hide) rm -f $(KBUILD_OUTPUT)/.config.old
	$(mk_kernel) oldnoconfig
	$(mk_kernel) $(KERNEL_TARGET) $(if $(MOD_ENABLED),modules)
	$(hide) $(ACP) -fp $(BUILT_KERNEL_TARGET) $@

$(INSTALLED_SYSTEM_MAP): $(INSTALLED_KERNEL_TARGET) | $(ACP)
	$(hide) $(ACP) $(KBUILD_OUTPUT)/System.map $@

# FIXME Workaround due to lack of simultaneous support of M= and O=; copy the
# source into an intermediate directory and compile it there, preserving
# timestamps so code is only rebuilt if it changes.
# Extra newline intentional to prevent calling foreach from concatenating
# into a single line
define make-ext-module
	$(hide) mkdir -p $(KBUILD_OUTPUT)/extmods/$(1)
	$(hide) $(ACP) -rtf $(1)/* $(KBUILD_OUTPUT)/extmods/$(1)
	$(mk_kernel) M=$(KBUILD_OUTPUT)/extmods/$(1) INSTALL_MOD_PATH=$(CURDIR)/$(2) modules
	$(mk_kernel) M=$(KBUILD_OUTPUT)/extmods/$(1) INSTALL_MOD_PATH=$(CURDIR)/$(2) modules_install

endef

define make-modules
	$(mk_kernel) INSTALL_MOD_PATH=$(CURDIR)/$(TARGET_OUT) modules_install
	$(foreach item,$(EXTERNAL_KERNEL_MODULES),$(call make-ext-module,$(item),$(TARGET_OUT)))
	$(hide) rm -f $(TARGET_OUT)/lib/modules/*/{build,source}
	$(hide) cd $(TARGET_OUT)/lib/modules && find -type f -print0 | xargs -t -0 -I{} mv {} .
endef

# Side effect: Modules placed in /system/lib/modules
$(INSTALLED_MODULES_TARGET): $(INSTALLED_KERNEL_TARGET) $(MINIGZIP) | $(ACP)
	$(hide) rm -rf $(TARGET_OUT)/lib/modules
	$(hide) mkdir -p $(TARGET_OUT)/lib/modules
	$(if $(MOD_ENABLED),$(call make-modules))
	$(hide) tar -cz -C $(TARGET_OUT)/lib/ -f $(CURDIR)/$@ modules

# Side effect: Firmware placed in /system/lib/firmware
$(INSTALLED_KERNELFW_TARGET): $(INSTALLED_KERNEL_TARGET) $(INSTALLED_MODULES_TARGET) $(MINIGZIP)
	$(hide) rm -rf $(TARGET_OUT)/lib/firmware
	$(hide) mkdir -p $(TARGET_OUT)/lib/firmware
	$(if $(FIRMWARE_ENABLED),$(mk_kernel) INSTALL_MOD_PATH=$(CURDIR)/$(TARGET_OUT) firmware_install)
	$(hide) tar -cz -C $(TARGET_OUT)/lib/ -f $(CURDIR)/$@ firmware

PREBUILT-PROJECT-kernel: \
		$(INSTALLED_KERNEL_TARGET) \
		$(INSTALLED_SYSTEM_MAP) \
		$(INSTALLED_MODULES_TARGET) \
		$(INSTALLED_KERNELFW_TARGET)
		$(hide) rm -rf out/prebuilts/kernel/$(TARGET_PREBUILT_TAG)/kernel/$(CUSTOM_BOARD)
		$(hide) mkdir -p out/prebuilts/kernel/$(TARGET_PREBUILT_TAG)/kernel/$(CUSTOM_BOARD)
		$(hide) $(ACP) -fp $^ out/prebuilts/kernel/$(TARGET_PREBUILT_TAG)/kernel/$(CUSTOM_BOARD)

else # use_prebuilt_kernel = true

$(info Using prebuilt kernel components)
$(INSTALLED_KERNEL_TARGET): $(kernel_prebuilt_image) | $(ACP)
	$(copy-file-to-new-target)

$(INSTALLED_SYSTEM_MAP): $(kernel_prebuilt_sysmap) | $(ACP)
	$(copy-file-to-new-target)

# Test if we have a kernel modules archive in the prebuilts area
ifneq ($(kernel_prebuilt_mods),)
# Side effect: Modules placed in /system/lib/modules
$(INSTALLED_MODULES_TARGET): $(kernel_prebuilt_mods) | $(ACP)
	$(hide) rm -rf $(TARGET_OUT)/lib/modules
	$(hide) mkdir -p $(TARGET_OUT)/lib/
	$(hide) tar -xz -C $(TARGET_OUT)/lib/ -f $<
	$(copy-file-to-new-target)
else # kernel_prebuilt_mods is empty
# We empty the modules target
INSTALLED_MODULES_TARGET :=
endif

# Test if we have a kernel firmware archive in the prebuilts area
ifneq ($(kernel_prebuilt_fw),)
# Side effect: Firmware placed in /system/lib/firmware
$(INSTALLED_KERNELFW_TARGET): $(kernel_prebuilt_fw) | $(ACP)
	$(hide) rm -rf $(TARGET_OUT)/lib/firmware
	$(hide) mkdir -p $(TARGET_OUT)/lib/
	$(hide) tar -xz -C $(TARGET_OUT)/lib/ -f $<
	$(copy-file-to-new-target)
else # kernel_prebuilt_fw is empty
# We empty the firmware target
INSTALLED_KERNELFW_TARGET :=
endif

# It makes no sense to use the automatic prebuilts machinery target, if we have
# used the prebuilt kernel. It would mean re-copying the same files in the
# upstream repository, from where they came initially. So, we return an error
# if anyone is trying a "make PREBUILT-*" target.
PREBUILT-PROJECT-kernel:
	$(error Automatic prebuilts for kernel are available only when building kernel from source)

endif # use_prebuilt_kernel

use_prebuilt_kernel :=

.PHONY: kernel
kernel: $(INSTALLED_KERNEL_TARGET) \
		$(INSTALLED_SYSTEM_MAP) \
		$(INSTALLED_MODULES_TARGET) \
		$(INSTALLED_KERNELFW_TARGET)

# FIXME THIS DOESN'T WORK
installclean: FILES += $(INSTALLED_KERNEL_TARGET) \
		$(INSTALLED_SYSTEM_MAP) \
		$(INSTALLED_MODULES_TARGET) \
		$(INSTALLED_KERNELFW_TARGET)

endif # TARGET_NO_KERNEL
