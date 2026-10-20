savedcmd_HwsUHDX1Capture.mod := printf '%s\n'   hws_video.o | awk '!x[$$0]++ { print("./"$$0) }' > HwsUHDX1Capture.mod
