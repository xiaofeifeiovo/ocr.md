#!/usr/bin/env python3

import argparse
import os
import sys
import base64
import tempfile
from pathlib import Path
from PIL import ImageGrab, Image, UnidentifiedImageError
import pyperclip

BASE_DIR = Path(__file__).resolve().parent
TEMP_IMAGE_PATHS = set()
OPENROUTER_API_KEY_ENVS = ("OPENROUTER_API_KEY",)
DEFAULT_MODEL = "google/gemini-3.1-flash-lite"
LATEX_OCR_PROMPT = (
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
)


def load_env_file(path=".env"):
    env_path = Path(path)
    if not env_path.is_absolute():
        env_path = BASE_DIR / env_path
    if not env_path.exists():
        return

    with env_path.open("r", encoding="utf-8") as env_file:
        for line in env_file:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and value and not os.environ.get(key):
                os.environ[key] = value


def get_api_key(env_names):
    for env_name in env_names:
        api_key = os.getenv(env_name, "").strip()
        if api_key:
            return api_key, env_name
    return None, None


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
    检查剪切板内容
    返回: ('text', content) 或 ('image', image_path) 或 ('unknown', None)
    """
    # 首先检查是否有图像
    clipboard_content = ImageGrab.grabclipboard()

    if isinstance(clipboard_content, Image.Image):
        # 剪切板中有图像，保存到临时文件以便发送给 OCR API。
        return 'image', save_temp_clipboard_image(clipboard_content)

    if isinstance(clipboard_content, list):
        # Windows 复制图片文件时 Pillow 可能返回文件路径列表。
        for item in clipboard_content:
            if isinstance(item, str) and os.path.isfile(item) and is_image_file(item):
                return 'image', item
    
    # 检查是否有文本内容
    try:
        text_content = pyperclip.paste()
        if text_content and isinstance(text_content, str) and not text_content.isspace():
            # 检查是否为文件路径
            if os.path.isfile(text_content):
                try:
                    if not is_image_file(text_content):
                        return 'text', text_content
                    return 'image', text_content
                except:
                    return 'text', text_content
            else:
                # 普通文本内容
                return 'text', text_content
    except Exception as e:
        print(f"检查剪切板文本时出错: {str(e)}")
    
    return 'unknown', None


def image_to_base64(image_path):
    """将图片文件转换为 base64 编码"""
    with open(image_path, "rb") as image_file:
        encoded_string = base64.b64encode(image_file.read()).decode('utf-8')
        return encoded_string


def ocr_image(image_path):
    """使用默认视觉模型对图片进行 OCR 转换"""
    from openai import OpenAI

    api_key, _ = get_api_key(OPENROUTER_API_KEY_ENVS)
    if not api_key:
        raise RuntimeError(
            f"Missing API key. Set one of: {', '.join(OPENROUTER_API_KEY_ENVS)}."
        )
    
    # 初始化OpenAI客户端
    client = OpenAI(
        api_key=api_key,
        base_url="https://openrouter.ai/api/v1"
    )

    # 将图片转换为 base64 编码
    base64_image = image_to_base64(image_path)
    image_url = f"data:image/png;base64,{base64_image}"

    # 创建聊天完成请求
    completion = client.chat.completions.create(
        model=DEFAULT_MODEL,
        messages=[
            {
                "role": "system",
                "content": LATEX_OCR_PROMPT,
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": image_url
                        },
                    },
                    {"type": "text", "text": "请处理这张图片。"},
                ],
            },
        ],
        stream=False,  # 关闭流式输出
        temperature=0.1,  # 设置较低的温度
    )

    # 返回 OCR 结果
    return completion.choices[0].message.content


def parse_args():
    parser = argparse.ArgumentParser(
        description="OCR an image from the clipboard or an explicit image file."
    )
    parser.add_argument(
        "--image",
        type=Path,
        help="OCR this image file instead of reading an image from the clipboard.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    load_env_file()
    load_env_file(".env.local")

    if args.image:
        content_data = str(args.image.expanduser().resolve())
        if not os.path.isfile(content_data):
            print(f"图片文件不存在: {content_data}")
            return 1
        if not is_image_file(content_data):
            print(f"文件不是有效图片: {content_data}")
            return 1
        print(f"正在读取图片文件: {content_data}")
        content_type = 'image'
    else:
        print("正在从剪切板读取内容...")

        # 检查剪切板内容
        content_type, content_data = check_clipboard_content()
    
    if content_type == 'text':
        print("剪切板中是文字内容，退出程序")
        return 0
    elif content_type == 'image':
        print("剪切板中是图片内容，开始 OCR 转换")
        
        # 执行 OCR 转换
        try:
            print(f"正在使用 {DEFAULT_MODEL} 进行 OCR 转换...")
            ocr_result = ocr_image(content_data)
            
            if not ocr_result or ocr_result.isspace():
                print("OCR 转换结果为空")
                # 清理临时图片文件
                cleanup_temp_image(content_data)
                return 1
            
            print("OCR 转换完成，将结果复制到剪切板")
            
            # 将 OCR 结果复制到剪切板
            pyperclip.copy(ocr_result)
            
            print("OCR 转换结果已复制到剪切板")
            print("转换结果预览：")
            print(ocr_result)
            
            # 清理临时图片文件
            cleanup_temp_image(content_data)
            
            return 0
            
        except Exception as e:
            print(f"OCR 转换失败: {str(e)}")
            # 清理临时图片文件
            cleanup_temp_image(content_data)
            return 1
    else:
        print("剪切板中不是图片或文字内容，退出程序")
        return 1


if __name__ == "__main__":
    sys.exit(main())
