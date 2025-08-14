# Package
version = "0.8.1"
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


task test, "Test the project":
  exec "nim c -r tests/rationals"

task make, "Export the project":
  exec "nim c -d:danger --out:auto-editor src/main.nim"
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
disableDecoders.add "sonic"
disableEncoders &= "avui,dca,mlp,opus,s302m,sonic,sonic_ls,truehd,vorbis".split(",")

# Technically obsolete
disableDecoders.add "flv"
disableEncoders.add "flv"
disableMuxers.add "flv"
disableDemuxers &= @["flv", "live_flv", "kux"]

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

let nvheaders = Package(
  name: "nv-codec-headers",
  sourceUrl: "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/n13.0.19.0.tar.gz",
  sha256: "86d15d1a7c0ac73a0eafdfc57bebfeba7da8264595bf531cf4d8db1c22940116",
)
let lame = Package(
  name: "lame",
  sourceUrl: "http://deb.debian.org/debian/pool/main/l/lame/lame_3.100.orig.tar.gz",
  sha256: "ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e",
  buildArguments: @["--disable-frontend", "--disable-decoder", "--disable-gtktest"],
)
let opus = Package(
  name: "opus",
  sourceUrl: "https://github.com/xiph/opus/releases/download/v1.5.2/opus-1.5.2.tar.gz",
  sha256: "65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1",
  buildArguments: @["--disable-doc", "--disable-extra-programs"],
)
let vpx = Package(
  name: "libvpx",
  sourceUrl: "https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.2.tar.gz",
  sha256: "26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa",
  buildArguments: "--disable-dependency-tracking --disable-examples --disable-unit-tests --enable-pic --enable-runtime-cpu-detect --enable-vp9-highbitdepth".split(" "),
)
let dav1d = Package(
  name: "dav1d",
  sourceUrl: "https://code.videolan.org/videolan/dav1d/-/archive/1.5.1/dav1d-1.5.1.tar.bz2",
  sha256: "4eddffd108f098e307b93c9da57b6125224dc5877b1b3d157b31be6ae8f1f093",
  buildSystem: "meson",
)
let svtav1 = Package(
  name: "libsvtav1",
  sourceUrl: "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v3.1.0/SVT-AV1-v3.1.0.tar.bz2",
  sha256: "8231b63ea6c50bae46a019908786ebfa2696e5743487270538f3c25fddfa215a",
  buildSystem: "cmake",
  buildArguments: @["-DBUILD_APPS=OFF", "-DBUILD_DEC=OFF", "-DBUILD_ENC=ON", "-DENABLE_NASM=ON"],
)
let x264 = Package(
  name: "x264",
  sourceUrl: "https://code.videolan.org/videolan/x264/-/archive/32c3b801191522961102d4bea292cdb61068d0dd/x264-32c3b801191522961102d4bea292cdb61068d0dd.tar.bz2",
  sha256: "d7748f350127cea138ad97479c385c9a35a6f8527bc6ef7a52236777cf30b839",
  buildArguments: "--disable-cli --disable-lsmash --disable-swscale --disable-ffms --enable-strip".split(" "),
)
let x265 = Package(
  name: "x265",
  sourceUrl: "https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.1.tar.gz",
  sha256: "a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29",
  buildSystem: "x265",
)
let ffmpeg = Package(
  name: "ffmpeg",
  sourceUrl: "https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz",
  sha256: "733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1",
)
var packages: seq[Package] = @[]
if not defined(macosx):
  packages.add nvheaders
packages &= [lame, opus, vpx, dav1d, svtav1, x264, x265]

func location(package: Package): string = # tar location
  if package.name == "libvpx":
    "v1.15.2.tar.gz"
  elif package.name == "nv-codec-headers":
    "n13.0.19.0.tar.gz"
  else:
    package.sourceUrl.split("/")[^1]

func dirName(package: Package): string =
  if package.name == "libvpx":
    return "libvpx-1.15.2"
  if package.name == "nv-codec-headers":
    return "nv-codec-headers-n13.0.19.0"

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

proc x265Build(buildPath: string, crossWindows: bool = false) =
  # Build x265 three times following the Python approach:
  #  1: Build 12 bits static library version in separate directory
  #  2: Build 10 bits static library version in separate directory  
  #  3: Build 8 bits version, linking also 10 and 12 bits
  # This last version will support 8, 10 and 12 bits pixel formats

  # Install intermediate builds in dummy directory
  let dummyInstallPath = absolutePath("dummy_install_path")
  mkDir(dummyInstallPath)

  # For 10/12 bits version, only x86_64 has assembly instructions available
  var flagsHighBits: seq[string] = @[]

  let isLinuxAarch64 = defined(linux) and hostCPU == "arm64"
  let isX86_64 = hostCPU in ["amd64", "i386"] # Nim uses "amd64" for x86_64

  if not isX86_64:
    flagsHighBits.add("-DENABLE_ASSEMBLY=0")
    flagsHighBits.add("-DENABLE_ALTIVEC=0")

    if isLinuxAarch64:
      flagsHighBits.add("-DENABLE_SVE2=OFF")

  # Build 12-bit version in x265-12bits directory
  echo "Building x265 12-bit..."
  mkDir("x265-12bits")
  withDir("x265-12bits"):
    var cmakeArgs = @[
      &"-DCMAKE_INSTALL_PREFIX={dummyInstallPath}",
      "-DCMAKE_BUILD_TYPE=Release",
      "-DBUILD_SHARED_LIBS=OFF",
      "-DBUILD_STATIC_LIBS=ON",
      "-DHIGH_BIT_DEPTH=1",
      "-DMAIN12=1",
      "-DEXPORT_C_API=0",
      "-DENABLE_CLI=0",
      "-DENABLE_SHARED=0"
    ] & flagsHighBits
    
    # Add cross-compilation flags if needed
    if crossWindows:
      cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
      cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc")
      cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++")
      cmakeArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
      cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
      cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
      cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")
    
    let cmakeCmd = "cmake ../source " & cmakeArgs.join(" ")
    echo "RUN: ", cmakeCmd
    exec cmakeCmd
    makeInstall()
    # Rename library in build directory
    exec "mv libx265.a libx265-12bits.a"

  # Build 10-bit version in x265-10bits directory
  echo "Building x265 10-bit..."
  mkDir("x265-10bits")
  withDir("x265-10bits"):
    var cmakeArgs = @[
      &"-DCMAKE_INSTALL_PREFIX={dummyInstallPath}",
      "-DCMAKE_BUILD_TYPE=Release",
      "-DBUILD_SHARED_LIBS=OFF",
      "-DBUILD_STATIC_LIBS=ON",
      "-DHIGH_BIT_DEPTH=1",
      "-DEXPORT_C_API=0",
      "-DENABLE_CLI=0",
      "-DENABLE_SHARED=0"
    ] & flagsHighBits
    
    # Add cross-compilation flags if needed
    if crossWindows:
      cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
      cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc")
      cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++")
      cmakeArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
      cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
      cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
      cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")
    
    let cmakeCmd = "cmake ../source " & cmakeArgs.join(" ")
    echo "RUN: ", cmakeCmd
    exec cmakeCmd
    makeInstall()
    # Rename library in build directory
    exec "mv libx265.a libx265-10bits.a"

  # Build 8-bit version (without multi-bit linking via CMake)
  echo "Building x265 8-bit..."
  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
    "-DENABLE_SHARED=0"
  ]
  
  if isLinuxAarch64:
    cmakeArgs.add("-DENABLE_SVE2=OFF")

  # Add cross-compilation flags if needed
  if crossWindows:
    cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc")
    cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++")
    cmakeArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")

  let cmakeCmd = "cmake source " & cmakeArgs.join(" ")
  echo "RUN: ", cmakeCmd
  exec cmakeCmd
  exec "make x265-static"  # Only build the static target
  
  # Manually combine all three libraries using libtool
  echo "Combining x265 libraries for multi-bit depth support..."
  mkDir("temp_combine")
  withDir("temp_combine"):
    # Copy all three libraries
    cpFile("../libx265.a", "libx265_8bit.a")
    cpFile("../x265-10bits/libx265-10bits.a", "libx265-10bits.a") 
    cpFile("../x265-12bits/libx265-12bits.a", "libx265-12bits.a")
    
    # Combine using libtool (macOS/BSD) or ar (Linux/Windows cross-compilation)
    when defined(macosx):
      exec "libtool -static -o libx265_combined.a libx265_8bit.a libx265-10bits.a libx265-12bits.a"
    else:
      # For Linux or cross-compilation, use ar with a script
      var arCommand = "ar"
      if crossWindows:
        arCommand = "x86_64-w64-mingw32-ar"
      
      exec "echo 'CREATE libx265_combined.a' > combine.mri"
      exec "echo 'ADDLIB libx265_8bit.a' >> combine.mri"
      exec "echo 'ADDLIB libx265-10bits.a' >> combine.mri" 
      exec "echo 'ADDLIB libx265-12bits.a' >> combine.mri"
      exec "echo 'SAVE' >> combine.mri"
      exec "echo 'END' >> combine.mri"
      exec &"{arCommand} -M < combine.mri"
    
    # Install the combined library and headers manually
    mkDir(&"{buildPath}/lib")
    mkDir(&"{buildPath}/include") 
    mkDir(&"{buildPath}/lib/pkgconfig")
    
    cpFile("libx265_combined.a", &"{buildPath}/lib/libx265.a")
    cpFile("../x265_config.h", &"{buildPath}/include/x265_config.h")
    cpFile("../source/x265.h", &"{buildPath}/include/x265.h")
    cpFile("../x265.pc", &"{buildPath}/lib/pkgconfig/x265.pc")


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
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
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
          let cmd = &"patch -d {package.name} -i {absolutePath(patchFile)} -p1"
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
                envPrefix = "CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib "
              let cmd = &"{envPrefix}./configure --prefix=\"{buildPath}\" --disable-shared --enable-static " & args.join(" ")
              echo "RUN: ", cmd
              exec cmd
            makeInstall()

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
  --disable-filters \
  --enable-filter=scale,pad,format,gblur,aformat,abuffer,abuffersink,aresample,atempo,anull,anullsrc,volume \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libvpx \
  --enable-libdav1d \
  --enable-libsvtav1 \
  --enable-libx264 \
  --enable-libx265 \
  --disable-encoder={encodersDisabled} \
  --disable-decoder={decodersDisabled} \
  --disable-demuxer={demuxersDisabled} \
  --disable-muxer={muxersDisabled} \
"""

if defined(arm) or defined(arm64):
  commonFlags &= "  --enable-neon \\\n"

if defined(macosx):
  commonFlags &= "  --enable-videotoolbox \\\n"
  commonFlags &= "  --enable-audiotoolbox \\\n"
else:
  commonFlags &= "  --enable-nvenc \\\n"
  commonFlags &= "  --enable-ffnvcodec \\\n"

commonFlags &= "--disable-autodetect"


proc setupDeps() =
  exec "pip install meson ninja"

task makeff, "Build FFmpeg from source":
  setupDeps()
  let buildPath = absolutePath("build")
  # Set PKG_CONFIG_PATH to include both standard and architecture-specific paths
  var pkgConfigPaths = @[buildPath / "lib/pkgconfig"]
  when defined(linux):
    pkgConfigPaths.add(buildPath / "lib/x86_64-linux-gnu/pkgconfig")
    pkgConfigPaths.add(buildPath / "lib64/pkgconfig")
  putEnv("PKG_CONFIG_PATH", pkgConfigPaths.join(":"))

  ffmpegSetup(crossWindows=false)

  # Configure and build FFmpeg
  withDir "ffmpeg_sources/ffmpeg":
    var ldflags = &"-L{buildPath}/lib"
    when defined(linux):
      ldflags &= &" -L{buildPath}/lib/x86_64-linux-gnu -L{buildPath}/lib64"

    exec &"""./configure --prefix="{buildPath}" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{buildPath}/include" \
      --extra-ldflags="{ldflags}" \
      --extra-libs="-lpthread -lm" \""" & "\n" & commonFlags
    makeInstall()

task makeffwin, "Build FFmpeg for Windows cross-compilation":
  setupDeps()
  let buildPath = absolutePath("build")
  putEnv("PKG_CONFIG_PATH", buildPath / "lib/pkgconfig")

  ffmpegSetup(crossWindows=true)

  # Configure and build FFmpeg with MinGW
  withDir "ffmpeg_sources/ffmpeg":
    var ldflags = &"-L{buildPath}/lib"
    when defined(linux):
      ldflags &= &" -L{buildPath}/lib/x86_64-linux-gnu -L{buildPath}/lib64"
    
    exec (&"""CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib PKG_CONFIG_PATH="{buildPath}/lib/pkgconfig" ./configure --prefix="{buildPath}" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{buildPath}/include" \
      --extra-ldflags="{ldflags}" \
      --extra-libs="-lpthread -lm -lstdc++" \
      --arch=x86_64 \
      --target-os=mingw32 \
      --cross-prefix=x86_64-w64-mingw32- \
      --enable-cross-compile \""" & "\n" & commonFlags)
    makeInstall()

task windows, "Cross-compile to Windows (requires mingw-w64)":
  echo "Cross-compiling for Windows (64-bit)..."
  if not dirExists("build"):
    echo "FFmpeg for Windows not found. Run 'nimble makeffwin' first."
  else:
    exec "nim c -d:danger --os:windows --cpu:amd64 --cc:gcc " &
         "--gcc.exe:x86_64-w64-mingw32-gcc " &
         "--gcc.linkerexe:x86_64-w64-mingw32-gcc " &
         "--passL:-lbcrypt " & # Add Windows Bcrypt library
         "--passL:-lstdc++ " & # Add C++ standard library
         "--passL:-static " &
         "--out:auto-editor.exe src/main.nim"

    # Strip the Windows binary
    exec "x86_64-w64-mingw32-strip -s auto-editor.exe"
