# -*- coding: utf-8 -*-
"""菜谱池：从 meal_pool.json（HowToCook 开源菜谱）加载并随机抽取。

meal_pool.json 由 tmp/howtocook_refetch.py 生成，字段：
{name, category, image(相对路径), description, ingredients[], steps[]}
"""
import json
import random
from pathlib import Path

POOL_FILE = Path(__file__).resolve().parent.parent / 'data' / 'meal_pool.json'

_pool = None


def load_pool():
    """懒加载菜谱池（进程内缓存）。"""
    global _pool
    if _pool is None:
        try:
            with open(POOL_FILE, encoding='utf-8') as f:
                _pool = json.load(f)
        except (FileNotFoundError, ValueError):
            _pool = []
    return _pool


def pool_size():
    return len(load_pool())


def random_meal():
    """随机抽一道菜，池子为空返回 None。"""
    pool = load_pool()
    if not pool:
        return None
    return random.choice(pool)
