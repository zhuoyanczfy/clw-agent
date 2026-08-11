# -*- coding: utf-8 -*-
"""故事书批量导入工具：把一个目录下的小小说/故事批量上传到后端（需 UPLOAD_TOKEN）。

文件约定：每个 .txt / .md 文件 = 一篇故事。
- 文件名（去扩展名）作为标题，如「一碗阳春面.md」
- 文件头部可选元信息（每行「键：值」，以 --- 结束），可覆盖文件名标题：

    标题：一碗阳春面
    分类：小小说
    来源：网络公版故事
    ---
    正文从这里开始……

用法：
  python shell/import_stories.py                    # 默认导入 shell/stories_inbox/
  python shell/import_stories.py 我的故事目录 --category 小小说 --source 佚名
  python shell/import_stories.py --dry-run          # 只预览，不真正上传
  python shell/import_stories.py --url http://139.196.27.224
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


def parse_file(path):
    """解析单篇故事：返回 (title, category, source, content)"""
    text = path.read_text(encoding='utf-8')
    title, category, source = path.stem, '', ''
    # 支持头部「键：值」元信息（以 --- 单独一行结束）
    lines = text.splitlines(keepends=True)
    meta_end = 0
    for i, line in enumerate(lines[:10]):
        if line.strip() == '---':
            meta_end = i
            break
        if '：' in line and i < 6:
            k, v = line.strip().split('：', 1)
            if k == '标题':
                title = v.strip()
            elif k == '分类':
                category = v.strip()
            elif k == '来源':
                source = v.strip()
    if meta_end:
        lines = lines[meta_end + 1:]
    content = ''.join(lines).strip()
    if not content:
        return None
    return title, category, source, content


def main():
    arg = argparse.ArgumentParser(description='批量导入故事书')
    arg.add_argument('dir', nargs='?', default=str(BASE / 'stories_inbox'),
                     help='故事目录（默认 shell/stories_inbox/）')
    arg.add_argument('--category', default='小小说', help='默认分类（文件头可单独覆盖）')
    arg.add_argument('--source', default='', help='默认来源/作者（文件头可单独覆盖）')
    arg.add_argument('--url', default='http://139.196.27.224', help='后端地址（默认云服务器）')
    arg.add_argument('--dry-run', action='store_true', help='只预览不上传')
    args = arg.parse_args()

    inbox = Path(args.dir)
    if not inbox.is_dir():
        print(f'错误：目录不存在 {inbox}')
        sys.exit(1)
    files = sorted(inbox.glob('*.txt')) + sorted(inbox.glob('*.md'))
    if not files:
        print(f'{inbox} 下没有 .txt / .md 文件，把每篇小小说存成一个文件放进去即可')
        sys.exit(1)

    stories = []
    for f in files:
        parsed = parse_file(f)
        if parsed:
            title, category, source, content = parsed
            stories.append({
                'title': title,
                'category': category or args.category,
                'source': source or args.source,
                'content': content,
            })

    print(f'共 {len(stories)} 篇：')
    for s in stories:
        print(f'  [{s["category"]}] {s["title"]}（{len(s["content"])} 字，来源：{s["source"] or "-"}）')
    if not stories:
        print('没有解析到有效故事')
        sys.exit(1)
    if args.dry_run:
        print('\n[dry-run] 预览完成，未上传')
        return

    token = load_token()
    if not token:
        print('错误：config.ini 未配置 UPLOAD_TOKEN，无法使用 API 上传（仍可在 Django Admin 管理）')
        sys.exit(1)

    headers = {'X-Upload-Token': token}
    ok = fail = 0
    for s in stories:
        try:
            resp = requests.post(
                f'{args.url}/api/stories/',
                headers=headers,
                data={k: s[k] for k in ('title', 'content', 'category', 'source')},
                timeout=60,
            )
            if resp.status_code in (200, 201):
                ok += 1
                print(f'  ✓ {s["title"]}')
            else:
                fail += 1
                print(f'  ✗ {s["title"]}（{resp.status_code}）: {resp.text[:120]}')
        except Exception as e:
            fail += 1
            print(f'  ✗ {s["title"]}（异常）: {e}')
    print(f'\n完成：成功 {ok} 篇，失败 {fail} 篇 → {args.url}')


if __name__ == '__main__':
    main()
