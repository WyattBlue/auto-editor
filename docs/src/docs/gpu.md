---
title: GPU Acceleration
---

# GPU Acceleration
## Does Auto-Editor support GPU acceleration?
Yes, enable it by linking a version of FFmpeg with GPU acceleration to Auto-Editor and setting the appropriate video codec.
Use `--my-ffmpeg` or `--ffmpeg-location` option for linking.

### How do I enable GPU acceleration on FFmpeg?
Compile FFmpeg with the appropriate flags and follow the relevant instructions.
 * [NVidia](https://web.archive.org/web/20230316164937/https://docs.nvidia.com/video-technologies/video-codec-sdk/ffmpeg-with-nvidia-gpu/). See [Supported GPUs](https://developer.nvidia.com/video-encode-and-decode-gpu-support-matrix-new)
 * AMD [Ubuntu+Windows](https://askubuntu.com/a/1132191)

FFmpeg [Compilation Guide](https://trac.ffmpeg.org/wiki/CompilationGuide)
 * [MacOS](https://trac.ffmpeg.org/wiki/CompilationGuide/macOS)
 * [Windows](https://trac.ffmpeg.org/wiki/CompilationGuide/CrossCompilingForWindows)
 * [Ubuntu / Debian / Mint](https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu)
 * [CentOS / RHEL / Fedor](https://trac.ffmpeg.org/wiki/CompilationGuide/Centos)
 * [Generic Compiling Guide](https://trac.ffmpeg.org/wiki/CompilationGuide/Generic)

Remember to set the export codec in auto-editor. `auto-editor --video-codec`.
Note that the resulting build is legally undistributable.

### Will enabling GPU acceleration make auto-editor go faster?
If you want to export to a certain codec that is compatible with your GPU, yes, in some cases, it will go noticeably faster, albeit with some slight quality loss.

However, in most other cases, GPU acceleration won't do anything since analyze and creating new media files are mostly CPU bound. Given how relatively complex enabling GPU acceleration is, it is not recommend for most users.

---
### Further Reading
 * [What is a GPU](https://www.intel.com/content/www/us/en/products/docs/processors/what-is-a-gpu.html)
 * [What's the difference between a CPU and a GPU](https://blogs.nvidia.com/blog/2009/12/16/whats-the-difference-between-a-cpu-and-a-gpu/)
