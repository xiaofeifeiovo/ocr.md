# Windows 使用说明

## 1. 安装依赖

建议使用 Python 3.10 或更高版本。

```powershell
pip install -r requirements.txt
```

## 2. 配置 API Key

复制 `.env.example` 为 `.env`，然后填入需要使用的 API Key：

```env
DASHSCOPE_API_KEY=
MIMO_API_KEY=
OPENROUTER_API_KEY=
```

也可以直接使用系统环境变量。服务端会优先读取已经存在的环境变量；如果没有，再读取项目目录下的 `.env` 和 `.env.local`。

支持的变量名：

```text
Qwen / DashScope: DASHSCOPE_API_KEY, QWEN_API_KEY, ALIYUN_DASHSCOPE_API_KEY
MiMo: MIMO_API_KEY, XIAOMI_MIMO_API_KEY
OpenRouter: OPENROUTER_API_KEY
```

## 3. 启动 Web 服务

双击 `start_server.bat`，或在项目目录运行：

```powershell
python -m uvicorn server:app --reload --port 8080
```

浏览器会访问：

```text
http://127.0.0.1:8080
```

## 4. 使用剪贴板 OCR

复制一张图片或图片文件后，双击 `ocr_clipboard.bat`。识别完成后，结果会自动复制回剪贴板。

## 5. Windows 安装版：Ctrl+Shift+6 截图 OCR

安装版会启动一个 `OCR Clipboard` 桌面程序。用户在程序中配置 API Key、
模型、输出格式和可选提示词后，按：

```text
Ctrl+Shift+6
```

拖动选择截图区域，松开鼠标后会进行 AI OCR，并把结果复制到剪贴板。
默认输出格式是 `LaTeX`。

程序内可以选择“开机自动启动”，也可以选择“开机自启时静默启动”。
静默启动会在登录后隐藏设置窗口，但热键仍然可用；再次打开程序会唤出已运行窗口。
OCR 完成后会显示系统通知，并将结果复制到剪贴板。

构建可执行文件：

```text
build_windows_app.bat
```

构建安装包：

```text
build_windows_installer.bat
```

更多说明见 `WINDOWS_HOTKEY.md`。
