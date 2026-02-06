# Package
version = "0.0.0"
author = "WyattBlue"
description = "Effort free video editing!"
license = "Unlicense"
srcDir = "src"
bin = @["main=auto-editor"]

# Dependencies
requires "nim >= 2.2.2"
requires "checksums"
requires "tinyre#77469f5"

# Tasks
import std/[os, strutils, strformat]
import src/cli

var disableVpx = getEnv("DISABLE_VPX").len > 0
var disableSvtAv1 = getEnv("DISABLE_SVTAV1").len > 0
var disableHevc = getEnv("DISABLE_HEVC").len > 0
var enable12bit = getEnv("ENABLE_12BIT").len > 0
var enableWhisper = getEnv("DISABLE_WHISPER").len == 0
var enableVpl = getEnv("DISABLE_VPL").len == 0 and not defined(macosx)
var enableCuda = getEnv("ENABLE_CUDA").len > 0 and not defined(macosx)

let posix = if false: "-posix" else: ""  # Ubuntu vs Homebrew

var flags = ""
if not disableVpx:
  flags &= "-d:enable_vpx "
if not disableSvtAv1:
  flags &= "-d:enable_svtav1 "
if not disableHevc:
  flags &= "-d:enable_hevc "
if enableWhisper:
  flags &= "-d:enable_whisper "
if enableVpl:
  flags &= "-d:enable_vpl "
if enableCuda:
  flags &= "-d:enable_cuda "

task test, "Run unit tests":
  exec &"nim c {flags} -r tests/unit"

task sprint, "Build the project quickly":
  exec &"nim c -d:danger --panics:on {flags} --out:auto-editor src/main.nim"

task make, "Export the project":
  exec &"nim c -d:danger --panics:on {flags} --passC:-flto --passL:-flto --out:auto-editor src/main.nim"
  when defined(macosx):
    exec "strip -ur auto-editor"
    exec "stat -f \"%z bytes\" ./auto-editor"
    echo ""
  when defined(linux):
    exec "strip -s auto-editor"

task cleanff, "Remove":
  rmDir "ffmpeg_sources"
  rmDir "build"

var disableDecoders: seq[string] = @[]
var disableEncoders: seq[string] = @[]
var disableDemuxers: seq[string] = @[]
var disableMuxers: seq[string] = @[]
var disableParsers: seq[string] = @[]

# Marked as 'Experimental'
disableEncoders &= "avui,dca,mlp,opus,s302m,truehd,vorbis".split(",")

# Can only decode (ambiguous encoder), Video [A-C]
disableDecoders &= "4xm,aasc,agm,aic,anm,ansi,apv,arbc,argo,aura,aura2,avrn,avs,bethsoftvid,bfi,bink,binkvideo,bmv_video,brender_pix,c93,cavs,cdgraphics,cdtoons,cdxl,clearvideo,cllc,cmv,cpia,cri,cscd,cyuv".split(",")
# [D-I]
disableDecoders &= "dds,dfa,dsicinvideo,dxa,dxtory,escape124,escape130,fic,flic,fmvc,fraps,frwu,g2m,gdv,gem,hnm4video,hq_hqa,hqx,hymt,idcin,idf,iff_ilbm,imm4,imm5,indeo2,indeo3,indeo4,indeo5,interplay_video,ipu".split(",")
# [J-M]
disableDecoders &= "jv,kgv1,kmvc,lagarith,lead,loco,lscr,m101,mad,mdec,media100,mimic,mjpegb,mmvideo,mobiclip,motionpixels,msa1,mscc,msmpeg4v1,msp2,mss1,mss2,mszh,mts2,mv30,mvc1,mvc2,mvdv,mvha,mwsc,mxpeg".split(",")
# [N-S]
disableDecoders &= "notchlc,nuv,paf_video,pdv,pgx,photocd,pictor,pixlet,prosumer,psd,ptx,qdraw,qpeg,rasc,rl2,rscc,rtv1,rv30,rv40,rv60,sanm,scpr,screenpresso,sga,sgirle,sheervideo,simbiosis_imx,smackvideo,smvjpeg,sp5x,srgc,svq3".split(",")
# [T-VP]
disableDecoders &= "targa_y216,tdsc,tgq,tgv,thp,tiertexseqvideo,tmv,tqi,truemotion1,truemotion2,truemotion2rt,tscc,tscc2,txd,ulti,v210x,vb,vble,vc1,vc1image,vcr1,vixl,vmdvideo,vmix,vmnc,vp3,vp4,vp5,vp6,vp6a,vp6f,vp7".split(",")
# [VQ-Z]
disableDecoders &= "vqc,vvc,wcmv,wmv3,wmv3image,wnv1,ws_vqa,xan_wc3,xan_wc4,xbin,xpm,ylc,yop,zerocodec".split(",")

# Can only decode, Audio [0-A]
disableDecoders &= "8svx_exp,8svx_fib,aac_latm,acelp.kelvin,adpcm_4xm,adpcm_afc,adpcm_agm,adpcm_aica,adpcm_ct,adpcm_dtk,adpcm_ea,adpcm_ea_maxis_xa,adpcm_ea_r1,adpcm_ea_r2,adpcm_ea_r3,adpcm_ea_xas,adpcm_ima_acorn,adpcm_ima_apc".split(",")
# [B-F]
disableDecoders &= "binkaudio_dct,binkaudio_rdft,bmv_audio,bonk,cbd2_dpcm,cook,derf_dpcm,dolby_e,dsd_lsbf,dsd_lsbf_planar,dsd_msbf,dsd_msbf_planar,dsicinaudio,dss_sp,dst,dvaudio,evrc,fastaudio,ftr".split(",")
disableDemuxers.add "bethsoftvid"
# [G-Q]
disableDecoders &= "g728,g729,gremlin_dpcm,gsm,gsm_ms,hca,hcom,iac,imc,interplay_dpcm,interplay_acm,mace3,mace6,metasound,misc4,mp1,mp3adu,msnsiren,musepack7,musepack8,osq,paf_audio,qcelp,qdm2,qdmc,qoa".split(",")
# [R-Z]
disableDecoders &= "ra_288,ralf,rka,sdx2_dpcm,shorten,sipr,siren,smackaud,sol_dpcm,tak,truespeech,twinvq,vmdaudio,wady_dpcm,wavarc,wavesynth,westwood_snd1,wmalossless,wmapro,wmavoice,xan_dpcm,xma1,xma2".split(",")

# Can only encode
disableEncoders &= "a64_multi,a64_multi5,ttml".split(",")

# Technically obsolete
disableDecoders &= "flv,jacosub,nellymoser,smacker,snow,sonic,sonic_ls".split(",")
disableEncoders &= "flv,nellymoser,snow,sonic".split(",")
disableMuxers &= "flv,f4v,jacosub,rso,segafilm".split(",")
disableDemuxers &= @["a64", "alp", "apm", "bink", "binka", "flv", "jacosub", "kux",
 "live_flv", "mm", "pp_bnk", "rso", "sdns", "segafilm", "smacker", "vmd"]
disableParsers &= @["misc4", "tak"]

# Image formats
disableDecoders.add "tiff"
disableEncoders.add "tiff"
disableMuxers.add "ico"
disableDemuxers &= "ico,image_tiff_pipe,image_svg_pipe".split(",")

type Package = object
  name: string
  sourceUrl: string
  sha256: string
  buildArguments: seq[string]
  buildSystem: string = "autoconf"
  ffFlag: string = ""

let nvheaders = Package(
  name: "nv-codec-headers",
  sourceUrl: "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/n13.0.19.0.tar.gz",
  sha256: "86d15d1a7c0ac73a0eafdfc57bebfeba7da8264595bf531cf4d8db1c22940116",
)
let libvpl = Package(
  name: "libvpl",
  sourceUrl: "https://github.com/intel/libvpl/archive/refs/tags/v2.16.0.tar.gz",
  sha256: "d60931937426130ddad9f1975c010543f0da99e67edb1c6070656b7947f633b6",
  buildSystem: "cmake",
  buildArguments: @[
    "-DINSTALL_LIB=ON",
    "-DINSTALL_DEV=ON",
    "-DINSTALL_EXAMPLES=OFF",
    "-DBUILD_EXPERIMENTAL=OFF",
    "-DBUILD_TESTS=OFF",
    "-DBUILD_EXAMPLES=OFF",
  ],
  ffFlag: "--enable-libvpl",
)
let lame = Package(
  name: "lame",
  sourceUrl: "http://deb.debian.org/debian/pool/main/l/lame/lame_3.100.orig.tar.gz",
  sha256: "ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e",
  buildArguments: @["--disable-frontend", "--disable-decoder", "--disable-gtktest", "--disable-dependency-tracking"],
  ffFlag: "--enable-libmp3lame",
)
let opus = Package(
  name: "opus",
  sourceUrl: "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz",
  sha256: "6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1",
  buildArguments: @["--disable-doc", "--disable-extra-programs"],
  ffFlag: "--enable-libopus",
)
let vpx = Package(
  name: "libvpx",
  sourceUrl: "https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.2.tar.gz",
  sha256: "26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa",
  buildArguments: "--disable-dependency-tracking --disable-examples --disable-unit-tests --enable-pic --enable-runtime-cpu-detect --enable-vp9-highbitdepth".split(" "),
  ffFlag: "--enable-libvpx",
)
let dav1d = Package(
  name: "dav1d",
  sourceUrl: "https://code.videolan.org/videolan/dav1d/-/archive/1.5.3/dav1d-1.5.3.tar.bz2",
  sha256: "e099f53253f6c247580c554d53a13f1040638f2066edc3c740e4c2f15174ce22",
  buildSystem: "meson",
  ffFlag: "--enable-libdav1d",
)
let svtav1 = Package(
  name: "libsvtav1",
  sourceUrl: "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v3.1.2/SVT-AV1-v3.1.2.tar.bz2",
  sha256: "802e9bb2b14f66e8c638f54857ccb84d3536144b0ae18b9f568bbf2314d2de88",
  buildSystem: "cmake",
  buildArguments: @["-DBUILD_APPS=OFF", "-DBUILD_DEC=OFF", "-DBUILD_ENC=ON", "-DENABLE_NASM=ON"],
  ffFlag: "--enable-libsvtav1",
)
let whisper = Package(
  name: "whisper",
  sourceUrl: "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.8.3.tar.gz",
  sha256: "870ba21409cdf66697dc4db15ebdb13bc67037d76c7cc63756c81471d8f1731a",
  buildSystem: "cmake",
  buildArguments: @[
    "-DGGML_NATIVE=OFF", # Favor portability, don't use native CPU instructions
    "-DGGML_CUDA=" & (if enableCuda: "ON" else: "OFF"),
    "-DWHISPER_SDL2=OFF",
    "-DWHISPER_BUILD_EXAMPLES=OFF",
    "-DWHISPER_BUILD_TESTS=OFF",
    "-DWHISPER_BUILD_SERVER=OFF",
    when defined(macosx) and hostCPU == "arm64": "-DGGML_METAL=ON" else: "-DGGML_METAL=OFF",
    when defined(macosx): "-DGGML_METAL_EMBED_LIBRARY=ON" else: "-DGGML_METAL_EMBED_LIBRARY=OFF",
  ],
  ffFlag: "--enable-whisper",
)
let x264 = Package(
  name: "x264",
  sourceUrl: "https://code.videolan.org/videolan/x264/-/archive/b35605ace3ddf7c1a5d67a2eb553f034aef41d55/x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.bz2",
  sha256: "6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224",
  buildArguments: "--disable-cli --disable-lsmash --disable-swscale --disable-ffms --enable-strip".split(" "),
  ffFlag: "--enable-libx264",
)
let x265 = Package(
  name: "x265",
  sourceUrl: "https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.1.tar.gz",
  sha256: "a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29",
  buildSystem: "x265",
  ffFlag: "--enable-libx265"
)
let ffmpeg = Package(
  name: "ffmpeg",
  sourceUrl: "https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz",
  sha256: "05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41",
)

proc setupPackages(enableWhisper: bool, crossWindowsArm: bool = false): seq[Package] =
  result = @[]
  if not defined(macosx) and not crossWindowsArm:
    result.add nvheaders
  if enableVpl and not crossWindowsArm:
    result.add libvpl
  if enableWhisper:
    result.add whisper
  result &= [lame, opus, dav1d, x264]
  if not disableVpx:
    result.add vpx
  if not disableSvtAv1:
    result.add svtav1
  if not disableHevc:
    result.add x265
  return result

func location(package: Package): string =
  package.sourceUrl.split("/")[^1]

func dirName(package: Package): string =
  if package.name == "libvpx":
    return "libvpx-1.15.2"
  if package.name == "libvpl":
    return "libvpl-2.16.0"
  if package.name == "nv-codec-headers":
    return "nv-codec-headers-n13.0.19.0"
  if package.name == "whisper":
    return "whisper.cpp-1.8.3"

  var name = package.location
  for ext in [".tar.gz", ".tar.xz", ".tar.bz2", ".orig"]:
    if name.endsWith(ext):
      name = name[0..^ext.len+1]

  if package.name != "x265":
    return name.replace("_", "-")
  return name


proc getFileHash(filename: string): string =
  let (existsOutput, existsCode) = gorgeEx("test -f " & filename)
  if existsCode != 0:
    raise newException(IOError, "File does not exist: " & filename)

  let (output, exitCode) = gorgeEx("shasum -a 256 " & filename)
  if exitCode != 0:
    raise newException(IOError, "Cannot hash file: " & filename)
  return output.split()[0]

proc checkHash(package: Package, filename: string) =
  let hash = getFileHash(filename)
  if package.sha256 != hash:
    echo filename
    echo &"sha256 hash of {package.name} tarball do not match!\nExpected: {package.sha256}\nGot: {hash}"
    quit(1)


proc makeInstall() =
  when defined(macosx):
    exec "make -j$(sysctl -n hw.ncpu)"
  elif defined(linux):
    exec "make -j$(nproc)"
  else:
    exec "make -j4"
  exec "make install"

proc cmakeBuild(package: Package, buildPath: string, crossWindows: bool = false, crossWindowsArm: bool = false) =
  mkDir("build_cmake")

  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
  ] & package.buildArguments

  if crossWindowsArm:
    let toolchainFile = buildPath.parentDir / "cmake" / "aarch64-w64-mingw32.cmake"
    cmakeArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")
  elif crossWindows:
    cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.add(&"-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc{posix}")
    cmakeArgs.add(&"-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++{posix}")
    cmakeArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")

  withDir "build_cmake":
    let cmakeCmd = "cmake " & cmakeArgs.join(" ") & " .."
    echo "RUN: ", cmakeCmd
    exec cmakeCmd
    makeInstall()

  # Fix whisper.pc file to include correct library order and dependencies
  if package.name == "whisper":
    # Fix library naming for cross-compilation - add lib prefix if missing
    let libDir = buildPath / "lib"
    for libFile in ["ggml.a", "ggml-base.a", "ggml-cpu.a"]:
      let srcFile = libDir / libFile
      let dstFile = libDir / ("lib" & libFile)
      if fileExists(srcFile) and not fileExists(dstFile):
        echo &"Renaming {srcFile} to {dstFile}"
        exec &"mv \"{srcFile}\" \"{dstFile}\""
    
    let pcFile = buildPath / "lib/pkgconfig/whisper.pc"
    if fileExists(pcFile):
      echo "Fixing whisper.pc file"
      var content = readFile(pcFile)

      # Replace the Libs line with correct library order and add Libs.private
      when defined(macosx) and defined(arm64):
        content = content.replace(
          "Libs: -L${libdir} -lggml  -lggml-base -lwhisper",
          "Libs: -L${libdir} -lggml -lggml-base -lwhisper -lggml-cpu -lggml-blas -lggml-metal"
        )
      elif defined(macosx):
        content = content.replace(
          "Libs: -L${libdir} -lggml  -lggml-base -lwhisper",
          "Libs: -L${libdir} -lggml -lggml-base -lwhisper -lggml-cpu -lggml-blas"
        )
      else:
        content = content.replace(
          "Libs: -L${libdir} -lggml  -lggml-base -lwhisper",
          (if enableCuda: "Libs: -L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu -lggml-cuda -L/usr/local/cuda-12.8/lib64/stubs -L/usr/local/cuda-12.8/lib64 -lcuda -lcudart -lcublas -lcublasLt"
           else: "Libs: -L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu")
        )

      if not content.contains("Libs.private:"):
        var libsPrivate = ""
        when defined(macosx):
          libsPrivate = "-framework Accelerate -framework MetalKit -framework Foundation"
          when hostCPU == "arm64":
            libsPrivate = "-framework Accelerate -framework Metal -framework MetalKit -framework Foundation"

        when defined(macosx):
          libsPrivate &= " -lc++"
        else:
          libsPrivate = "-lgomp -lpthread -lm -lstdc++"
        content = content.replace(
          "Cflags: -I${includedir}",
          &"Libs.private: {libsPrivate}\nCflags: -I${{includedir}}\n\nRequires:\nConflicts:"
        )

      writeFile(pcFile, content)

proc x265Build(buildPath: string, crossWindows: bool = false, crossWindowsArm: bool = false) =
  # Build x265 multiple times following the Homebrew approach:
  #  1: Build 12 bits static library version in separate directory (if enabled)
  #  2: Build 10 bits static library version in separate directory
  #  3: Build 8 bits version, linking also 10 and optionally 12 bits
  # By default supports 8 and 10 bits pixel formats (12-bit disabled for size)

  # For 10/12 bits version, only x86_64 has assembly instructions available
  var highBitDepthArgs: seq[string] = @[
    "-DHIGH_BIT_DEPTH=1",
    "-DEXPORT_C_API=0",
    "-DENABLE_SHARED=0",
    "-DENABLE_CLI=0"
  ]

  let isLinuxAarch64 = defined(linux) and hostCPU == "arm64"
  let isX86_64 = hostCPU in ["amd64", "i386"] # Nim uses "amd64" for x86_64

  if not isX86_64 or crossWindowsArm:
    highBitDepthArgs.add("-DENABLE_ASSEMBLY=0")

  if isLinuxAarch64:
    highBitDepthArgs.add("-DENABLE_SVE2=0")

  # Common cmake args for all builds
  var commonArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",  # CMake 4 compatibility for subdirectories
  ]

  # Add cross-compilation flags if needed
  if crossWindowsArm:
    let toolchainFile = buildPath.parentDir / "cmake" / "aarch64-w64-mingw32.cmake"
    commonArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")
    highBitDepthArgs.add("-DENABLE_ASSEMBLY=0")  # No x86 assembly for ARM64
  elif crossWindows:
    commonArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    commonArgs.add(&"-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc{posix}")
    commonArgs.add(&"-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++{posix}")
    commonArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
    commonArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
    commonArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
    commonArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")

  # Build 12-bit version (optional, disabled by default for size)
  if enable12bit:
    echo "Building x265 12-bit..."
    var cmake12Args = @["-S", "source", "-B", "12bit", "-DMAIN12=ON"] & highBitDepthArgs & commonArgs
    let cmake12Cmd = "cmake " & cmake12Args.join(" ")
    echo "RUN: ", cmake12Cmd
    exec cmake12Cmd
    exec "cmake --build 12bit"
    exec "mv 12bit/libx265.a 12bit/libx265_main12.a"

  # Build 10-bit version
  echo "Building x265 10-bit..."
  var cmake10Args = @["-S", "source", "-B", "10bit"] & highBitDepthArgs & commonArgs
  # Not applied for size: "-DENABLE_HDR10_PLUS=ON"
  let cmake10Cmd = "cmake " & cmake10Args.join(" ")
  echo "RUN: ", cmake10Cmd
  exec cmake10Cmd
  exec "cmake --build 10bit"
  exec "mv 10bit/libx265.a 10bit/libx265_main10.a"

  # Build 8-bit version with linked 10-bit and optionally 12-bit
  echo "Building x265 8-bit with multi-bit-depth support..."

  # Create 8bit directory and copy the 10-bit library
  mkDir("8bit")
  cpFile("10bit/libx265_main10.a", "8bit/libx265_main10.a")

  # Build cmake command
  var cmake8Cmd = "cmake -S source -B 8bit"
  if enable12bit:
    # Copy 12-bit library and configure for 12-bit support
    cpFile("12bit/libx265_main12.a", "8bit/libx265_main12.a")
    cmake8Cmd &= " \"-DEXTRA_LIB=x265_main10.a;x265_main12.a\""
    cmake8Cmd &= " -DLINKED_12BIT=1"
  else:
    cmake8Cmd &= " -DEXTRA_LIB=x265_main10.a"

  cmake8Cmd &= " -DEXTRA_LINK_FLAGS=-L."
  cmake8Cmd &= " -DLINKED_10BIT=1"
  cmake8Cmd &= " -DENABLE_SHARED=0"
  cmake8Cmd &= " -DENABLE_CLI=0"
  for arg in commonArgs:
    cmake8Cmd &= " " & arg

  if isLinuxAarch64:
    cmake8Cmd &= " -DENABLE_SVE2=0"

  echo "RUN: ", cmake8Cmd
  exec cmake8Cmd
  exec "cmake --build 8bit"

  # Manually combine libraries for multi-bit-depth support
  echo "Combining x265 libraries for multi-bit-depth support..."
  when defined(macosx):
    if enable12bit:
      exec "libtool -static -o 8bit/libx265_combined.a 8bit/libx265.a 10bit/libx265_main10.a 12bit/libx265_main12.a"
    else:
      exec "libtool -static -o 8bit/libx265_combined.a 8bit/libx265.a 10bit/libx265_main10.a"
  else:
    # For Linux or cross-compilation, use ar with MRI script
    var arCommand = "ar"
    if crossWindowsArm:
      arCommand = "llvm-ar"
    elif crossWindows:
      arCommand = "x86_64-w64-mingw32-ar"

    # Create MRI script with paths relative to 8bit directory
    withDir "8bit":
      exec "echo 'CREATE libx265_combined.a' > combine.mri"
      exec "echo 'ADDLIB libx265.a' >> combine.mri"
      exec "echo 'ADDLIB libx265_main10.a' >> combine.mri"
      if enable12bit:
        exec "echo 'ADDLIB libx265_main12.a' >> combine.mri"
      exec "echo 'SAVE' >> combine.mri"
      exec "echo 'END' >> combine.mri"
      exec &"{arCommand} -M < combine.mri"

  # Replace the 8-bit only library with the combined one
  exec "mv 8bit/libx265_combined.a 8bit/libx265.a"

  # Install from 8bit build
  exec "cmake --install 8bit"


proc mesonBuild(buildPath: string, crossWindows: bool = false, crossWindowsArm: bool = false) =
  mkDir("build_meson")

  var mesonArgs = @[
    &"--prefix={buildPath}",
    "--buildtype=release",
    "--default-library=static",
    "-Denable_docs=false",
    "-Denable_tools=false",
    "-Denable_examples=false",
    "-Denable_tests=false"
  ]

  if crossWindowsArm:
    # Create cross-compilation file for meson (Windows ARM64)
    let crossFile = "build_meson/meson-cross.txt"
    writeFile(crossFile, """
[binaries]
c = 'aarch64-w64-mingw32-clang'
cpp = 'aarch64-w64-mingw32-clang++'
ar = 'llvm-ar'
strip = 'llvm-strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
""")
    mesonArgs.add("--cross-file=meson-cross.txt")
  elif crossWindows:
    # Create cross-compilation file for meson
    let crossFile = "build_meson/meson-cross.txt"
    writeFile(crossFile, &"""
[binaries]
c = 'x86_64-w64-mingw32-gcc{posix}'
cpp = 'x86_64-w64-mingw32-g++{posix}'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
""")
    mesonArgs.add("--cross-file=meson-cross.txt")

  withDir "build_meson":
    let mesonCmd = "meson setup " & mesonArgs.join(" ") & " .."
    echo "RUN: ", mesonCmd
    exec mesonCmd
    exec "ninja"
    exec "ninja install"

proc ffmpegSetup(crossWindows: bool, crossWindowsArm: bool = false) =
  mkDir("ffmpeg_sources")
  mkDir("build")

  let buildPath = absolutePath("build")
  let packages = setupPackages(enableWhisper=enableWhisper, crossWindowsArm=crossWindowsArm)

  withDir "ffmpeg_sources":
    for package in @[ffmpeg] & packages:
      if not fileExists(package.location):
        exec &"curl -O -L {package.sourceUrl}"
        checkHash(package, "ffmpeg_sources" / package.location)

      var tarArgs = "xf"
      if package.location.endsWith("bz2"):
        tarArgs = "xjf"

      if not dirExists(package.name):
        exec &"tar {tarArgs} {package.location} && mv {package.dirName} {package.name}"
        let patchFile = &"../patches/{package.name}.patch"
        if fileExists(patchFile):
          let cmd = &"patch -d {package.name} -i {absolutePath(patchFile)} -p1 --force"
          echo "Applying patch: ", cmd
          exec cmd

      if package.name == "ffmpeg": # build later
        continue

      withDir package.name:
        if package.buildSystem == "cmake":
          cmakeBuild(package, buildPath, crossWindows, crossWindowsArm)
        elif package.buildSystem == "x265":
          x265build(buildPath, crossWindows, crossWindowsArm)
        elif package.buildSystem == "meson":
          mesonBuild(buildPath, crossWindows, crossWindowsArm)
        else:
          # Special handling for nv-codec-headers which doesn't use configure
          if package.name == "nv-codec-headers":
            exec &"make install PREFIX=\"{buildPath}\""
          else:
            if not fileExists("Makefile") or package.name == "x264":
              var args = package.buildArguments
              var envPrefix = ""
              if crossWindowsArm:
                if package.name == "libvpx":
                  args.add("--target=arm64-win64-gcc")
                else:
                  args.add("--host=aarch64-w64-mingw32")
                if package.name == "opus":
                  args.add("--disable-rtcd")
                envPrefix = "CC=aarch64-w64-mingw32-clang CXX=aarch64-w64-mingw32-clang++ AR=llvm-ar STRIP=llvm-strip RANLIB=llvm-ranlib "
              elif crossWindows:
                if package.name == "libvpx":
                  args.add("--target=x86_64-win64-gcc")
                else:
                  args.add("--host=x86_64-w64-mingw32")
                envPrefix = &"CC=x86_64-w64-mingw32-gcc{posix} CXX=x86_64-w64-mingw32-g++{posix} AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib "
              if package.name != "x264":
                args.add "--disable-shared"
              let cmd = &"{envPrefix}./configure --prefix=\"{buildPath}\" --enable-static " & args.join(" ")
              echo "RUN: ", cmd
              exec cmd
            makeInstall()

var filters: seq[string]
if enableWhisper:
  filters.add "whisper"
filters.add "scale,pad,format,gblur,aformat,abuffer,abuffersink,aresample,atempo,anull,anullsrc,volume,loudnorm,asetrate".split(",")

proc setupCommonFlags(packages: seq[Package], crossWindowsArm: bool = false): string =
  var commonFlags = &"""
  --enable-version3 \
  --enable-static \
  --disable-shared \
  --disable-programs \
  --disable-doc \
  --disable-network \
  --disable-indevs \
  --disable-outdevs \
  --disable-xlib \
  --disable-bsfs \
  --disable-protocols \
  --enable-protocol=file \
  --disable-filters \
  --enable-filter={filters.join(",")} \
  --disable-encoder={disableEncoders.join(",")} \
  --disable-decoder={disableDecoders.join(",")} \
  --disable-demuxer={disableDemuxers.join(",")} \
  --disable-muxer={disableMuxers.join(",")} \
  --disable-parser={disableParsers.join(",")} \
"""

  for package in packages:
    if package.ffFlag != "":
      commonFlags &= &"  {package.ffFlag} \\\n"

  if defined(arm) or defined(arm64) or crossWindowsArm:
    commonFlags &= "  --enable-neon \\\n"

  if defined(macosx):
    commonFlags &= "  --enable-videotoolbox \\\n"
    commonFlags &= "  --enable-audiotoolbox \\\n"
  elif not crossWindowsArm:
    commonFlags &= "  --enable-nvenc \\\n"
    commonFlags &= "  --enable-ffnvcodec \\\n"

  commonFlags &= "--disable-autodetect"
  return commonFlags


proc setupDeps() =
  let (mesonOutput, mesonCode) = gorgeEx("command -v meson")
  let (ninjaOutput, ninjaCode) = gorgeEx("command -v ninja")

  var toInstall: seq[string] = @[]

  if mesonCode != 0:
    toInstall.add("meson")
  if ninjaCode != 0:
    toInstall.add("ninja")

  if toInstall.len > 0:
    exec "pip install " & toInstall.join(" ")

task makeff, "Build FFmpeg from source":
  setupDeps()
  let buildPath = absolutePath("build")
  # Set PKG_CONFIG_PATH to include both standard and architecture-specific paths
  var pkgConfigPaths = @[buildPath / "lib/pkgconfig"]
  when defined(linux):
    when defined(arm64):
      pkgConfigPaths.add(buildPath / "lib/aarch64-linux-gnu/pkgconfig")
    else:
      pkgConfigPaths.add(buildPath / "lib/x86_64-linux-gnu/pkgconfig")
    pkgConfigPaths.add(buildPath / "lib64/pkgconfig")
    # Add common cmake install paths for pkg-config files
    pkgConfigPaths.add(buildPath / "lib/cmake")
    pkgConfigPaths.add(buildPath / "share/pkgconfig")
  putEnv("PKG_CONFIG_PATH", pkgConfigPaths.join(":"))

  ffmpegSetup(crossWindows=false)

  let packages = setupPackages(enableWhisper=enableWhisper)

  withDir "ffmpeg_sources/ffmpeg":
    try:
      exec &"""./configure --prefix="{buildPath}" \
        --pkg-config-flags="--static" \
        --extra-cflags="-I{buildPath}/include" \
        --extra-ldflags="-L{buildPath}/lib" \
        --extra-libs="-lpthread -lm -lstdc++" \""" & "\n" & setupCommonFlags(packages)
    except OSError:
      exec "cat ./ffbuild/config.log"
      quit(1)
    makeInstall()

let buildPath = absolutePath("build")

task makeffwin, "Build FFmpeg for Windows cross-compilation":
  setupDeps()
  putEnv("PKG_CONFIG_PATH", buildPath / "lib/pkgconfig")

  ffmpegSetup(crossWindows=true)

  let packages = setupPackages(enableWhisper=enableWhisper)

  # Configure and build FFmpeg with MinGW
  withDir "ffmpeg_sources/ffmpeg":
    exec (&"""CC=x86_64-w64-mingw32-gcc{posix} CXX=x86_64-w64-mingw32-g++{posix} AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib PKG_CONFIG_PATH="{buildPath}/lib/pkgconfig" ./configure --prefix="{buildPath}" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{buildPath}/include" \
      --extra-ldflags="-L{buildPath}/lib" \
      --extra-libs="-lpthread -lm -lstdc++" \
      --arch=x86_64 \
      --target-os=mingw32 \
      --cross-prefix=x86_64-w64-mingw32- \
      --enable-cross-compile \""" & "\n" & setupCommonFlags(packages))
    makeInstall()

task windows, "Cross-compile to Windows (requires mingw-w64)":
  echo "Cross-compiling for Windows (64-bit)..."

  if not dirExists("build"):
    echo "FFmpeg for Windows not found. Run 'nimble makeffwin' first."
  else:
    # lto causes issues with GCC.
    exec "nim c -d:danger --panics:on -d:windows " & flags &
         "--os:windows --cpu:amd64 --cc:gcc " &
        &"--gcc.exe:x86_64-w64-mingw32-gcc{posix} " &
        &"--gcc.linkerexe:x86_64-w64-mingw32-gcc{posix} " &
         "--passL:-static " &
         "--out:auto-editor.exe src/main.nim"

    # Strip the Windows binary
    exec "x86_64-w64-mingw32-strip -s auto-editor.exe"

task makeffwinarm, "Build FFmpeg for Windows ARM64 cross-compilation":
  setupDeps()
  let pkgConfigPath = buildPath / "lib/pkgconfig"
  putEnv("PKG_CONFIG_PATH", pkgConfigPath)
  putEnv("PKG_CONFIG_LIBDIR", pkgConfigPath)

  ffmpegSetup(crossWindows=false, crossWindowsArm=true)

  let packages = setupPackages(enableWhisper=enableWhisper, crossWindowsArm=true)

  # Configure and build FFmpeg with llvm-mingw for ARM64
  withDir "ffmpeg_sources/ffmpeg":
    exec (&"""CC=aarch64-w64-mingw32-clang CXX=aarch64-w64-mingw32-clang++ AR=llvm-ar STRIP=llvm-strip RANLIB=llvm-ranlib PKG_CONFIG_PATH="{pkgConfigPath}" PKG_CONFIG_LIBDIR="{pkgConfigPath}" ./configure --prefix="{buildPath}" \
      --pkg-config=pkg-config \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{buildPath}/include" \
      --extra-ldflags="-L{buildPath}/lib" \
      --extra-libs="-lpthread -lm -lstdc++" \
      --arch=aarch64 \
      --target-os=mingw32 \
      --cross-prefix=aarch64-w64-mingw32- \
      --enable-cross-compile \""" & "\n" & setupCommonFlags(packages, crossWindowsArm=true))

    makeInstall()

task windowsarm, "Cross-compile to Windows ARM64 (requires llvm-mingw)":
  echo "Cross-compiling for Windows ARM64..."

  if not dirExists("build"):
    echo "FFmpeg for Windows ARM64 not found. Run 'nimble makeffwinarm' first."
  else:
    exec "nim c -d:danger --panics:on -d:windows -d:windows_arm " & flags &
         "--os:windows --cpu:arm64 --cc:clang " &
         "--clang.exe:aarch64-w64-mingw32-clang " &
         "--clang.linkerexe:aarch64-w64-mingw32-clang " &
         "--passL:-static " &
         "--out:auto-editor.exe src/main.nim"

    # Strip the Windows binary
    exec "llvm-strip -s auto-editor.exe"

task zshcomplete, "Generate zsh completions":
  zshcomplete()
