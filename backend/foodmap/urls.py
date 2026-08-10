from django.urls import path

from . import views

app_name = 'foodmap'

urlpatterns = [
    # 健康检查与每日推荐
    path('api/health/', views.api_health, name='health'),
    path('api/dishes/', views.api_dishes, name='dishes'),
    path('api/dish/today/', views.api_dish_today, name='dish_today'),
    path('api/dish/<str:date>/', views.api_dish_by_date, name='dish_by_date'),
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
    # AI 智能推荐
    path('api/recommend/chat/', views.api_chat, name='recommend_chat'),
    path('api/recommend/verify/', views.api_recommend_verify, name='recommend_verify'),
    # 加载页图片
    path('api/splash/', views.api_splash, name='splash'),
    path('api/splash/upload/', views.api_splash_upload, name='splash_upload'),
    # 故事书
    path('api/stories/', views.api_stories, name='stories'),
    path('api/stories/categories/', views.api_story_categories, name='story_categories'),
    path('api/stories/random/', views.api_story_random, name='story_random'),
    path('api/stories/<int:story_id>/', views.api_story_detail, name='story_detail'),
]
