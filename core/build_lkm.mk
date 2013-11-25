# Defines how to build a Linux external kernel module


# The source tree currently has at least one kernel tree which contains
# symlinks to external drivers. This leads to the Android.mk
# files in those directories being read more than once. Thus an
# exclusion guard is needed.
ifeq ($($(LOCAL_MODULE)_EXCLUSION_GUARD),)
$(LOCAL_MODULE)_EXCLUSION_GUARD := true

ext_mod_dir := $(PRODUCT_KERNEL_OUTPUT)/extmods/$(LOCAL_MODULE_PATH)
ext_mod_file := $(ext_mod_dir)/.sentinel

ifneq ($(firstword $(LOCAL_KCONFIG_OVERRIDE_FILES)),)
# As the module has some extra CONFIG parameters, a new
# .config file must be created and used during build.

local_config_files := $(addprefix $(LOCAL_MODULE_PATH)/,$(LOCAL_KCONFIG_OVERRIDE_FILES))

ext_cfg_file :=	$(PRODUCT_KERNEL_OUTPUT)/extmods/$(LOCAL_MODULE_PATH)/.config

$(ext_cfg_file): $(local_config_files)
	$(hide) mkdir -p $(@D)
	$(hide) cat $^ > $@

$(ext_mod_file): $(ext_cfg_file)
$(ext_mod_file): PRIVATE_CONFIG_PATH:=KCONFIG_CONFIG=$(ext_cfg_file)

else
# Use the unmodified kernel config file
$(ext_mod_file): PRIVATE_CONFIG_PATH:=
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
	$(mk_kernel) M=$(@D)   modules
	touch $@

# Add module to list of modules to install. This must
# be done in one place in a for loop, as the
# install modifies common files.
EXTERNAL_KERNEL_MODULES_TO_INSTALL += $(ext_mod_file)

endif
