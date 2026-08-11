# -*- coding: utf-8 -*-
"""加载页图片批量处理 + 上传工具（保持原始构图，不裁切）。

处理：图片等比缩放到指定宽度（默认 1080，手机屏幕宽度级别）+ jpg 压缩
      —— 只减小体积、不改变构图；尺寸比例差异由 APP 的 BoxFit.cover 自然适配。
上传：--upload 时逐张上传到后端（需 config.ini 配置 UPLOAD_TOKEN）。

用法：
  python shell/process_splash.py 图片目录              # 只处理，输出到 <目录>/processed/
  python shell/process_splash.py 图片目录 --upload     # 处理并上传到云服务器
  python shell/process_splash.py 图片目录 --width 720  # 更小体积（微信图 720 宽够用）
"""
import argparse
import configparser
import sys
from pathlib import Path

from PIL import Image

BASE = Path(__file__).resolve().parent  # shell/（config.ini 在上一级 backend/config/）

EXTS = ('.jpg', '.jpeg', '.png', '.webp', '.bmp')


def load_token():
    parser = configparser.ConfigParser()
    parser.read_string(
        '[default]\n' + (BASE.parent / 'config' / 'config.ini').read_text(encoding='utf-8')
    )
    return parser.get('default', 'upload_token', fallback='').strip()


def process(inbox: Path, width: int) -> list:
    """等比缩放 + jpg 压缩，输出到 inbox/processed/，返回 (源文件, 处理结果) 列表"""
    out_dir = inbox / 'processed'
    out_dir.mkdir(exist_ok=True)
    results = []
    files = sorted(p for p in inbox.iterdir() if p.suffix.lower() in EXTS)
    for i, src in enumerate(files, 1):
        img = Image.open(src)
        img = img.convert('RGB')
        if img.width > width:
            h = round(img.height * width / img.width)
            img = img.resize((width, h), Image.LANCZOS)
        dst = out_dir / f'splash_{i:02d}.jpg'
        img.save(dst, 'JPEG', quality=85, optimize=True)
        results.append((src, dst))
    return results


def main():
    arg = argparse.ArgumentParser(description='加载页图片批量处理/上传')
    arg.add_argument('dir', help='图片目录（处理结果输出到 <目录>/processed/）')
    arg.add_argument('--width', type=int, default=1080, help='缩放宽度（默认 1080）')
    arg.add_argument('--upload', action='store_true', help='处理完成后上传到后端')
    arg.add_argument('--url', default='http://139.196.27.224', help='后端地址（默认云服务器）')
    args = arg.parse_args()

    inbox = Path(args.dir)
    if not inbox.is_dir():
        print(f'错误：目录不存在 {inbox}')
        sys.exit(1)

    results = process(inbox, args.width)
    if not results:
        print(f'{inbox} 下没有图片文件（支持 {", ".join(EXTS)}）')
        sys.exit(1)

    print(f'处理完成 {len(results)} 张 → {inbox / "processed"}：')
    for src, dst in results:
        src_mb = src.stat().st_size / 1024 / 1024
        dst_mb = dst.stat().st_size / 1024 / 1024
        print(f'  {src.name}: {src_mb:.2f}MB → {dst_mb:.2f}MB（{dst.name}）')
    if not args.upload:
        print('\n完成（未上传，加 --upload 上传到云服务器）')
        return

    import requests
    token = load_token()
    if not token:
        print('错误：config.ini 未配置 UPLOAD_TOKEN，无法上传（仍可处理图片）')
        sys.exit(1)
    headers = {'X-Upload-Token': token}
    ok = fail = 0
    for i, (src, dst) in enumerate(results, 1):
        try:
            with dst.open('rb') as f:
                resp = requests.post(
                    f'{args.url}/api/splash/upload/',
                    headers=headers,
                    files={'image': (f'splash_{i:02d}.jpg', f)},
                    data={'title': f'加载页 {i:02d}'},
                    timeout=120,
                )
            if resp.status_code in (200, 201):
                ok += 1
                print(f'  [OK] {dst.name} -> {args.url}')
            else:
                fail += 1
                print(f'  [FAIL] {dst.name} ({resp.status_code}): {resp.text[:120]}')
        except Exception as e:
            fail += 1
            print(f'  [FAIL] {dst.name} (异常): {e}')
    print(f'\n上传完成：成功 {ok} 张，失败 {fail} 张')


if __name__ == '__main__':
    main()
