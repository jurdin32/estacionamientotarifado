/// GUÍA RÁPIDA DE INTEGRACIÓN EN main.dart
/// 
/// Copia y pega según corresponda en tu main.dart

// ════════════════════════════════════════════════════════════════════════════
// OPCIÓN 1: USAR LA PANTALLA DE CONTROL DE IMPRESORA
// ════════════════════════════════════════════════════════════════════════════

/*
import 'package:flutter/material.dart';
import 'lib/tarjetas/views/ImpresoraBluetooth.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ImpresoraBluetooth(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}
*/

// ════════════════════════════════════════════════════════════════════════════
// OPCIÓN 2: AÑADIR BOTÓN FLOTANTE A TU PANTALLA ACTUAL
// ════════════════════════════════════════════════════════════════════════════

/*
import 'package:flutter/material.dart';
import 'lib/tarjetas/views/WidgetsImpresora.dart';
import 'lib/servicios/gestorImpresora.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class MyHomePage extends StatelessWidget {
  final GestorImpresora _gestor = GestorImpresora();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mi Aplicación'),
        actions: [
          // Estado de la impresora en la barra
          EstadoImpresoraCompacto(
            onPressed: () {
              _gestor.mostrarConfiguracionImpresora(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingImpresoraButton(
        onImpresora: () {
          _gestor.mostrarConfiguracionImpresora(context);
        },
      ),
      body: Center(
        child: Text('Tu contenido aquí'),
      ),
    );
  }
}
*/

// ════════════════════════════════════════════════════════════════════════════
// OPCIÓN 3: INTEGRACIÓN CON NAVEGACIÓN
// ════════════════════════════════════════════════════════════════════════════

/*
import 'package:flutter/material.dart';
import 'lib/tarjetas/views/ImpresoraBluetooth.dart';
import 'lib/tarjetas/views/WidgetsImpresora.dart';
import 'lib/servicios/gestorImpresora.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
      routes: {
        '/impresora': (context) => ImpresoraBluetooth(),
      },
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class MyHomePage extends StatelessWidget {
  final GestorImpresora _gestor = GestorImpresora();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mi App'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/impresora');
            },
          ),
        ],
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.pushNamed(context, '/impresora');
          },
          child: Text('Configurar Impresora'),
        ),
      ),
    );
  }
}
*/

// ════════════════════════════════════════════════════════════════════════════
// OPCIÓN 4: CON WIDGET COMPLETO DE NOTIFICACIONES (COMO TU PANTALLA ACTUAL)
// ════════════════════════════════════════════════════════════════════════════

/*
import 'package:flutter/material.dart';
import 'lib/tarjetas/views/NotificacionScreenEjemplo.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: NotificacionScreenConImpresora(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}
*/

// ════════════════════════════════════════════════════════════════════════════
// PASOS DE INTEGRACIÓN
// ════════════════════════════════════════════════════════════════════════════

/*
1. IMPORTA EN TU ARCHIVO (reemplaza según necesites):

   import 'lib/tarjetas/views/ImpresoraBluetooth.dart';
   import 'lib/tarjetas/views/WidgetsImpresora.dart';
   import 'lib/servicios/gestorImpresora.dart';

2. EN TU SCAFFOLD, AGREGA EL BOTÓN FLOTANTE:

   floatingActionButton: FloatingImpresoraButton(
     onImpresora: () {
       GestorImpresora().mostrarConfiguracionImpresora(context);
     },
   ),

3. EN TU APPBAR, AGREGA EL INDICADOR:

   actions: [
     EstadoImpresoraCompacto(
       onPressed: () {
         GestorImpresora().mostrarConfiguracionImpresora(context);
       },
     ),
   ],

4. PARA IMPRIMIR DESDE CUALQUIER BOTÓN:

   ElevatedButton(
     onPressed: () => _imprimirMulta(context),
     child: Text('Imprimir'),
   )

5. Y TU FUNCIÓN DE IMPRESIÓN:

   Future<void> _imprimirMulta(BuildContext context) async {
     final gestor = GestorImpresora();
     
     await gestor.imprimirMultaConDialogo(
       context: context,
       placa: 'ABC-1234',
       tipoMulta: 'Estacionamiento Prohibido',
       valor: 50.00,
       fechaEmision: DateTime.now().toString(),
       ubicacion: 'Calle Principal 123',
       numeroComprobante: 'CMP-2025-0001',
       observacion: 'Vehículo estacionado en zona prohibida',
       usuario: 'OPERADOR NOMBRE',
       idNotificacion: 1,
     );
   }
*/

// ════════════════════════════════════════════════════════════════════════════
// CHECKLIST DE CONFIGURACIÓN
// ════════════════════════════════════════════════════════════════════════════

/*
✓ Instalé flutter_bluetooth_serial en pubspec.yaml
✓ Instalé permission_handler en pubspec.yaml
✓ Configuré AndroidManifest.xml con permisos Bluetooth
✓ Configuré Info.plist en iOS (si aplica)
✓ Emparé la impresora manualmente en Configuración > Bluetooth
✓ Importé los archivos necesarios
✓ Agregué el widget flotante o indicador
✓ Probé la conexión con la pantalla ImpresoraBluetooth
✓ Probé la impresión de un ticket

SI TODO ESTO ESTÁ LISTO, ¡ESTÁ COMPLETAMENTE FUNCIONAL!
*/
