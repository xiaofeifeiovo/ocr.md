# AGENTS.md

## Project

OCR Clipboard — convert clipboard images to text via Qwen VL / MiMo models.
Two components share API models and prompts:

| File | Role |
|---|---|
| `server.py` | FastAPI web server (serves `index.html`, provides `POST /api/ocr`) |
| `index.html` | Single-page UI (drag-drop / paste / upload), pure HTML+CSS+JS, no build step |

Supporting files: `ocr_clipboard.command` (standalone macOS CLI clipboard OCR), `start_server.command` (one-click local server launcher), `framework.md` (original requirements), `qwenomni.md` (Qwen Omni reference notes).

## Dependencies

**No requirements.txt or pyproject.toml exists.** Install manually:

```
pip install fastapi uvicorn openai pillow pyperclip
```

## Commands

| Task | Command |
|---|---|
| Start web server | `uvicorn server:app --reload --port 8080` (run from project root) |
| Run clipboard CLI | `python ocr_clipboard.command` or double-click on macOS |

There are **no** test, lint, typecheck, or build commands configured.

## Architecture

- `server.py` defines `MODEL_CONFIG` dict and `SYSTEM_PROMPTS` formats. These are the single source of truth.
- `index.html` mirrors the model list in its UI. Adding or removing a model in `server.py` requires a matching change in `index.html`.
- All API keys are **hardcoded** in `server.py` and `ocr_clipboard.command`.

## Conventions & Gotchas

- **Never commit API keys.** They are currently hardcoded — flag this if asked to add new models.
- `index.html` has no build step — edit directly.
- `ocr_clipboard.command` creates temp PNG files during OCR and cleans them up on completion.
