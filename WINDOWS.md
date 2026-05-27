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
