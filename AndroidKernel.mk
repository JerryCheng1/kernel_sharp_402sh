#Android makefile to build kernel as a part of Android Build
PERL		= perl

ifeq ($(TARGET_PREBUILT_KERNEL),)

KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
KERNEL_CONFIG := $(KERNEL_OUT)/.config
ifeq ($(TARGET_KERNEL_APPEND_DTB), true)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/arm/boot/zImage-dtb
else
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/arm/boot/zImage
endif
KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
KERNEL_MODULES_INSTALL := system
KERNEL_MODULES_OUT := $(TARGET_OUT)/lib/modules
KERNEL_IMG=$(KERNEL_OUT)/arch/arm/boot/Image

ifneq ($(SH_MODEL_TYPE),)
DTC_FLAGS ?= -p 1024
else
DTS_NAMES ?= $(shell $(PERL) -e 'while (<>) {$$a = $$1 if /CONFIG_ARCH_((?:MSM|QSD|MPQ)[a-zA-Z0-9]+)=y/; $$r = $$1 if /CONFIG_MSM_SOC_REV_(?!NONE)(\w+)=y/; $$arch = $$arch.lc("$$a$$r ") if /CONFIG_ARCH_((?:MSM|QSD|MPQ)[a-zA-Z0-9]+)=y/} print $$arch;' $(KERNEL_CONFIG))
KERNEL_USE_OF ?= $(shell $(PERL) -e '$$of = "n"; while (<>) { if (/CONFIG_USE_OF=y/) { $$of = "y"; break; } } print $$of;' kernel/arch/arm/configs/$(KERNEL_DEFCONFIG))

ifeq "$(KERNEL_USE_OF)" "y"
DTS_FILES = $(wildcard $(TOP)/kernel/arch/arm/boot/dts/$(DTS_NAME)*.dts)
DTS_FILE = $(lastword $(subst /, ,$(1)))
DTB_FILE = $(addprefix $(KERNEL_OUT)/arch/arm/boot/,$(patsubst %.dts,%.dtb,$(call DTS_FILE,$(1))))
ZIMG_FILE = $(addprefix $(KERNEL_OUT)/arch/arm/boot/,$(patsubst %.dts,%-zImage,$(call DTS_FILE,$(1))))
KERNEL_ZIMG = $(KERNEL_OUT)/arch/arm/boot/zImage
DTC = $(KERNEL_OUT)/scripts/dtc/dtc

define append-dtb
mkdir -p $(KERNEL_OUT)/arch/arm/boot;\
$(foreach DTS_NAME, $(DTS_NAMES), \
   $(foreach d, $(DTS_FILES), \
      $(DTC) -p 1024 -O dtb -o $(call DTB_FILE,$(d)) $(d); \
      cat $(KERNEL_ZIMG) $(call DTB_FILE,$(d)) > $(call ZIMG_FILE,$(d));))
endef
else

define append-dtb
endef
endif
endif

ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),true)
$(info Using uncompressed kernel)
TARGET_PREBUILT_KERNEL := $(KERNEL_OUT)/piggy
else
TARGET_PREBUILT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)
endif

define mv-modules
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.dep`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`;\
ko=`find $$mpath/kernel -type f -name *.ko`;\
for i in $$ko; do mv $$i $(KERNEL_MODULES_OUT)/; done;\
fi
endef

define clean-module-folder
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.dep`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`; rm -rf $$mpath;\
fi
endef

$(KERNEL_OUT):
	mkdir -p $(KERNEL_OUT)

ifeq ($(TARGET_BUILD_VARIANT),user)
define format_kernel_config_engineering
endef
else
define CONFIGY
"CONFIG_DEVMEM CONFIG_DEVKMEM CONFIG_ANDROID_ENGINEERING CONFIG_MSM_DLOAD_MODE"
endef
define CONFIGN
""
endef
#define CONFIGYOP
#"CONFIG_SLUB_DEBUG CONFIG_SLUB_DEBUG_ON CONFIG_SLUB_STATS CONFIG_DEBUG_LIST CONFIG_DEBUG_STACK_USAGE CONFIG_DEBUG_ATOMIC_SLEEP CONFIG_DEBUG_PAGEALLOC"
#endef
define CONFIGYOP
""
endef
ifeq (,$(filter-out F%, $(SH_BUILD_ID)))
define format_kernel_config_engineering
	perl -le '@noappear = split(/ /, $(CONFIGY)); @config_y = @noappear;\
	@config_n = split(/ /, $(CONFIGN));\
	while (<>) {chomp($$_); $$line = $$_ ; s/^# // ; s/[ =].+$$// ; if (/^CONFIG/) { $$config = $$_ ; \
	if (grep {$$_ eq $$config} @config_y) { $$line = $$_ . "=y" ; @noappear = grep(!/^$$config$$/, @noappear); } \
	elsif (grep {$$_ eq $$config} @config_n) {$$line = "# " . $$_ . " is not set" ; } } \
	print $$line }\
	foreach (@noappear) { print $$_ . "=y"}' $(1) > $(KERNEL_OUT)/tmp
	rm $(1)
	cp $(KERNEL_OUT)/tmp $(1)
	$(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- oldnoconfig
endef
else
define format_kernel_config_engineering
	perl -le 'if ($$ENV{'SH_BUILD_DEBUG'} eq "y") {@noappear = split(/ /, ($(CONFIGY) . " " . $(CONFIGYOP))); } else {@noappear = split(/ /, $(CONFIGY));} @config_y = @noappear;\
	@config_n = split(/ /, $(CONFIGN));\
	while (<>) {chomp($$_); $$line = $$_ ; s/^# // ; s/[ =].+$$// ; if (/^CONFIG/) { $$config = $$_ ; \
	if (grep {$$_ eq $$config} @config_y) { $$line = $$_ . "=y" ; @noappear = grep(!/^$$config$$/, @noappear); } \
	elsif (grep {$$_ eq $$config} @config_n) {$$line = "# " . $$_ . " is not set" ; } } \
	print $$line }\
	foreach (@noappear) { print $$_ . "=y"}' $(1) > $(KERNEL_OUT)/tmp
	rm $(1)
	cp $(KERNEL_OUT)/tmp $(1)
	$(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- oldnoconfig
endef
endif
endif

$(KERNEL_CONFIG): $(KERNEL_OUT)
	$(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- $(KERNEL_DEFCONFIG)
	$(call format_kernel_config_engineering, $(KERNEL_CONFIG))

$(KERNEL_OUT)/piggy : $(TARGET_PREBUILT_INT_KERNEL)
	$(hide) gunzip -c $(KERNEL_OUT)/arch/arm/boot/compressed/piggy.gzip > $(KERNEL_OUT)/piggy

$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_OUT) $(KERNEL_CONFIG) $(KERNEL_HEADERS_INSTALL)
	$(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- zImage-dtb
	$(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- modules
	$(MAKE) -C kernel O=../$(KERNEL_OUT) INSTALL_MOD_PATH=../../$(KERNEL_MODULES_INSTALL) INSTALL_MOD_STRIP=1 ARCH=arm CROSS_COMPILE=arm-eabi- modules_install
	$(mv-modules)
	$(clean-module-folder)
	$(append-dtb)

$(KERNEL_HEADERS_INSTALL): $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- headers_install

kerneltags: $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- tags

kernelconfig: $(KERNEL_OUT) $(KERNEL_CONFIG)
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- menuconfig
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C kernel O=../$(KERNEL_OUT) ARCH=arm CROSS_COMPILE=arm-eabi- savedefconfig
	cp $(KERNEL_OUT)/defconfig kernel/arch/arm/configs/$(KERNEL_DEFCONFIG)

endif
