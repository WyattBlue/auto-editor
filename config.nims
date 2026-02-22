var enableVpx = getEnv("DISABLE_VPX").len == 0
var enableSvtav1 = getEnv("DISABLE_SVTAV1").len == 0
var enableHevc = getEnv("DISABLE_HEVC").len == 0
var enableWhisper = getEnv("DISABLE_WHISPER").len == 0
var enableVpl = getEnv("DISABLE_VPL").len == 0 and not defined(macosx)

switch("passC", "-I./build/include")
switch("passL", "-L./build/lib")

when defined(gcc):
  switch("passC", "-Wno-incompatible-pointer-types")

# See for details: https://simonbyrne.github.io/notes/fastmath/
switch("passC", "-fno-signaling-nans -fno-math-errno -fno-trapping-math -fno-signed-zeros")

# Core FFmpeg libraries
switch("passL", "-lavfilter -lavformat -lavcodec -lswresample -lswscale -lavutil")

# Codec libraries
switch("passL", "-lmp3lame -lopus -lx264 -ldav1d")
if enableVpx:
  switch("passL", "-lvpx")
if enableSvtav1:
  switch("passL", "-lSvtAv1Enc")
if enableHevc:
  switch("passL", "-lx265")
if enableVpl and not (defined(aarch64) or defined(arm64)):
  switch("passL", "-lvpl")

when defined(macosx):
  switch("passL", "-framework VideoToolbox -framework AudioToolbox")
  switch("passL", "-framework CoreFoundation -framework CoreMedia -framework CoreVideo")
elif defined(windows):
  switch("passL", "-lpthread -lbcrypt -lsetupapi -lole32 -luuid")

when defined(linux):
  when defined(arm64) or defined(aarch64):
    switch("passL", "-L./build/lib/aarch64-linux-gnu")
  else:
    switch("passL", "-L./build/lib/x86_64-linux-gnu")
  switch("passL", "-L./build/lib64")

if enableWhisper:
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
  else:
    switch("passL", "-lgomp")

if enableHevc or enableWhisper or defined(linux):
  # C++ standard library
  switch("passL", when defined(macosx): "-lc++" else: "-lstdc++")

# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
