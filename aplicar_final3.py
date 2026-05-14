#!/usr/bin/env python3
"""Aplica cambios D, E y metodos B/C/F con strings multilinea correctos."""
SQ = chr(39)
FILE = r"c:\Users\Johnny Urdin\Desktop\Tarifado\lib\tarjetas\views\EstacionamientoScreen.dart"

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

original = content

# CAMBIO D: _liberarEstacionamientoExpirado - modal en catch
old_d = f"""      }} catch (e) {{
        debugPrint({SQ}[ADVERTENCIA]  Error al liberar en servidor: $e{SQ});
      }}"""
new_d = f"""      }} catch (e) {{
        debugPrint({SQ}[ADVERTENCIA]  Error al liberar en servidor: $e{SQ});
        _mostrarErrorModal(_mensajeErrorLiberacion(e));
      }}"""
content = content.replace(old_d, new_d)
print(f"Cambio D: {content.count(new_d)} ocurrencias")

# CAMBIO E: Error en registro - modal
old_e = f"""                                            _showCustomSnackBar(
                                              {SQ}[X]  Error al sincronizar con el servidor: $e{SQ},
                                              isError: true,
                                            );"""
new_e = f"""                                            _mostrarErrorModal(_mensajeErrorRegistro(e));"""
content = content.replace(old_e, new_e)
print(f"Cambio E: {content.count(new_e)} ocurrencias")

# CAMBIOS B/C/F: Insertar metodos
old_m = f"\n  void _cambiarFiltroTab(int index) {{"

# Los strings multilinea deben usar \n literal en el archivo Dart
NL = "\\n"  # Esto escribe \n literal en el archivo Dart

new_m = f"""

  void _mostrarErrorModal(String mensaje) {{
    if (!mounted || _appEnSegundoPlano) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFD32F2F), size: 24),
            const SizedBox(width: 10),
            const Text({SQ}Error{SQ}, style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(mensaje, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text({SQ}Cerrar{SQ}, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }}

  String _mensajeErrorLiberacion(dynamic error) {{
    final msg = error.toString();
    if (msg.contains({SQ}SocketException{SQ}) ||
        msg.contains({SQ}HandshakeException{SQ}) ||
        msg.contains({SQ}TimeoutException{SQ}) ||
        msg.contains({SQ}sin conexión{SQ})) {{
      return {SQ}No se pudo conectar con el servidor para liberar el estacionamiento.{NL}{NL}{SQ}
          {SQ}El estacionamiento ya fue liberado localmente. {SQ}
          {SQ}Los cambios se sincronizar{NL}automáticamente cuando la conexión se restablezca.{SQ};
    }}
    if (msg.contains({SQ}409{SQ}) || msg.contains({SQ}Conflict{SQ})) {{
      return {SQ}El estacionamiento ya fue liberado por otro usuario.{NL}{NL}{SQ}
          {SQ}No es necesario realizar ninguna acción adicional.{SQ};
    }}
    if (msg.contains({SQ}401{SQ}) || msg.contains({SQ}No autorizado{SQ})) {{
      return {SQ}Su sesión ha expirado. Por favor, cierre sesión y vuelva a iniciarla.{SQ};
    }}
    final msgCorto = msg.length > 200 ? msg.substring(0, 200) : msg;
    return {SQ}Ocurrió un error al liberar el estacionamiento: {SQ} + msgCorto + {SQ}{NL}{NL}{SQ}
        {SQ}El estacionamiento ya fue liberado localmente. {SQ}
        {SQ}Si el problema persiste, contacte al administrador.{SQ};
  }}

  String _mensajeErrorRegistro(dynamic error) {{
    final msg = error.toString();
    if (msg.contains({SQ}SocketException{SQ}) ||
        msg.contains({SQ}HandshakeException{SQ}) ||
        msg.contains({SQ}TimeoutException{SQ})) {{
      return {SQ}No se pudo conectar con el servidor para registrar el estacionamiento.{NL}{NL}{SQ}
          {SQ}El registro se ha guardado localmente. {SQ}
          {SQ}Los cambios se sincronizarán automáticamente cuando la conexión se restablezca.{SQ};
    }}
    if (msg.contains({SQ}409{SQ}) || msg.contains({SQ}Conflict{SQ})) {{
      return {SQ}Este estacionamiento ya fue registrado por otro usuario.{NL}{NL}{SQ}
          {SQ}Por favor, seleccione otro espacio disponible.{SQ};
    }}
    if (msg.contains({SQ}400{SQ})) {{
      return {SQ}Los datos ingresados no son válidos.{NL}{NL}{SQ}
          {SQ}Verifique que la placa y el número de tarjeta sean correctos.{SQ};
    }}
    final msgCorto = msg.length > 200 ? msg.substring(0, 200) : msg;
    return {SQ}Ocurrió un error al registrar: {SQ} + msgCorto;
  }}

  void _cambiarFiltroTab(int index) {{"""

content = content.replace(old_m, new_m)
print(f"Metodos B/C/F insertados")

with open(FILE, 'w', encoding='utf-8') as f:
    f.write(content)
print("Archivo guardado")
