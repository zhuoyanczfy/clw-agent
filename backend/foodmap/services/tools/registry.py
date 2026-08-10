"""工具注册表：工具名 -> 实现函数。

Agent 的 function calling 通过工具名引用实现，新增工具只需在此登记一行，
并补充 tools_schema() 中的 OpenAI 格式定义。
"""
from foodmap.services.tools.restaurant_tools import search_restaurants

# 工具名 -> 工具函数
TOOL_REGISTRY = {
    "search_restaurants": search_restaurants,
}


def tools_schema():
    """返回 OpenAI 兼容的 tools 参数（供第一轮 function calling 请求）。"""
    return [
        {
            "type": "function",
            "function": {
                "name": "search_restaurants",
                "description": (
                    "搜索本地真实餐厅库（南京 25817 家，数据来自高德，含名称/区属/地址/评分）。"
                    "推荐餐厅前必须先调用本工具，只从查询结果中挑选推荐。"
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "keyword": {
                            "type": "string",
                            "description": "餐厅名关键词，如「鸭血粉丝」「小龙虾」",
                        },
                        "district": {
                            "type": "string",
                            "description": "区名（可选），如「鼓楼区」",
                        },
                    },
                    "required": ["keyword"],
                },
            },
        }
    ]


def resolve_tool(name):
    """按工具名返回实现函数；未知工具返回 None。"""
    return TOOL_REGISTRY.get(name)
