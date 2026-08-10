from django import forms

from .models import DiningRecord, District, Restaurant


class DiningRecordForm(forms.ModelForm):
    """用餐记录表单：支持选择已有餐厅或新建餐厅。"""

    district = forms.ModelChoiceField(
        queryset=District.objects.all(), required=False, label='所属区',
        empty_label='请选择区',
    )
    new_name = forms.CharField(max_length=100, required=False, label='新餐厅名称')
    new_address = forms.CharField(max_length=200, required=False, label='新餐厅地址')

    class Meta:
        model = DiningRecord
        fields = ['restaurant', 'date', 'rating', 'per_capita', 'mood', 'comment']
        widgets = {
            'date': forms.DateInput(attrs={'type': 'date'}),
            'comment': forms.Textarea(attrs={'rows': 4, 'placeholder': '写下那顿饭的味道、陪伴的人和当时的感受…'}),
            'per_capita': forms.NumberInput(attrs={'min': 0, 'placeholder': '选填'}),
            'mood': forms.TextInput(attrs={'placeholder': '例如：满足、惊喜、怀旧…'}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['restaurant'].queryset = Restaurant.objects.select_related('district').all()
        self.fields['restaurant'].empty_label = '—— 新建餐厅 ——'
        self.fields['restaurant'].label = '餐厅'
        # 与"新建餐厅"二选一，由 clean() 统一校验
        self.fields['restaurant'].required = False

    def clean(self):
        cleaned = super().clean()
        restaurant = cleaned.get('restaurant')
        new_name = (cleaned.get('new_name') or '').strip()
        district = cleaned.get('district')

        if not restaurant and not new_name:
            raise forms.ValidationError('请选择已有餐厅，或填写新餐厅名称')
        if new_name and not district:
            raise forms.ValidationError('新建餐厅需要选择所属区')

        if new_name:
            cleaned['restaurant'] = Restaurant.objects.get_or_create(
                name=new_name, district=district,
                defaults={'address': (cleaned.get('new_address') or '').strip()},
            )[0]
        return cleaned
