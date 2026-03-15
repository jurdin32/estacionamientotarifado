# ─────────────────────────────────────────────────────────────────────────────
# Añade en tu urls.py principal (o en el urls.py de tu app)
# ─────────────────────────────────────────────────────────────────────────────
from django.urls import path
from .views_permisos import PermisosUsuarioView   # ajusta el import según tu app

urlpatterns = [
    # ... tus URLs existentes ...

    # Permisos por usuario
    path(
        'api/permisos-usuario/<int:user_id>/',
        PermisosUsuarioView.as_view(),
        name='permisos-usuario',
    ),
]

# ─────────────────────────────────────────────────────────────────────────────
# Después registra el modelo en admin.py para gestionarlo desde el panel:
# ─────────────────────────────────────────────────────────────────────────────
#
# from django.contrib import admin
# from .models import UserPermisos
#
# @admin.register(UserPermisos)
# class UserPermisosAdmin(admin.ModelAdmin):
#     list_display  = ('user', 'perm_vehiculos', 'perm_tarjetas', 'perm_multas',
#                      'perm_notificaciones', 'perm_beneficiarios', 'perm_beneficiarios_escritura',
#                      'perm_credencial')
#     list_editable = ('perm_vehiculos', 'perm_tarjetas', 'perm_multas',
#                      'perm_notificaciones', 'perm_beneficiarios', 'perm_beneficiarios_escritura',
#                      'perm_credencial')
#
# ─────────────────────────────────────────────────────────────────────────────
# Migraciones (ejecutar en el servidor Django):
# ─────────────────────────────────────────────────────────────────────────────
#
#   python manage.py makemigrations
#   python manage.py migrate
