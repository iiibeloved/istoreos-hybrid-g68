// SPDX-License-Identifier: GPL-2.0+
/*
 * (C) Copyright 2016 Rockchip Electronics Co., Ltd
 */

#include <adc.h>
#include <command.h>
#include <env.h>
#include <log.h>
#include <asm/io.h>
#include <asm/arch-rockchip/boot_mode.h>
#include <dm/device.h>
#include <dm/uclass.h>
#include <linux/printk.h>

/*
 * 长按复位键进入 MaskROM 的 boot-mode 寄存器地址。
 *
 * 设备实测（运行中 immortalwrt 固件：u-boot 反汇编 + debugfs regmap）：
 *   PMU_GRF 基址 0xfdc20000 + 0x200 (OS_REG0) = 0xfdc20200
 *   写入 BROM magic = 0xEF08A53C (BOOT_BROM_DOWNLOAD)
 *
 * 等价于 immortalwrt 的 patch 形式：地址在源码自带兜底，
 * 不依赖 defconfig / Kconfig 设置该宏（上游 Kconfig 与本项目 defconfig 均无 default）。
 * 若构建系统在别处已定义此宏，此处 #ifndef 不会覆盖。
 *
 * 注意：不要再加 "#if (CONFIG_ROCKCHIP_BOOT_MODE_REG == 0) 空桩" 守卫——
 * 该宏未设置时等于 0，会让整段复位键→MaskROM 逻辑被编译成空函数（静默失效）。
 */
#ifndef CONFIG_ROCKCHIP_BOOT_MODE_REG
#define CONFIG_ROCKCHIP_BOOT_MODE_REG 0xfdc20200
#endif

void set_back_to_bootrom_dnl_flag(void)
{
	writel(BOOT_BROM_DOWNLOAD, CONFIG_ROCKCHIP_BOOT_MODE_REG);
}

/*
 * detect download key status by adc, most rockchip
 * based boards use adc sample the download key status,
 * but there are also some use gpio. So it's better to
 * make this a weak function that can be override by
 * some special boards.
 */
#define KEY_DOWN_MIN_VAL	0
#define KEY_DOWN_MAX_VAL	30

#ifndef RK_DNL_ADC_CHAN
#define RK_DNL_ADC_CHAN		0
#endif

__weak int rockchip_dnl_key_pressed(void)
{
#if CONFIG_IS_ENABLED(ADC)
	unsigned int val;
	struct udevice *dev;
	struct uclass *uc;
	int ret;

	ret = uclass_get(UCLASS_ADC, &uc);
	if (ret)
		return false;

	ret = -ENODEV;
	uclass_foreach_dev(dev, uc) {
		if (!strncmp(dev->name, "saradc", 6)) {
			ret = adc_channel_single_shot(dev->name,
						      RK_DNL_ADC_CHAN, &val);
			break;
		}
	}

	if (ret == -ENODEV) {
		pr_warn("%s: no saradc device found\n", __func__);
		return false;
	} else if (ret) {
		pr_err("%s: adc_channel_single_shot fail!\n", __func__);
		return false;
	}

	if ((val >= KEY_DOWN_MIN_VAL) && (val <= KEY_DOWN_MAX_VAL))
		return true;
	else
		return false;
#else
	return false;
#endif
}

void rockchip_dnl_mode_check(void)
{
#if CONFIG_IS_ENABLED(ADC)
	if (rockchip_dnl_key_pressed()) {
		printf("download key pressed, entering download mode...");
		set_back_to_bootrom_dnl_flag();
		do_reset(NULL, 0, 0, NULL);
	}
#endif
}

int setup_boot_mode(void)
{
	void *reg = (void *)CONFIG_ROCKCHIP_BOOT_MODE_REG;
	int boot_mode = readl(reg);

	rockchip_dnl_mode_check();

	boot_mode = readl(reg);
	debug("%s: boot mode 0x%08x\n", __func__, boot_mode);

#if !defined(CONFIG_SPL_BUILD) && !defined(CONFIG_TPL_BUILD)
	/* Clear boot mode */
	writel(BOOT_NORMAL, reg);

	switch (boot_mode) {
	case BOOT_FASTBOOT:
		debug("%s: enter fastboot!\n", __func__);
		env_set("preboot", "setenv preboot; fastboot usb 0");
		break;
	case BOOT_UMS:
		debug("%s: enter UMS!\n", __func__);
		env_set("preboot", "setenv preboot; ums mmc 0");
		break;
	}
#endif

	return 0;
}
