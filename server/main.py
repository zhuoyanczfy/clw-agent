# -*- coding: utf-8 -*-
"""专属美食关怀 APP 后端服务
提供每日美食推荐 API，供 Flutter APP 拉取今日推荐内容。
运行方式: uvicorn main:app --host 0.0.0.0 --port 8000
"""
import datetime

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from dishes import DISHES, dish_for_date

app = FastAPI(
    title="专属美食关怀 API",
    description="每日美食推荐服务",
    version="1.0.0",
)

# 允许所有来源（APP 端请求无跨域限制，本地调试方便）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {"message": "专属美食关怀 API 运行中", "docs": "/docs"}


@app.get("/api/dishes")
def list_dishes():
    """返回全部美食库"""
    return {"total": len(DISHES), "dishes": DISHES}


@app.get("/api/dish/today")
def today_dish():
    """返回今日推荐"""
    today = datetime.date.today().isoformat()
    dish = dish_for_date(today)
    return {"date": today, "dish": dish}


@app.get("/api/dish/{date}")
def dish_by_date(date: str):
    """返回指定日期的推荐（date 形如 2026-08-07）"""
    try:
        datetime.date.fromisoformat(date)
    except ValueError:
        return JSONResponse(status_code=400, content={"error": "日期格式错误，应为 YYYY-MM-DD"})
    return {"date": date, "dish": dish_for_date(date)}
