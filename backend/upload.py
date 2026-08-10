# -*- coding: utf-8 -*-
"""内容上传工具：加载页图片 / 故事书（需 config.ini 配置 UPLOAD_TOKEN，请求头 X-Upload-Token）。

用法：
  python upload.py splash 图片.png "标题"
  python upload.py story "标题" 正文.txt --category 历史故事 --cover 封面.jpg --source 出处
  python upload.py story "标题" "直接写正文内容" --category 历史故事
  python upload.py story 正文.md --title "标题" --category 历史故事
  python upload.py splash 图片.png --url http://127.0.0.1:8000
"""
import argparse
import configparser
import sys
from pathlib import Path

import requests

BASE = Path(__file__).resolve().parent


def load_token():
    parser = configparser.ConfigParser()
    parser.read_string(
        '[default]\n' + (BASE / 'config' / 'config.ini').read_text(encoding='utf-8')
    )
    return parser.get('default', 'upload_token', fallback='').strip()


def main():
    arg = argparse.ArgumentParser(description='上传加载页图片或故事')
    arg.add_argument('kind', choices=['splash', 'story'], help='splash=加载页图片, story=故事')
    arg.add_argument('first', help='splash: 图片路径；story: 标题或正文文件路径')
    arg.add_argument('second', nargs='?', help='splash: 标题；story: 正文（文件路径或文本，缺省时从 first 读取）')
    arg.add_argument('--title', help='story: 标题（first 为正文文件时必填）')
    arg.add_argument('--category', default='历史故事', help='story: 分类（默认 历史故事）')
    arg.add_argument('--cover', help='story: 封面图片路径（可选）')
    arg.add_argument('--source', default='', help='story: 来源/出处（可选）')
    arg.add_argument('--url', default='http://127.0.0.1:8000', help='后端地址（默认本机）')
    args = arg.parse_args()

    token = load_token()
    if not token:
        print('错误：config.ini 未配置 UPLOAD_TOKEN，无法使用 API 上传（仍可在 Django Admin 管理）')
        sys.exit(1)

    headers = {'X-Upload-Token': token}

    if args.kind == 'splash':
        image = Path(args.first)
        if not image.is_file():
            print(f'错误：找不到图片 {image}')
            sys.exit(1)
        title = args.second or image.stem
        with image.open('rb') as f:
            resp = requests.post(
                f'{args.url}/api/splash/upload/',
                headers=headers,
                files={'image': (image.name, f)},
                data={'title': title},
                timeout=60,
            )
    else:
        # 故事：标题 + 正文（second 为文件路径时读文件，否则当正文文本）
        title = args.title or args.first
        if args.second:
            body = args.second
            body_path = Path(body)
            if body_path.is_file():
                body = body_path.read_text(encoding='utf-8')
        else:
            body_path = Path(args.first)
            if not body_path.is_file():
                print('错误：请提供正文（文本或文件路径），或用 --title + 正文文件')
                sys.exit(1)
            body = body_path.read_text(encoding='utf-8')
        data = {
            'title': title,
            'content': body,
            'category': args.category,
            'source': args.source,
        }
        files = {}
        if args.cover:
            cover = Path(args.cover)
            if not cover.is_file():
                print(f'错误：找不到封面 {cover}')
                sys.exit(1)
            files['cover'] = (cover.name, cover.open('rb'))
        resp = requests.post(
            f'{args.url}/api/stories/',
            headers=headers,
            data=data,
            files=files or None,
            timeout=60,
        )
        if files:
            for f in files.values():
                f[1].close()

    if resp.status_code in (200, 201):
        print('上传成功:', resp.text)
    else:
        print(f'上传失败({resp.status_code}):', resp.text)
        sys.exit(1)


if __name__ == '__main__':
    main()
