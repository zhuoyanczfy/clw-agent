# -*- coding: utf-8 -*-
"""API Token 鉴权：只有持有正确 Token 的客户端才能访问 /api/ 接口。

Token 配置在 backend/config/config.ini 默认节的 API_TOKEN，APP 内置在
app/lib/config/app_config.dart 的 apiToken，两端保持一致即可。
"""
import configparser
import functools
import hmac

from django.http import JsonResponse


def _load_api_token():
    """从 config.ini 读取 API_TOKEN（每次调用实时读，改配置无需重启）。"""
    from config.settings import BASE_DIR
    parser = configparser.ConfigParser()
    parser.read_string(
        '[default]\n'
        + (BASE_DIR / 'config' / 'config.ini').read_text(encoding='utf-8')
    )
    return parser.get('default', 'api_token', fallback='').strip()


def _extract_token(request):
    """从请求头提取 Token，支持 X-Api-Token 或 Authorization: Bearer <token>。"""
    token = request.headers.get('X-Api-Token', '').strip()
    if token:
        return token
    auth = request.headers.get('Authorization', '').strip()
    if auth.startswith('Bearer '):
        return auth[7:].strip()
    return ''


def require_api_token(view_func):
    """API Token 鉴权装饰器：校验请求头中的 Token 与 config.ini 配置是否一致。

    未配置 API_TOKEN 时返回 503，提示先配置；配置后所有 /api/ 接口必须带 Token。
    """
    @functools.wraps(view_func)
    def wrapper(request, *args, **kwargs):
        expected = _load_api_token()
        if not expected:
            return JsonResponse(
                {'error': '后端未配置 API_TOKEN，请在 config/config.ini 中添加'},
                status=503,
            )
        provided = _extract_token(request)
        if not provided or not hmac.compare_digest(provided, expected):
            return JsonResponse({'error': '未授权：无效或缺失 API Token'}, status=401)
        return view_func(request, *args, **kwargs)
    return wrapper
