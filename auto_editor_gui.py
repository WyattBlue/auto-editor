import sys
import os
import subprocess
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinter.scrolledtext import ScrolledText
import threading
import queue
import time

class AutoEditorGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Auto-Editor 批量处理工具")
        self.root.geometry("900x700")
        self.root.minsize(800, 600)
        
        # 创建主滚动框架 - 添加这个可以滚动整个界面
        self.main_canvas = tk.Canvas(root, bg="#333333")
        self.main_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        # 添加滚动条
        self.scrollbar = ttk.Scrollbar(root, orient=tk.VERTICAL, command=self.main_canvas.yview)
        self.scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.main_canvas.configure(yscrollcommand=self.scrollbar.set)
        self.main_canvas.bind('<Configure>', lambda e: self.main_canvas.configure(scrollregion=self.main_canvas.bbox("all")))
        
        # 创建主框架放在画布上
        self.main_frame = tk.Frame(self.main_canvas, bg="#333333")
        self.main_canvas.create_window((0, 0), window=self.main_frame, anchor="nw")
        
        # 添加鼠标滚轮事件绑定
        self.main_canvas.bind_all("<MouseWheel>", self._on_mousewheel)
        
        # 创建消息队列
        self.queue = queue.Queue()
        
        # 视频文件列表
        self.video_files = []
        
        # 创建拖放区域
        self.create_drag_drop_area()
        
        # 创建文件列表区域
        self.create_file_list_area()
        
        # 创建参数设置区域1
        self.create_parameter_settings()
        
        # 创建日志区域
        self.create_log_area()
        
        # 创建操作按钮区域
        self.create_action_buttons()
        
        # 设置拖放事件
        self.setup_drag_drop()
        
        # 处理线程
        self.processing_thread = None
        self.stop_processing = False
        
        # 定期检查队列
        self.check_queue()
    
    def _on_mousewheel(self, event):
        """处理鼠标滚轮事件"""
        self.main_canvas.yview_scroll(int(-1*(event.delta/120)), "units")
    
    def create_drag_drop_area(self):
        """创建拖放区域"""
        drag_frame = tk.LabelFrame(self.main_frame, text="拖放视频文件到此区域", pady=10, padx=10, 
                                  bg="#333333", fg="white", font=('Arial', 10))
        drag_frame.pack(fill=tk.X, padx=10, pady=10)
        
        self.drag_label = tk.Label(
            drag_frame, 
            text="将视频文件拖放到此处\n或点击添加文件按钮浏览",
            justify=tk.CENTER,
            bg="#333333",
            fg="white",
            font=('Arial', 10)
        )
        self.drag_label.pack(fill=tk.X, padx=20, pady=20)
        
        # 添加文件按钮 - 使用明确的颜色设置
        add_button = tk.Button(
            drag_frame, 
            text="添加文件", 
            command=self.browse_files,
            font=('Arial', 10, 'bold'),  # 加粗文字
            bg="#5A9AE2",
            fg="white",
            activebackground="#3A80D2",
            activeforeground="white",
            highlightbackground="#5A9AE2",  # 确保macOS上按钮有颜色
            highlightcolor="#3A80D2",       # 确保点击时颜色变化
            highlightthickness=2,           # 增加高亮边框厚度
            bd=0,                           # 减少边框对颜色的影响
            borderwidth=1,                  # 保持边框可见
            padx=10,
            pady=5,
            relief=tk.FLAT                  # 使用扁平风格提高颜色显示一致性
        )
        add_button.pack(pady=5)
        
        # 添加文件夹按钮
        add_folder_button = tk.Button(
            drag_frame, 
            text="添加文件夹", 
            command=self.browse_folder,
            font=('Arial', 10, 'bold'),  # 加粗文字
            bg="#5A9AE2",
            fg="white",
            activebackground="#3A80D2",
            activeforeground="white",
            highlightbackground="#5A9AE2",  # 确保macOS上按钮有颜色
            highlightcolor="#3A80D2",       # 确保点击时颜色变化
            highlightthickness=2,           # 增加高亮边框厚度
            bd=0,                           # 减少边框对颜色的影响
            borderwidth=1,                  # 保持边框可见
            padx=10,
            pady=5,
            relief=tk.FLAT                  # 使用扁平风格提高颜色显示一致性
        )
        add_folder_button.pack(pady=5)
    
    def create_file_list_area(self):
        """创建文件列表区域"""
        list_frame = tk.LabelFrame(self.main_frame, text="待处理文件列表", pady=10, padx=10,
                                 bg="#333333", fg="white", font=('Arial', 10))
        list_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # 创建工具栏
        toolbar = tk.Frame(list_frame, bg="#333333")
        toolbar.pack(fill=tk.X, pady=(0, 5))
        
        # 添加移除选中和清空列表按钮
        remove_button = tk.Button(
            toolbar, 
            text="移除选中", 
            command=self.remove_selected,
            font=('Arial', 10, 'bold'),  # 加粗文字
            bg="#5A9AE2",
            fg="white",
            activebackground="#3A80D2",
            activeforeground="white",
            highlightbackground="#5A9AE2",  # 确保macOS上按钮有颜色
            highlightcolor="#3A80D2",       # 确保点击时颜色变化
            highlightthickness=2,           # 增加高亮边框厚度
            bd=0,                           # 减少边框对颜色的影响
            borderwidth=1,                  # 保持边框可见
            padx=10,
            pady=5,
            relief=tk.FLAT                  # 使用扁平风格提高颜色显示一致性
        )
        remove_button.pack(side=tk.LEFT, padx=5)
        
        clear_button = tk.Button(
            toolbar, 
            text="清空列表", 
            command=self.clear_list,
            font=('Arial', 10, 'bold'),  # 加粗文字
            bg="#5A9AE2",
            fg="white",
            activebackground="#3A80D2",
            activeforeground="white",
            highlightbackground="#5A9AE2",  # 确保macOS上按钮有颜色
            highlightcolor="#3A80D2",       # 确保点击时颜色变化
            highlightthickness=2,           # 增加高亮边框厚度
            bd=0,                           # 减少边框对颜色的影响
            borderwidth=1,                  # 保持边框可见
            padx=10,
            pady=5,
            relief=tk.FLAT                  # 使用扁平风格提高颜色显示一致性
        )
        clear_button.pack(side=tk.LEFT, padx=5)
        
        # 创建文件列表的滚动视图
        list_container = tk.Frame(list_frame, bg="#333333")
        list_container.pack(fill=tk.BOTH, expand=True)
        
        # 创建滚动条
        scrollbar = tk.Scrollbar(list_container)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        # 定义列名 - 修复bug: 在使用前定义columns变量
        columns = ("文件名", "路径", "状态")
        
        # 创建树状视图显示文件列表 - 确保样式适合深色主题
        self.file_list = ttk.Treeview(
            list_container, 
            columns=columns,
            show="headings",
            yscrollcommand=scrollbar.set
        )
        
        # 设置行高
        self.file_list.configure(height=10)
        
        # 设置列宽和标题
        self.file_list.column("文件名", width=150, anchor="w")
        self.file_list.column("路径", width=400, anchor="w")
        self.file_list.column("状态", width=100, anchor="center")
        
        for col in columns:  # 现在columns已定义
            self.file_list.heading(col, text=col)
        
        self.file_list.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.file_list.yview)
        
        # 设置列表样式
        style = ttk.Style()
        style.configure("Treeview", 
                      background="#444444", 
                      foreground="white", 
                      fieldbackground="#444444",
                      rowheight=25)
        style.map("Treeview", 
                background=[('selected', '#4A90E2')],
                foreground=[('selected', 'white')])
    
    def create_parameter_settings(self):
        """创建参数设置区域"""
        param_frame = tk.LabelFrame(self.main_frame, text="处理参数设置", pady=10, padx=10,
                                   bg="#333333", fg="white", font=('Arial', 10))
        param_frame.pack(fill=tk.X, padx=10, pady=10)
        
        # 创建参数网格
        param_grid = tk.Frame(param_frame, bg="#333333")
        param_grid.pack(fill=tk.X, padx=5, pady=5)
        
        # Margin 设置
        tk.Label(param_grid, text="边距 (margin):", bg="#333333", fg="white").grid(column=0, row=0, sticky=tk.W, padx=5, pady=5)
        
        margin_frame = tk.Frame(param_grid, bg="#333333")
        margin_frame.grid(column=1, row=0, sticky=tk.W, padx=5, pady=5)
        
        tk.Label(margin_frame, text="前缘:", bg="#333333", fg="white").pack(side=tk.LEFT)
        self.margin_before = tk.Entry(margin_frame, width=6, bg="#444444", fg="white", insertbackground="white")
        self.margin_before.pack(side=tk.LEFT, padx=(2, 5))
        self.margin_before.insert(0, "0.2")
        
        tk.Label(margin_frame, text="后缘:", bg="#333333", fg="white").pack(side=tk.LEFT)
        self.margin_after = tk.Entry(margin_frame, width=6, bg="#444444", fg="white", insertbackground="white")
        self.margin_after.pack(side=tk.LEFT, padx=(2, 5))
        self.margin_after.insert(0, "0.2")
        
        tk.Label(margin_frame, text="秒", bg="#333333", fg="white").pack(side=tk.LEFT)
        
        # 音频阈值设置
        tk.Label(param_grid, text="音频阈值 (threshold):", bg="#333333", fg="white").grid(column=0, row=1, sticky=tk.W, padx=5, pady=5)
        
        threshold_frame = tk.Frame(param_grid, bg="#333333")
        threshold_frame.grid(column=1, row=1, sticky=tk.W, padx=5, pady=5)
        
        self.threshold = tk.Entry(threshold_frame, width=6, bg="#444444", fg="white", insertbackground="white")
        self.threshold.pack(side=tk.LEFT, padx=(2, 5))
        self.threshold.insert(0, "0.02")
        
        # 视频速度设置
        tk.Label(param_grid, text="有声部分速度:", bg="#333333", fg="white").grid(column=0, row=2, sticky=tk.W, padx=5, pady=5)
        
        speed_frame = tk.Frame(param_grid, bg="#333333")
        speed_frame.grid(column=1, row=2, sticky=tk.W, padx=5, pady=5)
        
        self.video_speed = tk.Entry(speed_frame, width=6, bg="#444444", fg="white", insertbackground="white")
        self.video_speed.pack(side=tk.LEFT, padx=(2, 5))
        self.video_speed.insert(0, "1")
        
        tk.Label(speed_frame, text="倍速", bg="#333333", fg="white").pack(side=tk.LEFT)
        
        # 静音部分速度
        tk.Label(param_grid, text="静音部分速度:", bg="#333333", fg="white").grid(column=0, row=3, sticky=tk.W, padx=5, pady=5)
        
        silent_frame = tk.Frame(param_grid, bg="#333333")
        silent_frame.grid(column=1, row=3, sticky=tk.W, padx=5, pady=5)
        
        self.silent_speed = tk.Entry(silent_frame, width=6, bg="#444444", fg="white", insertbackground="white")
        self.silent_speed.pack(side=tk.LEFT, padx=(2, 5))
        self.silent_speed.insert(0, "8")
        
        tk.Label(silent_frame, text="倍速", bg="#333333", fg="white").pack(side=tk.LEFT)
        
        # 输出文件后缀
        tk.Label(param_grid, text="输出文件后缀:", bg="#333333", fg="white").grid(column=0, row=4, sticky=tk.W, padx=5, pady=5)
        
        self.output_suffix = tk.Entry(param_grid, bg="#444444", fg="white", insertbackground="white")
        self.output_suffix.grid(column=1, row=4, sticky=tk.W+tk.E, padx=5, pady=5)
        self.output_suffix.insert(0, "_edited")
    
    def create_log_area(self):
        """创建日志区域"""
        log_frame = tk.LabelFrame(self.main_frame, text="处理日志", pady=10, padx=10,
                                bg="#333333", fg="white", font=('Arial', 10))
        log_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # 创建滚动文本框
        self.log_text = ScrolledText(log_frame, height=8, bg="#333333", fg="white", insertbackground="white")
        self.log_text.pack(fill=tk.BOTH, expand=True)
        self.log_text.config(state=tk.DISABLED)
    
    def create_action_buttons(self):
        """创建操作按钮区域"""
        button_frame = tk.Frame(self.main_frame, pady=10, padx=10, bg="#333333")
        button_frame.pack(fill=tk.X, padx=10, pady=20) # 增加下方间距
        
        # 处理按钮 - 明显的样式
        self.process_button = tk.Button(
            button_frame, 
            text="开始处理", 
            command=self.start_processing,
            font=('Arial', 12, 'bold'),
            bg="#5A9AE2",
            fg="white",
            activebackground="#3A80D2",
            activeforeground="white",
            highlightbackground="#5A9AE2",  # 确保macOS上按钮有颜色
            highlightcolor="#3A80D2",       # 确保点击时颜色变化
            highlightthickness=2,           # 增加高亮边框厚度
            bd=0,                           # 减少边框对颜色的影响
            padx=25,
            pady=10,
            relief=tk.FLAT,                 # 使用扁平风格提高颜色显示一致性
            borderwidth=1                   # 确保有边框
        )
        self.process_button.pack(side=tk.RIGHT, padx=10)
        
        # 停止按钮
        self.stop_button = tk.Button(
            button_frame, 
            text="停止处理", 
            command=self.stop_processing_command, 
            state=tk.DISABLED,
            font=('Arial', 12, 'bold'),
            bg="#E75C4C",
            fg="white",
            activebackground="#C0392B",
            activeforeground="white",
            highlightbackground="#E75C4C",  # 确保macOS上按钮有颜色
            highlightcolor="#C0392B",       # 确保点击时颜色变化
            highlightthickness=2,           # 增加高亮边框厚度
            bd=0,                           # 减少边框对颜色的影响
            padx=25,
            pady=10,
            relief=tk.FLAT,                 # 使用扁平风格提高颜色显示一致性
            borderwidth=1                   # 确保有边框
        )
        self.stop_button.pack(side=tk.RIGHT, padx=10)

        # 添加额外的底部空间，确保滚动时按钮可见
        bottom_spacer = tk.Frame(self.main_frame, height=30, bg="#333333")
        bottom_spacer.pack(fill=tk.X, padx=10, pady=10)
    
    def setup_drag_drop(self):
        """设置拖放功能"""
        try:
            self.root.drop_target_register("DND_Files")
            self.root.dnd_bind("<<Drop>>", self.handle_drop)
        except Exception as e:
            # 如果不支持拖放，显示一个提示
            print(f"拖放功能不可用: {e}")
            self.queue.put("警告: 拖放功能不可用，请使用添加文件按钮")
    
    def handle_drop(self, event):
        """处理拖放事件"""
        files = self.root.tk.splitlist(event.data)
        for file in files:
            self.add_file_or_folder(file)
    
    def add_file_or_folder(self, path):
        """添加文件或文件夹"""
        if os.path.isdir(path):
            # 如果是文件夹，递归添加所有视频文件
            for root, _, files in os.walk(path):
                for file in files:
                    file_path = os.path.join(root, file)
                    if self.is_video_file(file_path):
                        self.add_video_file(file_path)
        elif self.is_video_file(path):
            # 如果是视频文件，直接添加
            self.add_video_file(path)
    
    def is_video_file(self, file_path):
        """判断是否为视频文件"""
        video_extensions = ['.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv', '.webm']
        _, ext = os.path.splitext(file_path)
        return ext.lower() in video_extensions
    
    def add_video_file(self, file_path):
        """添加视频文件到列表"""
        # 检查文件是否已在列表中
        for item in self.file_list.get_children():
            if self.file_list.item(item, 'values')[1] == file_path:
                return
        
        # 添加到文件列表
        filename = os.path.basename(file_path)
        self.file_list.insert('', 'end', values=(filename, file_path, "等待处理"))
        self.video_files.append(file_path)
        
        # 更新日志
        self.log(f"已添加文件: {filename}")
    
    def browse_files(self):
        """浏览并添加文件"""
        files = filedialog.askopenfilenames(
            title="选择视频文件",
            filetypes=(
                ("视频文件", "*.mp4 *.avi *.mov *.mkv *.wmv *.flv *.webm"),
                ("所有文件", "*.*")
            )
        )
        for file in files:
            if self.is_video_file(file):
                self.add_video_file(file)
    
    def browse_folder(self):
        """浏览并添加文件夹中的视频"""
        folder = filedialog.askdirectory(title="选择包含视频的文件夹")
        if folder:
            self.add_file_or_folder(folder)
    
    def remove_selected(self):
        """移除选中的文件"""
        selected_items = self.file_list.selection()
        if not selected_items:
            messagebox.showinfo("提示", "请先选择要移除的文件")
            return
        
        for item in selected_items:
            values = self.file_list.item(item, 'values')
            file_path = values[1]
            
            # 从视频文件列表中移除
            if file_path in self.video_files:
                self.video_files.remove(file_path)
            
            # 从树状视图中移除
            self.file_list.delete(item)
            
            # 更新日志
            self.log(f"已移除文件: {values[0]}")
    
    def clear_list(self):
        """清空文件列表"""
        if not self.video_files:
            return
        
        if messagebox.askyesno("确认", "确定要清空整个文件列表吗？"):
            self.file_list.delete(*self.file_list.get_children())
            self.video_files.clear()
            self.log("已清空文件列表")
    
    def log(self, message):
        """添加日志消息"""
        timestamp = time.strftime("%H:%M:%S")
        log_message = f"[{timestamp}] {message}"
        self.queue.put(log_message)
    
    def check_queue(self):
        """检查消息队列并更新日志"""
        try:
            while True:
                message = self.queue.get_nowait()
                self.log_text.config(state=tk.NORMAL)
                self.log_text.insert(tk.END, message + "\n")
                self.log_text.see(tk.END)
                self.log_text.config(state=tk.DISABLED)
                self.queue.task_done()
        except queue.Empty:
            # 如果队列为空，继续定期检查
            pass
        finally:
            self.root.after(100, self.check_queue)
    
    def start_processing(self):
        """开始处理视频文件"""
        if not self.video_files:
            messagebox.showinfo("提示", "请先添加要处理的视频文件")
            return
        
        # 检查参数有效性
        try:
            float(self.margin_before.get())
            float(self.margin_after.get())
            float(self.threshold.get())
            float(self.video_speed.get())
            float(self.silent_speed.get())
        except ValueError:
            messagebox.showerror("错误", "请输入有效的数值参数")
            return
        
        # 更新界面状态
        self.process_button.config(state=tk.DISABLED)
        self.stop_button.config(state=tk.NORMAL)
        
        # 重置处理状态
        self.stop_processing = False
        
        # 启动处理线程
        self.processing_thread = threading.Thread(target=self.process_videos)
        self.processing_thread.daemon = True
        self.processing_thread.start()
    
    def stop_processing_command(self):
        """停止处理命令"""
        if messagebox.askyesno("确认", "确定要停止当前处理过程吗？"):
            self.log("正在停止处理...")
            self.stop_processing = True
            self.stop_button.config(state=tk.DISABLED)
    
    def process_videos(self):
        """处理视频文件的线程函数"""
        total_files = len(self.video_files)
        processed = 0
        failed = 0
        
        self.log(f"开始处理 {total_files} 个视频文件")
        
        # 获取参数
        margin = f"{self.margin_before.get()}sec,{self.margin_after.get()}sec"
        threshold = self.threshold.get()
        video_speed = self.video_speed.get()
        silent_speed = self.silent_speed.get()
        suffix = self.output_suffix.get()
        
        for item in self.file_list.get_children():
            if self.stop_processing:
                self.log("处理已停止")
                break
            
            values = self.file_list.item(item, 'values')
            file_path = values[1]
            filename = values[0]
            
            # 更新状态为处理中
            self.file_list.item(item, values=(filename, file_path, "处理中"))
            self.root.update()
            
            # 构建输出路径
            file_dir = os.path.dirname(file_path)
            file_name, file_ext = os.path.splitext(filename)
            output_path = os.path.join(file_dir, f"{file_name}{suffix}{file_ext}")
            
            # 构建命令
            cmd = [
                "auto-editor",
                file_path,
                "--output", output_path,
                "--margin", margin,
                "--edit", f"audio:threshold={threshold}",
                "--video-speed", video_speed,
                "--silent-speed", silent_speed,
                "--no-open"
            ]
            
            self.log(f"正在处理: {filename}")
            self.log(f"命令: {' '.join(cmd)}")
            
            try:
                # 运行命令
                process = subprocess.Popen(
                    cmd, 
                    stdout=subprocess.PIPE, 
                    stderr=subprocess.PIPE,
                    text=True
                )
                
                # 读取输出
                while True:
                    output = process.stdout.readline()
                    if output == '' and process.poll() is not None:
                        break
                    if output:
                        self.log(output.strip())
                
                # 检查处理结果
                ret_code = process.wait()
                if ret_code == 0:
                    self.file_list.item(item, values=(filename, file_path, "完成"))
                    self.log(f"成功处理: {filename}")
                    processed += 1
                else:
                    stderr = process.stderr.read()
                    self.file_list.item(item, values=(filename, file_path, "失败"))
                    self.log(f"处理失败: {filename}")
                    self.log(f"错误: {stderr}")
                    failed += 1
            
            except Exception as e:
                self.file_list.item(item, values=(filename, file_path, "失败"))
                self.log(f"处理出错: {filename}")
                self.log(f"错误: {str(e)}")
                failed += 1
        
        # 处理完成，恢复界面状态
        self.process_button.config(state=tk.NORMAL)
        self.stop_button.config(state=tk.DISABLED)
        
        # 显示处理结果统计
        self.log(f"处理完成! 成功: {processed}, 失败: {failed}, 总计: {total_files}")
        
        # 弹出完成提示
        if not self.stop_processing:
            messagebox.showinfo("处理完成", f"所有视频处理完成!\n成功: {processed}\n失败: {failed}")

def setup_tkinter_extensions():
    """设置Tkinter扩展以支持拖放功能"""
    # 这里我们使用一个简单的方法来检测平台并导入适当的拖放支持
    if sys.platform == "win32":
        try:
            from tkinterdnd2 import TkinterDnD
            return TkinterDnD.Tk
        except ImportError:
            messagebox.showwarning(
                "功能受限",
                "未检测到tkinterdnd2模块，拖放功能将不可用。\n请使用命令安装：pip install tkinterdnd2"
            )
            return tk.Tk
    else:  # macOS 和 Linux
        try:
            # macOS 使用 tkinterdnd2
            from tkinterdnd2 import TkinterDnD
            return TkinterDnD.Tk
        except ImportError:
            try:
                # Linux 可能使用 tkDnD
                root = tk.Tk()
                root.tk.eval('package require tkdnd')
                return lambda: root
            except:
                messagebox.showwarning(
                    "功能受限",
                    "未检测到拖放支持模块，拖放功能将不可用。\n请使用命令安装：pip install tkinterdnd2"
                )
                return tk.Tk

def main():
    """主函数"""
    # 设置Tkinter根窗口
    TkRoot = setup_tkinter_extensions()
    root = TkRoot()
    
    # 创建应用
    app = AutoEditorGUI(root)
    
    # 启动主循环
    root.mainloop()

if __name__ == "__main__":
    main()