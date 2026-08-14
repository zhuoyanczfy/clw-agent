"""高德天气客户端（Web 服务 API 天气查询）。

配置从项目根目录 config/config.ini 读取（裸键值对格式）：
    WEATHER_ADCODE=320100   # 可选，天气查询城市编码，缺省南京

数据源：https://restapi.amap.com/v3/weather/weatherInfo
    extensions=base  -> 实况天气（lives，每小时更新多次）
    extensions=all   -> 预报天气（forecasts.casts，含当天+未来 3 天，每天 8/11/18 点更新）

为控制高德调用配额，做进程内缓存：实况 30 分钟、预报 3 小时。
"""

import time

import requests

from .amap import AMAP_BASE_URL, AMAPError, _api_key, _read_config

DEFAULT_ADCODE = '320100'  # 南京
LIVE_TTL = 30 * 60        # 实况缓存 30 分钟
FORECAST_TTL = 3 * 3600   # 预报缓存 3 小时

# 进程内缓存：{kind: (timestamp, data)}；gunicorn 各 worker 独立缓存，
# 命中率略降但调用量仍远低于配额（每 worker 每天至多几十次）。
_cache = {}


def _adcode():
    cfg = _read_config()
    code = cfg.get('WEATHER_ADCODE', '').strip()
    return code or DEFAULT_ADCODE


def _cached(kind, ttl):
    entry = _cache.get(kind)
    if entry and time.time() - entry[0] < ttl:
        return entry[1]
    return None


def _request_weather(extensions):
    """调高德天气接口，带重试；成功返回 JSON，失败抛 AMAPError。"""
    params = {
        'key': _api_key(),
        'city': _adcode(),
        'extensions': extensions,
    }
    for attempt in range(3):
        try:
            resp = requests.get(
                f'{AMAP_BASE_URL}/v3/weather/weatherInfo',
                params=params,
                timeout=15,
            )
            data = resp.json()
        except (requests.RequestException, ValueError) as exc:
            if attempt == 2:
                raise AMAPError(f'请求高德天气 API 失败: {exc}') from exc
            time.sleep(1.5)
            continue
        if data.get('status') != '1':
            raise AMAPError(
                f"高德天气 API 错误: {data.get('info')} (infocode={data.get('infocode')})"
            )
        return data
    raise AMAPError('高德天气 API 请求重试失败')


def get_weather():
    """返回 {'live': {...实况}, 'forecasts': [...4 天预报]}，带进程内缓存。"""
    result = {}
    live = _cached('live', LIVE_TTL)
    if live is None:
        data = _request_weather('base')
        live = (data.get('lives') or [{}])[0]
        _cache['live'] = (time.time(), live)
    result['live'] = live

    forecasts = _cached('forecast', FORECAST_TTL)
    if forecasts is None:
        data = _request_weather('all')
        forecasts = ((data.get('forecasts') or [{}])[0]).get('casts') or []
        _cache['forecast'] = (time.time(), forecasts)
    result['forecasts'] = forecasts
    return result
