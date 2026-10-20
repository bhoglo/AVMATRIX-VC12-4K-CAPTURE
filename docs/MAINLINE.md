# Mainline `hws` driver and the VC12-4K

This file compares the in-tree `hws` driver with this driver. It's the starting point for stage 4.6 of [SPEC.md](SPEC.md): adding the VC12-4K (`8888:8581`) to mainline so the card works without DKMS.

Compared against Linux `master` at `f47d223627f8` (7.4 merge window) on 2026-10-20. The driver is `drivers/media/pci/hws/`, 3,927 lines, in two commits:
- `ba07fd2f5742` "media: pci: add AVMatrix HWS capture driver", merged for 7.2;
- `23b8b4cbd886` "media: hws: Remove stale control ioctl prototypes".

Ben Hoff wrote it and maintains it (MAINTAINERS: "AVMATRIX HWS CAPTURE DRIVER", list `linux-media@vger.kernel.org`). AVMatrix is credited as co-author. Fedora/Nobara 7.2 kernels ship it as `hws.ko`.

The kernel clone used for this work is `~/git/linux`, branch `hws-vc12-4k`, sparse checkout of `drivers/media/pci/hws/`, `MAINTAINERS` and `Documentation/admin-guide/media/`. Patches to linux-media are based on the media tree's `next` branch (`https://git.linuxtv.org/media.git`). Fetch that before writing patches.

## Work already under way (checked 2026-10-20)

`master` isn't the whole story. The media patchwork (`patchwork.linuxtv.org`, search "hws") and Ben Hoff's own repository (`github.com/benhoff/hws`) show:

- **Accepted, not yet in Linus's tree** (they come in a later merge window):
  - "media: hws: fix device info register field masks" (2026-08-01). It reads the version from bits 15:8 and the sub-version from bits 23:16, as this driver does. Item 3 below is already fixed.
  - "media: hws: report measured colorimetry" (2026-08-07);
  - "media: pci: hws: only init channels the device actually has" (2026-08-19, Linkai Gong);
  - "media: hws: Wait for IRQ handler before returning buffers" (2026-08-08, Hao-Qun Huang).
- **HDMI audio, under review.** "media: hws: add HDMI audio capture support", v3, 5 patches, 2026-06-29. Patch 5 adds `hws_audio.c` (1,183 lines), an ALSA PCM capture device at 48 kHz stereo with 4096-byte packets. The other four rework the video DMA around the remap windows and a shared scratch arena. Patchwork state: changes requested. On 2026-07-27 Ben wrote that a v4 was drafted locally. Hans Verkuil asked about it on 2026-09-08. No v4 had been posted by 2026-10-20.

  Its registers match this card: ring address at register 24 + ch, enable in register 3, interrupt bit 8 + ch, toggle at 40 + ch. v3's `snd_pcm_hardware.info` has no `SNDRV_PCM_INFO_BATCH`, which this driver needed to stop PipeWire's crackle (stage 1 and PR #26 upstream). His newer branch `audio-upstream-v20-source-rewrite` (2026-09-13), probably the v4 in progress, does set it, and has no 8581 support.
- **Cleanup series, under review.** "remove debug controls and lifecycle tracing", "quiesce interrupts without disabling shared IRQ", "serialize video quiesce with queue state" (3 patches, 2026-09-15, changes requested).
- **A VC12-4K port, waiting for hardware.** Branch `feat/1chuhd-video-only-port` (5 commits, 2026-04-07) in `benhoff/hws`:
  - adds 8888:8581, 1F33:8581, 8888:85A1 and 8888:8591 as the "1CHUHD" family;
  - selects one channel;
  - raises the UHD geometry limits;
  - programs the four DMA slots;
  - assembles each frame on the CPU from scratch buffers.

  Its README says it builds but "has not been validated on real hardware", and it asks a hardware owner to run `collect_1chuhd_logs.sh`. The branch is video only, like this file's plan, and is 10 commits behind his `master`.

Its open questions, and what this driver's work has found:

| Question in the branch | Answer from this card |
|---|---|
| Toggle 1 fills slices 0 and 1, toggle 0 fills 2 and 3? | Yes. When the toggle reads 1, quarters 0 and 1 (the top half) are done; at 0 the frame is complete ([hws_video.c](../src/hws_video.c), `hws_zc_*`). |
| Are the slices contiguous chunks of one progressive YUYV frame? | Yes: quarters 0–2 are each (w·h·2 / 8192) × 2048 bytes, and quarter 3 is the rest, rounded up to 2 KiB. Pointing the four slots at consecutive parts of one buffer gives a correct frame with no CPU assembly (stage 4.4, 8 hours at 4K60). |
| Does interlaced input need different reconstruction? | Not tested on this card. Register 90 gives the field size (Windows accepts 1920 × 540, 720 × 288 and 720 × 240 fields), and register 5 bit 8 + ch the interlace flag (see [REGISTERS.md](REGISTERS.md)). |
| Is MMAP enough, or is DMABUF needed? | OBS captures with MMAP, and this driver's zero-copy path was tested with it. |
| Does `support_yv12` mean a missing format? | Register 88 bits 31:28 read 0 on this card: YUYV only. |

One more difference from the branch's test plan: a 4096 × 2160 source arrives as 3840 × 2160, because the card scales it, so a 4096-wide capture mode never occurs.

So contributing here means testing and finishing Ben's branch, and reviewing his audio series on this card. It doesn't mean writing the port from scratch. The rest of this file is the comparison against `master` and still describes what the port needs.

## Verdict

The card fits the `hws` driver. Both drivers come from the same vendor code base:
- the register block at BAR0 + 0x4000 is the same;
- the start sequence matches (0x00, addresses, 0x3FFFF to 0x134, 0x80000000, 0x80FFFFFF, 0x13);
- address translation works the same way (0x208 + 8·i, 512 MiB windows);
- input size, frame rate, picture controls, HDCP and output-size registers are at the same offsets.

The driver already has what a mainline VC12-4K driver needs:
- DV timings and source-change events;
- capture straight into `videobuf2-dma-contig` buffers;
- full-range colorimetry;
- brightness, contrast, saturation and hue controls.

It also has an unused per-board hook: each PCI table entry has a `driver_data` slot that is set to `NULL`.

The VC12-4K differs in four places: how a frame is split across DMA slots, the version register, the size limits, and audio. None of these needs a new driver.

## What is the same

| Area | Mainline | This driver | Notes |
|---|---|---|---|
| Interrupt enable | 0x3FFFF to 0x134 | same | |
| Start/stop (register 0) | 0x00 / 0x10 probe; 0x80000000, 0x80FFFFFF, 0x13 start | same | |
| Address table | 0x208 + 8·ch, upper 32 bits then 512 MiB page | 0x208 + 8·i | |
| Buffer address | register 16 + ch, (ch + 1)·0x20000000 + low 29 bits | register 16 + i | |
| Length | register 50 + ch, half size / 16 | register 50 + i, quarter / 16 | see below |
| Buffer toggle | register 32 + ch, bit 0 | register 32 + i | |
| Interrupt status | register 1, bit ch, acknowledged by writing back | register 1 bit 0 (video), bit 8 (audio) | |
| Signal and interlace | register 5, bits ch and 8 + ch | same | |
| Input size | register 90 + 2·ch | same | |
| Picture controls | register 91 + 2·ch, S<<24 \| H<<16 \| C<<8 \| B | same | hue has no effect on this card |
| HDCP | register 8, bit ch | same | |
| Input rate | register 110 + ch | same | this card is FPGA 122, which has it |
| Output size and rate | registers 120 + ch, 130 + ch | same | no effect on this card (probe 4.3) |
| Colour range | `V4L2_QUANTIZATION_FULL_RANGE` | full range | matches stage 4.5 |

## What has to change for the VC12-4K

### 1. One input, four DMA slots

Mainline gives each input channel one DMA slot: address-table entry ch, buffer register 16 + ch, length register 50 + ch. The card writes each frame in two halves (`half_size = sizeimage / 2`) into one `dma-contig` buffer.

The VC12-4K has one input, but it uses all four slots for that input. Each frame arrives as four quarters, one per slot (registers 16–19, 50–53, toggles 32–35, table entries 0–3). The quarter lengths follow the Windows rule: quarters 0–2 are each (w·h·2 / 8192) × 2048 bytes, and quarter 3 gets the rest, rounded up to 2 KiB (`hws_quarter_sizes()` in [hws_calc.h](../src/hws_calc.h)).

This is what our zero-copy path (stage 4.4) already does. It points the four slots at the four quarters of one app buffer, every frame. In mainline, that would be the only capture path, which mainline already assumes. The 512 MiB window rule and the contiguity rule from stage 4.4 apply. Each quarter must sit inside one window, and a 4K frame (16.6 MiB) needs contiguous DMA addresses. That works with an IOMMU, but without one it needs CMA.

So the board profile needs:
- the number of input channels (1);
- slots per frame (4);
- the quarter-size rule.

### 2. The register 26 doorbell

Mainline writes the buffer address to register 26 + ch before every frame (`hws_set_dma_doorbell()`). On this card, registers 24–27 are the HDMI audio ring addresses. 25 and 26 read back 0, so they are probably something else here. For the VC12-4K, the profile should skip this write.

### 3. The version register

Fixed by the accepted "fix device info register field masks" patch (see above). On `master`, mainline still reads register 88 as version = bits 7:0, sub-version = bits 15:8. On this card, that gives version 255 and sub-version 122. The Windows driver and this driver read the version from bits 15:8 (122) and the sub-version from bits 23:16. The version matters because mainline picks `hw_ver` and register 9's value from it. The profile needs the right layout for 8581.

### 4. Register 9 and the size limits

Mainline:
- writes register 9 as 1920 × 1080 × 2 / 16;
- caps formats at `MAX_VIDEO_HW_W` × `MAX_VIDEO_HW_H` (1920 × 1080);
- sizes buffers to `MAX_MM_VIDEO_SIZE` (4 MiB).

The VC12-4K needs:
- input up to 4096 × 2160 (the card delivers 3840 × 2160 for a 4096-wide source);
- register 9 set to the largest programmed quarter (stage 6; see register 9 in [REGISTERS.md](REGISTERS.md));
- a 4.5 MiB per-slot limit for a 4096 × 2160 quarter.

These become profile fields.

### 5. DV modes and frame rates

Mainline's mode table stops at 1920 × 1080 at 60 Hz. The VC12-4K needs these modes from its EDID:
- 3840 × 2160 at 24–60 Hz;
- 4096 × 2160 at 25–60 Hz;
- 2560 × 1440 at 60 and 144 Hz;
- 2560 × 1080;
- 1920 × 1080 at 120 and 240 Hz.

Mainline's rate check (`fps > 240` is rejected) already covers 240.

Register 110 gives whole frames per second only. To tell 59.94 from 60 Hz, we measure the time between frame-end interrupts (stage 4.2). That could be a later patch.

### 6. Audio

Mainline `master` has no audio, but Ben Hoff's audio series (v3, see above) adds it with the same registers. The VC12-4K's HDMI audio needs:
- the audio ring addresses (registers 24 + i);
- the audio enable (register 3);
- the audio interrupt (register 1, bit 8, with the toggle in register 40);
- an ALSA PCM capture device.

The PCM has to work the way our fixed driver does:
- report itself as BATCH, with periods matching the card's 4096-byte packets;
- drop the two stale packets after each enable;
- deliver silence while the source sends none.

Ben's series covers the multi-channel cards with the same register scheme. For this card, what's left is testing it here, and the stale-packet drop if it lacks one.

## What doesn't carry over

These features of this driver don't belong in a mainline driver. The usual V4L2 practice, and the media maintainers, push this work to userspace.

- **CPU scaling to 17 sizes.** Mainline offers the input's size only, and userspace scales.
- **Several programs capturing at once, each at its own rate.** Mainline uses one standard `vb2` queue: one program streams, and others can watch through PipeWire.
- **The copy path, and the `zero_copy` and `debug_dma` options.** Mainline captures into app buffers only.
- **Our stage 1–3 locking and delivery fixes as code.** Mainline is a separate rewrite with its own locking. The bugs those fixes addressed have to be checked against mainline's code, not ported.

The knowledge carries over: the register notes, the quarter rule, the register 9 overrun, the audio packet behaviour, HDCP and run-state recovery. [REGISTERS.md](REGISTERS.md) and [results.md](results.md) hold the evidence.

## A possible patch series

Written before Ben's VC12-4K branch turned up. His branch already covers parts 1–4 in its own way. The list stays as a check of what a finished port needs:

1. `media: hws: add per-board configuration`: use the existing `driver_data` slot for channel count, slots per frame, size limits, doorbell and version layout. No behaviour change for existing boards.
2. `media: hws: support frames split across several DMA slots`.
3. `media: hws: add 4K and high-refresh DV timings`, enabled only for boards whose profile allows them.
4. `media: hws: add AVMatrix VC12-4K (8888:8581)`.
5. Later, as its own series: `media: hws: add HDMI audio capture`.

Patches 1–3 touch code paths the multi-channel cards use, and we have no such card to test with. That's the main reason to agree on the design with the driver's author first.

## Testing

The plan, from stage 4.6:
1. Build `drivers/media/pci/hws` out of tree against the running kernel's headers, from the kernel clone (`make -C /lib/modules/$(uname -r)/build M=$PWD/drivers/media/pci/hws`).
2. Unbind `HwsUHDX1Capture` from the card and bind the test `hws`.
3. Run the stage 1 and 2 checks, plus `v4l2-compliance`.

Use the Switch 2 as the source. Don't change the PC GPU output's mode on HDMI-A-2 (see the README's known issues).

Don't bind the unmodified in-tree `hws` to the card (for example through `new_id`). It would treat the card as a 4-channel board, write register 26, and program the slots for 1080p halves. The card's DMA target would then be wrong.
