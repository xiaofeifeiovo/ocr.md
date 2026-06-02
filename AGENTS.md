# AGENTS.md

## Project

OCR Clipboard — convert clipboard images to text via Qwen VL / MiMo models.
Two components share API models and prompts:

| File | Role |
|---|---|
| `server.py` | FastAPI web server (serves `index.html`, provides `POST /api/ocr`) |
| `index.html` | Single-page UI (drag-drop / paste / upload), pure HTML+CSS+JS, no build step |

Supporting files: `ocr_clipboard.command` (standalone CLI clipboard OCR), `screenshot_ocr.command` (macOS region screenshot OCR launcher), `MACOS_SHORTCUT.md` (macOS shortcut setup), `start_server.command` (macOS one-click local server launcher), `start_server.bat` (Windows one-click local server launcher), `ocr_clipboard.bat` (Windows clipboard OCR launcher), `framework.md` (original requirements), `qwenomni.md` (Qwen Omni reference notes).

## Dependencies

Install from `requirements.txt`:

```
pip install -r requirements.txt
```

Or install manually:

```
pip install fastapi uvicorn openai pillow pyperclip pymupdf python-multipart
```

## Commands

| Task | Command |
|---|---|
| Start web server | `uvicorn server:app --reload --port 8080` (run from project root) |
| Start web server on Windows | double-click `start_server.bat` |
| Run clipboard CLI | `python ocr_clipboard.command` or double-click on macOS |
| Run macOS screenshot OCR | `./screenshot_ocr.command` |
| Run clipboard CLI on Windows | double-click `ocr_clipboard.bat` |

There are **no** test, lint, typecheck, or build commands configured.

## Architecture

- `server.py` defines `MODEL_CONFIG` dict and `SYSTEM_PROMPTS` formats. These are the single source of truth.
- `index.html` mirrors the model list in its UI. Adding or removing a model in `server.py` requires a matching change in `index.html`.
- API keys are read from environment variables first, then `.env` / `.env.local`.
- Supported Qwen / DashScope variables: `DASHSCOPE_API_KEY`, `QWEN_API_KEY`, `ALIYUN_DASHSCOPE_API_KEY`.
- Supported MiMo variables: `MIMO_API_KEY`, `XIAOMI_MIMO_API_KEY`.
- Supported OpenRouter variable: `OPENROUTER_API_KEY`.

## Conventions & Gotchas

- **Never commit API keys.** Keep real secrets in environment variables, `.env`, or `.env.local`.
- `index.html` has no build step — edit directly.
- `ocr_clipboard.command` creates temp PNG files during OCR and cleans them up on completion.
