<p align="center"><img src="https://raw.githubusercontent.com/wyattblue/auto-editor/master/site/src/img/auto-editor-banner.webp" title="Auto-Editor" width="700"></p>

**Auto-Editor**是一款命令行应用程序，通过各种方法（最常用的是音频响度）自动**编辑视频和音频**。

---

[![Actions Status](https://github.com/wyattblue/auto-editor/workflows/build/badge.svg)](https://github.com/wyattblue/auto-editor/actions)
<a href="https://github.com/psf/black"><img alt="Code style: black" src="https://img.shields.io/badge/code%20style-black-000000.svg"></a>

在进行实际编辑之前，您可以通过这个基础案例：删除视频静音区段。剪切这些区域是一项乏味的任务，特别是当视频非常长时。

```
auto-editor path/to/your/video.mp4
```

<h2 align="center">安装</h2>

```
pip install auto-editor
```

有关更多信息，请参阅[安装说明](https://auto-editor.com/installing)。

<h2 align="center">剪切</h2>

通过使用`--margin`选项来改变视频的**节奏**。

`--margin`选项添加一些"静默"部分，使编辑更加流畅。将`--margin`设置为`0.2sec`后，这将在每一次剪辑前后各多保留0.2秒原视频的内容。

```
auto-editor example.mp4 --margin 0.2sec
```

<h3>处理多个音轨</h3>
默认情况下，仅使用第一个音轨进行编辑（track 0）。您可以使用以下命令更改此设置。

使用所有音轨进行编辑：
```
auto-editor multi-track.mov --edit audio:stream=all
```

仅使用第二、第四和第六个音轨：
```
# 音轨编号从0开始
auto-editor so-many-tracks.mp4 --edit "(or audio:stream=1 audio:stream=3 audio:stream=5)"
```

<h3>剪切方法</h3>

`--edit`选项决定auto-editor进行剪辑的方案。

例如，通过设置`--edit motion`来剪辑视频中的静止部分。

```
# 剪辑掉运动百分比低于2%的部分。
auto-editor example.mp4 --edit motion:threshold=2%

# 默认情况下，--edit设置为"audio:threshold=4%"。
auto-editor example.mp4

# 不同的音轨可以使用不同的属性设置。
auto-editor multi-track.mov --edit "(or audio:stream=0 audio:threshold=10%,stream=1)"
```

可以同时使用不同的编辑方法。
```
# 'threshold'始终是edit-method对象的第一个参数
auto-editor example.mp4 --edit "(or audio:3% motion:6%)"
```

<h3>保留本应被Auto-Editor剪除的内容</h3>

要导出auto-editor本应被剪切掉的部分，请将`--video-speed`设置为`99999`，`--silent-speed`设置为`1`。这与通常的默认值相反。

```
auto-editor example.mp4 --video-speed 99999 --silent-speed 1
```

<h2 align="center">导出到编辑器</h2>

使用以下命令创建一个可以导入Adobe Premiere Pro的XML文件：

```
auto-editor example.mp4 --export premiere
```

Auto-Editor还可以导出到：

|目标软件|命令|
|-|-|
|DaVinci Resolve|`--export resolve`|
|Final Cut Pro|`--export final-cut-pro`|
|ShotCut|`--export shotcut`|

同理可以导入到其他支持`premiere`格式的编辑器（例如Sony Vegas）。如果您喜欢的编辑器不支持该格式，您可以使用`--export clip-sequence`，它会创建许多视频剪辑，此后可以像导入其他视频一样导入和操作。

<h2 align="center">手动编辑</h2>

使用`--cut-out`选项强制删除一个区域。

```
# 剪辑掉前30秒。
auto-editor example.mp4 --cut-out start,30sec

# 剪辑掉前30帧。
auto-editor example.mp4 --cut-out start,30

# 剪辑掉最后10秒。
auto-editor example.mp4 --cut-out -10sec,end

# 剪辑掉前10秒和剪辑掉从15秒到20秒的范围。
auto-editor example.mp4 --cut-out start,10sec 15sec,20sec
```

当然，您可以使用基于`--edit`的配置。

如果您不希望进行**任何自动的剪辑**，可以使用`--edit none`或`--edit all/e`。

```
# 剪辑掉前5秒，其余部分保留。
auto-editor example.mp4 --edit none --cut-out start,5sec

# 保留前5秒，剪辑掉其余部分。
auto-editor example.mp4 --edit all/e --add-in start,5sec
```

<h2 align="center">更多选项</h2>

列出所有可用选项：

```
auto-editor --help
```

使用`--help`获取关于特定选项的更多信息：

```
auto-editor --scale --help
  --scale NUM

    默认值: 1.0
    将输出视频的分辨率缩放NUM倍
```

<h3 align="center">Auto-Editor可在所有主要平台上使用</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/site/src/img/cross-platform.webp" width="500" title="Windows、MacOS和Linux"></p>

## 文章
 - [如何安装Auto-Editor](https://auto-editor.com/installing)
 - [所有选项（及其功能）](https://auto-editor.com/options)
 - [文档](https://auto-editor.com/docs)
 - [博客](https://auto-editor.com/blog)

## 版权
Auto-Editor采用[Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE)授权，并包含除下列目录之外的所有目录。Auto-Editor由[这些人](https://auto-editor.com/blog/thank-you-early-testers)创建。

ae-ffmpeg采用[LGPLv3许可证](https://github.com/WyattBlue/auto-editor/blob/master/ae-ffmpeg/LICENSE.txt)。ffmpeg和ffprobe程序由FFmpeg团队创建。
