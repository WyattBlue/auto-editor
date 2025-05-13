# Auto-Editor GUI

这是 [Auto-Editor](https://github.com/WyattBlue/auto-editor) 的图形用户界面版本，旨在为用户提供一个友好、简单的操作界面，使视频编辑过程更加便捷。

![Auto-Editor GUI截图](resources/screenshot.png)

## 主要特性

- **直观的图形界面**：无需记忆命令行参数，所有功能都可通过界面操作完成
- **批量处理**：支持同时处理多个视频文件
- **拖放支持**：直接将视频文件拖入应用中进行处理
- **参数可视化设置**：通过界面轻松调整所有编辑参数
- **实时日志**：处理过程中实时查看进度和状态
- **深色主题**：舒适的视觉体验

## 安装说明

### 前提条件

- Python 3.7+
- 已安装 [auto-editor](https://github.com/WyattBlue/auto-editor)

### 方法一：从源码安装

1. 克隆仓库：
   ```
   git clone https://github.com/99hansling/auto-editor-gui.git
   cd auto-editor-gui
   ```

2. 安装依赖：
   ```
   pip install -r requirements.txt
   ```

3. 运行应用：
   ```
   python auto_editor_gui.py
   ```

### 方法二：使用预编译版本

1. 在[发布页面](https://github.com/99hansling/auto-editor-gui/releases)下载最新版本
2. 解压并运行可执行文件

## 使用指南

1. **添加视频**：点击"添加文件"或将视频拖放到界面中
2. **设置参数**：
   - 边距(margin)：设置保留的静音部分长度
   - 音频阈值(threshold)：检测声音的灵敏度
   - 有声部分速度：正常部分的播放速度
   - 静音部分速度：静音部分的播放速度
   - 输出文件后缀：处理后文件的命名方式

3. **开始处理**：点击"开始处理"按钮，应用将自动处理所有添加的视频

## 常见问题

**Q: 为什么我无法使用拖放功能？**  
A: 确保已安装tkinterdnd2库，可以使用`pip install tkinterdnd2`安装。

**Q: 处理速度受哪些因素影响？**  
A: 处理速度主要取决于视频长度、分辨率以及您的计算机性能。

## 致谢

本项目基于 [WyattBlue/auto-editor](https://github.com/WyattBlue/auto-editor) 开发，感谢原作者开发的出色工具。GUI界面由@99hansling开发。

## 贡献指南

欢迎提交问题报告和功能建议！如果您想为项目做出贡献，请：

1. Fork本仓库
2. 创建您的特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交您的更改 (`git commit -m '添加一些很棒的功能'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启一个Pull Request

## 许可证

本项目采用Unlicense许可证 - 查看[LICENSE](LICENSE)文件了解更多信息。

---

## 命令行参数参考

Auto-Editor GUI支持auto-editor的所有功能，以下是一些常用参数的说明：

### 基本参数

- **边距(margin)**：在有声部分前后添加多少秒的静音部分
- **音频阈值(threshold)**：音频必须超过此音量才被认为是"有声"部分
- **有声部分速度(video-speed)**：保留部分的播放速度
- **静音部分速度(silent-speed)**：静音部分的播放速度

有关更多详细信息，请参阅[Auto-Editor文档](https://github.com/WyattBlue/auto-editor/blob/master/README.md)
