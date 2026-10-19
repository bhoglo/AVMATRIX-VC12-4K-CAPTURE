# VC12-4K registers

This file lists what is known about the card's registers and where each fact comes from:

- **driver**: this driver (`src/`), which descends from the vendor's own code.
- **mainline**: the in-tree `hws` driver (`drivers/media/pci/hws/hws_reg.h`) for AVMatrix's multi-channel capture cards. It uses the same register layout but doesn't support this card.
- **measured**: read on this card (FPGA version 122) while it captured a Switch 2 at 3840×2160, 60 fps. See [results.md](results.md).

Stage 5 of [SPEC.md](SPEC.md) extends this file. Record negative results too, so nobody repeats a probe.

All registers are 32 bits wide, in BAR0.

## PCIe bridge

| Offset | Access | Meaning | Source |
|---|---|---|---|
| 0x134 | W | Interrupt enable. Written 0x3FFFF at init. | driver, mainline |
| 0x138 | — | Named "interrupt decode". Not used. | driver, mainline |
| 0x148 | — | Named "bridge enable". The write to it is commented out. | driver |
| 0x208 + 8·i | R/W | Address-translation entry i. The upper 32 bits of a host bus address go at +0, its 512 MiB-aligned lower part at +4. The entry maps the card's window i, which starts at (i + 1) · 0x20000000, onto host memory. | driver, mainline |

The translation entries match the layout of the `AXIBAR2PCIEBAR_nU`/`nL` registers in AMD/Xilinx's AXI Bridge for PCI Express (PG194, offsets 0x208–0x234). That suggests the card uses an AMD/Xilinx FPGA with that bridge. Reading the chip markings would confirm it.

## Capture block

"Register n" means BAR0 + 0x4000 + 4·n.
- `ch` is the input channel. This card has one.
- `i` is the DMA buffer. There are four, and each frame arrives as four quarters, one per buffer.
- The last 10 KiB of each buffer hold an audio ring.

| n | Access | Meaning | Source | Measured |
|---|---|---|---|---|
| 0 | R/W | **Read:** global status. 0xFFFFFFFF means the card is gone. Mainline names bit 3 "DMA busy".<br>**Write:** 0x00 at the start of `InitVideoSys`, 0x13 at its end, and 0x10 in `StopDsp`. Mainline describes the low byte as selecting "YUYV/BT.709/etc". | driver, mainline | 0x0000000B |
| 1 | R/W | Interrupt status. Writing the handled bits back acknowledges them. (Mainline acknowledges at BAR0 + 0x8004 instead.) | driver | |
| 2 | R/W | Video capture enable, bit i | driver | |
| 3 | R/W | Audio capture enable, bit i | driver | |
| 4 | R | Mainline: main control, where bit 0 enables interrupts. This driver doesn't use it. | mainline | 0x00000001 |
| 5 | R | Bit ch: signal present. Bit 8 + ch: interlaced. | driver, mainline | 0x00000001 |
| 8 | R | Bit ch: HDCP detected | mainline | 0 (Switch 2) |
| 9 | R/W | Mainline: "DMA max size", written at probe. This driver doesn't use it. | mainline | 0x00044000 |
| 16 + i | R/W | Buffer i's address as the card sees it: (i + 1) · 0x20000000 plus the low 29 bits of the bus address | driver, mainline | |
| 24 + i | R/W | Audio ring address of buffer i, in the same form. The driver writes 24–27, but 25 and 26 read back 0, so the card seems to implement only 24 (one audio channel). | driver | 25, 26: 0 |
| 26 + ch | W | Mainline: per-channel DMA address, rewritten before every frame in its zero-copy path. On this card it falls inside the audio-address range above. | mainline | 0 |
| 32 + i | R | Bit 0: which half of buffer i the DMA engine is filling | driver, mainline | toggles |
| 40 + i | R | Bit 0: audio toggle for channel i | driver | |
| 50 + i | R/W | Half-frame length of buffer i, in 16-byte units | driver, mainline | |
| 88 | R | Device info. This driver reads:<br>- bits 15:8: version<br>- bits 23:16: sub-version<br>- bits 25:24: port ID<br>- bits 31:28: YV12 support<br><br>Bits 7:0 are unexplained. Mainline reads the version from bits 7:0 and the sub-version from bits 15:8, which would give 255 and 122 on this card. A mainline port (stage 4.6) must use this driver's layout for 8581. | driver, mainline | 0x00007AFF: version 122, sub-version 0, port 0, no YV12 |
| 90 + 2·ch | R | Input size: width in bits 15:0, height in bits 31:16. The height is per field when the input is interlaced. | driver, mainline | 3840×2160 |
| 91 + 2·ch | R/W | Picture: saturation << 24, hue << 16, contrast << 8, brightness. Hue reads back but has no visible effect. | driver, mainline | |
| 110 + ch | R | Input frame rate in whole fps | mainline | 60 |
| 120 + ch | R/W | Output size (h << 16 \| w). Mainline writes the requested size there. This driver never writes it. | mainline | 1920×1080 |
| 130 + ch | R/W | Output frame rate. Mainline doesn't write it either. | mainline | 60 |

## Not yet known

- What the bridge registers at 0x134–0x148 do beyond their names.
- Bits 7:0 of register 88, which read 0xFF here.
- Whether registers 9, 120 and 130 do anything on this card. Stage 4.3 probes 120 and 130.
- Every register not listed above, notably 54–87 and 92–109.
- Whether the card gives the host any access to its HDMI receiver: EDID, InfoFrames, audio format.

## Vendor ancestry

This driver's names come from Windows:
- `DispatchCreate`;
- the `StartKSThread` kernel-streaming thread;
- `READ_REGISTER_ULONG` and `WRITE_REGISTER_ULONG`, borrowed from the Windows HAL.

The vendor's Windows driver is probably the same code base, which is why stage 5 starts there.
