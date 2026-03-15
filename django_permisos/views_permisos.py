import json
from django.http import JsonResponse
from django.views import View
from django.contrib.auth.models import User
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

# Ajusta el import según la app donde esté tu modelo
from .models import UserPermisos


CAMPOS_PERM = [
    'perm_vehiculos',
    'perm_tarjetas',
    'perm_multas',
    'perm_notificaciones',
    'perm_mis_notificaciones',
    'perm_beneficiarios',
    'perm_beneficiarios_escritura',
    'perm_credencial',
]


def _get_user_from_request(request):
    """
    Extrae el usuario autenticado desde:
      1. Query param ?_tk=TOKEN  (workaround Apache que elimina Authorization)
      2. Header Authorization: Token TOKEN
    """
    token_str = (
        request.GET.get('_tk')
        or request.META.get('HTTP_AUTHORIZATION', '').replace('Token ', '').strip()
    )
    if not token_str:
        return None
    try:
        from rest_framework.authtoken.models import Token
        token = Token.objects.select_related('user').get(key=token_str)
        return token.user
    except Exception:
        return None


@method_decorator(csrf_exempt, name='dispatch')
class PermisosUsuarioView(View):
    """
    GET  /api/permisos-usuario/<user_id>/
        → Devuelve los permisos del usuario.
        → Requiere ser superusuario O ser el mismo usuario.

    PATCH /api/permisos-usuario/<user_id>/
        → Actualiza los permisos. Solo superusuarios pueden hacerlo.
        → Body JSON: { "perm_vehiculos": false, "perm_tarjetas": true, ... }
    """

    def get(self, request, user_id):
        requester = _get_user_from_request(request)
        if requester is None:
            return JsonResponse({'error': 'No autenticado'}, status=401)

        # Solo el propio usuario o un superusuario puede ver los permisos
        if not requester.is_superuser and requester.id != int(user_id):
            return JsonResponse({'error': 'No autorizado'}, status=403)

        try:
            target = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return JsonResponse({'error': 'Usuario no encontrado'}, status=404)

        # Superusuarios siempre tienen todo
        if target.is_superuser:
            return JsonResponse({campo: True for campo in CAMPOS_PERM})

        permisos, _ = UserPermisos.objects.get_or_create(user=target)
        return JsonResponse(permisos.to_dict())

    def patch(self, request, user_id):
        requester = _get_user_from_request(request)
        if requester is None:
            return JsonResponse({'error': 'No autenticado'}, status=401)
        if not requester.is_superuser:
            return JsonResponse(
                {'error': 'Solo superusuarios pueden modificar permisos'},
                status=403,
            )

        try:
            target = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return JsonResponse({'error': 'Usuario no encontrado'}, status=404)

        try:
            data = json.loads(request.body)
        except Exception:
            return JsonResponse({'error': 'JSON inválido'}, status=400)

        permisos, _ = UserPermisos.objects.get_or_create(user=target)
        for campo in CAMPOS_PERM:
            if campo in data:
                setattr(permisos, campo, bool(data[campo]))
        permisos.save()
        return JsonResponse(permisos.to_dict())
