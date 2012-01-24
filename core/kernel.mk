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

ifeq ($(TARGET_PREBUILT_KERNEL_DIR),)

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

else # TARGET_PREBUILT_KERNEL_DIR

$(INSTALLED_KERNEL_TARGET): $(TARGET_PREBUILT_KERNEL_DIR)/kernel | $(ACP)
	$(copy-file-to-new-target)

$(INSTALLED_SYSTEM_MAP): $(TARGET_PREBUILT_KERNEL_DIR)/System.map | $(ACP)
	$(copy-file-to-new-target)

# Side effect: Modules placed in /system/lib/modules
$(INSTALLED_MODULES_TARGET): $(TARGET_PREBUILT_KERNEL_DIR)/kernelmod.tar.gz | $(ACP)
	$(hide) rm -rf $(TARGET_OUT)/lib/modules
	$(hide) mkdir -p $(TARGET_OUT)/lib/
	$(hide) tar -xz -C $(TARGET_OUT)/lib/ -f $<
	$(copy-file-to-new-target)

# Side effect: Firmware placed in /system/lib/firmware
$(INSTALLED_KERNELFW_TARGET): $(TARGET_PREBUILT_KERNEL_DIR)/kernelfw.tar.gz | $(ACP)
	$(hide) rm -rf $(TARGET_OUT)/lib/firmware
	$(hide) mkdir -p $(TARGET_OUT)/lib/
	$(hide) tar -xz -C $(TARGET_OUT)/lib/ -f $<
	$(copy-file-to-new-target)

endif # TARGET_PREBUILT_KERNEL_DIR

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
