# Package
version = "29.5.0"
author = "WyattBlue"
description = "Auto-Editor: Efficient media analysis and rendering"
license = "Unlicense"
srcDir = "src"
bin = @["main=auto-editor"]

# Dependencies
requires "nim >= 2.2.2"
requires "tinyre >= 1.6.0"
requires "checksums"

# Tasks
import std/os
import std/[strutils, strformat]
import src/cli

var disableHevc = getEnv("DISABLE_HEVC").len > 0
var enable12bit = getEnv("ENABLE_12BIT").len > 0
var enableWhisper = getEnv("DISABLE_WHISPER").len == 0

var flags = ""
if not disableHevc:
  flags &= "-d:enable_hevc "
if enableWhisper:
  flags &= "-d:enable_whisper "

task test, "Run unit tests":
  exec &"nim c {flags} -r tests/unit"

task make, "Export the project":
  exec &"nim c -d:danger --panics:on {flags} --passC:-flto --passL:-flto --out:auto-editor src/main.nim"
  when defined(macosx):
    exec "strip -ur auto-editor"
    exec "stat -f \"%z bytes\" ./auto-editor"
    echo ""
  when defined(linux):
    exec "strip -s auto-editor"

task cleanff, "Remove":
  rmDir("ffmpeg_sources")
  rmDir("build")

var disableDecoders: seq[string] = @[]
var disableEncoders: seq[string] = @[]
var disableDemuxers: seq[string] = @[]
var disableMuxers: seq[string] = @[]

# Marked as 'Experimental'
disableEncoders &= "avui,dca,mlp,opus,s302m,sonic,sonic_ls,truehd,vorbis".split(",")

# Can only decode (ambiguous encoder), Video [A-C]
disableDecoders &= "4xm,aasc,agm,aic,anm,ansi,apv,arbc,argo,aura,aura2,avrn,avs,bethsoftvid,bfi,binkvideo,bmv_video,brender_pix,c93,cavs,cdgraphics,cdtoons,cdxl,clearvideo,cllc,cmv,cpia,cri,cscd,cyuv".split(",")
# [D-I]
disableDecoders &= "dds,dfa,dsicinvideo,dxa,dxtory,escape124,escape130,fic,flic,fmvc,fraps,frwu,g2m,gdv,gem,hnm4video,hq_hqa,hqx,hymt,idcin,idf,iff_ilbm,imm4,imm5,indeo2,indeo3,indeo4,indeo5,interplayvideo,ipu".split(",")
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
disableDecoders &= "g728,g729,gremlin_dpcm,gsm,gsm_ms,hca,hcom,iac,imc,interplay_dpcm,interplayacm,mace3,mace6,metasound,misc4,mp1,mp3adu,msnsiren,musepack7,musepack8,osq,paf_audio,qcelp,qdm2,qdmc,qoa".split(",")
# [R-Z]
disableDecoders &= "ra_288,ralf,rka,sdx2_dpcm,shorten,sipr,siren,smackaud,sol_dpcm,tak,truespeech,twinvq,vmdaudio,wady_dpcm,wavarc,wavesynth,westwood_snd1,wmalossless,wmapro,wmavoice,xan_dpcm,xma1,xma2".split(",")

# Can only encode
disableEncoders &= "a64_multi,a64_multi5,ttml".split(",")

# Technically obsolete
disableDecoders &= @["flv", "snow"]
disableEncoders &= @["flv", "snow"]
disableMuxers &= @["flv", "f4v", "rso", "segafilm"]
disableDemuxers &= @["flv", "live_flv", "kux", "a64", "alp", "apm", "mm", "pp_bnk", "rso", "vmd", "sdns"]
disableDemuxers &= @["segafilm"]

# Image formats
disableDecoders &= @["tiff"]
disableEncoders &= @["tiff"]
disableMuxers &= @["ico"]
disableDemuxers &= @["ico", "image_tiff_pipe", "image_svg_pipe"]

let encodersDisabled = disableEncoders.join(",")
let decodersDisabled = disableDecoders.join(",")
let demuxersDisabled = disableDemuxers.join(",")
let muxersDisabled = disableMuxers.join(",")

type Package = object
  name: string
  sourceUrl: string
  sha256: string
  buildArguments: seq[string]
  buildSystem: string = "autoconf"
  ffFlag: string = ""
  mirrorUrl: string = ""

let nvheaders = Package(
  name: "nv-codec-headers",
  sourceUrl: "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/n13.0.19.0.tar.gz",
  sha256: "86d15d1a7c0ac73a0eafdfc57bebfeba7da8264595bf531cf4d8db1c22940116",
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
  sourceUrl: "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.tar.gz",
  sha256: "b7637334527201fdfd6dd6a02e67aceffb0e5e60155bbd89175647a80301c92c",
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
  sourceUrl: "https://code.videolan.org/videolan/dav1d/-/archive/1.5.2/dav1d-1.5.2.tar.bz2",
  sha256: "c748a3214cf02a6d23bc179a0e8caea9d6ece1e46314ef21f5508ca6b5de6262",
  buildSystem: "meson",
  ffFlag: "--enable-libdav1d",
)
let svtav1 = Package(
  name: "libsvtav1",
  sourceUrl: "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v3.1.0/SVT-AV1-v3.1.0.tar.bz2",
  sha256: "8231b63ea6c50bae46a019908786ebfa2696e5743487270538f3c25fddfa215a",
  buildSystem: "cmake",
  buildArguments: @["-DBUILD_APPS=OFF", "-DBUILD_DEC=OFF", "-DBUILD_ENC=ON", "-DENABLE_NASM=ON"],
  ffFlag: "--enable-libsvtav1",
)
let whisper = Package(
  name: "whisper",
  sourceUrl: "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.8.2.tar.gz",
  sha256: "bcee25589bb8052d9e155369f6759a05729a2022d2a8085c1aa4345108523077",
  buildSystem: "cmake",
  buildArguments: @[
    "-DGGML_NATIVE=OFF", # Favor portability, don't use native CPU instructions
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
  sourceUrl: "https://code.videolan.org/videolan/x264/-/archive/32c3b801191522961102d4bea292cdb61068d0dd/x264-32c3b801191522961102d4bea292cdb61068d0dd.tar.bz2",
  sha256: "d7748f350127cea138ad97479c385c9a35a6f8527bc6ef7a52236777cf30b839",
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

proc setupPackages(enableWhisper: bool): seq[Package] =
  result = @[]
  if not defined(macosx):
    result.add nvheaders
  if enableWhisper:
    result.add whisper
  result &= [lame, opus, vpx, dav1d, svtav1, x264]
  if not disableHevc:
    result.add x265
  return result

func location(package: Package): string = # tar location
  if package.name == "libvpx":
    "v1.15.2.tar.gz"
  elif package.name == "nv-codec-headers":
    "n13.0.19.0.tar.gz"
  elif package.name == "whisper":
    "v1.8.2.tar.gz"
  else:
    package.sourceUrl.split("/")[^1]

func dirName(package: Package): string =
  if package.name == "libvpx":
    return "libvpx-1.15.2"
  if package.name == "nv-codec-headers":
    return "nv-codec-headers-n13.0.19.0"
  if package.name == "whisper":
    return "whisper.cpp-1.8.2"

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

proc cmakeBuild(package: Package, buildPath: string, crossWindows: bool = false) =
  mkDir("build_cmake")

  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
  ] & package.buildArguments

  if crossWindows:
    cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix")
    cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix")
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
          "Libs: -L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu"
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

proc x265Build(buildPath: string, crossWindows: bool = false) =
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

  if not isX86_64:
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
  if crossWindows:
    commonArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    commonArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix")
    commonArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix")
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
    if crossWindows:
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


proc mesonBuild(buildPath: string, crossWindows: bool = false) =
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

  if crossWindows:
    # Create cross-compilation file for meson
    let crossFile = "build_meson/meson-cross.txt"
    writeFile(crossFile, """
[binaries]
c = 'x86_64-w64-mingw32-gcc-posix'
cpp = 'x86_64-w64-mingw32-g++-posix'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
pkgconfig = 'x86_64-w64-mingw32-pkg-config'

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

proc ffmpegSetup(crossWindows: bool) =
  # Create directories
  mkDir("ffmpeg_sources")
  mkDir("build")

  let buildPath = absolutePath("build")
  let packages = setupPackages(enableWhisper=enableWhisper)

  withDir "ffmpeg_sources":
    for package in @[ffmpeg] & packages:
      if not fileExists(package.location):

        if package.mirrorUrl != "":
          exec &"curl -O -L {package.mirrorUrl}"
        else:
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
          cmakeBuild(package, buildPath, crossWindows)
        elif package.buildSystem == "x265":
          x265build(buildPath, crossWindows)
        elif package.buildSystem == "meson":
          mesonBuild(buildPath, crossWindows)
        else:
          # Special handling for nv-codec-headers which doesn't use configure
          if package.name == "nv-codec-headers":
            exec &"make install PREFIX=\"{buildPath}\""
          else:
            if not fileExists("Makefile") or package.name == "x264":
              var args = package.buildArguments
              var envPrefix = ""
              if crossWindows:
                if package.name == "libvpx":
                  args.add("--target=x86_64-win64-gcc")
                else:
                  args.add("--host=x86_64-w64-mingw32")
                envPrefix = "CC=x86_64-w64-mingw32-gcc-posix CXX=x86_64-w64-mingw32-g++-posix AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib "
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

proc setupCommonFlags(packages: seq[Package]): string =
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
    --disable-encoder={encodersDisabled} \
    --disable-decoder={decodersDisabled} \
    --disable-demuxer={demuxersDisabled} \
    --disable-muxer={muxersDisabled} \
  """

  for package in packages:
    if package.ffFlag != "":
      commonFlags &= &"  {package.ffFlag} \\\n"

  if defined(arm) or defined(arm64):
    commonFlags &= "  --enable-neon \\\n"

  if defined(macosx):
    commonFlags &= "  --enable-videotoolbox \\\n"
    commonFlags &= "  --enable-audiotoolbox \\\n"
  else:
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

  # Debug: List pkg-config files to verify whisper.pc exists
  when defined(linux):
    echo "Checking for whisper.pc files:"
    exec &"find {buildPath} -name 'whisper.pc' -type f"
    echo "Current PKG_CONFIG_PATH: ", getEnv("PKG_CONFIG_PATH")
    exec "pkg-config --list-all | grep whisper || echo 'whisper not found in pkg-config'"

  withDir "ffmpeg_sources/ffmpeg":
    exec &"""./configure --prefix="{buildPath}" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{buildPath}/include" \
      --extra-ldflags="-L{buildPath}/lib" \
      --extra-libs="-lpthread -lm" \""" & "\n" & setupCommonFlags(packages)
    makeInstall()

task makeffwin, "Build FFmpeg for Windows cross-compilation":
  setupDeps()
  let buildPath = absolutePath("build")
  putEnv("PKG_CONFIG_PATH", buildPath / "lib/pkgconfig")

  ffmpegSetup(crossWindows=true)

  let packages = setupPackages(enableWhisper=enableWhisper)

  # Configure and build FFmpeg with MinGW
  withDir "ffmpeg_sources/ffmpeg":
    exec (&"""CC=x86_64-w64-mingw32-gcc-posix CXX=x86_64-w64-mingw32-g++-posix AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib PKG_CONFIG_PATH="{buildPath}/lib/pkgconfig" ./configure --prefix="{buildPath}" \
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
    exec "nim c -d:danger " & flags & " --os:windows --cpu:amd64 --cc:gcc " &
         "--gcc.exe:x86_64-w64-mingw32-gcc-posix " &
         "--gcc.linkerexe:x86_64-w64-mingw32-gcc-posix " &
         "--passL:-lbcrypt " & # Add Windows Bcrypt library
         "--passL:-lstdc++ " & # Add C++ standard library
         "--passL:-static " &
         "--out:auto-editor.exe src/main.nim"

    # Strip the Windows binary
    exec "x86_64-w64-mingw32-strip -s auto-editor.exe"

task zshcomplete, "Generate zsh completions":
  echo "#compdef auto-editor"
  echo ""
  echo "_auto-editor() {"
  echo "  local -a subcommands"
  echo "  subcommands=("
  for (command, help) in commands:
    if help != "":
      echo "    '" & command & ":" & help.replace("'", "'\\''") & "'"
    else:
      echo "    '" & command & "'"
  echo "  )"
  echo ""
  echo "  _describe 'command' subcommands"
  echo "}"
  echo ""
  echo "_auto-editor \"$@\""
