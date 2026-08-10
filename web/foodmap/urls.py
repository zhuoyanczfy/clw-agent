from django.urls import path

from . import views

app_name = 'foodmap'

urlpatterns = [
    path('', views.index, name='index'),
    path('api/districts.geojson', views.districts_geojson, name='districts_geojson'),
    path('district/<int:district_id>/', views.district_detail, name='district_detail'),
    path('districts/', views.district_list, name='district_list'),
    path('restaurant/<int:restaurant_id>/', views.restaurant_detail, name='restaurant_detail'),
    path('record/new/', views.record_form, name='record_new'),
    path('record/<int:record_id>/', views.record_detail, name='record_detail'),
    path('record/<int:record_id>/edit/', views.record_form, name='record_edit'),
    path('record/<int:record_id>/delete/', views.record_delete, name='record_delete'),
    path('record/photo/<int:photo_id>/delete/', views.photo_delete, name='photo_delete'),
    # AI 智能推荐
    path('recommend/', views.recommend, name='recommend'),
    path('api/recommend/chat', views.chat, name='recommend_chat'),
    path('api/recommend/wishlist', views.wishlist_add, name='wishlist_add'),
    path('api/recommend/verify', views.recommend_verify, name='recommend_verify'),
    path('api/recommend/wishlist/<int:item_id>/eaten', views.wishlist_eaten, name='wishlist_eaten'),
    path('api/recommend/wishlist/<int:item_id>/delete', views.wishlist_delete, name='wishlist_delete'),
]
