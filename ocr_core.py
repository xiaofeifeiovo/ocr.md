import base64
import os
from pathlib import Path
import re

from openai import OpenAI

BASE_DIR = Path(__file__).resolve().parent

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
DEFAULT_FORMAT = "tex"

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


def load_env_file(path: str | Path = ".env") -> None:
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


def validate_model_name(model: str) -> None:
    if model not in MODEL_CONFIG:
        raise ValueError(f"Invalid model: {model}. Must be one of: {', '.join(MODEL_CONFIG)}")


def validate_format_name(output_format: str) -> None:
    if output_format not in SYSTEM_PROMPTS:
        raise ValueError(
            f"Invalid format: {output_format}. Must be one of: {', '.join(SYSTEM_PROMPTS)}"
        )


def get_api_key(
    env_names: tuple[str, ...],
    api_keys: dict[str, str] | None = None,
) -> tuple[str | None, str | None]:
    api_keys = api_keys or {}
    for env_name in env_names:
        api_key = api_keys.get(env_name, "").strip()
        if api_key:
            return api_key, env_name
    for env_name in env_names:
        api_key = os.getenv(env_name, "").strip()
        if api_key:
            return api_key, env_name
    return None, None


def build_client(model: str, api_keys: dict[str, str] | None = None) -> OpenAI:
    validate_model_name(model)
    model_cfg = MODEL_CONFIG[model]
    api_key_envs = model_cfg["api_key_env"]
    api_key, _ = get_api_key(api_key_envs, api_keys)
    if not api_key:
        raise RuntimeError(f"Missing API key. Set one of: {', '.join(api_key_envs)}.")
    return OpenAI(api_key=api_key, base_url=model_cfg["base_url"])


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
    api_keys: dict[str, str] | None = None,
) -> str:
    model_cfg = MODEL_CONFIG[model]
    client = build_client(model, api_keys)
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


load_env_file()
load_env_file(".env.local")
