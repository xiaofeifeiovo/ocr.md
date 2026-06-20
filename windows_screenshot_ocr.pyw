#!/usr/bin/env python3

import ctypes
from ctypes import wintypes
import json
import logging
import os
from pathlib import Path
import queue
import sys
import tempfile
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk
import winreg

from PIL import ImageGrab, ImageTk
import pyperclip

from ocr_core import (
    DEFAULT_FORMAT,
    DEFAULT_MODEL,
    MODEL_CONFIG,
    SYSTEM_PROMPTS,
    ocr_image_bytes,
    strip_markdown_fences,
    validate_format_name,
    validate_model_name,
)

APP_NAME = "OCR Clipboard"
MUTEX_NAME = "OCRClipboardDesktopApp"
SHOW_EVENT_NAME = "OCRClipboardShowWindowEvent"
RUN_KEY_NAME = "OCR Clipboard"

APP_DIR = Path(os.getenv("APPDATA", str(Path.home()))) / "OCRClipboard"
LOCAL_APP_DIR = Path(os.getenv("LOCALAPPDATA", str(APP_DIR))) / "OCRClipboard"
CONFIG_PATH = APP_DIR / "config.json"
LOG_PATH = LOCAL_APP_DIR / "ScreenshotOCRHotkey.log"

HOTKEY_ID = 1
VK_6 = 0x36
WM_HOTKEY = 0x0312
WM_QUIT = 0x0012
WM_APP = 0x8000
NOTIFY_CALLBACK_MESSAGE = WM_APP + 20
MOD_SHIFT = 0x0004
MOD_CONTROL = 0x0002
MOD_NOREPEAT = 0x4000
ERROR_ALREADY_EXISTS = 183
WAIT_OBJECT_0 = 0
INFINITE = 0xFFFFFFFF

SM_XVIRTUALSCREEN = 76
SM_YVIRTUALSCREEN = 77
SM_CXVIRTUALSCREEN = 78
SM_CYVIRTUALSCREEN = 79

HWND_TOPMOST = -1
SWP_SHOWWINDOW = 0x0040
IDI_APPLICATION = 32512
NIM_ADD = 0x00000000
NIM_MODIFY = 0x00000001
NIM_DELETE = 0x00000002
NIF_MESSAGE = 0x00000001
NIF_ICON = 0x00000002
NIF_TIP = 0x00000004
NIF_INFO = 0x00000010
NIIF_INFO = 0x00000001
NOTIFICATION_ICON_ID = 100

FORMAT_LABELS = {
    "tex": "LaTeX",
    "formula": "公式识别",
    "markdown": "Markdown",
    "plain": "纯文本",
}

DEFAULT_CONFIG = {
    "model": DEFAULT_MODEL,
    "format": DEFAULT_FORMAT,
    "custom_prompt": "",
    "api_keys": {
        "DASHSCOPE_API_KEY": "",
        "MIMO_API_KEY": "",
        "OPENROUTER_API_KEY": "",
    },
    "launch_at_login": False,
    "silent_launch_at_login": False,
}

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
shell32 = ctypes.windll.shell32
kernel32.CreateMutexW.restype = wintypes.HANDLE
kernel32.CreateEventW.restype = wintypes.HANDLE
kernel32.GetLastError.restype = wintypes.DWORD
kernel32.GetCurrentThreadId.restype = wintypes.DWORD

mutex_handle = None


class POINT(ctypes.Structure):
    _fields_ = [("x", wintypes.LONG), ("y", wintypes.LONG)]


class MSG(ctypes.Structure):
    _fields_ = [
        ("hwnd", wintypes.HWND),
        ("message", wintypes.UINT),
        ("wParam", wintypes.WPARAM),
        ("lParam", wintypes.LPARAM),
        ("time", wintypes.DWORD),
        ("pt", POINT),
    ]


class NOTIFYICONDATAW(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("hWnd", wintypes.HWND),
        ("uID", wintypes.UINT),
        ("uFlags", wintypes.UINT),
        ("uCallbackMessage", wintypes.UINT),
        ("hIcon", wintypes.HANDLE),
        ("szTip", wintypes.WCHAR * 128),
        ("dwState", wintypes.DWORD),
        ("dwStateMask", wintypes.DWORD),
        ("szInfo", wintypes.WCHAR * 256),
        ("uTimeoutOrVersion", wintypes.UINT),
        ("szInfoTitle", wintypes.WCHAR * 64),
        ("dwInfoFlags", wintypes.DWORD),
    ]


def setup_logging() -> None:
    LOCAL_APP_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        filename=LOG_PATH,
        level=logging.INFO,
        format="[%(asctime)s] %(levelname)s %(message)s",
        encoding="utf-8",
    )


def setup_dpi_awareness() -> None:
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            user32.SetProcessDPIAware()
        except Exception:
            logging.exception("Could not enable DPI awareness")


def message_box(title: str, message: str) -> None:
    user32.MessageBoxW(None, str(message), str(title), 0x40)


def deep_merge(defaults: dict, loaded: dict) -> dict:
    result = dict(defaults)
    for key, value in loaded.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            nested = dict(result[key])
            nested.update(value)
            result[key] = nested
        else:
            result[key] = value
    return result


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        return deep_merge(DEFAULT_CONFIG, {})
    try:
        loaded = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception:
        logging.exception("Could not read config")
        return deep_merge(DEFAULT_CONFIG, {})
    config = deep_merge(DEFAULT_CONFIG, loaded)
    if config.get("model") not in MODEL_CONFIG:
        config["model"] = DEFAULT_MODEL
    if config.get("format") not in SYSTEM_PROMPTS:
        config["format"] = DEFAULT_FORMAT
    return config


def save_config(config: dict) -> None:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(
        json.dumps(config, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def app_command(silent: bool = False) -> str:
    if getattr(sys, "frozen", False):
        command = f'"{sys.executable}"'
    else:
        command = f'"{sys.executable}" "{Path(__file__).resolve()}"'
    if silent:
        command += " --silent"
    return command


def set_launch_at_login(enabled: bool, silent: bool = False) -> None:
    with winreg.OpenKey(
        winreg.HKEY_CURRENT_USER,
        r"Software\Microsoft\Windows\CurrentVersion\Run",
        0,
        winreg.KEY_SET_VALUE,
    ) as key:
        if enabled:
            winreg.SetValueEx(key, RUN_KEY_NAME, 0, winreg.REG_SZ, app_command(silent))
        else:
            try:
                winreg.DeleteValue(key, RUN_KEY_NAME)
            except FileNotFoundError:
                pass


def request_existing_window() -> None:
    event = kernel32.CreateEventW(None, False, False, SHOW_EVENT_NAME)
    if event:
        kernel32.SetEvent(event)
        kernel32.CloseHandle(event)


def virtual_screen_bbox() -> tuple[int, int, int, int]:
    left = user32.GetSystemMetrics(SM_XVIRTUALSCREEN)
    top = user32.GetSystemMetrics(SM_YVIRTUALSCREEN)
    width = user32.GetSystemMetrics(SM_CXVIRTUALSCREEN)
    height = user32.GetSystemMetrics(SM_CYVIRTUALSCREEN)
    if width <= 0 or height <= 0:
        width = user32.GetSystemMetrics(0)
        height = user32.GetSystemMetrics(1)
        left = 0
        top = 0
    return left, top, left + width, top + height


def position_window(window: tk.Toplevel, x: int, y: int, width: int, height: int) -> None:
    window.geometry(f"{width}x{height}+0+0")
    window.update_idletasks()
    user32.SetWindowPos(window.winfo_id(), HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW)


class HotkeyThread(threading.Thread):
    def __init__(self, events: queue.Queue):
        super().__init__(daemon=True)
        self.events = events
        self.thread_id = None

    def run(self) -> None:
        self.thread_id = kernel32.GetCurrentThreadId()
        modifiers = MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT
        if not user32.RegisterHotKey(None, HOTKEY_ID, modifiers, VK_6):
            error_code = kernel32.GetLastError()
            self.events.put(("hotkey_error", error_code))
            return

        self.events.put(("hotkey_ready", None))
        msg = MSG()
        try:
            while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) != 0:
                if msg.message == WM_HOTKEY and msg.wParam == HOTKEY_ID:
                    self.events.put(("capture", None))
                user32.TranslateMessage(ctypes.byref(msg))
                user32.DispatchMessageW(ctypes.byref(msg))
        finally:
            user32.UnregisterHotKey(None, HOTKEY_ID)
            self.events.put(("hotkey_stopped", None))

    def stop(self) -> None:
        if self.thread_id:
            user32.PostThreadMessageW(self.thread_id, WM_QUIT, 0, 0)


class RegionSelector:
    def __init__(self, master: tk.Tk, screenshot, bbox: tuple[int, int, int, int]):
        self.screenshot = screenshot
        self.bbox = bbox
        self.start_x = 0
        self.start_y = 0
        self.rect_id = None
        self.result_path = None

        left, top, _, _ = bbox
        self.window = tk.Toplevel(master)
        self.window.overrideredirect(True)
        self.window.attributes("-topmost", True)
        self.window.configure(cursor="crosshair")
        position_window(self.window, left, top, screenshot.width, screenshot.height)

        self.canvas = tk.Canvas(
            self.window,
            width=screenshot.width,
            height=screenshot.height,
            highlightthickness=0,
            cursor="crosshair",
        )
        self.canvas.pack(fill=tk.BOTH, expand=True)
        self.photo = ImageTk.PhotoImage(screenshot)
        self.canvas.create_image(0, 0, image=self.photo, anchor="nw")
        self.draw_instruction()

        self.canvas.bind("<ButtonPress-1>", self.on_press)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)
        self.window.bind("<Escape>", self.cancel)
        self.window.grab_set()
        self.window.focus_force()

    def draw_instruction(self) -> None:
        text = "拖动选择 OCR 区域，Esc 取消"
        self.canvas.create_rectangle(16, 16, 270, 52, fill="#111827", outline="#111827")
        self.canvas.create_text(
            28,
            34,
            text=text,
            fill="#f9fafb",
            anchor="w",
            font=("Segoe UI", 12, "bold"),
        )

    def on_press(self, event) -> None:
        self.start_x = event.x
        self.start_y = event.y
        if self.rect_id is not None:
            self.canvas.delete(self.rect_id)
        self.rect_id = self.canvas.create_rectangle(
            self.start_x,
            self.start_y,
            event.x,
            event.y,
            outline="#22c55e",
            width=2,
        )

    def on_drag(self, event) -> None:
        if self.rect_id is not None:
            self.canvas.coords(self.rect_id, self.start_x, self.start_y, event.x, event.y)

    def on_release(self, event) -> None:
        x1, x2 = sorted((self.start_x, event.x))
        y1, y2 = sorted((self.start_y, event.y))
        x1 = max(0, min(self.screenshot.width, x1))
        x2 = max(0, min(self.screenshot.width, x2))
        y1 = max(0, min(self.screenshot.height, y1))
        y2 = max(0, min(self.screenshot.height, y2))

        if x2 - x1 < 8 or y2 - y1 < 8:
            self.cancel()
            return

        cropped = self.screenshot.crop((x1, y1, x2, y2))
        fd, path = tempfile.mkstemp(prefix="ocr_screenshot_", suffix=".png")
        os.close(fd)
        cropped.save(path, "PNG")
        self.result_path = path
        self.window.destroy()

    def cancel(self, event=None) -> None:
        self.result_path = None
        self.window.destroy()

    def run(self) -> str | None:
        self.window.wait_window()
        return self.result_path


class OCRApp:
    def __init__(self, root: tk.Tk, *, silent_start: bool = False):
        self.root = root
        self.events = queue.Queue()
        self.running_lock = threading.Lock()
        self.config = load_config()
        self.hotkey_thread = HotkeyThread(self.events)
        self.show_event_handle = None
        self.status_var = tk.StringVar(value="正在启动热键...")

        self.model_var = tk.StringVar(value=self.config["model"])
        self.format_var = tk.StringVar(value=self.config["format"])
        self.dashscope_key_var = tk.StringVar(
            value=self.config["api_keys"].get("DASHSCOPE_API_KEY", "")
        )
        self.mimo_key_var = tk.StringVar(value=self.config["api_keys"].get("MIMO_API_KEY", ""))
        self.openrouter_key_var = tk.StringVar(
            value=self.config["api_keys"].get("OPENROUTER_API_KEY", "")
        )
        self.launch_at_login_var = tk.BooleanVar(value=bool(self.config.get("launch_at_login")))
        self.silent_launch_at_login_var = tk.BooleanVar(
            value=bool(self.config.get("silent_launch_at_login"))
        )

        self.build_ui()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.start_show_event_listener()
        self.hotkey_thread.start()
        self.root.after(100, self.poll_events)

        if not self.has_required_key(self.config):
            self.status_var.set("请先保存 API Key；保存后即可使用 Ctrl+Shift+6。")
        else:
            self.status_var.set("准备就绪：Ctrl+Shift+6 截图 OCR。")
        if silent_start:
            self.root.withdraw()

    def build_ui(self) -> None:
        self.root.title(APP_NAME)
        self.root.geometry("680x660")
        self.root.minsize(600, 580)

        container = ttk.Frame(self.root, padding=18)
        container.pack(fill=tk.BOTH, expand=True)

        title = ttk.Label(container, text="OCR Clipboard", font=("Segoe UI", 16, "bold"))
        title.pack(anchor="w")
        subtitle = ttk.Label(
            container,
            text="启动后按 Ctrl+Shift+6，框选截图区域，AI OCR 结果会复制到剪切板。",
        )
        subtitle.pack(anchor="w", pady=(4, 16))

        settings = ttk.LabelFrame(container, text="识别设置", padding=12)
        settings.pack(fill=tk.X)
        settings.columnconfigure(1, weight=1)

        ttk.Label(settings, text="模型").grid(row=0, column=0, sticky="w", pady=4)
        model_combo = ttk.Combobox(
            settings,
            textvariable=self.model_var,
            values=list(MODEL_CONFIG.keys()),
            state="readonly",
        )
        model_combo.grid(row=0, column=1, sticky="ew", pady=4, padx=(12, 0))

        ttk.Label(settings, text="输出格式").grid(row=1, column=0, sticky="w", pady=4)
        format_combo = ttk.Combobox(
            settings,
            textvariable=self.format_var,
            values=list(FORMAT_LABELS.keys()),
            state="readonly",
        )
        format_combo.grid(row=1, column=1, sticky="ew", pady=4, padx=(12, 0))

        ttk.Label(settings, text="启动").grid(row=2, column=0, sticky="w", pady=4)
        startup_row = ttk.Frame(settings)
        startup_row.grid(row=2, column=1, sticky="ew", pady=4, padx=(12, 0))
        ttk.Checkbutton(
            startup_row,
            text="开机自动启动（保存配置后生效）",
            variable=self.launch_at_login_var,
        ).pack(anchor="w")
        ttk.Checkbutton(
            startup_row,
            text="开机自启时静默启动",
            variable=self.silent_launch_at_login_var,
        ).pack(anchor="w", pady=(4, 0))

        keys = ttk.LabelFrame(container, text="API Key", padding=12)
        keys.pack(fill=tk.X, pady=(14, 0))
        keys.columnconfigure(1, weight=1)

        ttk.Label(keys, text="DashScope / Qwen").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(keys, textvariable=self.dashscope_key_var, show="*").grid(
            row=0, column=1, sticky="ew", pady=4, padx=(12, 0)
        )
        ttk.Label(keys, text="MiMo").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(keys, textvariable=self.mimo_key_var, show="*").grid(
            row=1, column=1, sticky="ew", pady=4, padx=(12, 0)
        )
        ttk.Label(keys, text="OpenRouter").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(keys, textvariable=self.openrouter_key_var, show="*").grid(
            row=2, column=1, sticky="ew", pady=4, padx=(12, 0)
        )

        prompt_frame = ttk.LabelFrame(container, text="自定义系统提示词（可选）", padding=12)
        prompt_frame.pack(fill=tk.BOTH, expand=True, pady=(14, 0))
        self.prompt_text = tk.Text(prompt_frame, height=8, wrap="word", undo=True)
        self.prompt_text.pack(fill=tk.BOTH, expand=True)
        self.prompt_text.insert("1.0", self.config.get("custom_prompt", ""))

        buttons = ttk.Frame(container)
        buttons.pack(fill=tk.X, pady=(16, 0))
        ttk.Button(buttons, text="保存配置", command=self.save_from_ui).pack(side=tk.LEFT)
        ttk.Button(buttons, text="立即截图 OCR", command=self.start_capture).pack(
            side=tk.LEFT, padx=(8, 0)
        )
        ttk.Button(buttons, text="打开日志", command=self.open_log).pack(side=tk.LEFT, padx=(8, 0))
        ttk.Button(buttons, text="退出", command=self.on_close).pack(side=tk.RIGHT)

        status_bar = ttk.Label(
            container,
            textvariable=self.status_var,
            relief=tk.SUNKEN,
            anchor="w",
            padding=(8, 5),
        )
        status_bar.pack(fill=tk.X, pady=(16, 0))

        config_hint = ttk.Label(
            container,
            text=f"配置文件：{CONFIG_PATH}",
            foreground="#666666",
        )
        config_hint.pack(anchor="w", pady=(8, 0))

    def collect_config(self) -> dict:
        config = deep_merge(DEFAULT_CONFIG, self.config)
        config["model"] = self.model_var.get().strip()
        config["format"] = self.format_var.get().strip()
        config["custom_prompt"] = self.prompt_text.get("1.0", "end").strip()
        config["api_keys"] = {
            "DASHSCOPE_API_KEY": self.dashscope_key_var.get().strip(),
            "MIMO_API_KEY": self.mimo_key_var.get().strip(),
            "OPENROUTER_API_KEY": self.openrouter_key_var.get().strip(),
        }
        config["launch_at_login"] = bool(self.launch_at_login_var.get())
        config["silent_launch_at_login"] = bool(self.silent_launch_at_login_var.get())
        return config

    def save_from_ui(self) -> bool:
        config = self.collect_config()
        try:
            validate_model_name(config["model"])
            validate_format_name(config["format"])
            save_config(config)
            set_launch_at_login(
                config["launch_at_login"],
                config["silent_launch_at_login"],
            )
        except Exception as exc:
            logging.exception("Could not save settings")
            messagebox.showerror(APP_NAME, f"保存失败：{exc}")
            return False

        self.config = config
        self.status_var.set("配置已保存。按 Ctrl+Shift+6 开始截图 OCR。")
        return True

    def api_keys_for_config(self, config: dict) -> dict[str, str]:
        return {
            "DASHSCOPE_API_KEY": config["api_keys"].get("DASHSCOPE_API_KEY", ""),
            "QWEN_API_KEY": config["api_keys"].get("DASHSCOPE_API_KEY", ""),
            "ALIYUN_DASHSCOPE_API_KEY": config["api_keys"].get("DASHSCOPE_API_KEY", ""),
            "MIMO_API_KEY": config["api_keys"].get("MIMO_API_KEY", ""),
            "XIAOMI_MIMO_API_KEY": config["api_keys"].get("MIMO_API_KEY", ""),
            "OPENROUTER_API_KEY": config["api_keys"].get("OPENROUTER_API_KEY", ""),
        }

    def has_required_key(self, config: dict) -> bool:
        model = config.get("model", DEFAULT_MODEL)
        env_names = MODEL_CONFIG.get(model, {}).get("api_key_env", ())
        api_keys = self.api_keys_for_config(config)
        return any(api_keys.get(name) or os.getenv(name, "").strip() for name in env_names)

    def start_show_event_listener(self) -> None:
        self.show_event_handle = kernel32.CreateEventW(None, False, False, SHOW_EVENT_NAME)
        if not self.show_event_handle:
            logging.warning("Could not create show-window event")
            return

        def wait_for_show_requests() -> None:
            while True:
                result = kernel32.WaitForSingleObject(self.show_event_handle, INFINITE)
                if result == WAIT_OBJECT_0:
                    self.events.put(("show_window", None))
                else:
                    logging.warning("Show-window event wait returned %s", result)
                    break

        threading.Thread(target=wait_for_show_requests, daemon=True).start()

    def show_window(self) -> None:
        self.root.deiconify()
        self.root.state("normal")
        self.root.lift()
        self.root.focus_force()
        self.status_var.set("准备就绪：Ctrl+Shift+6 截图 OCR。")

    def show_windows_notification(self, title: str, message: str) -> bool:
        try:
            data = NOTIFYICONDATAW()
            data.cbSize = ctypes.sizeof(NOTIFYICONDATAW)
            data.hWnd = self.root.winfo_id()
            data.uID = NOTIFICATION_ICON_ID
            data.uCallbackMessage = NOTIFY_CALLBACK_MESSAGE
            data.hIcon = user32.LoadIconW(None, IDI_APPLICATION)
            data.szTip = APP_NAME[:127]

            shell32.Shell_NotifyIconW(NIM_DELETE, ctypes.byref(data))
            data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
            if not shell32.Shell_NotifyIconW(NIM_ADD, ctypes.byref(data)):
                return False

            data.uFlags = NIF_INFO
            data.szInfoTitle = title[:63]
            data.szInfo = message[:255]
            data.dwInfoFlags = NIIF_INFO
            if not shell32.Shell_NotifyIconW(NIM_MODIFY, ctypes.byref(data)):
                shell32.Shell_NotifyIconW(NIM_DELETE, ctypes.byref(data))
                return False

            self.root.after(6000, self.delete_notification_icon)
            return True
        except Exception:
            logging.exception("Could not show Windows notification")
            return False

    def delete_notification_icon(self) -> None:
        data = NOTIFYICONDATAW()
        data.cbSize = ctypes.sizeof(NOTIFYICONDATAW)
        data.hWnd = self.root.winfo_id()
        data.uID = NOTIFICATION_ICON_ID
        shell32.Shell_NotifyIconW(NIM_DELETE, ctypes.byref(data))

    def notify_user(self, title: str, message: str) -> None:
        if not self.show_windows_notification(title, message):
            self.show_toast(f"{title}：{message}")

    def poll_events(self) -> None:
        while True:
            try:
                event, payload = self.events.get_nowait()
            except queue.Empty:
                break
            if event == "capture":
                self.start_capture()
            elif event == "hotkey_ready":
                logging.info("Registered Ctrl+Shift+6")
            elif event == "hotkey_error":
                self.status_var.set("Ctrl+Shift+6 注册失败，可能已被其他程序占用。")
                messagebox.showwarning(
                    APP_NAME,
                    f"无法注册 Ctrl+Shift+6，可能已被其他程序占用。\nWindows 错误码：{payload}",
                )
            elif event == "ocr_done":
                self.status_var.set("OCR 已完成，结果已复制到剪切板。")
                self.notify_user("OCR 已完成", "结果已复制到剪切板。")
            elif event == "ocr_error":
                self.status_var.set("OCR 失败，请检查 API Key、模型设置和日志。")
                messagebox.showerror(APP_NAME, f"OCR 失败：{payload}\n\n日志：{LOG_PATH}")
            elif event == "ocr_started":
                self.status_var.set("正在识别截图...")
                self.show_toast("正在识别截图...")
            elif event == "show_window":
                self.show_window()
        self.root.after(100, self.poll_events)

    def start_capture(self) -> None:
        if not self.running_lock.acquire(blocking=False):
            self.status_var.set("OCR 正在运行，请稍候。")
            return

        config = self.collect_config()
        try:
            validate_model_name(config["model"])
            validate_format_name(config["format"])
        except Exception as exc:
            self.running_lock.release()
            messagebox.showerror(APP_NAME, str(exc))
            return

        if not self.has_required_key(config):
            self.running_lock.release()
            messagebox.showwarning(APP_NAME, "请先填写当前模型需要的 API Key 并保存配置。")
            return

        self.config = config
        save_config(config)
        try:
            set_launch_at_login(
                config["launch_at_login"],
                config["silent_launch_at_login"],
            )
        except Exception:
            logging.exception("Could not update launch at login while starting capture")

        previous_state = self.root.state()
        hide_for_capture = previous_state in {"normal", "zoomed"}
        if hide_for_capture:
            self.root.withdraw()
            self.root.update()

        image_path = None
        try:
            time.sleep(0.12)
            bbox = virtual_screen_bbox()
            try:
                screenshot = ImageGrab.grab(bbox=bbox, all_screens=True)
            except TypeError:
                screenshot = ImageGrab.grab(bbox=bbox)
            selector = RegionSelector(self.root, screenshot, bbox)
            image_path = selector.run()
        except Exception as exc:
            logging.exception("Screenshot selection failed")
            messagebox.showerror(APP_NAME, f"截图失败：{exc}")
        finally:
            if hide_for_capture:
                self.root.deiconify()
                if previous_state == "zoomed":
                    self.root.state("zoomed")
                self.root.lift()

        if not image_path:
            self.running_lock.release()
            self.status_var.set("已取消截图。")
            return

        self.events.put(("ocr_started", None))
        threading.Thread(target=self.run_ocr_worker, args=(image_path, config), daemon=True).start()

    def run_ocr_worker(self, image_path: str, config: dict) -> None:
        try:
            with open(image_path, "rb") as image_file:
                image_bytes = image_file.read()

            output_format = config["format"]
            custom_prompt = config.get("custom_prompt", "").strip()
            system_prompt = custom_prompt if custom_prompt else SYSTEM_PROMPTS[output_format]
            result = ocr_image_bytes(
                image_bytes,
                model=config["model"],
                system_prompt=system_prompt,
                user_text="请处理这张图片。",
                temperature=0.01 if output_format == "formula" else 0.1,
                api_keys=self.api_keys_for_config(config),
            )
            if not result or result.isspace():
                raise RuntimeError("OCR 转换结果为空")

            if output_format in {"tex", "formula"}:
                result = strip_markdown_fences(result)
            pyperclip.copy(result)
            logging.info("OCR completed with %d characters", len(result))
            self.events.put(("ocr_done", None))
        except Exception as exc:
            logging.exception("OCR failed")
            self.events.put(("ocr_error", str(exc)))
        finally:
            try:
                os.remove(image_path)
            except OSError:
                logging.exception("Could not remove temp screenshot: %s", image_path)
            self.running_lock.release()

    def show_toast(self, message: str, duration_ms: int = 2200) -> None:
        toast = tk.Toplevel(self.root)
        toast.overrideredirect(True)
        toast.attributes("-topmost", True)
        toast.configure(bg="#111827")
        label = tk.Label(
            toast,
            text=message,
            bg="#111827",
            fg="#f9fafb",
            padx=18,
            pady=12,
            font=("Segoe UI", 10),
        )
        label.pack()
        toast.update_idletasks()
        width = toast.winfo_reqwidth()
        height = toast.winfo_reqheight()
        screen_width = toast.winfo_screenwidth()
        screen_height = toast.winfo_screenheight()
        x = max(16, screen_width - width - 28)
        y = max(16, screen_height - height - 64)
        toast.geometry(f"{width}x{height}+{x}+{y}")
        toast.after(duration_ms, toast.destroy)

    def open_log(self) -> None:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        LOG_PATH.touch(exist_ok=True)
        os.startfile(LOG_PATH)  # type: ignore[attr-defined]

    def on_close(self) -> None:
        self.hotkey_thread.stop()
        self.root.after(100, self.root.destroy)


def create_single_instance_mutex() -> bool:
    global mutex_handle
    mutex_handle = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if not mutex_handle:
        return True
    if kernel32.GetLastError() == ERROR_ALREADY_EXISTS:
        request_existing_window()
        return False
    return True


def main() -> int:
    setup_logging()
    setup_dpi_awareness()
    logging.info("Starting %s", APP_NAME)
    silent_start = any(arg.lower() in {"--silent", "/silent"} for arg in sys.argv[1:])

    if not create_single_instance_mutex():
        return 0

    root = tk.Tk()
    try:
        OCRApp(root, silent_start=silent_start)
        root.mainloop()
    finally:
        logging.info("Exiting %s", APP_NAME)
    return 0


if __name__ == "__main__":
    sys.exit(main())
