#!/usr/bin/env python3

import argparse
import os
import sys
import tempfile
from pathlib import Path

from PIL import ImageGrab, Image, UnidentifiedImageError
import pyperclip

from ocr_core import (
    DEFAULT_FORMAT,
    DEFAULT_MODEL,
    MODEL_CONFIG,
    SYSTEM_PROMPTS,
    load_env_file,
    ocr_image_bytes,
)

BASE_DIR = Path(__file__).resolve().parent
TEMP_IMAGE_PATHS = set()


def env_default(name, fallback):
    return os.getenv(name, "").strip() or fallback


def is_image_file(path):
    try:
        with Image.open(path) as image:
            image.verify()
        return True
    except (OSError, UnidentifiedImageError):
        return False


def save_temp_clipboard_image(image):
    fd, temp_path = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    image.save(temp_path, "PNG")
    TEMP_IMAGE_PATHS.add(temp_path)
    return temp_path


def cleanup_temp_image(path):
    if path in TEMP_IMAGE_PATHS and os.path.exists(path):
        os.remove(path)
        TEMP_IMAGE_PATHS.discard(path)


def check_clipboard_content():
    """
    检查剪切板内容。
    返回: ("text", content) 或 ("image", image_path) 或 ("unknown", None)
    """
    clipboard_content = ImageGrab.grabclipboard()

    if isinstance(clipboard_content, Image.Image):
        return "image", save_temp_clipboard_image(clipboard_content)

    if isinstance(clipboard_content, list):
        # Windows 复制图片文件时 Pillow 可能返回文件路径列表。
        for item in clipboard_content:
            if isinstance(item, str) and os.path.isfile(item) and is_image_file(item):
                return "image", item

    try:
        text_content = pyperclip.paste()
        if text_content and isinstance(text_content, str) and not text_content.isspace():
            if os.path.isfile(text_content):
                if is_image_file(text_content):
                    return "image", text_content
                return "text", text_content
            return "text", text_content
    except Exception as e:
        print(f"检查剪切板文本时出错: {str(e)}")

    return "unknown", None


def validate_model_name(model):
    if model not in MODEL_CONFIG:
        available = ", ".join(MODEL_CONFIG)
        raise ValueError(f"Invalid model: {model}. Must be one of: {available}")


def validate_format_name(output_format):
    if output_format not in SYSTEM_PROMPTS:
        available = ", ".join(SYSTEM_PROMPTS)
        raise ValueError(f"Invalid format: {output_format}. Must be one of: {available}")


def resolve_prompt(args):
    if args.prompt_file:
        return args.prompt_file.expanduser().read_text(encoding="utf-8").strip()
    if args.prompt:
        return args.prompt.strip()
    return ""


def ocr_image(image_path, *, model, output_format, prompt=""):
    """使用与网页 OCR 相同的模型配置和系统提示词识别图片。"""
    validate_model_name(model)
    validate_format_name(output_format)
    system_prompt = prompt if prompt else SYSTEM_PROMPTS[output_format]

    with open(image_path, "rb") as image_file:
        image_bytes = image_file.read()

    return ocr_image_bytes(
        image_bytes,
        model=model,
        system_prompt=system_prompt,
        user_text="请处理这张图片。",
        temperature=0.01 if output_format == "formula" else 0.1,
    )


def parse_args():
    parser = argparse.ArgumentParser(
        description="OCR an image from the clipboard or an explicit image file."
    )
    parser.add_argument(
        "--image",
        type=Path,
        help="OCR this image file instead of reading an image from the clipboard.",
    )
    parser.add_argument(
        "--format",
        choices=sorted(SYSTEM_PROMPTS),
        default=env_default("OCR_FORMAT", DEFAULT_FORMAT),
        help="Output format. Defaults to OCR_FORMAT or tex.",
    )
    parser.add_argument(
        "--model",
        default=env_default("OCR_MODEL", DEFAULT_MODEL),
        help="AI model name. Defaults to OCR_MODEL or the web UI default model.",
    )
    parser.add_argument(
        "--prompt",
        help="Custom system prompt. Matches the web UI custom prompt behavior.",
    )
    parser.add_argument(
        "--prompt-file",
        type=Path,
        help="Read a custom system prompt from this UTF-8 text file.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    load_env_file()
    load_env_file(".env.local")

    prompt = resolve_prompt(args)

    if args.image:
        content_data = str(args.image.expanduser().resolve())
        if not os.path.isfile(content_data):
            print(f"图片文件不存在: {content_data}")
            return 1
        if not is_image_file(content_data):
            print(f"文件不是有效图片: {content_data}")
            return 1
        print(f"正在读取图片文件: {content_data}")
        content_type = "image"
    else:
        print("正在从剪切板读取内容...")
        content_type, content_data = check_clipboard_content()

    if content_type == "text":
        print("剪切板中是文字内容，退出程序")
        return 0

    if content_type != "image":
        print("剪切板中不是图片或文字内容，退出程序")
        return 1

    print("剪切板/输入中是图片内容，开始 OCR 转换")

    try:
        print(f"正在使用 {args.model} 进行 {args.format} OCR 转换...")
        ocr_result = ocr_image(
            content_data,
            model=args.model,
            output_format=args.format,
            prompt=prompt,
        )

        if not ocr_result or ocr_result.isspace():
            print("OCR 转换结果为空")
            return 1

        print("OCR 转换完成，将结果复制到剪切板")
        pyperclip.copy(ocr_result)

        print("OCR 转换结果已复制到剪切板")
        print("转换结果预览：")
        print(ocr_result)
        return 0
    except Exception as e:
        print(f"OCR 转换失败: {str(e)}")
        return 1
    finally:
        cleanup_temp_image(content_data)


if __name__ == "__main__":
    sys.exit(main())
