# ─────────────────────────────────────────────────────────────────────────────
# Añade esto a tu models.py de Django
# ─────────────────────────────────────────────────────────────────────────────
from django.db import models
from django.contrib.auth.models import User


class UserPermisos(models.Model):
    """
    Permisos por módulo para cada usuario (no superusuarios).
    Se crea automáticamente con todos los permisos en True cuando no existe.
    """
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='custom_permisos',
    )
    perm_vehiculos              = models.BooleanField(default=True)
    perm_tarjetas               = models.BooleanField(default=True)
    perm_multas                 = models.BooleanField(default=True)
    perm_notificaciones         = models.BooleanField(default=True)
    perm_mis_notificaciones     = models.BooleanField(default=True)
    perm_beneficiarios          = models.BooleanField(default=True)
    perm_beneficiarios_escritura = models.BooleanField(default=False)  # Registro/edición de beneficiarios
    perm_credencial             = models.BooleanField(default=True)

    def to_dict(self):
        return {
            'perm_vehiculos':               self.perm_vehiculos,
            'perm_tarjetas':                self.perm_tarjetas,
            'perm_multas':                  self.perm_multas,
            'perm_notificaciones':          self.perm_notificaciones,
            'perm_mis_notificaciones':      self.perm_mis_notificaciones,
            'perm_beneficiarios':           self.perm_beneficiarios,
            'perm_beneficiarios_escritura': self.perm_beneficiarios_escritura,
            'perm_credencial':              self.perm_credencial,
        }

    class Meta:
        verbose_name = 'Permisos de usuario'
        verbose_name_plural = 'Permisos de usuarios'
