import base64
from datetime import datetime
import os
from pathlib import Path
import re
import subprocess
import sys
from threading import Lock
from uuid import uuid4

from fastapi import BackgroundTasks, FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse, JSONResponse
import fitz
from openai import OpenAI

BASE_DIR = Path(__file__).resolve().parent
app = FastAPI(title="OCR Web Service")
PDF_JOBS = {}
PDF_JOBS_LOCK = Lock()

DASHSCOPE_API_KEY_ENVS = (
    "DASHSCOPE_API_KEY",
    "QWEN_API_KEY",
    "ALIYUN_DASHSCOPE_API_KEY",
)
MIMO_API_KEY_ENVS = (
    "MIMO_API_KEY",
    "XIAOMI_MIMO_API_KEY",
)
OPENROUTER_API_KEY_ENVS = ("OPENROUTER_API_KEY",)
DEFAULT_MODEL = "google/gemini-3.1-flash-lite"


def load_env_file(path: str = ".env") -> None:
    env_path = Path(path)
    if not env_path.is_absolute():
        env_path = BASE_DIR / env_path
    if not env_path.exists():
        return

    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and value and not os.environ.get(key):
            os.environ[key] = value


load_env_file()
load_env_file(".env.local")


SYSTEM_PROMPTS = {
    "markdown": (
        "你是一个严谨的 OCR 转写工具，任务是将图片中的可见内容转换为忠实的 Markdown。\n"
        "严格规则：\n"
        "- 只输出 Markdown 正文，不要包含开场白、总结、解释或代码块包裹\n"
        "- 按阅读顺序保留标题、段落、列表、表格、脚注标记、引用和数学公式\n"
        "- 表格优先使用 Markdown 表格；结构过复杂时用清晰的纯文本排版\n"
        "- 行内公式使用 $...$，独立成行或多行公式使用 $$...$$\n"
        "- 对无法确定的字符保持克制，可用 [?] 标记，不要自行补写原文没有的内容\n"
        "- 不要遗漏任何可见文字、数字、符号或注释"
    ),
    "tex": (
        "你是一个严谨的 OCR 转写工具，任务是将图片中的内容转换为可直接插入 LaTeX 文档的正文片段。\n"
        "严格规则：\n"
        "- 只输出 LaTeX 正文片段，不要包含开场白、总结、解释或代码块包裹\n"
        "- 输出内容默认已经位于 \\begin{document} 内部；不要输出 \\documentclass、导言区、\\begin{document} 或 \\end{document}\n"
        "- 保留章节标题、段落、列表、表格、脚注、编号、引用标记和公式等原有结构\n"
        "- 行内公式仅在原文确为行内数学时克制使用 $...$ 包裹\n"
        "- 独立成行、居中展示或多行推导的公式使用 $$...$$ 包裹；不要使用 \\(...\\) 或 \\[...\\]\n"
        "- 不要把普通正文整段放进数学环境；文字与公式混排时保持原本语义\n"
        "- 表格优先使用 tabular、longtable、booktabs 等正文环境，不要额外引入宏包\n"
        "- 对无法确定的字符保持克制，可用 \\text{[?]} 标记，不要自行补写原文没有的内容\n"
        "- 不要遗漏任何可见文字、数字、符号或注释"
    ),
    "formula": (
        "你是一个专业的数学 OCR 工具，任务是将图片中的手写或打印公式转换为 LaTeX 正文片段。\n"
        "严格规则：\n"
        "- 只输出 LaTeX，不要包含开场白、总结、解释或代码块包裹\n"
        "- 输出内容默认已经位于 \\begin{document} 内部；不要输出导言区或 document 环境\n"
        "- 单个独立公式或主要公式使用 $$...$$ 包裹；短小的行内公式只有在原图确为行内时使用 $...$\n"
        "- 多行推导保持原有换行，可在 $$...$$ 内使用 aligned、alignedat、cases、matrix 等环境\n"
        "- 准确识别积分、求和、分式、根号、上下标、希腊字母、矩阵、向量、集合符号和标点\n"
        "- 手写笔迹不规整时根据数学上下文谨慎推断；无法确定的符号用 \\text{[?]} 标记\n"
        "- 不要遗漏任何公式内容，也不要添加原图中没有的内容"
    ),
    "plain": (
        "你是一个严谨的 OCR 转写工具，任务是将图片中的可见内容提取为纯文本。\n"
        "严格规则：\n"
        "- 只输出纯文本，不要包含开场白、总结、解释、Markdown 语法或代码块\n"
        "- 按阅读顺序保留段落、换行、列表层级和表格的大致排版\n"
        "- 数学、单位、标点和大小写尽量按原样转写，不要改写成解释性文字\n"
        "- 对无法确定的字符保持克制，可用 [?] 标记\n"
        "- 不要遗漏任何可见文字，也不要添加原文中没有的内容"
    ),
}

PDF_LATEX_PROMPT = (
    "你是一个严谨的 OCR 转写工具，任务是将 PDF 单页图片中的内容转换为 LaTeX 正文片段。\n"
    "严格规则：\n"
    "- 只输出当前页面的 LaTeX 正文片段，不要包含开场白、总结、解释或代码块包裹\n"
    "- 输出内容默认已经位于 \\begin{document} 内部；不要输出 \\documentclass、导言区、\\begin{document} 或 \\end{document}\n"
    "- 保留章节标题、段落、表格、列表、公式、脚注、页眉页脚中有意义的内容和编号结构\n"
    "- 行内公式仅在原文确为行内数学时克制使用 $...$ 包裹\n"
    "- 独立成行、居中展示或多行推导的公式使用 $$...$$ 包裹；不要使用 \\(...\\) 或 \\[...\\]\n"
    "- 表格优先使用 tabular、longtable、booktabs 等正文环境，不要额外引入宏包\n"
    "- 对无法确定的字符保持克制，可用 \\text{[?]} 标记，不要自行补写原页面没有的内容\n"
    "- 不要遗漏任何可见文字、数字、符号或注释"
)

LATEX_PREAMBLE = r"""\documentclass[UTF8]{article}
\usepackage[a4paper,margin=1in]{geometry}
\usepackage{amsmath}
\usepackage{amssymb}
\usepackage{graphicx}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{array}
\usepackage{hyperref}
\usepackage{xeCJK}

\begin{document}
"""


@app.get("/")
async def index():
    return FileResponse(BASE_DIR / "index.html")


MODEL_CONFIG = {
    "qwen3-vl-plus": {
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "api_key_env": DASHSCOPE_API_KEY_ENVS,
        "display_name": "高精度（Qwen3-VL）",
        "enable_thinking_support": True,
    },
    "qwen3-vl-flash": {
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "api_key_env": DASHSCOPE_API_KEY_ENVS,
        "display_name": "快速（Qwen3-VL）",
        "enable_thinking_support": True,
    },
    "qwen3.5-plus": {
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "api_key_env": DASHSCOPE_API_KEY_ENVS,
        "display_name": "最佳质量（Qwen3.5）",
        "enable_thinking_support": True,
    },
    "qwen3.5-flash": {
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "api_key_env": DASHSCOPE_API_KEY_ENVS,
        "display_name": "快速（Qwen3.5）",
        "enable_thinking_support": True,
    },
    "qwen3.5-omni-flash": {
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "api_key_env": DASHSCOPE_API_KEY_ENVS,
        "display_name": "多模态快速（Qwen3.5-Omni）",
        "enable_thinking_support": False,
        "stream_required": True,
        "modalities": ["text"],
    },
    "qwen-vl-plus": {
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "api_key_env": DASHSCOPE_API_KEY_ENVS,
        "display_name": "均衡（Qwen2.5-VL）",
        "enable_thinking_support": True,
    },
    "qwen-vl-max": {
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "api_key_env": DASHSCOPE_API_KEY_ENVS,
        "display_name": "高精度（Qwen2.5-VL）",
        "enable_thinking_support": True,
    },
    "mimo-v2.5": {
        "base_url": "https://token-plan-cn.xiaomimimo.com/v1",
        "api_key_env": MIMO_API_KEY_ENVS,
        "display_name": "MiMo v2.5",
        "enable_thinking_support": False,
    },
    "google/gemini-3.1-flash-lite": {
        "base_url": "https://openrouter.ai/api/v1",
        "api_key_env": OPENROUTER_API_KEY_ENVS,
        "display_name": "Gemini Flash Lite",
        "enable_thinking_support": False,
    },
}

VALID_MODELS = {name: cfg["display_name"] for name, cfg in MODEL_CONFIG.items()}


def validate_model(model: str) -> None:
    if model not in VALID_MODELS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid model: {model}. Must be one of: {', '.join(VALID_MODELS)}",
        )


def get_api_key(env_names: tuple[str, ...]) -> tuple[str | None, str | None]:
    for env_name in env_names:
        api_key = os.getenv(env_name, "").strip()
        if api_key:
            return api_key, env_name
    return None, None


def build_client(model: str) -> OpenAI:
    model_cfg = MODEL_CONFIG[model]
    api_key_envs = model_cfg["api_key_env"]
    api_key, _ = get_api_key(api_key_envs)
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail=f"Missing API key. Set one of: {', '.join(api_key_envs)}.",
        )
    return OpenAI(
        api_key=api_key,
        base_url=model_cfg["base_url"],
    )


def strip_markdown_fences(text: str) -> str:
    cleaned = text.strip()
    cleaned = re.sub(r"^```(?:latex|tex)?\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    return cleaned.strip()


def ocr_image_bytes(
    image_bytes: bytes,
    *,
    model: str,
    system_prompt: str,
    user_text: str,
    temperature: float = 0.1,
) -> str:
    model_cfg = MODEL_CONFIG[model]
    client = build_client(model)
    base64_image = base64.b64encode(image_bytes).decode("utf-8")
    image_url = f"data:image/png;base64,{base64_image}"

    completion_kwargs = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": system_prompt,
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": image_url},
                    },
                    {"type": "text", "text": user_text},
                ],
            },
        ],
        "stream": model_cfg.get("stream_required", False),
        "temperature": temperature,
    }
    if model_cfg.get("modalities"):
        completion_kwargs["modalities"] = model_cfg["modalities"]
    if model_cfg["enable_thinking_support"]:
        completion_kwargs["extra_body"] = {"enable_thinking": False}

    completion = client.chat.completions.create(**completion_kwargs)
    if model_cfg.get("stream_required"):
        chunks = []
        for chunk in completion:
            if not chunk.choices:
                continue
            content = chunk.choices[0].delta.content
            if content:
                chunks.append(content)
        return "".join(chunks)

    return completion.choices[0].message.content or ""


def pdf_page_count(pdf_bytes: bytes) -> int:
    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Invalid PDF file: {exc}") from exc
    with doc:
        return doc.page_count


def render_pdf_pages(
    pdf_bytes: bytes,
    zoom: float = 2.0,
    start_page: int | None = None,
    end_page: int | None = None,
) -> list[tuple[int, bytes]]:
    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Invalid PDF file: {exc}") from exc

    pages = []
    matrix = fitz.Matrix(zoom, zoom)
    with doc:
        first_page = start_page or 1
        last_page = end_page or doc.page_count
        for page_number in range(first_page, last_page + 1):
            page = doc.load_page(page_number - 1)
            pix = page.get_pixmap(matrix=matrix, alpha=False)
            pages.append((page_number, pix.tobytes("png")))
    return pages


def build_latex_document(page_texts: list[str], page_numbers: list[int] | None = None) -> str:
    body = []
    for index, text in enumerate(page_texts, start=1):
        page_number = page_numbers[index - 1] if page_numbers else index
        body.append(f"% Page {page_number}")
        body.append(strip_markdown_fences(text))
        body.append("")
    document_body = "\n".join(body)
    return f"{LATEX_PREAMBLE}\n{document_body}\\end{{document}}\n"


def output_tex_path(original_filename: str) -> Path:
    outputs_dir = BASE_DIR / "outputs"
    outputs_dir.mkdir(exist_ok=True)
    stem = Path(original_filename or "document").stem
    safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", stem).strip("._") or "document"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return outputs_dir / f"{safe_stem}_{timestamp}.tex"


def outputs_dir_path() -> Path:
    outputs_dir = BASE_DIR / "outputs"
    outputs_dir.mkdir(exist_ok=True)
    return outputs_dir.resolve()


def open_path(path: Path) -> None:
    if sys.platform.startswith("win"):
        os.startfile(path)  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.run(["open", str(path)], check=True)
    else:
        subprocess.run(["xdg-open", str(path)], check=True)


def validate_page_range(
    start_page: int | None,
    end_page: int | None,
    page_count: int,
) -> tuple[int, int]:
    start = start_page or 1
    end = end_page or page_count

    if start < 1 or end < 1:
        raise HTTPException(status_code=400, detail="Page range must start at page 1 or later.")
    if start > page_count:
        raise HTTPException(status_code=400, detail=f"Start page exceeds PDF page count: {page_count}.")
    if end > page_count:
        raise HTTPException(status_code=400, detail=f"End page exceeds PDF page count: {page_count}.")
    if start > end:
        raise HTTPException(status_code=400, detail="Start page must be less than or equal to end page.")
    return start, end


def update_pdf_job(job_id: str, **changes) -> None:
    with PDF_JOBS_LOCK:
        if job_id in PDF_JOBS:
            PDF_JOBS[job_id].update(changes)


def run_pdf_ocr_job(
    *,
    job_id: str,
    pdf_bytes: bytes,
    filename: str,
    model: str,
    system_prompt: str,
    start_page: int,
    end_page: int,
) -> None:
    try:
        rendered_pages = render_pdf_pages(pdf_bytes, start_page=start_page, end_page=end_page)
        page_texts = []
        page_numbers = []
        update_pdf_job(job_id, status="running")

        for processed_count, (page_number, page_image) in enumerate(rendered_pages, start=1):
            update_pdf_job(job_id, current_page=page_number)
            page_text = ocr_image_bytes(
                page_image,
                model=model,
                system_prompt=system_prompt,
                user_text=f"请将第 {page_number} 页转换为 LaTeX 正文片段。",
                temperature=0.1,
            )
            page_texts.append(page_text)
            page_numbers.append(page_number)
            update_pdf_job(job_id, processed_pages=processed_count)

        latex_text = build_latex_document(page_texts, page_numbers)
        output_path = output_tex_path(filename)
        output_path.write_text(latex_text, encoding="utf-8")
        update_pdf_job(
            job_id,
            status="completed",
            success=True,
            text=latex_text,
            output_file=str(output_path),
            current_page=end_page,
        )
    except Exception as e:
        update_pdf_job(job_id, status="failed", success=False, text=str(e))


@app.post("/api/ocr")
async def ocr_endpoint(
    image: UploadFile = File(...),
    format: str = Form(default="plain"),
    model: str = Form(default=DEFAULT_MODEL),
    prompt: str = Form(default=None),
):
    if format not in SYSTEM_PROMPTS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid format: {format}. Must be one of: plain, markdown, tex",
        )

    validate_model(model)

    system_prompt = prompt if prompt else SYSTEM_PROMPTS[format]
    if not prompt and format in SYSTEM_PROMPTS:
        system_prompt = SYSTEM_PROMPTS[format]

    image_bytes = await image.read()

    try:
        result_text = ocr_image_bytes(
            image_bytes,
            model=model,
            system_prompt=system_prompt,
            user_text="请处理这张图片。",
            temperature=0.01 if format == "formula" else 0.1,
        )
        return {"text": result_text, "format": format, "model": model, "success": True}
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"text": str(e), "format": "", "success": False},
        )


@app.post("/api/pdf-ocr")
async def pdf_ocr_endpoint(
    background_tasks: BackgroundTasks,
    pdf: UploadFile = File(...),
    model: str = Form(default=DEFAULT_MODEL),
    prompt: str = Form(default=None),
    start_page: int | None = Form(default=None),
    end_page: int | None = Form(default=None),
):
    validate_model(model)

    filename = pdf.filename or ""
    content_type = pdf.content_type or ""
    if not filename.lower().endswith(".pdf") and content_type != "application/pdf":
        raise HTTPException(status_code=400, detail="Please upload a PDF file.")

    pdf_bytes = await pdf.read()
    if not pdf_bytes:
        raise HTTPException(status_code=400, detail="PDF file is empty.")

    page_count = pdf_page_count(pdf_bytes)
    start, end = validate_page_range(start_page, end_page, page_count)
    total_pages = end - start + 1
    system_prompt = prompt.strip() if prompt and prompt.strip() else PDF_LATEX_PROMPT
    job_id = uuid4().hex

    with PDF_JOBS_LOCK:
        PDF_JOBS[job_id] = {
            "job_id": job_id,
            "success": True,
            "status": "queued",
            "text": "",
            "output_file": "",
            "processed_pages": 0,
            "total_pages": total_pages,
            "pdf_page_count": page_count,
            "start_page": start,
            "end_page": end,
            "current_page": None,
            "model": model,
        }

    background_tasks.add_task(
        run_pdf_ocr_job,
        job_id=job_id,
        pdf_bytes=pdf_bytes,
        filename=filename,
        model=model,
        system_prompt=system_prompt,
        start_page=start,
        end_page=end,
    )

    return {
        "success": True,
        "job_id": job_id,
        "status": "queued",
        "processed_pages": 0,
        "total_pages": total_pages,
        "pdf_page_count": page_count,
        "start_page": start,
        "end_page": end,
        "model": model,
    }


@app.get("/api/pdf-ocr/{job_id}")
async def pdf_ocr_status_endpoint(job_id: str):
    with PDF_JOBS_LOCK:
        job = PDF_JOBS.get(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="PDF OCR job not found.")
        return dict(job)


@app.post("/api/open-outputs")
async def open_outputs_endpoint():
    outputs_dir = outputs_dir_path()
    try:
        open_path(outputs_dir)
        return {"success": True, "path": str(outputs_dir)}
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"success": False, "path": str(outputs_dir), "text": str(e)},
        )


# Run with: uvicorn server:app --reload --port 8080
