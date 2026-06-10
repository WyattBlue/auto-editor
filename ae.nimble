# Package
version = "0.0.0"
author = "WyattBlue"
description = "Effort free video editing!"
license = "Unlicense"
srcDir = "src"
bin = @["main=auto-editor"]

# Dependencies
requires "nim >= 2.2.2"
requires "csort == 1.0.0"
requires "nimcrypto == 0.7.3"

# Tasks
import std/[os, strutils, strformat, sequtils]

var disableVpx = getEnv("DISABLE_VPX").len > 0
var disableSvtAv1 = getEnv("DISABLE_SVTAV1").len > 0
var disableHevc = getEnv("DISABLE_HEVC").len > 0
var enable12bit = getEnv("ENABLE_12BIT").len > 0
let enableWhisper = getEnv("DISABLE_WHISPER").len == 0
let enableVpl = getEnv("DISABLE_VPL").len == 0 and not defined(macosx)

let
  nativeBuildPath = absolutePath("build")
  winBuildPath = absolutePath("build_win")
  winArmBuildPath = absolutePath("build_winarm")
  armv7BuildPath = absolutePath("build_armv7")
  wasmBuildPath = absolutePath("build_wasm")
  wa64BuildPath = absolutePath("build_wasm64")
  ffmpegSrcDir = absolutePath("ffmpeg_sources/ffmpeg")

type CrossKind = enum native, gccWin, llvmWin, armv7, wasm32, wasm64

proc stripProgram(kind: CrossKind = native) =
  let file = (
    if kind == gccWin or kind == llvmWin: "auto-editor.exe"
    elif kind == wasm32: "docs/src/auto-editor-web.wasm"
    elif kind == wasm64: "docs/src/auto-editor-web64.wasm"
    else: "auto-editor"
  )

  case kind
  of wasm32, wasm64:
    exec "wasm-strip " & file
  of gccWin:
    exec "x86_64-w64-mingw32-strip -s " & file
  of llvmWin:
    exec "llvm-strip -s " & file
  of armv7:
    exec "arm-linux-gnueabihf-strip -s " & file
  of native:
    when defined(macosx):
      exec "strip -ur " & file
    when defined(linux):
      exec "strip -s " & file

  when defined(macosx):
    exec &"stat -f \"%z bytes\" ./{file}"
    echo ""
  elif defined(linux):
    exec &"stat -c \"%s bytes\" ./{file}"
    echo ""

task test, "Run unit tests":
  exec "nim c -r tests/unit"

task make, "Export the project":
  exec "nim c -d:danger --out:auto-editor src/main.nim"
  stripProgram()

task brewmake, "Build auto-editor with deps dynamically linked.":
  exec "nim c -d:dynamic -d:danger --out:auto-editor src/main.nim"
  stripProgram()

task cleanff, "Clean build files":
  rmDir "build"
  rmDir "build_win"
  rmDir "build_winarm"
  rmDir "build_armv7"
  rmDir "build_wasm"
  rmDir "build_wasm64"
  for kind, path in walkDir("ffmpeg_sources"):
    if kind == pcDir: rmDir path


var disableDecoders: seq[string] = @[]
var disableParsers: seq[string] = @[]

# Can only decode (ambiguous encoder), Video [A-C]
disableDecoders &= "4xm,aasc,agm,aic,anm,ansi,apv,arbc,argo,aura,aura2,avrn,avs,bethsoftvid,bfi,bink,binkvideo,bmv_video,brender_pix,c93,cavs,cdgraphics,cdtoons,cdxl,clearvideo,cllc,cmv,cpia,cri,cscd,cyuv".split(",")
# [D-I]
disableDecoders &= "dds,dfa,dsicinvideo,dxa,dxtory,escape124,escape130,fic,flic,fmvc,fraps,frwu,g2m,gdv,gem,hnm4video,hq_hqa,hqx,hymt,idcin,idf,iff_ilbm,imm4,imm5,indeo2,indeo3,indeo4,indeo5,interplay_video,ipu".split(",")
# [J-M]
disableDecoders &= "jv,kgv1,kmvc,lagarith,lead,loco,lscr,m101,mad,mdec,media100,mimic,mjpegb,mmvideo,mobiclip,motionpixels,msa1,mscc,msmpeg4v1,msp2,mss1,mss2,mszh,mts2,mv30,mvc1,mvc2,mvdv,mvha,mwsc,mxpeg".split(",")
# [N-S]
disableDecoders &= "notchlc,nuv,paf_video,pdv,pgx,photocd,pictor,pixlet,prosumer,psd,ptx,qdraw,qpeg,rasc,rl2,rscc,rtv1,rv10,rv20,rv30,rv40,rv60,sanm,scpr,screenpresso,sga,sgirle,sheervideo,simbiosis_imx,smackvideo,smvjpeg,sp5x,srgc,svq3".split(",")
# [T-VP]
disableDecoders &= "targa_y216,tdsc,tgq,tgv,thp,tiertexseqvideo,tmv,tqi,truemotion1,truemotion2,truemotion2rt,tscc,tscc2,txd,ulti,v210x,vb,vble,vc1,vc1image,vcr1,vixl,vmdvideo,vmix,vmnc,vp3,vp4,vp5,vp6,vp6a,vp6f,vp7".split(",")
# [VQ-Z]
disableDecoders &= "vplayer,vqc,vvc,wcmv,wmv1,wmv2,wmv3,wmv3image,wnv1,ws_vqa,xan_wc3,xan_wc4,xbin,xpm,ylc,yop,zerocodec".split(",")

# Can only decode, Audio [0-A]
disableDecoders &= "8svx_exp,8svx_fib,aac_latm,acelp.kelvin,adpcm_4xm,adpcm_afc,adpcm_agm,adpcm_aica,adpcm_ct,adpcm_dtk,adpcm_ea,adpcm_ea_maxis_xa,adpcm_ea_r1,adpcm_ea_r2,adpcm_ea_r3,adpcm_ea_xas,adpcm_ima_acorn,adpcm_ima_apc".split(",")
# [B-F]
disableDecoders &= "binkaudio_dct,binkaudio_rdft,bmv_audio,bonk,cbd2_dpcm,cook,derf_dpcm,dolby_e,dsd_lsbf,dsd_lsbf_planar,dsd_msbf,dsd_msbf_planar,dsicinaudio,dss_sp,dst,dvaudio,evrc,fastaudio,ftr".split(",")
# [G-Q]
disableDecoders &= "g728,g729,gremlin_dpcm,gsm,gsm_ms,hca,hcom,iac,imc,interplay_dpcm,interplay_acm,mace3,mace6,metasound,misc4,mp1,mp3adu,msnsiren,musepack7,musepack8,osq,paf_audio,qcelp,qdm2,qdmc,qoa".split(",")
# [R-Z]
disableDecoders &= "ra_288,ralf,rka,sdx2_dpcm,shorten,sipr,siren,smackaud,sol_dpcm,tak,truespeech,twinvq,vmdaudio,wady_dpcm,wavarc,wavesynth,westwood_snd1,wmalossless,wmapro,wmav1,wmav2,wmavoice,xan_dpcm,xma1,xma2,zero12v".split(",")

# Technically obsolete [adpcm]
disableDecoders &= "adpcm_adx,adpcm_argo,adpcm_g722,adpcm_g726,adpcm_g726le,adpcm_ima_alp,adpcm_ima_amv,adpcm_ima_apm,adpcm_ima_cunning,adpcm_ima_dat4,adpcm_ima_dk3,adpcm_ima_dk4,adpcm_ima_ea_eacs,adpcm_ima_ea_sead,adpcm_ima_iss,adpcm_ima_moflex,adpcm_ima_mtf,adpcm_ima_oki,adpcm_ima_qt,adpcm_ima_qt_at,adpcm_ima_rad,adpcm_ima_smjpeg,adpcm_ima_ssi,adpcm_ima_wav,adpcm_ima_ws,adpcm_ima_xbox,adpcm_ms,adpcm_mtaf,adpcm_psx,adpcm_sanyo,adpcm_sbpro_2,adpcm_sbpro_3,adpcm_sbpro_4,adpcm_swf,adpcm_thp,adpcm_thp_le,adpcm_vima,adpcm_xa,adpcm_xmd,adpcm_yamaha,adpcm_zork".split(",")

# Technically obsolute
disableDecoders &= "alias_pix,apac,ape,atrac1,atrac3,atrac3al,atrac3p,atrac3pal,atrac9,asv1,asv2,avrp,bmp,ccaption,cinepak,cljr,cllc,comfortnoise,dpx,eacmv,eamad,eatgq,eatgv,eatqi,eightbps,eightsvx_exp,eightsvx_fib,ffvhuff,ffwavesynth,flv,g723_1,g726,g726le,g728,g729,hnm4_video,huffyuv,ircam,jacosub,magicyuv,nellymoser,on2avc,pam,pbm,pcm_vidc,pgmyuv,pjs,qtrle,ra_144,roq,roq_dpcm,rpza,r10k,r210,sgi,speedhq,speex,smacker,smc,snow,sonic,sonic_ls,subrip,utvideo,v210,v308,v408,v410,wbmp,wrapped_avframe,ws_snd1,wsaud,xbm,xface,xsub,xwd,y41p,yuv4".split(",")

disableDecoders &= ["pcm_alaw", "pcm_mulaw"]

disableDecoders &= ["h261", "opus"]  # We use libopus

# Irrelevant to this project
disableDecoders &= "cc_dec,dirac,fits,jpeg2000,jpegls,mpl2,msrle,pgssub,qoi,sami,subviewer,subviewer1,sunrast,targa,tiff,vvc_qsv".split(",")

disableParsers &= "bmp,cavsvideo,cook,dpx,g723_1,g729,misc4,sipr,tak,xbm,xma,xwd".split(",")

disableParsers &= ["h261", "vvc"]
disableParsers &= "adx,dirac,jpeg2000,jpegxs,qoi,vc1".split(",")

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
# AMD AMF SDK headers (header-only); the runtime is loaded from the driver.
# FFmpeg 8.1 requires AMF_VERSION >= 1.4.36.0.
let amfheaders = Package(
  name: "amf-headers",
  sourceUrl: "https://github.com/GPUOpen-LibrariesAndSDKs/AMF/archive/refs/tags/v1.4.36.tar.gz",
  sha256: "240a42033babc7920e5476506d5ac0c5628f67908833168e746406808d0ef146",
  ffFlag: "--enable-amf",
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
  sourceUrl: "https://github.com/webmproject/libvpx/archive/refs/tags/v1.16.0.tar.gz",
  sha256: "7a479a3c66b9f5d5542a4c6a1b7d3768a983b1e5c14c60a9396edc9b649e015c",
  buildArguments: "--disable-dependency-tracking --disable-examples --disable-unit-tests --enable-runtime-cpu-detect --enable-vp9-highbitdepth".split(" "),
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
  sourceUrl: "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.1.0/SVT-AV1-v4.1.0.tar.bz2",
  sha256: "184162d3db3a4448882b17230413b4938ca252eef6b3c5e2f1236b2fcf497881",
  buildSystem: "cmake",
  buildArguments: @["-DBUILD_APPS=OFF", "-DBUILD_DEC=OFF", "-DBUILD_ENC=ON", "-DENABLE_NASM=ON"],
  ffFlag: "--enable-libsvtav1",
)
let whisper = Package(
  name: "whisper",
  sourceUrl: "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.8.4.tar.gz",
  sha256: "b26f30e52c095ccb75da40b168437736605eb280de57381887bf9e2b65f31e66",
  buildSystem: "cmake",
  buildArguments: @[
    "-DGGML_NATIVE=OFF", # Favor portability, don't use native CPU instructions
    "-DGGML_CUDA=OFF",
    "-DWHISPER_SDL2=OFF",
    "-DWHISPER_BUILD_EXAMPLES=OFF",
    "-DWHISPER_BUILD_TESTS=OFF",
    "-DWHISPER_BUILD_SERVER=OFF",
    when defined(macosx) and hostCPU == "arm64": "-DGGML_METAL=ON" else: "-DGGML_METAL=OFF",
    when defined(macosx): "-DGGML_METAL_EMBED_LIBRARY=ON" else: "-DGGML_METAL_EMBED_LIBRARY=OFF",
    when defined(macosx): "-DGGML_BLAS=ON" else: "-DGGML_BLAS=OFF",
  ],
  ffFlag: "--enable-whisper",
)
let x264 = Package(
  name: "x264",
  sourceUrl: "https://code.videolan.org/videolan/x264/-/archive/b35605ace3ddf7c1a5d67a2eb553f034aef41d55/x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.bz2",
  sha256: "6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224",
  buildArguments: "--disable-cli --disable-lsmash --disable-swscale --disable-ffms --disable-opencl --enable-strip".split(" "),
  ffFlag: "--enable-libx264",
)
let x265 = Package(
  name: "x265",
  sourceUrl: "https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.2.tar.gz",
  sha256: "40b1ea0453e0309f0eba934e0ddf533f8f6295966679e8894e8f1c1c8d5e1210",
  buildSystem: "x265",
  ffFlag: "--enable-libx265"
)
let zlib = Package(
  name: "zlib",
  sourceUrl: "https://zlib.net/zlib-1.3.2.tar.gz",
  sha256: "bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16",
  ffFlag: "--enable-zlib",
)
let ffmpeg = Package(
  name: "ffmpeg",
  sourceUrl: "https://ffmpeg.org/releases/ffmpeg-8.1.1.tar.xz",
  sha256: "b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3",
)

proc selectPackages(kind: CrossKind = native): seq[Package] =
  result = @[]
  let isMacNative = defined(macosx) and kind == native
  let isWasm = kind == wasm32 or kind == wasm64
  if kind != armv7 and kind != llvmWin and not isMacNative and not isWasm:
    result.add nvheaders
  # AMD AMF: x86_64 Windows and Linux only
  if kind == gccWin or (kind == native and not isMacNative and hostCPU == "amd64"):
    result.add amfheaders
  if enableVpl and kind != llvmWin and kind != armv7 and not isWasm:
    result.add libvpl
  if enableWhisper:
    result.add whisper
  result &= [lame, opus, dav1d, x264, zlib]
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
    return "libvpx-1.16.0"
  if package.name == "libvpl":
    return "libvpl-2.16.0"
  if package.name == "nv-codec-headers":
    return "nv-codec-headers-n13.0.19.0"
  if package.name == "amf-headers":
    return "AMF-1.4.36"
  if package.name == "whisper":
    return "whisper.cpp-1.8.4"

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

proc download(package: Package) =
  if not fileExists(package.location):
    exec &"curl -fL --retry 5 --retry-all-errors --retry-delay 2 -O {package.sourceUrl}"
    let filename = "ffmpeg_sources" / package.location
    let hash = getFileHash(filename)
    if package.sha256 != hash:
      echo &"{filename}\nsha256 hash of {package.name} tarball do not match!"
      echo &"Expected: {package.sha256}\nGot: {hash}"
      quit(1)

proc extract(package: Package) =
  if not dirExists(package.name):
    let tarArgs = (if package.location.endsWith("bz2"): "xjf" else: "xf")
    exec &"tar {tarArgs} {package.location} && mv {package.dirName} {package.name}"
    let patchFile = &"../patches/{package.name}.patch"
    if fileExists(patchFile):
      let cmd = &"patch -d {package.name} -i {absolutePath(patchFile)} -p1 --force"
      echo "Applying patch: ", cmd
      exec cmd

proc makeInstall =
  when defined(macosx):
    exec "make -j$(sysctl -n hw.ncpu)"
  elif defined(linux):
    exec "make -j$(nproc)"
  else:
    exec "make -j4"
  exec "make install"

proc cmakeBuild(package: Package, buildPath: string, kind: CrossKind) =
  let cmakeBuildDir = buildPath / "pkg" / package.name
  mkDir(cmakeBuildDir)

  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
  ] & package.buildArguments

  if kind == armv7 and package.name == "libsvtav1":
    # SVT-AV1 enables NASM x86 asm; force off for ARM cross-compile
    cmakeArgs = cmakeArgs.filterIt(it != "-DENABLE_NASM=ON")
    cmakeArgs.add("-DENABLE_NASM=OFF")
    # Disable LTO: bitcode embeds -mfloat-abi=hard without -mfpu, so the LTO
    # recompile during FFmpeg's link tests fails ("architecture lacks an FPU")
    cmakeArgs.add("-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF")
    cmakeArgs.add("-DSVT_AV1_LTO=OFF")

  let sourceDir = absolutePath(".")
  if package.name == "libsvtav1" or package.name == "whisper":
    cmakeArgs.add(&"-DCMAKE_C_FLAGS=-ffile-prefix-map={sourceDir}/=")
    cmakeArgs.add(&"-DCMAKE_CXX_FLAGS=-ffile-prefix-map={sourceDir}/=")

  if package.name == "libsvtav1":
    # SVT-AV1's CMakeLists writes archives into the source tree at
    # Bin/${CMAKE_BUILD_TYPE}/. Override the CACHE PATH so the .a stays in
    # the build dir and re-installs don't produce a hybrid BSD/GNU archive.
    cmakeArgs.add(&"-DCMAKE_OUTPUT_DIRECTORY={cmakeBuildDir}/Bin")

  if kind == gccWin:
    let toolchainFile = buildPath.parentDir / "scripts" / "x86_64-w64-mingw32.cmake"
    cmakeArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")
  elif kind == llvmWin:
    let toolchainFile = buildPath.parentDir / "scripts" / "aarch64-w64-mingw32.cmake"
    cmakeArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")
    if package.name == "whisper":
      cmakeArgs.add("-DGGML_OPENMP=OFF")
  elif kind == armv7:
    let toolchainFile = buildPath.parentDir / "scripts" / "arm-linux-gnueabihf.cmake"
    cmakeArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")
    if package.name == "whisper":
      cmakeArgs.add("-DGGML_OPENMP=OFF")

  withDir cmakeBuildDir:
    if not fileExists("CMakeCache.txt"):
      let cmakeCmd = "cmake " & cmakeArgs.join(" ") & " " & sourceDir
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

    # ggml-base.a is built but not installed by cmake; copy it manually
    let ggmlBaseDst = libDir / "libggml-base.a"
    if not fileExists(ggmlBaseDst):
      let ggmlBaseSrc = "build_cmake/ggml/src/ggml-base.a"
      if fileExists(ggmlBaseSrc):
        echo &"Copying {ggmlBaseSrc} to {ggmlBaseDst}"
        exec &"cp \"{ggmlBaseSrc}\" \"{ggmlBaseDst}\""
    
    # Write whisper.pc from scratch to avoid format changes breaking string substitution
    let pcFile = buildPath / "lib/pkgconfig/whisper.pc"
    echo "Writing whisper.pc file"
    when defined(macosx) and hostCPU == "arm64":
      let libs = "-L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu -lggml-blas -lggml-metal"
      let libsPrivate = "-framework Accelerate -framework Metal -framework MetalKit -framework Foundation -lc++"
    elif defined(macosx):
      let libs = "-L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu -lggml-blas"
      let libsPrivate = "-framework Accelerate -framework MetalKit -framework Foundation -lc++"
    else:
      let libs = "-L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu"
      # OpenMP is disabled for Windows ARM cross-compile; native Linux uses libgomp
      let libsPrivate = if kind == llvmWin: "-lpthread -lm -lstdc++"
                        else: "-lgomp -lpthread -lm -lstdc++"
    writeFile(pcFile, &"""prefix={buildPath}
exec_prefix=${{prefix}}
libdir=${{exec_prefix}}/lib
includedir=${{prefix}}/include

Name: whisper
Description: whisper.cpp
Version: 1.8.4
Libs: {libs}
Libs.private: {libsPrivate}
Cflags: -I${{includedir}}
""")

proc cmakeBuildWasm(package: Package, buildPath: string, kind: CrossKind = wasm32) =
  let cmakeBuildDir = buildPath / "pkg" / package.name
  mkDir(cmakeBuildDir)
  let memArg = if kind == wasm64: " -sMEMORY64=1" else: ""

  let sourceDir = absolutePath(".")
  withDir cmakeBuildDir:
    if not fileExists("CMakeCache.txt"):
      var args = @[
        &"-DCMAKE_INSTALL_PREFIX={buildPath}",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_SHARED_LIBS=OFF",
      ]
      case package.name
      of "whisper":
        args &= @[
          "-DGGML_NATIVE=OFF", "-DGGML_CUDA=OFF", "-DGGML_METAL=OFF",
          "-DGGML_BLAS=OFF", "-DGGML_OPENMP=OFF", "-DGGML_BACKEND_DL=OFF",
          "-DWHISPER_SDL2=OFF", "-DWHISPER_BUILD_EXAMPLES=OFF",
          "-DWHISPER_BUILD_TESTS=OFF", "-DWHISPER_BUILD_SERVER=OFF",
        ]
        # -msimd128 enables ggml's hand-written wasm SIMD paths
        args &= @[
          &"\"-DCMAKE_C_FLAGS=-msimd128{memArg}\"",
          &"\"-DCMAKE_CXX_FLAGS=-msimd128{memArg}\"",
        ]
        if kind == wasm64:
          args.add "\"-DCMAKE_EXE_LINKER_FLAGS=-sMEMORY64=1\""
      of "libsvtav1":
        args &= @[
          "-DBUILD_APPS=OFF", "-DBUILD_DEC=OFF", "-DBUILD_ENC=ON", "-DENABLE_NASM=OFF",
          &"\"-DCMAKE_C_FLAGS=-matomics -mbulk-memory -msimd128{memArg}\"",
          &"\"-DCMAKE_CXX_FLAGS=-matomics -mbulk-memory -msimd128{memArg}\"",
        ]
      else:
        args &= package.buildArguments
        args &= @[&"\"-DCMAKE_C_FLAGS=-matomics -mbulk-memory -msimd128{memArg}\"",
                  &"\"-DCMAKE_CXX_FLAGS=-matomics -mbulk-memory -msimd128{memArg}\""]
      exec "emcmake cmake " & sourceDir & " " & args.join(" ")
    exec "make -j4 && make install"

  if package.name == "whisper":
    let libDir = buildPath / "lib"
    for libFile in ["ggml.a", "ggml-base.a", "ggml-cpu.a"]:
      let srcFile = libDir / libFile
      let dstFile = libDir / ("lib" & libFile)
      if fileExists(srcFile) and not fileExists(dstFile):
        exec &"mv \"{srcFile}\" \"{dstFile}\""
    let ggmlBaseDst = libDir / "libggml-base.a"
    if not fileExists(ggmlBaseDst):
      let ggmlBaseSrc = cmakeBuildDir / "ggml/src/ggml-base.a"
      if fileExists(ggmlBaseSrc):
        exec &"cp \"{ggmlBaseSrc}\" \"{ggmlBaseDst}\""
    writeFile(libDir / "pkgconfig" / "whisper.pc", &"""prefix={buildPath}
exec_prefix=${{prefix}}
libdir=${{exec_prefix}}/lib
includedir=${{prefix}}/include

Name: whisper
Description: whisper.cpp
Version: 1.8.4
Libs: -L${{libdir}} -lwhisper -lggml-base -lggml -lggml-cpu
Libs.private: -lpthread -lm -lstdc++
Cflags: -I${{includedir}}
""")

proc mesonBuild(package: Package, buildPath: string, kind: CrossKind) =
  let mesonBuildDir = buildPath / "pkg" / package.name
  let root = buildPath.parentDir
  mkDir(mesonBuildDir)

  var mesonArgs = @[
    &"--prefix={buildPath}",
    "--buildtype=release",
    "--default-library=static",
    "-Denable_docs=false",
    "-Denable_tools=false",
    "-Denable_examples=false",
    "-Denable_tests=false"
  ]
  if kind == wasm32 or kind == wasm64:
    mesonArgs.add "-Denable_asm=false"
    let memArg = if kind == wasm64: " -sMEMORY64=1" else: ""
    mesonArgs.add &"-Dc_args=\"-matomics -mbulk-memory -msimd128{memArg}\""
    if kind == wasm64:
      mesonArgs.add "-Dc_link_args=\"-sMEMORY64=1\""
    let bits = (if kind == wasm64: "64" else: "32")
    mesonArgs.add &"--cross-file={root}/scripts/wasm{bits}-emcc.txt"
  elif kind == gccWin:
    mesonArgs.add &"--cross-file={root}/scripts/x86_64-w64-mingw32.txt"
  elif kind == llvmWin:
    mesonArgs.add &"--cross-file={root}/scripts/aarch64-w64-mingw32.txt"
  elif kind == armv7:
    mesonArgs.add &"--cross-file={root}/scripts/arm-linux-gnueabihf.txt"

  let sourceDir = absolutePath(".")
  withDir mesonBuildDir:
    exec ("meson setup " & mesonArgs.join(" ") & " " & sourceDir)
    exec "ninja"
    exec "ninja install"

proc x265Build(buildPath: string, kind: CrossKind) =
  # Build x265 multiple times following the Homebrew approach:
  #  1: Build 12 bits static library version in separate directory (if enabled)
  #  2: Build 10 bits static library version in separate directory
  #  3: Build 8 bits version, linking also 10 and optionally 12 bits
  # By default supports 8 and 10 bits pixel formats (12-bit disabled for size)

  if fileExists(buildPath / "lib" / "pkgconfig" / "x265.pc"):
    return

  let isWasm = kind == wasm32 or kind == wasm64
  let cmakePrefix = if isWasm: "emcmake cmake" else: "cmake"
  let memArg = if kind == wasm64: " -sMEMORY64=1" else: ""

  let sourceDir = absolutePath("source")
  let pkgDir = buildPath / "pkg"
  let dir12bit = pkgDir / "x265_12bit"
  let dir10bit = pkgDir / "x265_10bit"
  let dir8bit = pkgDir / "x265_8bit"

  # For 10/12 bits version, only x86_64 has assembly instructions available
  var highBitDepthArgs: seq[string] = @[
    "-DHIGH_BIT_DEPTH=1",
    "-DEXPORT_C_API=0",
    "-DENABLE_SHARED=0",
    "-DENABLE_CLI=0"
  ]
  let isLinuxAarch64 = hostOS == "linux" and hostCPU == "arm64"

  if hostCPU != "amd64" or kind == llvmWin or isWasm:
    highBitDepthArgs.add("-DENABLE_ASSEMBLY=0")

  if isLinuxAarch64:
    highBitDepthArgs.add("-DENABLE_SVE2=0")

  var commonArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
  ]

  if isWasm:
    commonArgs.add(&"\"-DCMAKE_C_FLAGS=-matomics -mbulk-memory -msimd128 -pthread{memArg}\"")
    commonArgs.add(&"\"-DCMAKE_CXX_FLAGS=-matomics -mbulk-memory -msimd128 -pthread{memArg}\"")
    if kind == wasm64:
      commonArgs.add("\"-DCMAKE_EXE_LINKER_FLAGS=-sMEMORY64=1\"")

  if kind == llvmWin:
    let toolchainFile = buildPath.parentDir / "scripts" / "aarch64-w64-mingw32.cmake"
    commonArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")
    highBitDepthArgs.add("-DENABLE_ASSEMBLY=0")  # No x86 assembly for ARM64
  elif kind == gccWin:
    let toolchainFile = buildPath.parentDir / "scripts" / "x86_64-w64-mingw32.cmake"
    commonArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")

  # Build 12-bit version (optional, disabled by default for size)
  if enable12bit:
    echo "Building x265 12-bit..."
    var cmake12Args = @["-S", sourceDir, "-B", dir12bit, "-DMAIN12=ON"] & highBitDepthArgs & commonArgs
    let cmake12Cmd = cmakePrefix & " " & cmake12Args.join(" ")
    echo "RUN: ", cmake12Cmd
    exec cmake12Cmd
    exec &"cmake --build {dir12bit}"
    exec &"mv {dir12bit}/libx265.a {dir12bit}/libx265_main12.a"

  # Build 10-bit version
  echo "Building x265 10-bit..."
  var cmake10Args = @["-S", sourceDir, "-B", dir10bit] & highBitDepthArgs & commonArgs
  # Not applied for size: "-DENABLE_HDR10_PLUS=ON"
  let cmake10Cmd = cmakePrefix & " " & cmake10Args.join(" ")
  echo "RUN: ", cmake10Cmd
  exec cmake10Cmd
  exec &"cmake --build {dir10bit}"
  exec &"mv {dir10bit}/libx265.a {dir10bit}/libx265_main10.a"

  # Build 8-bit version with linked 10-bit and optionally 12-bit
  echo "Building x265 8-bit with multi-bit-depth support..."

  # Create 8bit directory and copy the 10-bit library
  mkDir(dir8bit)
  cpFile(dir10bit / "libx265_main10.a", dir8bit / "libx265_main10.a")

  # Build cmake command
  var cmake8Cmd = &"{cmakePrefix} -S {sourceDir} -B {dir8bit}"
  if enable12bit:
    # Copy 12-bit library and configure for 12-bit support
    cpFile(dir12bit / "libx265_main12.a", dir8bit / "libx265_main12.a")
    cmake8Cmd &= " \"-DEXTRA_LIB=x265_main10.a;x265_main12.a\""
    cmake8Cmd &= " -DLINKED_12BIT=1"
  else:
    cmake8Cmd &= " -DEXTRA_LIB=x265_main10.a"

  cmake8Cmd &= " -DEXTRA_LINK_FLAGS=-L."
  cmake8Cmd &= " -DLINKED_10BIT=1"
  cmake8Cmd &= " -DENABLE_SHARED=0"
  cmake8Cmd &= " -DENABLE_CLI=0"
  if isWasm:
    cmake8Cmd &= " -DENABLE_ASSEMBLY=0"
  for arg in commonArgs:
    cmake8Cmd &= " " & arg

  if isLinuxAarch64:
    cmake8Cmd &= " -DENABLE_SVE2=0"

  echo "RUN: ", cmake8Cmd
  exec cmake8Cmd
  exec &"cmake --build {dir8bit}"

  # Manually combine libraries for multi-bit-depth support
  echo "Combining x265 libraries for multi-bit-depth support..."
  if defined(macosx) and not isWasm:
    if enable12bit:
      exec &"libtool -static -o {dir8bit}/libx265_combined.a {dir8bit}/libx265.a {dir10bit}/libx265_main10.a {dir12bit}/libx265_main12.a"
    else:
      exec &"libtool -static -o {dir8bit}/libx265_combined.a {dir8bit}/libx265.a {dir10bit}/libx265_main10.a"
  else:
    let arCommand = (
      case kind
      of llvmWin: "llvm-ar"
      of gccWin: "x86_64-w64-mingw32-ar"
      of wasm32, wasm64: "emar"
      else: "ar"
    )
    withDir dir8bit:
      exec "echo 'CREATE libx265_combined.a' > combine.mri"
      exec "echo 'ADDLIB libx265.a' >> combine.mri"
      exec "echo 'ADDLIB libx265_main10.a' >> combine.mri"
      if enable12bit:
        exec "echo 'ADDLIB libx265_main12.a' >> combine.mri"
      exec "echo 'SAVE' >> combine.mri"
      exec "echo 'END' >> combine.mri"
      exec &"{arCommand} -M < combine.mri"

  # Replace the 8-bit only library with the combined one
  exec &"mv {dir8bit}/libx265_combined.a {dir8bit}/libx265.a"

  # Install from 8bit build
  exec &"cmake --install {dir8bit}"

proc autoconfBuildWasm(package: Package, buildPath: string, kind: CrossKind = wasm32) =
  let sourceDir = absolutePath(".")
  let autoBuildDir = buildPath / "pkg" / package.name
  mkDir(autoBuildDir)
  let memArg = if kind == wasm64: " -sMEMORY64=1" else: ""
  let ldFlags = if kind == wasm64: "-sMEMORY64=1" else: ""
  let x264Host = if kind == wasm64: "x86_64-gnu" else: "i686-gnu"
  withDir autoBuildDir:
    case package.name
    of "x264":
      if not fileExists("config.mak"):
        exec &"""CFLAGS="-matomics -mbulk-memory -msimd128{memArg}" LDFLAGS="{ldFlags}" emconfigure {sourceDir}/configure --prefix="{buildPath}" --host={x264Host} --enable-static --disable-cli --disable-asm --disable-interlaced --disable-lsmash --disable-swscale --disable-ffms --extra-cflags="-s USE_PTHREADS=1" """
        # x264 has no wasm asm, so the C path is all we get. Its configure
        # force-appends -fno-tree-vectorize last, which suppresses LLVM
        # autovectorization. Rewrite it in-place to enable wasm SIMD and
        # re-enable vectorization (must land after x264's flag to win).
        let makPath = "config.mak"
        writeFile(makPath, readFile(makPath).replace(
          "-fno-tree-vectorize", "-msimd128 -mrelaxed-simd -ftree-vectorize"))
      exec "emmake make -j4"
      exec "make install"
    of "libvpx":
      if not fileExists("Makefile"):
        exec &"""LDFLAGS="{ldFlags}" emconfigure {sourceDir}/configure --prefix="{buildPath}" --target=generic-gnu --disable-dependency-tracking --disable-runtime-cpu-detect --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --extra-cflags="-matomics -mbulk-memory -msimd128{memArg}" """
      makeInstall()
    of "zlib":
      # zlib ships a hand-written configure (not autotools): it reads CFLAGS
      # and LDFLAGS from the *environment*, not as positional args, so the
      # flags must be exported. Without -sMEMORY64=1 reaching the compiler it
      # silently emits wasm32 objects that can't link into the wasm64 build.
      # It also hard-codes AR=libtool whenever the build host is macOS,
      # ignoring emconfigure's AR=emar (native libtool can't archive wasm
      # objects); spoofing uname keeps it on the generic path.
      if not fileExists("Makefile"):
        exec &"""CFLAGS="-matomics -mbulk-memory -msimd128{memArg}" LDFLAGS="{ldFlags}" emconfigure {sourceDir}/configure --prefix="{buildPath}" --static --uname=Linux """
      makeInstall()
    else:
      # lame, opus — use package.buildArguments; opus also needs --disable-rtcd
      let extraArgs = if package.name == "opus": @["--disable-rtcd"] else: @[]
      if not fileExists("Makefile"):
        let args = (package.buildArguments & extraArgs).join(" ")
        exec &"""emconfigure {sourceDir}/configure --prefix="{buildPath}" --enable-static --disable-shared {args} CFLAGS="-matomics -mbulk-memory -msimd128{memArg}" LDFLAGS="{ldFlags}" """
      makeInstall()

proc ffmpegSetup(buildPath: string): seq[Package] =
  let kind =
    if buildPath.endsWith("_winarm"): llvmWin
    elif buildPath.endsWith("_win"): gccWin
    elif buildPath.endsWith("_armv7"): armv7
    elif buildPath.endsWith("_wasm64"): wasm64
    elif buildPath.endsWith("_wasm"): wasm32
    else: native
  let isWasm = kind == wasm32 or kind == wasm64
  let packages = selectPackages(kind)

  mkDir("ffmpeg_sources")
  withDir "ffmpeg_sources":
    for package in @[ffmpeg] & packages:
      package.download()
      package.extract()
      if package.name == "ffmpeg":
        continue

      withDir package.name:
        if package.buildSystem == "cmake":
          if isWasm:
            cmakeBuildWasm(package, buildPath, kind)
          else:
            cmakeBuild(package, buildPath, kind)
        elif package.buildSystem == "meson":
          mesonBuild(package, buildPath, kind)
        elif package.buildSystem == "x265":
          x265Build(buildPath, kind)
        elif isWasm:
          autoconfBuildWasm(package, buildPath, kind)
        else:
          # Special handling for nv-codec-headers which doesn't use configure
          if package.name == "nv-codec-headers":
            exec &"make install PREFIX=\"{buildPath}\""
          elif package.name == "amf-headers":
            # Header-only: FFmpeg expects <AMF/core/Version.h>
            exec &"rm -rf \"{buildPath}/include/AMF\" && mkdir -p \"{buildPath}/include\" && cp -r amf/public/include \"{buildPath}/include/AMF\""
          else:
            let sourceDir = absolutePath(".")
            let autoBuildDir = buildPath / "pkg" / package.name
            mkDir(autoBuildDir)
            withDir autoBuildDir:
              if not fileExists("Makefile") or package.name == "x264":
                var args = package.buildArguments
                var envPrefix = ""
                if kind == llvmWin:
                  if package.name == "libvpx":
                    args.add("--target=arm64-win64-gcc")
                  else:
                    args.add("--host=aarch64-w64-mingw32")
                  if package.name == "opus":
                    args.add("--disable-rtcd")
                  envPrefix = "CC=aarch64-w64-mingw32-clang CXX=aarch64-w64-mingw32-clang++ AR=llvm-ar STRIP=llvm-strip RANLIB=llvm-ranlib "
                elif kind == armv7:
                  if package.name == "libvpx":
                    args.add("--target=armv7-linux-gcc")
                  else:
                    args.add("--host=arm-linux-gnueabihf")
                  if package.name == "x264":
                    # x264 ARM asm uses R_ARM_MOVW_ABS_NC; needs PIC to link
                    # into FFmpeg's -fPIC test programs.
                    args.add("--enable-pic")
                  envPrefix = "CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++ AR=arm-linux-gnueabihf-ar STRIP=arm-linux-gnueabihf-strip RANLIB=arm-linux-gnueabihf-ranlib "
                  if package.name == "libvpx":
                    envPrefix &= "CROSS=arm-linux-gnueabihf- "
                elif kind == gccWin:
                  if package.name == "libvpx":
                    args.add("--target=x86_64-win64-gcc")
                  else:
                    args.add("--host=x86_64-w64-mingw32")
                  envPrefix = "CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib "
                if package.name != "x264":
                  args.add "--disable-shared"
                let cmd = &"{envPrefix}{sourceDir}/configure --prefix=\"{buildPath}\" --enable-static " & args.join(" ")
                echo "RUN: ", cmd
                exec cmd
              makeInstall()
  return packages


func basicPcms(): seq[string] =
  result.add "pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le".split(",")
  for t in ["s", "u"]:
    result.add &"pcm_{t}8"
    for size in ["16", "24", "32", "64"]:
      if t == "u" and size == "64": continue
      result.add &"pcm_{t}{size}le"

proc setupCommonFlags(packages: seq[Package], kind: CrossKind = native): string =
  var enableEncoders: seq[string] = "aac,aac_fixed,ac3,ac3_fixed,alac,ass,cfhd,dvbsub,dvdsub,dvvideo,ffv1,flac,gif,h263,h263p,hdr,libmp3lame,libopus,libx264,libx264rgb,movtext,mp2,mp2fixed,mpeg1video,mpeg2video,mpeg4,prores,prores_aw,prores_ks,srt,ssa,text,vorbis,webvtt".split(",")

  enableEncoders &= basicPcms()
  enableEncoders &= "pcm_bluray,pcm_s32le_planar,pcm_s24le_planar,pcm_s16be_planar,pcm_s16le_planar,pcm_s8_planar".split(",")

  var enableMuxers: seq[string] = "ac3,latm,adts,lrc,aiff,m4v,asf,matroska,matroska_audio,ass,ast,mov,au,mp2,avi,mp3,avif,mp4,mpeg1system,caf,mpeg1video,mpeg2dvd,dv,mpeg2video,psp,sox,flac,spdif,flv,obu,srt,gif,oga,w64,h263,ogg,wav,h264,ogv,webm,hevc,oma,iamf,opus,ipod,webvtt,ismv".split(",")
  enableMuxers &= basicPcms()

  let enableDemuxers = enableMuxers & @["image2", "png_pipe", "mpegts"]

  var filters = "aformat,abuffer,abuffersink,aresample,asetrate,atempo,anull,anullsrc,chromakey,colorkey,crop,drawbox,deesser,erosion,format,gblur,hflip,lenscorrection,loudnorm,lut,lutrgb,lutyuv,negate,overlay,pad,rotate,scale,vflip,volume".split(",")

  for package in packages:
    if package.name == "libvpx":
      enableEncoders &= ["libvpx_vp8", "libvpx_vp9"]
    if package.name == "x265":
      enableEncoders.add "libx265"
    if package.name == "libsvtav1":
      enableEncoders.add "libsvtav1"
    if package.name == "amf-headers":
      enableEncoders &= ["h264_amf", "hevc_amf", "av1_amf"]
    if package.name == "whisper":
      filters.add "whisper"

  let isCrossWasm = kind == wasm32 or kind == wasm64
  let isMacNative = defined(macosx) and kind == native

  if not isCrossWasm:
    if isMacNative:
      enableEncoders.add "aac_at,alac_at,h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox".split(",")
    elif kind != armv7 and kind != llvmWin:
      enableEncoders.add "av1_nvenc,h264_nvenc,hevc_nvenc"
    if enableVpl:
      enableEncoders.add "av1_qsv,hevc_qsv,mjpeg_qsv,mpeg2_qsv,vc1_qsv,vp8_qsv,vp9_qsv,vvc_qsv"

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
  --disable-decoder={disableDecoders.join(",")} \
  --disable-encoders \
  --enable-encoder={enableEncoders.join(",")} \
  --disable-demuxers \
  --enable-demuxer={enableDemuxers.join(",")} \
  --disable-muxers \
  --enable-muxer={enableMuxers.join(",")} \
  --disable-parser={disableParsers.join(",")} \
"""

  for package in packages:
    if package.ffFlag != "":
      commonFlags &= &"  {package.ffFlag} \\\n"

  if not isCrossWasm:
    if defined(arm) or defined(arm64) or kind == llvmWin or kind == armv7:
      commonFlags &= "  --enable-neon \\\n"

    if isMacNative:
      commonFlags &= "  --enable-videotoolbox \\\n"
      commonFlags &= "  --enable-audiotoolbox \\\n"
    elif kind != armv7 and kind != llvmWin:
      commonFlags &= "  --enable-nvenc \\\n"
      commonFlags &= "  --enable-ffnvcodec \\\n"

  commonFlags &= "--disable-autodetect"
  return commonFlags

proc setupDeps =
  let (mesonOutput, mesonCode) = gorgeEx("command -v meson")
  let (ninjaOutput, ninjaCode) = gorgeEx("command -v ninja")

  var toInstall: seq[string] = @[]
  if mesonCode != 0: toInstall.add "meson"
  if ninjaCode != 0: toInstall.add "ninja"
  if toInstall.len > 0:
    exec "pip install " & toInstall.join(" ")

task downloaddeps, "Download and Extract Cxx Dependencies":
  let allPackages = @[ffmpeg, nvheaders, libvpl, whisper, lame, opus, dav1d, x264, zlib, vpx, svtav1, x265]
  mkDir "ffmpeg_sources"
  withDir "ffmpeg_sources":
    for package in allPackages:
      download(package)

task makeff, "Build FFmpeg from source":
  setupDeps()
  let buildPath = nativeBuildPath

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

  let packages = ffmpegSetup(buildPath)

  let ffmpegBuildDir = buildPath / "pkg" / "ffmpeg"
  mkDir(ffmpegBuildDir)
  withDir ffmpegBuildDir:
    try:
      exec &"""{ffmpegSrcDir}/configure --prefix="{buildPath}" \
        --pkg-config-flags="--static" \
        --extra-cflags="-I{buildPath}/include" \
        --extra-ldflags="-L{buildPath}/lib" \
        --extra-libs="-lpthread -lm -lstdc++" \""" & "\n" & setupCommonFlags(packages)
    except OSError:
      exec &"cat {ffmpegSrcDir}/ffbuild/config.log"
      quit(1)
    makeInstall()

task makeffwin, "Build FFmpeg for Windows cross-compilation":
  setupDeps()
  putEnv("PKG_CONFIG_PATH", winBuildPath / "lib/pkgconfig")
  let packages = ffmpegSetup(winBuildPath)

  let ffmpegBuildDirWin = winBuildPath / "pkg" / "ffmpeg"
  mkDir(ffmpegBuildDirWin)
  withDir ffmpegBuildDirWin:
    exec (&"""CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib PKG_CONFIG_PATH="{winBuildPath}/lib/pkgconfig" {ffmpegSrcDir}/configure --prefix="{winBuildPath}" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{winBuildPath}/include" \
      --extra-ldflags="-L{winBuildPath}/lib" \
      --extra-libs="-lpthread -lm -lstdc++" \
      --arch=x86_64 \
      --target-os=mingw32 \
      --cross-prefix=x86_64-w64-mingw32- \
      --enable-cross-compile \""" & "\n" & setupCommonFlags(packages, gccWin))
    makeInstall()

task makewin, "Cross-compile to Windows (requires mingw-w64)":
  echo "Cross-compiling for Windows (64-bit)..."

  if not dirExists(winBuildPath):
    echo "FFmpeg for Windows not found. Run 'nimble makeffwin' first."
  else:
    exec "nim c -d:danger --passL:-static --os:windows --cpu:amd64 --cc:gcc " &
         "--gcc.exe:x86_64-w64-mingw32-gcc " &
         "--gcc.linkerexe:x86_64-w64-mingw32-gcc " &
         "--out:auto-editor.exe src/main.nim"
    stripProgram(gccWin)

task makeffwinarm, "Build FFmpeg for Windows ARM64 cross-compilation":
  setupDeps()
  let pkgConfigPath = winArmBuildPath  / "lib/pkgconfig"
  putEnv("PKG_CONFIG_PATH", pkgConfigPath)
  putEnv("PKG_CONFIG_LIBDIR", pkgConfigPath)

  let packages = ffmpegSetup(winArmBuildPath)

  let ffmpegBuildDirWinArm = winArmBuildPath / "pkg" / "ffmpeg"
  mkDir(ffmpegBuildDirWinArm)
  withDir ffmpegBuildDirWinArm:
    exec (&"""CC=aarch64-w64-mingw32-clang CXX=aarch64-w64-mingw32-clang++ AR=llvm-ar STRIP=llvm-strip RANLIB=llvm-ranlib PKG_CONFIG_PATH="{pkgConfigPath}" PKG_CONFIG_LIBDIR="{pkgConfigPath}" {ffmpegSrcDir}/configure --prefix="{winArmBuildPath}" \
      --pkg-config=pkg-config \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{winArmBuildPath}/include" \
      --extra-ldflags="-L{winArmBuildPath}/lib" \
      --extra-libs="-lpthread -lm -lstdc++" \
      --arch=aarch64 \
      --target-os=mingw32 \
      --cross-prefix=aarch64-w64-mingw32- \
      --enable-cross-compile \""" & "\n" & setupCommonFlags(packages, llvmWin))
    makeInstall()

task makewinarm, "Cross-compile to Windows ARM64 (requires llvm-mingw)":
  echo "Cross-compiling for Windows ARM64..."

  if not dirExists(winArmBuildPath):
    echo "FFmpeg for Windows ARM64 not found. Run 'nimble makeffwinarm' first."
  else:
    exec "nim c -d:danger --passL:-static --os:windows --cpu:arm64 --cc:clang " &
         "--clang.exe:aarch64-w64-mingw32-clang " &
         "--clang.linkerexe:aarch64-w64-mingw32-clang " &
         "--out:auto-editor.exe src/main.nim"
    stripProgram(llvmWin)

task makeffarmv7, "Build FFmpeg for Linux ARMv7 cross-compilation":
  setupDeps()
  let pkgConfigPath = armv7BuildPath / "lib/pkgconfig"
  putEnv("PKG_CONFIG_PATH", pkgConfigPath)
  putEnv("PKG_CONFIG_LIBDIR", pkgConfigPath)

  let packages = ffmpegSetup(armv7BuildPath)

  let ffmpegBuildDirArmv7 = armv7BuildPath / "pkg" / "ffmpeg"
  mkDir(ffmpegBuildDirArmv7)
  withDir ffmpegBuildDirArmv7:
    try:
      exec (&"""CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++ AR=arm-linux-gnueabihf-ar STRIP=arm-linux-gnueabihf-strip RANLIB=arm-linux-gnueabihf-ranlib PKG_CONFIG_PATH="{pkgConfigPath}" PKG_CONFIG_LIBDIR="{pkgConfigPath}" {ffmpegSrcDir}/configure --prefix="{armv7BuildPath}" \
        --pkg-config=pkg-config \
        --pkg-config-flags="--static" \
        --extra-cflags="-I{armv7BuildPath}/include -march=armv7-a -mfpu=neon-vfpv3 -mfloat-abi=hard" \
        --extra-ldflags="-L{armv7BuildPath}/lib" \
        --extra-libs="-lpthread -lm -lstdc++" \
        --arch=arm \
        --cpu=armv7-a \
        --target-os=linux \
        --cross-prefix=arm-linux-gnueabihf- \
        --enable-cross-compile \""" & "\n" & setupCommonFlags(packages, armv7))
    except OSError:
      exec "cat ffbuild/config.log"
      quit(1)
    makeInstall()

task makearmv7, "Cross-compile to Linux ARMv7 (requires arm-linux-gnueabihf toolchain)":
  echo "Cross-compiling for Linux ARMv7..."

  if not dirExists(armv7BuildPath):
    echo "FFmpeg for Linux ARMv7 not found. Run 'nimble makeffarmv7' first."
  else:
    exec "nim c -d:danger --passL:-static --os:linux --cpu:arm --cc:gcc " &
         "--gcc.exe:arm-linux-gnueabihf-gcc " &
         "--gcc.linkerexe:arm-linux-gnueabihf-gcc " &
         "--passC:-march=armv7-a --passC:-mfpu=neon-vfpv3 --passC:-mfloat-abi=hard " &
         "--out:auto-editor src/main.nim"
    stripProgram(armv7)


proc buildFFmpegForWasm(buildPath: string, kind: CrossKind) =
  setupDeps()
  putEnv("PKG_CONFIG_PATH", buildPath / "lib/pkgconfig")
  mkDir(buildPath)

  let packages = ffmpegSetup(buildPath)

  # lame ships no .pc file; create one so FFmpeg's configure can find it
  mkDir(buildPath / "lib" / "pkgconfig")
  writeFile(buildPath / "lib" / "pkgconfig" / "mp3lame.pc", &"""prefix={buildPath}
exec_prefix=${{prefix}}
libdir=${{prefix}}/lib
includedir=${{prefix}}/include

Name: mp3lame
Description: MPEG Layer 3 audio codec
Version: 3.100
Libs: -L${{libdir}} -lmp3lame
Cflags: -I${{includedir}}
""")

  let arch = if kind == wasm64: "x86_64" else: "x86_32"
  let memArg = if kind == wasm64: " -sMEMORY64=1" else: ""

  let ffmpegBuildDir = buildPath / "pkg" / "ffmpeg"
  mkDir(ffmpegBuildDir)
  withDir ffmpegBuildDir:
    exec (&"""PKG_CONFIG_PATH="{buildPath}/lib/pkgconfig" {ffmpegSrcDir}/configure --prefix="{buildPath}" \
      --cc=emcc \
      --cxx=em++ \
      --ar=emar \
      --ranlib=emranlib \
      --nm=emnm \
      --pkg-config-flags="--static" \
      --enable-cross-compile \
      --target-os=none \
      --arch={arch} \
      --disable-x86asm \
      --disable-inline-asm \
      --enable-pthreads \
      --disable-w32threads \
      --disable-os2threads \
      --extra-cflags="-I{buildPath}/include -matomics -mbulk-memory -msimd128 -pthread{memArg}" \
      --extra-ldflags="-L{buildPath}/lib -matomics -mbulk-memory -msimd128 -pthread{memArg}" \""" & "\n" & setupCommonFlags(packages, kind))
    makeInstall()

task makeffwasm, "Build FFmpeg for WebAssembly (requires emscripten)":
  buildFFmpegForWasm(wasmBuildPath, wasm32)

task makeffwasm64, "Build FFmpeg for WebAssembly 64-bit (requires emscripten)":
  buildFFmpegForWasm(wa64BuildPath, wasm64)

task makewasm, "Compile to wasm32 (requires emscripten, wabt)":
  echo "Compiling for wasm (32-bit)..."
  if not dirExists("build_wasm"):
    echo "FFmpeg for wasm not found. Run 'nimble makeffwasm' first."
  else:
    exec "nim c -d:danger -d:emscripten --threads:on --os:linux --cpu:wasm32 " &
        "--out:docs/src/auto-editor-web.js src/main.nim"
    stripProgram(wasm32)

task makewasm64, "Compile to wasm64 (requires emscripten, wabt)":
  echo "Compiling for wasm (64-bit)..."
  if not dirExists("build_wasm64"):
    echo "FFmpeg for wasm64 not found. Run 'nimble makeffwasm64' first."
  else:
    # --cpu:riscv64 picked for its 64-bit pointer ABI; using --cpu:amd64 makes
    # nimcrypto pull in x86 SHA/AVX intrinsics that emscripten can't compile.
    exec "nim c -d:danger -d:emscripten --threads:on --os:linux --cpu:riscv64 " &
         "--out:docs/src/auto-editor-web64.js src/main.nim"
    stripProgram(wasm64)
