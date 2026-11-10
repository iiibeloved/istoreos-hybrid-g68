
/* ==== NSY-G68 long-press Reset -> MaskROM: begin ==== */
/*
 * 上电/BROM: idbloader(TPL+SPL) 启动后，SPL 里读 SARADC 通道 0：
 *   按键按下(SARADC 原始值 0..30) -> 向 RK3568 boot-mode 寄存器写
 *   0xEF08A53C 并复位 -> BROM 进入 MaskROM（RKDevTool 可见设备）。
 *
 * 该块由 scripts/apply-device.sh 在构建前自动拼接在上游 rk3568.c 末尾，
 * 不修改上游函数体；上游若合并同类逻辑，本块会自动降级（见脚本）。
 */
#include <adc.h>
#include <command.h>
#include <asm/io.h>
#include <dm/uclass.h>

#define NSY_G68_BOOT_MODE_REG	0xfdc20200
#define NSY_G68_BROM_DL_MAGIC	0xEF08A53C
#define NSY_G68_DNL_ADC_CHAN	0
#define NSY_G68_DNL_KEY_MIN	0
#define NSY_G68_DNL_KEY_MAX	30

static int nsy_g68_read_dnl_key(unsigned int *val)
{
	struct udevice *dev;
	struct uclass *uc;
	int ret;

	ret = uclass_get(UCLASS_ADC, &uc);
	if (ret)
		return ret;

	uclass_foreach_dev(dev, uc) {
		if (!strncmp(dev->name, "saradc", 6)) {
			return adc_channel_single_shot(dev->name,
						      NSY_G68_DNL_ADC_CHAN, val);
		}
	}
	return -ENODEV;
}

int rockchip_dnl_key_pressed(void)
{
	unsigned int val = 0xffff;
	int ret = nsy_g68_read_dnl_key(&val);

	if (ret)
		return 0;
	return (val >= NSY_G68_DNL_KEY_MIN && val <= NSY_G68_DNL_KEY_MAX);
}

#ifdef CONFIG_SPL_BUILD
void spl_board_init(void)
{
	unsigned int val = 0xffff;
	int ret = nsy_g68_read_dnl_key(&val);

	if (ret || val > NSY_G68_DNL_KEY_MAX)
		return;

	writel(NSY_G68_BROM_DL_MAGIC, (void *)NSY_G68_BOOT_MODE_REG);
	do_reset(NULL, 0, 0, NULL);
}
#endif
/* ==== NSY-G68 long-press Reset -> MaskROM: end ==== */
