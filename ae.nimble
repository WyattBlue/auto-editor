# Package
version = "0.0.0"
author = "WyattBlue"
description = "Effort free video editing!"
license = "Unlicense"
srcDir = "src"
bin = @["main=auto-editor"]

# Dependencies
requires "nim >= 2.2.2"
requires "tinyre#77469f5"
requires "csort == 1.0.0"
requires "nimcrypto == 0.7.3"

# Tasks
import std/[os, strutils, strformat]

var disableVpx = getEnv("DISABLE_VPX").len > 0
var disableSvtAv1 = getEnv("DISABLE_SVTAV1").len > 0
var disableHevc = getEnv("DISABLE_HEVC").len > 0
var enable12bit = getEnv("ENABLE_12BIT").len > 0
let enableWhisper = getEnv("DISABLE_WHISPER").len == 0
let enableVpl = getEnv("DISABLE_VPL").len == 0 and not defined(macosx)

let buildPath = absolutePath("build")

proc stripProgram(forWasm, gccWin, llvmWin: bool = false) =
  var file = "auto-editor"
  if gccWin or llvmWin:
    file = "auto-editor.exe"
  elif forWasm:
    file = "docs/src/auto-editor-web.wasm"

  if forWasm:
    exec "wasm-strip " & file
  elif gccWin:
    exec "x86_64-w64-mingw32-strip -s " & file
  elif llvmWin:
    exec "llvm-strip -s " & file
  elif defined(macosx):
    exec "strip -ur " & file
  elif defined(linux):
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
  exec "nim c -d:danger --panics:on --passC:-flto --passL:-flto --out:auto-editor src/main.nim"
  stripProgram()

task brewmake, "Build auto-editor with deps dynamically linked.":
  exec "nim c -d:dynamic -d:danger --panics:on --passC:-flto --passL:-flto --out:auto-editor src/main.nim"
  stripProgram()

task cleanff, "Clean build files":
  rmDir "build"
  rmDir "build_wasm"
  for kind, path in walkDir("ffmpeg_sources"):
    if kind == pcDir: rmDir path


var disableDecoders: seq[string] = @[]
var disableDemuxers: seq[string] = @[]
var disableMuxers: seq[string] = @[]
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
disableDecoders &= "alias_pix,apac,ape,atrac1,atrac3,atrac3al,atrac3p,atrac3pal,atrac9,asv1,asv2,avrp,bmp,ccaption,cinepak,cljr,cllc,comfortnoise,dpx,eacmv,eamad,eatgq,eatgv,eatqi,eightbps,eightsvx_exp,eightsvx_fib,ffvhuff,ffwavesynth,flv,g723_1,g726,g726le,g728,g729,hnm4_video,huffyuv,ircam,jacosub,magicyuv,nellymoser,on2avc,pam,pbm,pcm_vidc,pgmyuv,pjs,qtrle,ra_144,roq,roq_dpcm,rpza,r10k,r210,sgi,speedhq,speex,smacker,smc,snow,sonic,sonic_ls,subrip,utvideo,v210,v308,v408,v410,wbmp,wrapped_avframe,ws_snd1,xbm,xface,xsub,xwd,y41p,yuv4".split(",")
disableMuxers &= "amv,cavsvideo,flv,f4v,g722,g723_1,g726,g726le,gxf,ircam,jacosub,mcc,mxf,mxf_d10,mxf_opatom,nut,pcm_vidc,rm,roq,rso,segafilm,sup,swf,truehd,ttml,voc,wsaud,wtv,wv".split(",")
disableDemuxers &= "a64,alp,ape,apm,bethsoftvid,bink,binka,cavsvideo,dsicin,flv,g722,g723_1,g726,g726le,g728,g729,gxf,ircam,jacosub,kux,live_flv,mcc,mm,mxf,nistsphere,nut,pcm_vidc,pjs,pp_bnk,redspark,rm,roq,rso,sdns,segafilm,smush,smacker,swf,tedcaptions,thp,vmd,voc,wtv,xa,xmd,xmv,xvag,xwma,yop".split(",")
disableParsers &= "bmp,cavsvideo,cook,dpx,g723_1,g729,misc4,sipr,tak,xbm,xma,xwd".split(",")

disableDemuxers &= ["pcm_alaw", "pcm_mulaw"]
disableMuxers &= ["pcm_alaw", "pcm_mulaw"]
disableDecoders &= ["pcm_alaw", "pcm_mulaw"]

## h26 whatever
disableDemuxers &= ["h261"]
disableMuxers &= ["h261", "rtp", "rtp_mpegts"]
disableDecoders &= ["h261"]
disableParsers.add "h261"

# Irrelevant to this project
disableDecoders &= "cc_dec,dirac,fits,jpeg2000,jpegls,mpl2,msrle,pgssub,qoi,sami,subviewer,subviewer1,sunrast,targa,tiff".split(",")
disableMuxers &= "fits,framecrc,framehash,framemd5,hash,hls,ico,image2,image2pipe,md5,rawvideo,segment,smoothstreaming,stream_segment,streamhash,tee,uncodedframecrc".split(",")
disableDemuxers &= "fits,hls,ico,image_tiff_pipe,image_svg_pipe,image2,image2pipe,jpegxl_anim,vplayer".split(",")
disableParsers &= "jpeg2000,jpegxs,qoi".split(",")

disableDemuxers &= "image_bmp_pipe,image_cri_pipe,image_dds_pipe,image_dpx_pipe,image_exr_pipe,image_gem_pipe,image_gif_pipe,image_hdr_pipe,image_j2k_pipe,image_jpeg_pipe,image_jpegls_pipe,image_jpegxl_pipe,image_jpegxs_pipe,image_pam_pipe,image_pbm_pipe,image_pcx_pipe,image_pfm_pipe,image_pgm_pipe,image_pgmyuv_pipe,image_pgx_pipe,image_phm_pipe,image_photocd_pipe,image_pictor_pipe,image_png_pipe,image_ppm_pipe,image_psd_pipe,image_qdraw_pipe,image_qoi_pipe,image_sgi_pipe,image_sunrast_pipe,image_vbn_pipe,image_webp_pipe,image_xbm_pipe,image_xpm_pipe,image_xwd_pipe".split(",")


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
  buildArguments: "--disable-cli --disable-lsmash --disable-swscale --disable-ffms --enable-strip".split(" "),
  ffFlag: "--enable-libx264",
)
let x265 = Package(
  name: "x265",
  sourceUrl: "https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.2.tar.gz",
  sha256: "40b1ea0453e0309f0eba934e0ddf533f8f6295966679e8894e8f1c1c8d5e1210",
  buildSystem: "x265",
  ffFlag: "--enable-libx265"
)
let ffmpeg = Package(
  name: "ffmpeg",
  sourceUrl: "https://ffmpeg.org/releases/ffmpeg-8.1.tar.xz",
  sha256: "b072aed6871998cce9b36e7774033105ca29e33632be5b6347f3206898e0756a",
)

proc selectPackages(enableWhisper: bool, crossWindowsArm: bool = false): seq[Package] =
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
    return "libvpx-1.16.0"
  if package.name == "libvpl":
    return "libvpl-2.16.0"
  if package.name == "nv-codec-headers":
    return "nv-codec-headers-n13.0.19.0"
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
    exec &"curl -O -L {package.sourceUrl}"
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

proc cmakeBuild(package: Package, buildPath: string, crossWindows: bool = false, crossWindowsArm: bool = false) =
  mkDir("build_cmake")

  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
  ] & package.buildArguments

  if package.name == "libsvtav1" or package.name == "whisper":
    let srcDir = absolutePath(".")
    cmakeArgs.add(&"-DCMAKE_C_FLAGS=-ffile-prefix-map={srcDir}/=")
    cmakeArgs.add(&"-DCMAKE_CXX_FLAGS=-ffile-prefix-map={srcDir}/=")

  if crossWindowsArm:
    let toolchainFile = buildPath.parentDir / "cmake" / "aarch64-w64-mingw32.cmake"
    cmakeArgs.add(&"-DCMAKE_TOOLCHAIN_FILE={toolchainFile}")
    if package.name == "whisper":
      cmakeArgs.add("-DGGML_OPENMP=OFF")
  elif crossWindows:
    cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc")
    cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++")
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
      let libsPrivate = if crossWindowsArm: "-lpthread -lm -lstdc++"
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
  let isLinuxAarch64 = hostOS == "linux" and hostCPU == "arm64"

  if hostCPU != "amd64" or crossWindowsArm:
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
    commonArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc")
    commonArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++")
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
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
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

  let packages = selectPackages(enableWhisper=enableWhisper, crossWindowsArm=crossWindowsArm)

  withDir "ffmpeg_sources":
    for package in @[ffmpeg] & packages:
      package.download()
      package.extract()
      if package.name == "ffmpeg":
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
                envPrefix = "CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib "
              if package.name != "x264":
                args.add "--disable-shared"
              let cmd = &"{envPrefix}./configure --prefix=\"{buildPath}\" --enable-static " & args.join(" ")
              echo "RUN: ", cmd
              exec cmd
            makeInstall()


proc setupCommonFlags(packages: seq[Package], crossWasm: bool = false, winArm: bool = false): string =
  var enableEncoders: seq[string] = "aac,aac_fixed,ac3,ac3_fixed,alac,ass,cfhd,dvbsub,dvdsub,dvvideo,ffv1,flac,gif,h263,h263p,hdr,libmp3lame,libopus,libx264,libx264rgb,movtext,mp2,mp2fixed,mpeg1video,mpeg2video,mpeg4,prores,prores_aw,prores_ks,srt,ssa,text,webvtt".split(",")

  enableEncoders.add "pcm_f16le,pcm_f24le,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le".split(",")
  for t in ["s", "u"]:
    enableEncoders.add &"pcm_{t}8"
    for size in ["16", "24", "32", "64"]:
      if t == "u" and size == "64": continue
      enableEncoders.add &"pcm_{t}{size}le"
  enableEncoders &= "pcm_bluray,pcm_s32le_planar,pcm_s24le_planar,pcm_s16be_planar,pcm_s16le_planar,pcm_s8_planar".split(",")

  var filters = "scale,crop,pad,format,gblur,lut,negate,aformat,abuffer,abuffersink,aresample,atempo,anull,anullsrc,volume,loudnorm,asetrate".split(",")

  for package in packages:
    if package.name == "libvpx":
      enableEncoders &= ["libvpx_vp8", "libvpx_vp9"]
    if package.name == "x265":
      enableEncoders.add "libx265"
    if package.name == "libsvtav1":
      enableEncoders.add "libsvtav1"
    if package.name == "whisper":
      filters.add "whisper"

  if not crossWasm:
    when defined(macosx):
      enableEncoders.add "aac_at,alac_at,h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox".split(",")
    else:
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
  --disable-encoders \
  --enable-encoder={enableEncoders.join(",")} \
  --disable-decoder={disableDecoders.join(",")} \
  --disable-demuxer={disableDemuxers.join(",")} \
  --disable-muxer={disableMuxers.join(",")} \
  --disable-parser={disableParsers.join(",")} \
"""

  for package in packages:
    if package.ffFlag != "":
      commonFlags &= &"  {package.ffFlag} \\\n"

  if not crossWasm:
    if defined(arm) or defined(arm64) or winArm:
      commonFlags &= "  --enable-neon \\\n"

    if defined(macosx):
      commonFlags &= "  --enable-videotoolbox \\\n"
      commonFlags &= "  --enable-audiotoolbox \\\n"
    elif not winArm:
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
  let allPackages = @[ffmpeg, nvheaders, libvpl, whisper, lame, opus, dav1d, x264, vpx, svtav1, x265]
  mkDir "ffmpeg_sources"
  withDir "ffmpeg_sources":
    for package in allPackages:
      download(package)

task makeff, "Build FFmpeg from source":
  setupDeps()
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

  let packages = selectPackages(enableWhisper=enableWhisper)

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

task makeffwin, "Build FFmpeg for Windows cross-compilation":
  setupDeps()
  putEnv("PKG_CONFIG_PATH", buildPath / "lib/pkgconfig")

  ffmpegSetup(crossWindows=true)
  let packages = selectPackages(enableWhisper=enableWhisper)

  # Configure and build FFmpeg with MinGW
  withDir "ffmpeg_sources/ffmpeg":
    exec (&"""CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib PKG_CONFIG_PATH="{buildPath}/lib/pkgconfig" ./configure --prefix="{buildPath}" \
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
    exec "nim c -d:danger --panics:on --os:windows --cpu:amd64 --cc:gcc " &
         "--gcc.exe:x86_64-w64-mingw32-gcc " &
         "--gcc.linkerexe:x86_64-w64-mingw32-gcc " &
         "--passL:-static " &
         "--out:auto-editor.exe src/main.nim"
    stripProgram(gccWin=true)

task makeffwinarm, "Build FFmpeg for Windows ARM64 cross-compilation":
  setupDeps()
  let pkgConfigPath = buildPath / "lib/pkgconfig"
  putEnv("PKG_CONFIG_PATH", pkgConfigPath)
  putEnv("PKG_CONFIG_LIBDIR", pkgConfigPath)

  ffmpegSetup(crossWindows=false, crossWindowsArm=true)

  let packages = selectPackages(enableWhisper=enableWhisper, crossWindowsArm=true)

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
      --enable-cross-compile \""" & "\n" & setupCommonFlags(packages, winArm=true))

    makeInstall()

task windowsarm, "Cross-compile to Windows ARM64 (requires llvm-mingw)":
  echo "Cross-compiling for Windows ARM64..."

  if not dirExists("build"):
    echo "FFmpeg for Windows ARM64 not found. Run 'nimble makeffwinarm' first."
  else:
    exec "nim c -d:danger --panics:on --os:windows --cpu:arm64 --cc:clang " &
         "--clang.exe:aarch64-w64-mingw32-clang " &
         "--clang.linkerexe:aarch64-w64-mingw32-clang " &
         "--passL:-static " &
         "--out:auto-editor.exe src/main.nim"
    stripProgram(llvmWin=true)

let wasmBuildPath = absolutePath("build_wasm")

proc autoconfBuildWasm(package: Package, buildPath: string) =
  case package.name
  of "x264":
    if not fileExists("config.mak"):
      exec &"""CFLAGS="-matomics -mbulk-memory" emconfigure ./configure --prefix="{buildPath}" --host=i686-gnu --enable-static --disable-cli --disable-asm --disable-lsmash --disable-swscale --disable-ffms --extra-cflags="-s USE_PTHREADS=1" """
    exec "emmake make -j4"
    exec "make install"
  of "libvpx":
    if not fileExists("Makefile"):
      exec &"""emconfigure ./configure --prefix="{buildPath}" --target=generic-gnu --disable-dependency-tracking --disable-runtime-cpu-detect --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --extra-cflags="-matomics -mbulk-memory" """
    makeInstall()
  else:
    # lame, opus — use package.buildArguments; opus also needs --disable-rtcd
    let extraArgs = if package.name == "opus": @["--disable-rtcd"] else: @[]
    if not fileExists("Makefile"):
      let args = (package.buildArguments & extraArgs).join(" ")
      exec &"""emconfigure ./configure --prefix="{buildPath}" --enable-static --disable-shared {args} CFLAGS="-matomics -mbulk-memory" """
    makeInstall()

proc cmakeBuildWasm(package: Package, buildPath: string) =
  mkDir("build_wasm_cmake")
  withDir "build_wasm_cmake":
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
      of "libsvtav1":
        args &= @[
          "-DBUILD_APPS=OFF", "-DBUILD_DEC=OFF", "-DBUILD_ENC=ON", "-DENABLE_NASM=OFF",
          "\"-DCMAKE_C_FLAGS=-matomics -mbulk-memory\"",
          "\"-DCMAKE_CXX_FLAGS=-matomics -mbulk-memory\"",
        ]
      else:
        args &= package.buildArguments
        args &= @["\"-DCMAKE_C_FLAGS=-matomics -mbulk-memory\"",
                  "\"-DCMAKE_CXX_FLAGS=-matomics -mbulk-memory\""]
      exec "emcmake cmake .. " & args.join(" ")
    exec "make -j4"
    exec "make install"

  if package.name == "whisper":
    let libDir = buildPath / "lib"
    for libFile in ["ggml.a", "ggml-base.a", "ggml-cpu.a"]:
      let srcFile = libDir / libFile
      let dstFile = libDir / ("lib" & libFile)
      if fileExists(srcFile) and not fileExists(dstFile):
        exec &"mv \"{srcFile}\" \"{dstFile}\""
    let ggmlBaseDst = libDir / "libggml-base.a"
    if not fileExists(ggmlBaseDst):
      let ggmlBaseSrc = "build_wasm_cmake/ggml/src/ggml-base.a"
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

proc mesonBuildWasm(package: Package, buildPath: string) =
  mkDir("build_meson")
  writeFile("build_meson/meson-cross.txt", """
[binaries]
c = 'emcc'
cpp = 'em++'
ar = 'emar'
strip = 'wasm-strip'

[host_machine]
system = 'emscripten'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'
""")
  withDir "build_meson":
    if not fileExists("build.ninja"):
      exec &"""meson setup --prefix="{buildPath}" --buildtype=release --default-library=static -Denable_docs=false -Denable_tools=false -Denable_examples=false -Denable_tests=false -Denable_asm=false -Dc_args="-matomics -mbulk-memory" --cross-file=meson-cross.txt .."""
    exec "ninja"
    exec "ninja install"

task makeffwasm, "Build FFmpeg for WebAssembly (requires emscripten)":
  setupDeps()
  putEnv("PKG_CONFIG_PATH", wasmBuildPath / "lib/pkgconfig")
  mkDir("ffmpeg_sources")
  mkDir("build_wasm")

  let wasmPackages = @[ffmpeg, lame, x264, opus, dav1d, vpx, whisper, svtav1]
  for package in wasmPackages:
    withDir "ffmpeg_sources":
      package.download()
      package.extract()
    if package.name == "ffmpeg": continue
    withDir &"ffmpeg_sources/{package.name}":
      case package.buildSystem
      of "cmake": cmakeBuildWasm(package, wasmBuildPath)
      of "meson": mesonBuildWasm(package, wasmBuildPath)
      else: autoconfBuildWasm(package, wasmBuildPath)

  # lame ships no .pc file; create one so FFmpeg's configure can find it
  mkDir(wasmBuildPath / "lib" / "pkgconfig")
  writeFile(wasmBuildPath / "lib" / "pkgconfig" / "mp3lame.pc", &"""prefix={wasmBuildPath}
exec_prefix=${{prefix}}
libdir=${{prefix}}/lib
includedir=${{prefix}}/include

Name: mp3lame
Description: MPEG Layer 3 audio codec
Version: 3.100
Libs: -L${{libdir}} -lmp3lame
Cflags: -I${{includedir}}
""")

  withDir "ffmpeg_sources/ffmpeg":
    exec (&"""./configure --prefix="{wasmBuildPath}" \
      --cc=emcc \
      --cxx=em++ \
      --ar=emar \
      --ranlib=emranlib \
      --nm=emnm \
      --enable-cross-compile \
      --target-os=none \
      --arch=x86_32 \
      --disable-x86asm \
      --disable-inline-asm \
      --enable-pthreads \
      --disable-w32threads \
      --disable-os2threads \
      --extra-cflags="-I{wasmBuildPath}/include -matomics -mbulk-memory -pthread" \
      --extra-ldflags="-L{wasmBuildPath}/lib -matomics -mbulk-memory -pthread" \""" & "\n" & setupCommonFlags(wasmPackages, crossWasm=true))
    makeInstall()

task makewasmweb, "Compile to wasm for browser (requires emscripten, wabt)":
  echo "Compiling for wasm (browser)..."
  if not dirExists("build_wasm"):
    echo "FFmpeg for wasm not found. Run 'nimble makeffwasm' first."
  else:
    exec "nim c -d:danger --panics:on -d:wasmBuild -d:nimNoGetRandom --passC:-flto --passL:-flto --threads:on --os:linux --cpu:wasm32 --cc:clang " &
        "--clang.exe:emcc " &
        "--clang.linkerexe:emcc " &
        "--passC:-pthread " &
        "--passC:-g0 " &
        "--passL:-pthread " &
        "--passL:-g0 " &
        "--passL:-sINITIAL_MEMORY=67108864 " &
        "--passL:-sALLOW_MEMORY_GROWTH=1 " &
        "--passL:-sMAXIMUM_MEMORY=4294967296 " &
        "--passL:-Wno-pthreads-mem-growth " &
        "--passL:-sSTACK_SIZE=1048576 " &
        "--passL:-sPTHREAD_POOL_SIZE=navigator.hardwareConcurrency " &
        "--passL:-sPROXY_TO_PTHREAD=1 " &
        "--passL:-sEXIT_RUNTIME=1 " &
        "--passL:-sMODULARIZE=1 " &
        "--passL:-sEXPORT_NAME=AutoEditor " &
        "--passL:-sEXPORTED_RUNTIME_METHODS=[FS] " &
        "--passL:-sENVIRONMENT=web,worker " &
        "--out:docs/src/auto-editor-web.js src/main.nim"
    stripProgram(forWasm=true)
