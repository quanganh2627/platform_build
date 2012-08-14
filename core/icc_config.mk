# Forces the following modules to be compiled with Intel* compiler independent of DEFAULT_COMPILER
ICC_MODULES     :=
# Forces the following modules to be compiled with GNU* compiler independent of DEFAULT_COMPILER
GCC_MODULES     :=
# Modules that are compiled with -ipo if configured to be compiled with Intel compiler
ICC_IPO_MODULES := libc_common libc_nomalloc libc libcutils liblog
ICC_IPO_MODULES += libdvm dexdump dvz dalvikvm
ICC_IPO_MODULES += libxslt libxml2 libskia libskiagpu
ICC_IPO_MODULES += libwebcore libv8 libhyphenation
ICC_IPO_MODULES += libva_videoencoder libva_videodecoder libmixvideo libmixcommon libmfldadvci
ICC_IPO_MODULES += libSh3a libmixvbp libasfparser libft2 libicui18n libicuuc
ICC_IPO_MODULES += libfdlibm libdex libpvr2d
# Enable source-code modifications for improved vectorization in libskia and libskiagpu
# Set ENABLE_ICC_MOD to empty string to disable modifications
ENABLE_ICC_MOD  := true

# Modules that require -ffreestanding to avoid dependence on libintlc
# Applies only to modules that are configured to be built with icc
ICC_FREESTANDING_MODULES := libc_common libc_nomalloc libc libc_malloc_debug_leak libc_malloc_debug_qemu libbionic_ssp libc_netbsd
ICC_FREESTANDING_MODULES += libdl libm linker update_osip libosip

TARGET_ICC_TOOLS_PREFIX := \
	prebuilts/PRIVATE/icc/linux-x86/x86/x86-android-linux-12.1/bin/

TARGET_ICC     := $(abspath $(TARGET_ICC_TOOLS_PREFIX)icc)
TARGET_ICPC    := $(abspath $(TARGET_ICC_TOOLS_PREFIX)icpc)
TARGET_XIAR    := $(abspath $(TARGET_ICC_TOOLS_PREFIX)xiar)
TARGET_XILD    := $(abspath $(TARGET_ICC_TOOLS_PREFIX)xild)

export ANDROID_GNU_X86_TOOLCHAIN:=$(abspath $(dir $(TARGET_TOOLS_PREFIX)))/../
export ANDROID_SYSROOT:=

ifeq ($(strip $(DEFAULT_COMPILER)),icc)
  intel-target-need-intel-libraries:=true
  define intel-target-use-icc
    $(if $(filter $(strip $1),$(GCC_MODULES)),,$(if $(strip $(LOCAL_CLANG)),,true))
  endef
else
  ifneq ($(strip $(ICC_MODULES)),)
    intel-target-need-intel-libraries:=true
  else
    intel-target-need-intel-libraries:=
  endif
  define intel-target-use-icc
    $(if $(filter $(strip $1),$(ICC_MODULES)),true)
  endef
endif

define intel-target-cc
  $(if $(strip $(call intel-target-use-icc,$1)),$(TARGET_ICC),$(abspath $(TARGET_CC)))
endef

define intel-target-cxx
  $(if $(strip $(call intel-target-use-icc,$1)),$(TARGET_ICPC),$(abspath $(TARGET_CXX)))
endef

define intel-target-ipo-enable
  $(and $(strip $(call intel-target-use-icc,$1)),$(filter $(strip $1),$(ICC_IPO_MODULES)))
endef

define intel-target-freestanding-enable
  $(and $(strip $(call intel-target-use-icc,$1)),$(filter $(strip $1),$(ICC_FREESTANDING_MODULES)))
endef

ifneq ($(call intel-target-need-intel-libraries),)
  ICC_COMPILER_LIBRARIES := libsvml libimf libintlc
  TARGET_DEFAULT_SYSTEM_SHARED_LIBRARIES := $(ICC_COMPILER_LIBRARIES) $(TARGET_DEFAULT_SYSTEM_SHARED_LIBRARIES)
  TARGET_AR            := $(TARGET_XIAR)
  TARGET_LD            := $(TARGET_XILD)
endif

define do-icc-flags-subst
  $(1) := $(subst $(2),$(3),$($(1)))
endef

define icc-flags-subst
  $(eval $(call do-icc-flags-subst,$(1),$(2),$(3)))
endef

TARGET_GLOBAL_ICC_CFLAGS := $(TARGET_GLOBAL_CFLAGS)
TARGET_GLOBAL_ICC_CFLAGS += -no-prec-div
TARGET_GLOBAL_ICC_CFLAGS += -fno-builtin-memset -fno-builtin-strcmp -fno-builtin-strlen -fno-builtin-strchr
TARGET_GLOBAL_ICC_CFLAGS += -fno-builtin-cos -fno-builtin-sin -fno-builtin-tan
TARGET_GLOBAL_ICC_CFLAGS += -restrict -i_nopreempt -Bsymbolic
TARGET_GLOBAL_ICC_CFLAGS += -diag-disable 144,556,279,803,2646,589,83,290,180,1875 #-diag-error 592,117,1101
TARGET_GLOBAL_ICC_CFLAGS += -g1
TARGET_GLOBAL_ICC_CFLAGS += -D__GCC_HAVE_SYNC_COMPARE_AND_SWAP_4

$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-mstackrealign,-falign-stack=assume-4-byte)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-O2,-O3)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-march=atom,-xSSSE3_ATOM)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-msse3,)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-mfpmath=sse,)
# icc generates pic by default.
# TARGET_GLOBAL_CFLAGS are passed to linker and override -fno-pic for link-time optimization in webkit
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-fPIC,)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-fPIE,)
# bionic is the only libc configuration of Intel* compiler for Android*
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-mbionic,)
# Unsupported options
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-fno-inline-functions-called-once,)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-funswitch-loops,)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CFLAGS,-funwind-tables,)

TARGET_GLOBAL_ICC_CPPFLAGS := $(TARGET_GLOBAL_CPPFLAGS)
$(call icc-flags-subst,TARGET_GLOBAL_ICC_CPPFLAGS,-fno-use-cxa-atexit,)
TARGET_GLOBAL_ICC_CPPFLAGS += -Qoption,c,--use_atexit

#Called from core/binary.mk
define do-icc-flags
  $(call icc-flags-subst,LOCAL_CFLAGS,-march=atom,-xSSSE3_ATOM)
  $(call icc-flags-subst,LOCAL_CFLAGS,-mtune=atom,-xSSSE3_ATOM)
  $(call icc-flags-subst,LOCAL_CFLAGS,-msse3,-xSSSE3_ATOM)
  ifneq ($(strip $(call intel-target-freestanding-enable,$(LOCAL_MODULE))),)
    LOCAL_CFLAGS   += -ffreestanding
  endif
  ifneq ($(strip $(call intel-target-ipo-enable,$(LOCAL_MODULE))),)
    LOCAL_CFLAGS   += -ipo -g0
    LOCAL_LDFLAGS  += -ipo4
  endif
  ifneq ($(strip $(ENABLE_ICC_MOD)),)
    ifeq ($(strip $(LOCAL_MODULE)),libskia)
      LOCAL_CFLAGS += -DICC_SKIA
    endif
    ifeq ($(strip $(LOCAL_MODULE)),libskiagpu)
      LOCAL_CFLAGS += -DICC_SKIA
    endif
  endif
  ifeq ($(strip $(LOCAL_MODULE)),libwebcore)
    LOCAL_CFLAGS += -g0
  endif
endef

#Called from core/binary.mk
define do-icc-libs
  ifneq ($(filter libpng,$(LOCAL_STATIC_LIBRARIES)),)
    LOCAL_STATIC_LIBRARIES += libimf_s
  endif
  ifneq ($(filter libc,$(LOCAL_SYSTEM_SHARED_LIBRARIES)),)
    ifeq ($(filter libintlc,$(LOCAL_SYSTEM_SHARED_LIBRARIES)),)
      ifeq ($(strip $(call intel-target-freestanding-enable,$(LOCAL_MODULE))),)
        LOCAL_SYSTEM_SHARED_LIBRARIES += libintlc
      endif
    endif
  endif
  # Stack protector support functions live in libirc.a
  ifeq ($(filter libintlc,$(LOCAL_SYSTEM_SHARED_LIBRARIES)),)
    LOCAL_STATIC_LIBRARIES += libirc
  endif
  ifeq ($(strip $(LOCAL_MODULE)),linker)
    LOCAL_STATIC_LIBRARIES += libirc
  endif
  ifneq ($(filter libm,$(LOCAL_SYSTEM_SHARED_LIBRARIES)),)
    ifeq ($(filter libimf,$(LOCAL_SYSTEM_SHARED_LIBRARIES)),)
      LOCAL_SYSTEM_SHARED_LIBRARIES := $(patsubst libm,libimf libm,$(LOCAL_SYSTEM_SHARED_LIBRARIES))
    endif
  endif
endef

define icc-flags
  $(eval $(call do-icc-flags))
endef

define icc-libs
  $(eval $(call do-icc-libs))
endef
