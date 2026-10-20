savedcmd_HwsUHDX1Capture.o := ld -m elf_x86_64 -z noexecstack --no-warn-rwx-segments   -r -o HwsUHDX1Capture.o @HwsUHDX1Capture.mod  ; /usr/src/kernels/7.2.10-200.nobara.fc44.x86_64/tools/objtool/objtool --hacks=jump_label --hacks=noinstr --hacks=skylake --ibt --prefix=16 --orc --retpoline --rethunk --sls --static-call --uaccess  --link  --module HwsUHDX1Capture.o

HwsUHDX1Capture.o: $(wildcard /usr/src/kernels/7.2.10-200.nobara.fc44.x86_64/tools/objtool/objtool)
