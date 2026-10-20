#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};


MODULE_INFO(depends, "snd-pcm,videobuf2-v4l2,v4l2-dv-timings,snd,videobuf2-common,videodev,videobuf2-vmalloc,videobuf2-dma-contig");

MODULE_ALIAS("pci:v00008888d00008581sv00008888sd00000007bc*sc*i*");
MODULE_ALIAS("pci:v00008888d000085A1sv00008888sd00000007bc*sc*i*");
MODULE_ALIAS("pci:v00001F33d00008581sv00008888sd00000007bc*sc*i*");
MODULE_ALIAS("pci:v00008888d00008591sv00008888sd00000007bc*sc*i*");

MODULE_INFO(srcversion, "FBA939D1AAC60E8C53BE29D");
