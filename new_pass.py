from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.http import JsonResponse

def change_password(request):
    username = request.GET.get("username")
    password = request.GET.get("password")
    new_pass = request.GET.get("new_pass")

    if password:  # cambio normal
        user = authenticate(username=username, password=password)
    else:  # reset sin contraseña
        try:
            user = User.objects.get(username=username)
        except User.DoesNotExist:
            user = None

    if user:
        user.set_password(new_pass)
        user.save()
        return JsonResponse({"status": "ok"})

    return JsonResponse({"status": "error"})