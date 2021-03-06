#!/bin/sh
#################################################################################
# Copyright 2018 Technexion Ltd.
#
# Author: Richard Hu <richard.hu@technexion.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#################################################################################

DRIVE=/dev/sdX

PLATFORM="imx8mq"
BRANCH_VER="imx_4.9.51_imx8m_ga"
DDR_FW_VER="7.4"
#BOARD="fsl-imx8mq-evk"
BOARD="pico-8m"

FSL_MIRROR="https://www.nxp.com/lgfiles/NMG/MAD/YOCTO"
FIRMWARE_DIR="firmware_imx8mq"
MKIMAGE_DIR="imx-mkimage"
MKIMAGE_PLAT="iMX8M"
MKIMAGE_TARGET="flash_hdmi_spl_uboot"

SPL_ORI="spl/u-boot-spl.bin"
UBOOT_ORI="u-boot-nodtb.bin"
FW_DIR="firmware_imx8mq"
IMX_BOOT="flash.bin"
TWD=`pwd`

install_firmware()
{
	cd ${TWD}
	#Get and Build NXP imx-mkimage tool
	if [ ! -d ${MKIMAGE_DIR} ] ; then
		git clone https://source.codeaurora.org/external/imx/imx-mkimage -b ${BRANCH_VER} || printf "Fails to fetch imx-mkimage source code \n" 
	fi

	#Collect required firmware files to generate bootable binary
	if [ ! -d ${FIRMWARE_DIR} ] ; then
		mkdir ${FIRMWARE_DIR}
	fi

	cd ${FIRMWARE_DIR} && FWD=`pwd`
	
	#Get, build and copy the ARM Trusted Firmware
	if [ ! -d imx-atf ] ; then
		git clone https://source.codeaurora.org/external/imx/imx-atf -b ${BRANCH_VER} || printf "Fails to fetch ATF source code \n"
	fi
	cd imx-atf
	#Apply patch to adapt for different types of LPDDR4
	if [ ! -f 0001-ATF-support-to-different-LPDDR4-configurations.patch ] ; then
		wget "https://github.com/TechNexion/meta-edm-bsp-release/raw/rocko_4.9.88-2.0.0_GA/recipes-bsp/imx-atf/imx-atf/0001-ATF-support-to-different-LPDDR4-configurations.patch"
		git am 0001-ATF-support-to-different-LPDDR4-configurations.patch
	fi

	if [ ! -f build/imx8mq/release/bl31.bin ] ; then
		make PLAT=${PLATFORM} bl31 || printf "Fails to build ATF firmware \n"
	fi	
	if [ -f build/imx8mq/release/bl31.bin ] ; then
		printf "Copy build/imx8mq/release/bl31.bin to $MKIMAGE_DIR \n"
		cp build/imx8mq/release/bl31.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
	else
		printf "Cannot find release/bl31.bin \n"
	fi
	
	#Get and copy the DDR and HDMI firmware
	cd ${FWD}
	if [ ! -d firmware-imx-${DDR_FW_VER} ] ; then
		wget ${FSL_MIRROR}/firmware-imx-${DDR_FW_VER}.bin && \
		chmod +x firmware-imx-${DDR_FW_VER}.bin && \
		./firmware-imx-${DDR_FW_VER}.bin || \
		printf "Fails to fetch DDR firmware \n"
	fi

	if [ -d firmware-imx-${DDR_FW_VER}/firmware/ddr/synopsys ] ; then
		cp firmware-imx-${DDR_FW_VER}/firmware/ddr/synopsys/lpddr4_pmu_train_1d_dmem.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
		cp firmware-imx-${DDR_FW_VER}/firmware/ddr/synopsys/lpddr4_pmu_train_1d_imem.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
		cp firmware-imx-${DDR_FW_VER}/firmware/ddr/synopsys/lpddr4_pmu_train_2d_dmem.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
		cp firmware-imx-${DDR_FW_VER}/firmware/ddr/synopsys/lpddr4_pmu_train_2d_imem.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
		cp firmware-imx-${DDR_FW_VER}/firmware/hdmi/cadence/signed_hdmi_imx8m.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
	else
		printf "Cannot find DDR firmware \n"
	fi
}

install_uboot_dtb()
{
	#Copy uboot binary
	cd ${TWD}
	if [ -f u-boot-nodtb.bin ] ; then
		cp u-boot-nodtb.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
	else
		printf "Cannot find u-boot-nodtb.bin. Please build u-boot first! \n"
	fi

	#Copy SPL binary
	cd ${TWD}
	if [ -f spl/u-boot-spl.bin ] ; then
		cp spl/u-boot-spl.bin ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
	else
		printf "Cannot find spl/u-boot-spl.bin. Please build u-boot first! \n"
	fi

	#Copy device tree file
	cd ${TWD}
	if [ -f arch/arm/dts/${BOARD}.dtb ] ; then
		cp arch/arm/dts/${BOARD}.dtb ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}
	else
		printf "Cannot find arch/arm/dts/${BOARD}.dtb. Please build u-boot first! \n"
	fi
}

generate_imx_boot()
{
	cd ${TWD}
	#Before generating the flash.bin, transfer the mkimage generated by U-Boot to iMX8M folder
	if [ -f tools/mkimage ] ; then
		cp tools/mkimage ${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}/mkimage_uboot
	else
		printf "Cannot find tools/mkimage. Please build u-boot first! \n"
	fi

	#Generate bootable binary (This binary contains SPL and u-boot.bin) for flashing
	cd ${MKIMAGE_DIR}
	make SOC=${MKIMAGE_PLAT} dtbs=${BOARD}.dtb ${MKIMAGE_TARGET} && \
	printf "Make target: ${MKIMAGE_TARGET} and generate flash.bin... \n" || printf "Fails to generate flash.bin... \n"
}

flash_imx_boot()
{
	cd ${TWD}
	if [ ! -b $DRIVE ]; then
     echo "$DRIVE doesn't exist !!!"
     exit
	fi
	sudo umount ${DRIVE}?
	sleep 0.1
	sudo dd if=${TWD}/${MKIMAGE_DIR}/${MKIMAGE_PLAT}/${IMX_BOOT} of=${DRIVE} bs=1k seek=33 oflag=dsync && \
	printf "Flash flash.bin... \n" || printf "Fails to flash flash.bin... \n"
}

usage()
{
    echo -e "\nUsage: install_uboot_imx8mq.sh
    Optional parameters: [-d disk-path] [-b board_name] [-t] [-c] [-h]"
	echo "
    * This script is used to download required firmware files, generate and flash bootable u-boot binary
    *
    * [-d disk-path]: specify the disk to flash u-boot binary, e.g., /dev/sdd
    * [-b dtb_name]: specify the name of dtb, e.g.,fsl-imx8mq-evk, wand-pi-8m, pico-8m
    * [-t]: target u-boot binary is without HDMI firmware
    * [-c]: clean temporary directory
    * [-h]: help
"
}

print_settings()
{
	echo "*************************************************************"
	echo "Before run this script, please build u-boot first!
	"
	echo "The disk path to flash u-boot: $DRIVE"
	echo "The default board name: $BOARD"
	echo "Make target: ${MKIMAGE_TARGET}"
	echo "*************************************************************
		
	"
}

while getopts "tchd:b:" OPTION
do
	case $OPTION in
		d)
			DRIVE="$OPTARG"
			;;
		b)
			BOARD="$OPTARG"
			;;
		t)
			MKIMAGE_TARGET='flash_spl_uboot';
			;;
		c)
			rm -rf ${FIRMWARE_DIR} ${MKIMAGE_DIR}
			echo "Clean ${FIRMWARE_DIR} ${MKIMAGE_DIR}..."
			exit
			;;
		?|h) usage
			exit
			;;
        *) usage
			exit
			;;
	esac
done

if [ "$(id -u)" = "0" ]; then
	echo "This script can not be run as root"
	exit 1
fi

print_settings
install_firmware
install_uboot_dtb
generate_imx_boot
if [ -b $DRIVE ]; then
	flash_imx_boot
else
	echo Target block device $DRIVE does not exist, so skip flash_imx_boot
fi
