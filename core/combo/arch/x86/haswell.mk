# Configuration for Linux on x86.
# Generating binaries for Haswell processors.
# FIXME: This is just ivy bridge; update for Haswell
# capabilities once we have compiler support

ARCH_X86_HAVE_MMX    := true
ARCH_X86_HAVE_SSE    := true
ARCH_X86_HAVE_SSE2   := true
ARCH_X86_HAVE_SSE3   := true
ARCH_X86_HAVE_SSSE3  := true
ARCH_X86_HAVE_SSE4   := true
ARCH_X86_HAVE_SSE4_1 := true
ARCH_X86_HAVE_SSE4_2 := true
ARCH_X86_HAVE_AES_NI := true
ARCH_X86_HAVE_AVX    := true

# CFLAGS for this arch
arch_variant_cflags := \
	-march=corei7-avx \
	-mstackrealign \
	-mfpmath=sse \
