SHELL := /bin/bash

ifdef TARGET
$(shell echo $(TARGET) > .target)
else
ifeq (,$(wildcard .target))
TARGET = bbb
else
TARGET = $(shell cat .target)
endif
endif

$(info TARGET: $(TARGET))
SUPPORTED_TARGETS := $(notdir $(wildcard targets/*))
$(if $(filter $(TARGET),$(SUPPORTED_TARGETS)),,$(error Invalid TARGET variable; valid values are: $(SUPPORTED_TARGETS)))

.PHONY: default
default: all

################################## Buildroot ###################################

.PHONY: patch
patch:
	shopt -s nullglob; \
	for patch in patches/*.patch; do \
		[ -f "$$patch" ] || continue \
		patch -d buildroot -p1 --forward < $$patch || true; \
	done

export BR2_EXTERNAL=$(CURDIR)
export BR2_DEFCONFIG=$(CURDIR)/targets/$(TARGET)/defconfig
export O=$(CURDIR)/build/$(TARGET)

## Pass targets to buildroot
%:
	$(MAKE) BR2_EXTERNAL=$(BR2_EXTERNAL) BR2_DEFCONFIG=$(BR2_DEFCONFIG) O=$(O) -C buildroot $*

all menuconfig: $(O)/.config

## Making sure defconfig is already run
$(O)/.config: 
	$(MAKE) defconfig

## Import BR2_* definitions
include $(BR2_DEFCONFIG)

################################### U-Boot #####################################

export UBOOT_DIR = $(O)/build/uboot-$(BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION)

$(O)/images/u-boot.elf:
	$(MAKE) uboot
	mv $(O)/images/u-boot $@

## Generate reference defconfig with missing options set to default as a base for comparison using diffconfig
$(UBOOT_DIR)/.$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG)_defconfig:
	$(MAKE) -C $(UBOOT_DIR) KCONFIG_CONFIG=$@ $(BR2_TARGET_UBOOT_BOARD_DEFCONFIG)_defconfig

## Generate diff with reference config
uboot-diffconfig: $(UBOOT_DIR)/.$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG)_defconfig linux-extract
	$(LINUX_DIR)/scripts/diffconfig -m $< $(UBOOT_DIR)/.config > $(BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES)

#################################### Linux ####################################

export LINUX_DIR = $(O)/build/linux-$(BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION)

## Generate reference defconfig with missing options set to default as a base for comparison using diffconfig
$(LINUX_DIR)/.$(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig:
	$(MAKE) -C $(LINUX_DIR) KCONFIG_CONFIG=$@ ARCH=arm $(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig

## Generate diff with reference config
linux-diffconfig: $(LINUX_DIR)/.$(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig linux-extract
	$(LINUX_DIR)/scripts/diffconfig -m $< $(LINUX_DIR)/.config > $(BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES)

#################################### Busybox ##################################

BUSYBOX_VERSION = $$(awk '/^BUSYBOX_VERSION/{print $$3}' buildroot/package/busybox/busybox.mk)
export BUSYBOX_DIR = $(O)/build/busybox-$(BUSYBOX_VERSION)

busybox-diffconfig: $(BR2_PACKAGE_BUSYBOX_CONFIG)
	$(LINUX_DIR)/scripts/diffconfig -m $< $(BUSYBOX_DIR)/.config > $(BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES)

#################################### Clean #####################################

.PHONY: clean-all clean-target

clean-all: clean

clean-target:
	rm -rf $(O)/target
	find $(O) -name ".stamp_target_installed" |xargs rm -rf

clean-images:
	rm -f $(O)/images/*

################################################################################

.PHONY: flash-%
flash-%:
	@if lsblk -do name,tran | grep usb | grep $*; then \
		(umount /dev/$*1 || true) && \
		(umount /dev/$*2 || true) && \
		dd if=$(O)/images/sdcard.img of=/dev/$* bs=4k status=progress && \
		sync; \
		scripts/expand-rootfs.sh /dev/$*; \
		sync; partprobe; \
	else echo "Invalid device"; \
	fi