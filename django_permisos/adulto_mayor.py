# =============================================================================
#  BENEFICIARIOS ADULTO MAYOR / DISCAPACIDAD
#  Agrega esto a tu proyecto Django:
#    - Model: en models.py  →  copia la clase AdultoMayor
#    - Serializer: en serializers.py  →  copia AdultoMayorSerializer
#    - ViewSet: en views.py  →  copia AdultoMayorViewSet
#    - URL: en urls.py  →  registra el router
#    - Admin: en admin.py  →  copia AdultoMayorAdmin
#  Luego: python manage.py makemigrations && python manage.py migrate
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# 1.  models.py  →  agregar esta clase
# ─────────────────────────────────────────────────────────────────────────────
from django.db import models


class AdultoMayor(models.Model):
    """
    Registro de beneficiarios de descuento en estacionamiento tarifado.
    Cédula ÚNICA → una persona, un vehículo.
    Placa ÚNICA  → un vehículo no puede pertenecer a dos beneficiarios.
    """

    TIPO_CHOICES = [
        ('AM', 'Adulto Mayor'),
        ('DC', 'Discapacitado'),
    ]

    tipo_beneficiario = models.CharField(
        max_length=2,
        choices=TIPO_CHOICES,
        default='AM',
        verbose_name='Tipo beneficiario',
    )

    # ── Persona ───────────────────────────────────────────────────────────
    propietario             = models.CharField(max_length=200, verbose_name='Nombre completo')
    cedula                  = models.CharField(max_length=20, unique=True, verbose_name='Cédula')
    numero_documento        = models.CharField(max_length=30, blank=True, default='')
    tipo_ident              = models.CharField(max_length=50, blank=True, default='')
    fecha_nacimiento        = models.CharField(max_length=20, blank=True, default='')
    correo                  = models.CharField(max_length=100, blank=True, default='')
    celular                 = models.CharField(max_length=20, blank=True, default='')
    direccion               = models.CharField(max_length=300, blank=True, default='')
    porcentaje_discapacidad = models.CharField(max_length=10, blank=True, default='')

    # ── Vehículo ──────────────────────────────────────────────────────────
    placa            = models.CharField(max_length=10, unique=True, verbose_name='Placa')
    marca            = models.CharField(max_length=60, blank=True, default='')
    modelo           = models.CharField(max_length=60, blank=True, default='')
    anio             = models.CharField(max_length=10, blank=True, default='')
    color            = models.CharField(max_length=40, blank=True, default='')
    cilindraje       = models.CharField(max_length=30, blank=True, default='')
    tonelaje         = models.CharField(max_length=20, blank=True, default='')
    tipo_servicio    = models.CharField(max_length=50, blank=True, default='')
    tipo_peso        = models.CharField(max_length=50, blank=True, default='')
    avaluo_comercial = models.CharField(max_length=50, blank=True, default='')
    inicio_pcir      = models.CharField(max_length=30, blank=True, default='')
    hasta_pcir       = models.CharField(max_length=30, blank=True, default='')

    # ── Control ───────────────────────────────────────────────────────────
    activo              = models.BooleanField(default=True)
    observaciones       = models.TextField(blank=True, default='')
    fecha_registro      = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['propietario']
        verbose_name = 'Beneficiario'
        verbose_name_plural = 'Beneficiarios'
        constraints = [
            models.UniqueConstraint(fields=['cedula'], name='unique_cedula_beneficiario'),
            models.UniqueConstraint(fields=['placa'],  name='unique_placa_beneficiario'),
        ]

    def __str__(self):
        return f'{self.propietario} / {self.placa} ({self.get_tipo_beneficiario_display()})'


# ─────────────────────────────────────────────────────────────────────────────
# 2.  serializers.py  →  agregar este serializer
# ─────────────────────────────────────────────────────────────────────────────
from rest_framework import serializers
# from .models import AdultoMayor   ← descomenta si está en archivo separado


class AdultoMayorSerializer(serializers.ModelSerializer):

    class Meta:
        model  = AdultoMayor
        fields = '__all__'
        read_only_fields = ['fecha_registro', 'fecha_actualizacion']

    def validate_cedula(self, value):
        value = value.strip()
        # En updates, excluir el propio registro
        instance = self.instance
        qs = AdultoMayor.objects.filter(cedula=value)
        if instance:
            qs = qs.exclude(pk=instance.pk)
        if qs.exists():
            raise serializers.ValidationError(
                'La cédula ya está registrada. El beneficio es para un vehículo por persona.'
            )
        return value

    def validate_placa(self, value):
        value = value.strip().upper()
        instance = self.instance
        qs = AdultoMayor.objects.filter(placa=value)
        if instance:
            qs = qs.exclude(pk=instance.pk)
        if qs.exists():
            raise serializers.ValidationError(
                'La placa ya se encuentra registrada en el sistema.'
            )
        return value


# ─────────────────────────────────────────────────────────────────────────────
# 3.  views.py  →  agregar este ViewSet
# ─────────────────────────────────────────────────────────────────────────────
from rest_framework import viewsets, permissions, status
from rest_framework.response import Response
# from .models import AdultoMayor
# from .serializers import AdultoMayorSerializer


class AdultoMayorViewSet(viewsets.ModelViewSet):
    """
    list    GET  /api/adulto-mayor/           → cualquier usuario autenticado con perm_beneficiarios
    create  POST /api/adulto-mayor/           → requiere perm_beneficiarios_escritura
    retrieve GET /api/adulto-mayor/{id}/
    update  PUT  /api/adulto-mayor/{id}/      → requiere perm_beneficiarios_escritura
    partial PUT  PATCH /api/adulto-mayor/{id}/
    destroy DELETE /api/adulto-mayor/{id}/    → solo superusuarios
    """

    queryset           = AdultoMayor.objects.all().order_by('propietario')
    serializer_class   = AdultoMayorSerializer
    permission_classes = [permissions.IsAuthenticated]

    def _tiene_perm_escritura(self, user):
        if user.is_superuser:
            return True
        try:
            return user.custom_permisos.perm_beneficiarios_escritura
        except Exception:
            return False

    def _tiene_perm_lectura(self, user):
        if user.is_superuser:
            return True
        try:
            return user.custom_permisos.perm_beneficiarios
        except Exception:
            return True  # por defecto True si no existe el registro

    def list(self, request, *args, **kwargs):
        if not self._tiene_perm_lectura(request.user):
            return Response({'error': 'Sin permiso para ver beneficiarios'}, status=403)
        return super().list(request, *args, **kwargs)

    def retrieve(self, request, *args, **kwargs):
        if not self._tiene_perm_lectura(request.user):
            return Response({'error': 'Sin permiso para ver beneficiarios'}, status=403)
        return super().retrieve(request, *args, **kwargs)

    def create(self, request, *args, **kwargs):
        if not self._tiene_perm_escritura(request.user):
            return Response(
                {'error': 'No tiene permiso para registrar beneficiarios'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return super().create(request, *args, **kwargs)

    def update(self, request, *args, **kwargs):
        if not self._tiene_perm_escritura(request.user):
            return Response(
                {'error': 'No tiene permiso para editar beneficiarios'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return super().update(request, *args, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        kwargs['partial'] = True
        return self.update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        if not request.user.is_superuser:
            return Response(
                {'error': 'Solo superusuarios pueden eliminar beneficiarios'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return super().destroy(request, *args, **kwargs)


# ─────────────────────────────────────────────────────────────────────────────
# 4.  urls.py  →  registrar en el router DRF
# ─────────────────────────────────────────────────────────────────────────────
#
# from rest_framework.routers import DefaultRouter
# from .views import AdultoMayorViewSet
#
# router = DefaultRouter()
# router.register(r'api/adulto-mayor', AdultoMayorViewSet, basename='adulto-mayor')
#
# urlpatterns = [
#     ...
#     path('', include(router.urls)),
# ]


# ─────────────────────────────────────────────────────────────────────────────
# 5.  admin.py  →  registro en el panel de administración
# ─────────────────────────────────────────────────────────────────────────────
#
# from django.contrib import admin
# from .models import AdultoMayor
#
# @admin.register(AdultoMayor)
# class AdultoMayorAdmin(admin.ModelAdmin):
#     list_display   = ('propietario', 'cedula', 'placa', 'tipo_beneficiario', 'activo', 'fecha_registro')
#     list_filter    = ('tipo_beneficiario', 'activo')
#     search_fields  = ('propietario', 'cedula', 'placa')
#     readonly_fields = ('fecha_registro', 'fecha_actualizacion')
#     list_editable  = ('activo',)


# ─────────────────────────────────────────────────────────────────────────────
# 6.  Migraciones
# ─────────────────────────────────────────────────────────────────────────────
#
#   python manage.py makemigrations
#   python manage.py migrate
