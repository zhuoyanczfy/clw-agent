# -*- coding: utf-8 -*-
"""一次性脚本：从 server/dishes.py 生成 app/lib/data/dishes.dart"""
import re

src = open(r'd:\code\clw_agent\server\dishes.py', encoding='utf-8').read()
start = src.index('DISHES = [')
end = src.index('\n]', start) + 2
block = src[start:end]

entries = re.findall(
    r'\{\s*"id":\s*"([^"]+)",\s*"name":\s*"([^"]+)",\s*"category":\s*"([^"]+)",\s*"description":\s*"((?:[^"\\]|\\.)*)",\s*"recipe":\s*"((?:[^"\\]|\\.)*)",\s*"image_url":\s*"([^"]+)",?\s*\}',
    block,
    re.S,
)

lines = [
    "/// 内置美食库（与后端 server/dishes.py 保持一致，断网时按日期轮换使用）",
    "library;",
    "",
    "import '../models/dish.dart';",
    "",
    "const List<Dish> builtinDishes = [",
]
for eid, name, cat, desc, recipe, url in entries:
    lines.append("  Dish(")
    lines.append(f"    id: {eid!r},")
    lines.append(f"    name: {name!r},")
    lines.append(f"    category: {cat!r},")
    lines.append(f"    description: {desc!r},")
    lines.append(f"    recipe: {recipe!r},")
    lines.append(f"    imageUrl: {url!r},")
    lines.append("  ),")
lines.append("];")

out = '\n'.join(lines) + '\n'
with open(r'd:\code\clw_agent\app\lib\data\dishes.dart', 'w', encoding='utf-8') as f:
    f.write(out)
print('生成完成，共', len(entries), '道菜')
