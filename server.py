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

from ocr_core import (
    DEFAULT_MODEL,
    PDF_LATEX_PROMPT,
    SYSTEM_PROMPTS,
    VALID_MODELS,
    ocr_image_bytes,
    strip_markdown_fences,
)

BASE_DIR = Path(__file__).resolve().parent
app = FastAPI(title="OCR Web Service")
PDF_JOBS = {}
PDF_JOBS_LOCK = Lock()

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


def validate_model(model: str) -> None:
    if model not in VALID_MODELS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid model: {model}. Must be one of: {', '.join(VALID_MODELS)}",
        )


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
