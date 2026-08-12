# -*- coding: utf-8 -*-
"""加载页图片上传工具（需 config.ini 配置 UPLOAD_TOKEN，请求头 X-Upload-Token）。

用法：
  python upload.py splash 图片.png "标题"
  python upload.py splash 图片.png --url http://127.0.0.1:8000
"""
import argparse
import configparser
import sys
from pathlib import Path

import requests

BASE = Path(__file__).resolve().parent  # shell/（config.ini 在上一级 backend/config/）


def load_token():
    parser = configparser.ConfigParser()
    parser.read_string(
        '[default]\n' + (BASE.parent / 'config' / 'config.ini').read_text(encoding='utf-8')
    )
    return parser.get('default', 'upload_token', fallback='').strip()


def main():
    arg = argparse.ArgumentParser(description='上传加载页图片')
    arg.add_argument('image', help='图片路径')
    arg.add_argument('title', nargs='?', help='标题（缺省用文件名）')
    arg.add_argument('--url', default='http://127.0.0.1:8000', help='后端地址（默认本机）')
    args = arg.parse_args()

    token = load_token()
    if not token:
        print('错误：config.ini 未配置 UPLOAD_TOKEN，无法使用 API 上传（仍可在 Django Admin 管理）')
        sys.exit(1)

    headers = {'X-Upload-Token': token}

    image = Path(args.image)
    if not image.is_file():
        print(f'错误：找不到图片 {image}')
        sys.exit(1)
    title = args.title or image.stem
    with image.open('rb') as f:
        resp = requests.post(
            f'{args.url}/api/splash/upload/',
            headers=headers,
            files={'image': (image.name, f)},
            data={'title': title},
            timeout=60,
        )

    if resp.status_code in (200, 201):
        print('上传成功:', resp.text)
    else:
        print(f'上传失败({resp.status_code}):', resp.text)
        sys.exit(1)


if __name__ == '__main__':
    main()
