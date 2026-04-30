import std/[strformat, strutils]

var enableVpx = getEnv("DISABLE_VPX").len == 0
var enableSvtav1 = getEnv("DISABLE_SVTAV1").len == 0
var enableHevc = getEnv("DISABLE_HEVC").len == 0
var enableWhisper = getEnv("DISABLE_WHISPER").len == 0
var enableVpl = getEnv("DISABLE_VPL").len == 0 and not defined(macosx)

when defined(dynamic):
  let ffmpegCflags = gorgeEx("pkg-config --cflags libavutil", "")
  if ffmpegCflags.exitCode == 0:
    switch("passC", ffmpegCflags.output.strip())
  let ffmpegLibs = gorgeEx("pkg-config --libs libavfilter libavformat libavcodec libswresample libswscale libavutil", "")
  if ffmpegLibs.exitCode == 0:
    switch("passL", ffmpegLibs.output.strip())
else:
  let buildPath = (
    if hostCPU == "wasm32": "build_wasm"
    elif hostOS == "windows" and hostCPU == "arm64": "build_winarm"
    elif hostOS == "windows" and hostCPU != "arm64": "build_win"
    else: "build"
  )
  switch("passC", &"-I./{buildPath}/include")
  switch("passL", &"-L./{buildPath}/lib")
  when hostCPU == "wasm32":
    switch("define", "noSignalHandler")
    --cc:clang
    --clang.exe:emcc
    --clang.linkerexe:emcc

# See for details: https://simonbyrne.github.io/notes/fastmath/
switch("passC", "-fno-signaling-nans -fno-math-errno -fno-trapping-math -fno-signed-zeros")
when defined(gcc):
  switch("passC", "-Wno-incompatible-pointer-types")

if not defined(dynamic):
  # Core FFmpeg libraries
  switch("passL", "-lavfilter -lavformat -lavcodec -lswresample -lswscale -lavutil")
  # Codec libraries
  switch("passL", "-lmp3lame -lopus -lx264 -ldav1d")
  if enableVpx:
    switch("passL", "-lvpx")
  if enableSvtav1:
    switch("passL", "-lSvtAv1Enc")
  if hostCPU != "wasm32":
    if enableHevc:
      switch("passL", "-lx265")
    if enableVpl and not (hostCPU == "arm64" and hostOS == "windows"):
      switch("passL", "-lvpl")

when hostOS == "macosx":
  if defined(dynamic):
    let (osVer, _) = gorgeEx("sw_vers -productVersion", "")
    let majorVer = osVer.strip().split(".")[0]
    switch("passC", "-mmacosx-version-min=" & majorVer & ".0")
    switch("passL", "-mmacosx-version-min=" & majorVer & ".0")
  switch("passL", "-framework VideoToolbox -framework AudioToolbox")
  switch("passL", "-framework CoreFoundation -framework CoreMedia -framework CoreVideo")
elif hostOS == "windows":
  switch("passL", "-lpthread -lbcrypt -lsetupapi -lole32 -luuid")
elif not defined(dynamic) and hostOS == "linux" and hostCPU != "wasm32":
  when hostCPU == "arm64":
    switch("passL", "-L./build/lib/aarch64-linux-gnu")
  else:
    switch("passL", "-L./build/lib/x86_64-linux-gnu")
  switch("passL", "-L./build/lib64")

if not defined(dynamic) and enableWhisper:
  switch("passL", "-lwhisper")
  switch("passL", "-lggml-base")
  switch("passL", "-lggml")
  switch("passL", "-lggml-cpu")
  when defined(macosx):
    switch("passL", "-lggml-blas")
    when defined(arm64):
      switch("passL", "-lggml-metal")
    switch("passL", "-framework Accelerate")
    switch("passL", "-framework Metal -framework MetalKit -framework Foundation")
  elif not (hostOS == "windows" and hostCPU == "arm64") and hostCPU != "wasm32":
    switch("passL", "-lgomp")

if not defined(dynamic):
  if enableHevc or enableWhisper or defined(linux):
    # Link the C++ standard library
    switch("passL", when defined(macosx): "-lc++" else: "-lstdc++")

# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
