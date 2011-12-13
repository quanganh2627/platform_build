#
# Copyright (C) 2009 The Android-x86 Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#

ifeq ($(TARGET_PREBUILT_KERNEL),)

ifeq ($(TARGET_ARCH),x86)
KERNEL_TARGET := bzImage
TARGET_KERNEL_CONFIG ?= android-x86_defconfig
endif
ifeq ($(TARGET_ARCH),arm)
KERNEL_TARGET := zImage
TARGET_KERNEL_CONFIG ?= goldfish_defconfig
endif

TARGET_KERNEL_SOURCE ?= kernel

KBUILD_OUTPUT := $(CURDIR)/$(TARGET_OUT_INTERMEDIATES)/kernel

# Leading "+" somehow causes sub-make to inherit -j passed to parent Make
mk_kernel := + $(hide) $(MAKE) -C $(TARGET_KERNEL_SOURCE)  O=$(KBUILD_OUTPUT) ARCH=$(TARGET_ARCH) $(if $(SHOW_COMMANDS),V=1)
ifneq ($(TARGET_TOOLS_PREFIX),)
ifneq ($(USE_CCACHE),)
ccache := prebuilt/$(HOST_PREBUILT_TAG)/ccache/ccache
mk_kernel += CROSS_COMPILE="$(CURDIR)/$(ccache) $(CURDIR)/$(TARGET_TOOLS_PREFIX)"
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

# Extra newline intentional to prevent calling foreach from concatenating
# into a single line delimited by '+'
define make-module-item
	mkdir -p $(KBUILD_OUTPUT)/extmods/$(1)
	$(ACP) -rtf $(1)/* $(KBUILD_OUTPUT)/extmods/$(1)
	$(mk_kernel) M=$(KBUILD_OUTPUT)/extmods/$(1) INSTALL_MOD_PATH=$(CURDIR)/$(TARGET_OUT) modules
	$(mk_kernel) M=$(KBUILD_OUTPUT)/extmods/$(1) INSTALL_MOD_PATH=$(CURDIR)/$(TARGET_OUT) modules_install

endef

$(INSTALLED_KERNEL_TARGET): $(KERNEL_DOTCONFIG_FILE)
	$(mk_kernel) oldnoconfig
	$(mk_kernel) $(KERNEL_TARGET) $(if $(MOD_ENABLED),modules)
	$(hide) $(ACP) -fp $(BUILT_KERNEL_TARGET) $@
ifdef TARGET_PREBUILT_MODULES
	$(hide) $(ACP) -r $(TARGET_PREBUILT_MODULES) $(TARGET_OUT)/lib
else
	$(hide) rm -rf $(TARGET_OUT)/lib/modules
	$(if $(MOD_ENABLED),$(mk_kernel) INSTALL_MOD_PATH=$(CURDIR)/$(TARGET_OUT) modules_install)
	$(foreach item,$(EXTERNAL_KERNEL_MODULES),$(call make-module-item,$(item)))
	$(hide) rm -f $(TARGET_OUT)/lib/modules/*/{build,source}
	$(hide) cd $(TARGET_OUT)/lib/modules && find -type f | xargs ln -t .
endif
	$(if $(FIRMWARE_ENABLED),$(mk_kernel) INSTALL_MOD_PATH=$(CURDIR)/$(TARGET_OUT) firmware_install)

installclean: FILES += $(KBUILD_OUTPUT) $(INSTALLED_KERNEL_TARGET)

TARGET_PREBUILT_KERNEL  := $(INSTALLED_KERNEL_TARGET)

.PHONY: kernel
kernel: $(TARGET_PREBUILT_KERNEL)

else

$(INSTALLED_KERNEL_TARGET): $(TARGET_PREBUILT_KERNEL) | $(ACP)
	$(copy-file-to-new-target)

endif # TARGET_PREBUILT_KERNEL
