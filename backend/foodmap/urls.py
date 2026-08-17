from django.urls import path

from . import views

app_name = 'foodmap'

urlpatterns = [
    # 健康检查与每日推荐
    path('api/health/', views.api_health, name='health'),
    path('api/dishes/', views.api_dishes, name='dishes'),
    path('api/dish/today/', views.api_dish_today, name='dish_today'),
    path('api/dish/<str:date>/', views.api_dish_by_date, name='dish_by_date'),
    # 美食收藏
    path('api/favorites/', views.api_favorites, name='favorites'),
    path('api/favorites/<str:slug>/', views.api_favorite_delete, name='favorite_delete'),
    # 区与餐厅
    path('api/districts/', views.api_districts, name='districts'),
    path('api/districts.geojson', views.api_districts_geojson, name='districts_geojson'),
    path('api/restaurants/', views.api_restaurants, name='restaurants'),
    path('api/restaurants/<int:restaurant_id>/', views.api_restaurant_detail, name='restaurant_detail'),
    # 用餐记录与照片
    path('api/records/', views.api_records, name='records'),
    path('api/records/<int:record_id>/', views.api_record_detail, name='record_detail'),
    path('api/records/<int:record_id>/photos/', views.api_photo_upload, name='photo_upload'),
    path('api/records/photos/<int:photo_id>/', views.api_photo_delete, name='photo_delete'),
    # 待尝清单
    path('api/wishlist/', views.api_wishlist, name='wishlist'),
    path('api/wishlist/<int:item_id>/eaten/', views.api_wishlist_eaten, name='wishlist_eaten'),
    path('api/wishlist/<int:item_id>/', views.api_wishlist_delete, name='wishlist_delete'),
    # 宠物名片
    path('api/pets/', views.api_pets, name='pets'),
    path('api/pets/<int:pet_id>/', views.api_pet_detail, name='pet_detail'),
    path('api/pets/<int:pet_id>/photos/', views.api_pet_photos, name='pet_photos'),
    path('api/pets/photos/<int:photo_id>/', views.api_pet_photo_delete, name='pet_photo_delete'),
    path('api/pets/<int:pet_id>/events/', views.api_pet_events, name='pet_events'),
    path('api/pets/events/<int:event_id>/', views.api_pet_event_delete, name='pet_event_delete'),
    # AI 智能推荐
    path('api/chat/sessions/', views.api_chat_sessions, name='chat_sessions'),
    path('api/chat/sessions/<int:session_id>/', views.api_chat_session_detail, name='chat_session_detail'),
    path('api/recommend/chat/', views.api_chat, name='recommend_chat'),
    path('api/recommend/verify/', views.api_recommend_verify, name='recommend_verify'),
    # APP 云端配置
    path('api/config/', views.api_config, name='config'),
    # 天气预报
    path('api/weather/', views.api_weather, name='weather'),
    # 加载页图片
    path('api/splash/', views.api_splash, name='splash'),
    path('api/splash/upload/', views.api_splash_upload, name='splash_upload'),
    # 每日占卜
    path('api/divination/today/', views.api_divination_today, name='divination_today'),
    # 好句好段
    path('api/quotes/today/', views.api_quote_today, name='quote_today'),
    path('api/quotes/history/', views.api_quote_history, name='quote_history'),
    path('api/quotes/random/', views.api_quote_random, name='quote_random'),
    # 每日菜单（HowToCook 菜谱池）
    path('api/meal/today/', views.api_meal_today, name='meal_today'),
    path('api/meal/history/', views.api_meal_history, name='meal_history'),
    path('api/meal/random/', views.api_meal_random, name='meal_random'),
]
