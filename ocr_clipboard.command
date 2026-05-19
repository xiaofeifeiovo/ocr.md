#!/usr/bin/env python3

import os
import sys
import base64
import tempfile
from PIL import ImageGrab, Image
import pyperclip


def load_env_file(path=".env"):
    if not os.path.exists(path):
        return

    with open(path, "r", encoding="utf-8") as env_file:
        for line in env_file:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


def check_clipboard_content():
    """
    检查剪切板内容
    返回: ('text', content) 或 ('image', image_path) 或 ('unknown', None)
    """
    # 首先检查是否有图像
    clipboard_image = ImageGrab.grabclipboard()
    
    if clipboard_image is not None:
        # 剪切板中有图像
        # 创建临时文件保存图像
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_file:
            clipboard_image.save(temp_file.name, 'PNG')
            return 'image', temp_file.name
    
    # 检查是否有文本内容
    try:
        text_content = pyperclip.paste()
        if text_content and isinstance(text_content, str) and not text_content.isspace():
            # 检查是否为文件路径
            if os.path.isfile(text_content):
                try:
                    Image.open(text_content)
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
    """使用 qwen3-vl 对图片进行 OCR 转换"""
    from openai import OpenAI

    api_key = os.getenv("DASHSCOPE_API_KEY")
    if not api_key:
        raise RuntimeError("Missing API key. Set DASHSCOPE_API_KEY before running OCR.")
    
    # 初始化OpenAI客户端
    client = OpenAI(
        api_key=api_key,
        base_url="https://dashscope.aliyuncs.com/compatible-mode/v1"
    )

    # 将图片转换为 base64 编码
    base64_image = image_to_base64(image_path)
    image_url = f"data:image/png;base64,{base64_image}"

    # 创建聊天完成请求
    completion = client.chat.completions.create(
        model="qwen3-vl-flash",
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": image_url
                        },
                    },
                    {"type": "text", "text": "请将图片中的内容转化为 markdown 格式，只输出 markdown 文本"},
                ],
            },
        ],
        stream=False,  # 关闭流式输出
        temperature=0.1,  # 设置较低的温度
        extra_body={
            'enable_thinking': False  # 关闭思考参数
        }
    )

    # 返回 OCR 结果
    return completion.choices[0].message.content


def main():
    load_env_file()
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
            print("正在使用 qwen3-vl 进行 OCR 转换...")
            ocr_result = ocr_image(content_data)
            
            if not ocr_result or ocr_result.isspace():
                print("OCR 转换结果为空")
                # 清理临时图片文件
                if content_data != sys.argv[0] and os.path.exists(content_data):
                    os.remove(content_data)
                return 1
            
            print("OCR 转换完成，将结果复制到剪切板")
            
            # 将 OCR 结果复制到剪切板
            pyperclip.copy(ocr_result)
            
            print("OCR 转换结果已复制到剪切板")
            print("转换结果预览：")
            print(ocr_result)
            
            # 清理临时图片文件
            if content_data != sys.argv[0] and os.path.exists(content_data):
                os.remove(content_data)
            
            return 0
            
        except Exception as e:
            print(f"OCR 转换失败: {str(e)}")
            # 清理临时图片文件
            if content_data != sys.argv[0] and content_data and os.path.exists(content_data):
                os.remove(content_data)
            return 1
    else:
        print("剪切板中不是图片或文字内容，退出程序")
        return 1


if __name__ == "__main__":
    sys.exit(main())
