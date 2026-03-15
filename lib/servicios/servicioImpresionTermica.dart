import 'dart:io';
import 'dart:async';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;

class ServicioImpresionTermica {
  static final ServicioImpresionTermica _instancia =
      ServicioImpresionTermica._internal();
  factory ServicioImpresionTermica() => _instancia;
  ServicioImpresionTermica._internal();

  // Para Android/iOS (impresora Bluetooth clásica)
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  // Para Windows - puerto serie/USB
  RandomAccessFile? _serialPort;

  bool _conectado = false;
  bool _imprimiendo = false;
  final bool _esWindows = Platform.isWindows;
  String? _conexionTipo; // 'bluetooth' | 'usb'
  String? _conexionPuerto; // puerto USB/COM cuando aplique

  // ==================== ESC/POS COMANDOS ====================

  // Alineación
  static final List<int> _alinearIzquierda = [0x1B, 0x61, 0x00]; // ESC a 0
  static final List<int> _alinearCentro = [0x1B, 0x61, 0x01]; // ESC a 1

  // Estilos de texto — usando ESC ! que es universal en POS-58.
  // ESC E (0x1B 0x45) no está soportado por muchos clones y provoca imprimir 'E'.
  // ESC ! bits: 0=fuente B, 3=negrita, 4=doble alto, 5=doble ancho
  static final List<int> _negritaOn = [0x1B, 0x21, 0x08]; // ESC ! bit3 on
  static final List<int> _negritaOff = [0x1B, 0x21, 0x00]; // ESC ! 0 (reset)
  static final List<int> _dobleAlturaOn = [0x1B, 0x21, 0x10]; // ESC ! bit4
  static final List<int> _dobleAlturaOff = [
    0x1B,
    0x21,
    0x00,
  ]; // ESC ! 0 (reset)
  static final List<int> _tamanoGrande = [0x1B, 0x21, 0x30]; // ESC ! bits 4+5

  // Corte de papel
  static final List<int> _cortarPapel = [
    0x1D,
    0x56,
    0x41,
    0x10,
  ]; // GS V 65 (corte completo)
  // Avanzar línea
  static final List<int> _avanzarLinea = [0x0A]; // LF

  // Escanear dispositivos Bluetooth emparejados (no hace scan activo → rápido)
  Future<List<BluetoothDevice>> escanearDispositivos() async {
    if (_esWindows) return [];
    try {
      // getBondedDevices lee el caché del sistema operativo sin hacer scan activo
      final List<BluetoothDevice> dispositivos = await _printer
          .getBondedDevices();
      if (dispositivos.isEmpty) return [];

      // Filtrar preferentemente impresoras térmicas (por nombre común)
      final filtrados = dispositivos.where((device) {
        if (device.name == null) return false;

        final name = device.name!.toLowerCase();
        return name.contains('printer') ||
            name.contains('pos') ||
            name.contains('print') ||
            name.contains('thermal') ||
            name.contains('bt') ||
            name.contains('epson') ||
            name.contains('star') ||
            name.contains('bixolon') ||
            name.contains('zjiang');
      }).toList();

      // Si el filtro queda vacío, devolver todos los emparejados para que el usuario
      // pueda seleccionar manualmente la impresora emparejada.
      if (filtrados.isEmpty) {
        print(
          "⚠️ No se encontraron dispositivos que coincidan con el filtro. Devuelvo todos los emparejados.",
        );
        return dispositivos;
      }

      return filtrados;
    } catch (e) {
      print("❌ Error escaneando dispositivos: $e");
      return [];
    }
  }

  // Conectar a una impresora
  Future<bool> conectarDispositivo(BluetoothDevice dispositivo) async {
    try {
      // Desconectar si hay conexión previa
      await desconectar();

      print("🔌 Conectando a: ${dispositivo.name} (${dispositivo.address})");

      // Para Windows, simular conexión exitosa (si se seleccionó Bluetooth en UI)
      if (_esWindows) {
        await Future.delayed(Duration(milliseconds: 500)); // Simular latencia
        _conectado = true;
        _conexionTipo = 'bluetooth';
        print("✅ Conexión simulada en Windows - EXITOSA");
        return true;
      }

      // Para Android - Intentar conexión real con timeout usando BlueThermalPrinter
      try {
        await _printer.connect(dispositivo).timeout(Duration(seconds: 10));

        final bool isConnected = (await _printer.isConnected) ?? false;
        if (isConnected) {
          _conectado = true;
          print("✅ Conexión real en Android - EXITOSA");
          // Guardar configuración de impresora seleccionada
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('printer_type', 'bluetooth');
            await prefs.setString('printer_address', dispositivo.address ?? '');
            await prefs.setString('printer_name', dispositivo.name ?? '');
          } catch (e) {
            print('⚠️ No se pudo guardar la configuración de impresora: $e');
          }
          return true;
        }
      } on TimeoutException {
        print("❌ Timeout en conexión");
        _conectado = false;
        return false;
      } catch (e) {
        print("❌ Error conectando (printer): $e");
      }

      _conectado = false;
      return false;
    } catch (e) {
      print("❌ Error conectando: $e");
      _conectado = false;
      return false;
    }
  }

  // ================= USB / SERIAL (Windows) =====================================

  /// Lista puertos disponibles: USB directos (USB001, USB002...) + puertos COM.
  /// Usa dos fuentes: wmic (impresoras instaladas) + registro (COM serie).
  Future<List<String>> listarPuertosUSB() async {
    if (!_esWindows) return [];
    final ports = <String>{};

    // Fuente 1: impresoras instaladas en Windows via PowerShell Get-Printer
    // (reemplaza wmic que está obsoleto en Windows 11)
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-Printer | Select-Object -ExpandProperty PortName',
      ], runInShell: false);
      final output = result.stdout as String;
      for (final line in output.split('\n')) {
        // Quitar posible ":" al final (ej: "LPT1:" → "LPT1") y espacios
        final raw = line.trim().replaceAll(':', '').toUpperCase();
        if (RegExp(r'^(COM\d+|USB\d+|LPT\d+)$').hasMatch(raw)) {
          ports.add(raw);
        }
      }
    } catch (e) {
      print('⚠️ PowerShell Get-Printer no disponible: $e');
    }

    // Fuente 2: registro Windows (adaptadores USB-serie, COM virtuales)
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM',
      ], runInShell: false);
      final output = result.stdout as String;
      for (final m in RegExp(r'COM\d+').allMatches(output)) {
        ports.add(m.group(0)!);
      }
    } catch (_) {}

    // Ordenar: USB primero, luego COM, luego LPT; dentro de cada tipo por número
    final sorted = ports.toList()
      ..sort((a, b) {
        int t(String p) => p.startsWith('USB')
            ? 0
            : p.startsWith('COM')
            ? 1
            : 2;
        final cmp = t(a).compareTo(t(b));
        if (cmp != 0) return cmp;
        final na =
            int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '0') ?? 0;
        final nb =
            int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '0') ?? 0;
        return na.compareTo(nb);
      });
    return sorted;
  }

  /// Conecta a un puerto de impresora USB/COM en Windows.
  /// USB/LPT: se marca como conectado sin abrir fichero (se usa copy /b al imprimir).
  /// COM: se abre como RandomAccessFile con el prefijo \\.\
  Future<bool> conectarPuertoUSB(String puerto) async {
    if (!_esWindows) return false;
    try {
      await desconectar();
      final puertoNorm = puerto.replaceAll(':', '').toUpperCase().trim();
      final esCOM = RegExp(r'^COM\d+$').hasMatch(puertoNorm);
      if (esCOM) {
        // Puertos COM: abrir como RandomAccessFile
        final path = '\\\\.\\$puertoNorm';
        _serialPort = await File(path).open(mode: FileMode.write);
      } else {
        // Puertos USB/LPT: no se pueden abrir como File en Win10/11.
        // Los datos se enviarán con "copy /b tempfile USB001" al imprimir.
        _serialPort = null;
      }
      _conectado = true;
      _conexionTipo = 'usb';
      _conexionPuerto = puertoNorm;
      print('✅ Puerto $puertoNorm listo (${esCOM ? "serial" : "copy /b"})');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('printer_type', 'usb');
        await prefs.setString('printer_port', puertoNorm);
      } catch (_) {}
      return true;
    } catch (e) {
      print('❌ Error conectando puerto $puerto: $e');
      _conectado = false;
      _serialPort = null;
      return false;
    }
  }

  // Guardar/leer configuración de impresora para persistencia
  Future<void> cargarConfiguracionYConectarSiAplica() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tipo = prefs.getString('printer_type');
      if (tipo == null) return;

      if (tipo == 'bluetooth') {
        final address = prefs.getString('printer_address') ?? '';
        if (address.isEmpty) return;

        // Intentar encontrar el dispositivo emparejado con esa dirección
        try {
          final dispositivos = await _printer.getBondedDevices();
          final match = dispositivos.firstWhere(
            (d) => (d.address ?? '') == address,
            orElse: () => BluetoothDevice(null, ''),
          );
          if ((match.address ?? '').isNotEmpty) {
            await conectarDispositivo(match);
          }
        } catch (e) {
          print(
            '⚠️ Error buscando dispositivo emparejado para auto-conectar: $e',
          );
        }
      } else if (tipo == 'usb') {
        final port = prefs.getString('printer_port') ?? '';
        if (port.isNotEmpty && _esWindows) {
          await conectarPuertoUSB(port);
        }
      }
    } catch (e) {
      print('⚠️ Error cargando configuración de impresora: $e');
    }
  }

  Future<Map<String, String?>> obtenerConfiguracionGuardada() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'printer_type': prefs.getString('printer_type'),
      'printer_address': prefs.getString('printer_address'),
      'printer_name': prefs.getString('printer_name'),
      'printer_port': prefs.getString('printer_port'),
    };
  }

  /// Devuelve la impresora guardada en SharedPreferences (sin hacer scan Bluetooth).
  Future<BluetoothDevice?> obtenerDispositivoGuardado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('printer_type') != 'bluetooth') return null;
      final address = prefs.getString('printer_address') ?? '';
      if (address.isEmpty) return null;
      final name = prefs.getString('printer_name') ?? 'Impresora';
      return BluetoothDevice(name, address);
    } catch (_) {
      return null;
    }
  }

  /// Elimina la configuración guardada de impresora (útil para cambiar o resetear)
  Future<void> limpiarConfiguracion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('printer_type');
      await prefs.remove('printer_address');
      await prefs.remove('printer_name');
      await prefs.remove('printer_port');
      // Además limpiar estado interno si aplica
      _conexionTipo = null;
      _conexionPuerto = null;
      _conectado = false;
      print('ℹ️ Configuración de impresora limpiada');
    } catch (e) {
      print('⚠️ Error limpiando configuración de impresora: $e');
    }
  }

  // Desconectar de la impresora
  Future<void> desconectar() async {
    try {
      // Cerrar puerto serie/USB si está abierto
      if (_serialPort != null) {
        try {
          await _serialPort!.close();
        } catch (_) {}
        _serialPort = null;
        print('✅ Puerto COM cerrado');
      }

      if (_conexionTipo != 'usb') {
        try {
          await _printer.disconnect();
          print('✅ Conexión Bluetooth desconectada');
        } catch (e) {
          print('⚠️ Error desconectando Bluetooth: $e');
        }
      }

      _conectado = false;
      _conexionTipo = null;
      _conexionPuerto = null;
    } catch (e) {
      print('❌ Error desconectando: $e');
    }
  }

  // Verificar estado de conexión
  bool get estaConectado => _conectado;
  bool get imprimiendo => _imprimiendo;

  // Obtener dispositivo conectado
  BluetoothDevice? get dispositivoConectado {
    if (!_conectado) return null;
    if (_conexionTipo == 'usb') {
      return BluetoothDevice('Impresora USB', _conexionPuerto ?? 'USB');
    }
    return BluetoothDevice('Impresora Térmica', 'Conectada');
  }

  // ==================== IMPRIMIR TICKET ====================

  Future<void> imprimirMulta({
    required String placa,
    required String tipoMulta,
    required double valor,
    required String fechaEmision,
    required String ubicacion,
    required String numeroComprobante,
    required String observacion,
    required String usuario,
    required int idNotificacion,
  }) async {
    if (_imprimiendo) {
      throw Exception("Ya se está imprimiendo");
    }

    _imprimiendo = true;

    try {
      // Verificar conexión
      if (!estaConectado) {
        throw Exception(
          "No hay impresora conectada. Conecte una impresora primero.",
        );
      }

      // Cargar logo de la empresa desde assets para imprimirlo al inicio del ticket.
      // En Windows desktop, rootBundle falla con assets no empaquetados; se usa
      // dart:io leyendo desde data/flutter_assets/ junto al ejecutable (más confiable).
      List<int> logoBytes = [];
      try {
        Uint8List? rawData;

        if (Platform.isWindows) {
          // Ruta 1: junto al ejecutable (release / debug con flutter run)
          final exeDir = File(Platform.resolvedExecutable).parent.path;
          final candidates = [
            '$exeDir\\data\\flutter_assets\\assets\\images\\logo.png',
            '$exeDir\\..\\data\\flutter_assets\\assets\\images\\logo.png',
          ];
          for (final c in candidates) {
            final f = File(c);
            if (await f.exists()) {
              rawData = await f.readAsBytes();
              print('✅ Logo leído desde: $c');
              break;
            }
          }
        }

        // Fallback universal: rootBundle (funciona en Android / otros SO)
        if (rawData == null) {
          final bd = await rootBundle.load('assets/images/logo.png');
          rawData = bd.buffer.asUint8List();
        }

        final image = img.decodeImage(rawData);
        if (image != null) {
          logoBytes = _imagenAEscPosRaster(image);
          print(
            '✅ Logo listo: ${image.width}x${image.height}px → ${logoBytes.length} bytes raster',
          );
        } else {
          print('⚠️ Logo: img.decodeImage devolvio null');
        }
      } catch (e) {
        print('⚠️ No se pudo cargar el logo para imprimir: $e');
      }

      // Generar comandos ESC/POS
      final bytes = _generarTicketTermico(
        logoBytes: logoBytes,
        placa: placa,
        tipoMulta: tipoMulta,
        valor: valor,
        fechaEmision: fechaEmision,
        ubicacion: ubicacion,
        numeroComprobante: numeroComprobante,
        observacion: observacion,
        usuario: usuario,
        idNotificacion: idNotificacion,
      );

      // Enviar a la impresora
      await _enviarABluetooth(bytes);

      print("Ticket impreso exitosamente");
    } catch (e) {
      print("Error imprimiendo: $e");
      rethrow;
    } finally {
      _imprimiendo = false;
    }
  }

  // ==================== GENERACIÓN DE TICKET ====================

  List<int> _generarTicketTermico({
    required List<int> logoBytes,
    required String placa,
    required String tipoMulta,
    required double valor,
    required String fechaEmision,
    required String ubicacion,
    required String numeroComprobante,
    required String observacion,
    required String usuario,
    required int idNotificacion,
  }) {
    List<int> bytes = [];

    // [0x1B, 0x01] = ESC SOH: secuencia ESC "sacrificial" como primer comando.
    // Este clon POS-58 siempre imprime el 2do byte de la PRIMERA secuencia ESC.
    // 0x01 = SOH (Start of Heading) es un caracter de control invisible.
    // Tras este par de bytes, todas las secuencias ESC siguientes funcionan correctamente.
    bytes.addAll([0x1B, 0x01]);

    // LOGO al inicio, sin ESC previo (usa GS que empieza con 0x1D, no 0x1B)
    if (logoBytes.isNotEmpty) {
      bytes.addAll(_alinearCentro);
      bytes.addAll(logoBytes);
      bytes.addAll(_avanzarLinea);
    }

    // ENCABEZADO
    bytes.addAll(_alinearCentro);
    bytes.addAll(_dobleAlturaOn);
    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('TRANSITO EL GUABO EP\n'));
    bytes.addAll(_dobleAlturaOff);
    bytes.addAll(_negritaOff);
    bytes.addAll(_avanzarLinea);

    // INFORMACIÓN PRINCIPAL
    bytes.addAll(_alinearIzquierda);

    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('ID: '));
    bytes.addAll(_negritaOff);
    bytes.addAll(_toBytes('$idNotificacion\n'));

    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Comprobante: '));
    bytes.addAll(_negritaOff);
    bytes.addAll(_toBytes('$numeroComprobante\n'));

    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Fecha: '));
    bytes.addAll(_negritaOff);
    bytes.addAll(_toBytes('$fechaEmision\n'));

    bytes.addAll(_avanzarLinea);

    // DATOS DE MULTA
    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Placa: '));
    bytes.addAll(_negritaOff);
    bytes.addAll(_toBytes('$placa\n'));

    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Tipo de infraccion:\n'));
    bytes.addAll(_negritaOff);
    bytes.addAll(_formatearTextoMultilinea(tipoMulta, 32));

    // "Valor:" en tamaño normal, solo el número en tamaño grande (ESC ! 0x30)
    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Valor: '));
    bytes.addAll(_tamanoGrande);
    bytes.addAll(_toBytes('\$${valor.toStringAsFixed(2)}\n'));
    bytes.addAll(_dobleAlturaOff); // ESC ! 0x00 = reset a tamaño normal
    bytes.addAll(_negritaOff);

    bytes.addAll(_avanzarLinea);

    // UBICACION
    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Ubicacion:\n'));
    bytes.addAll(_negritaOff);
    bytes.addAll(_formatearTextoMultilinea(ubicacion, 32));
    bytes.addAll(_avanzarLinea);

    // OBSERVACIONES
    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Observaciones:\n'));
    bytes.addAll(_negritaOff);
    bytes.addAll(_formatearTextoMultilinea(observacion, 32));
    bytes.addAll(_avanzarLinea);

    // USUARIO — etiqueta y nombre en tamaño normal
    bytes.addAll(_alinearCentro);
    bytes.addAll(_negritaOn);
    bytes.addAll(_toBytes('Registrado por:\n'));
    bytes.addAll(_negritaOff);
    bytes.addAll(_toBytes('$usuario\n'));

    bytes.addAll(_avanzarLinea);

    // PIE DE PAGINA
    bytes.addAll(_alinearIzquierda);
    bytes.addAll(_toBytes('Este comprobante es válido\n'));
    bytes.addAll(_toBytes('para el pago de la infracción.\n'));
    bytes.addAll(_avanzarLinea);
    bytes.addAll(
      _formatearTextoMultilinea(
        'Le recomendamos proceder con el pago lo antes posible para evitar '
        'recargos adicionales, y posibles sanciones. Puede realizar trámite de '
        'impugnación durante los primeros 3 días laborables a partir de la fecha '
        'de la notificación, una vez transcurrido este tiempo debe realizar el '
        'pago correspondiente.',
        32,
      ),
    );

    bytes.addAll(_avanzarLinea);
    bytes.addAll(_avanzarLinea);
    bytes.addAll(_avanzarLinea);

    bytes.addAll(_cortarPapel);

    return bytes;
  }

  // ==================== MÉTODOS AUXILIARES ====================

  // Tabla de encoding para las POS-58 en mode PC437 (code page por defecto).
  // Los bytes 0xA0-0xA5, 0x81, 0x82, 0x90, 0x9A, etc. son IGUALES en PC437 y
  // PC850 para los caracteres españoles más comunes (tildes minúsculas + Ñ/ñ).
  // Para Á/Í/Ó/Ú (difieren entre PC437 y PC850) se usa el ASCII sin tilde como
  // fallback seguro.
  static const Map<int, int> _charMap = {
    0xE1: 0xA0, // á  (PC437 = PC850)
    0xE9: 0x82, // é  (PC437 = PC850)
    0xED: 0xA1, // í  (PC437 = PC850)
    0xF3: 0xA2, // ó  (PC437 = PC850)
    0xFA: 0xA3, // ú  (PC437 = PC850)
    0xF1: 0xA4, // ñ  (PC437 = PC850)
    0xD1: 0xA5, // Ñ  (PC437 = PC850)
    0xFC: 0x81, // ü  (PC437 = PC850)
    0xDC: 0x9A, // Ü  (PC437 = PC850)
    0xC9: 0x90, // É  (PC437 = PC850)
    0xC1: 0x41, // Á → A (difiere en PC437, fallback ASCII)
    0xCD: 0x49, // Í → I (difiere en PC437, fallback ASCII)
    0xD3: 0x4F, // Ó → O (difiere en PC437, fallback ASCII)
    0xDA: 0x55, // Ú → U (difiere en PC437, fallback ASCII)
    0xBF: 0xA8, // ¿  (PC437 = PC850)
    0xA1: 0xAD, // ¡  (PC437 = PC850)
    0xB0: 0xF8, // °  (PC437 = PC850)
    0x2013: 0x2D, // en dash → -
    0x2014: 0x2D, // em dash → -
    0x2018: 0x27, // ' → '
    0x2019: 0x27, // ' → '
    0x201C: 0x22, // " → "
    0x201D: 0x22, // " → "
  };

  static List<int> _toBytes(String text) {
    final out = <int>[];
    for (final rune in text.runes) {
      if (_charMap.containsKey(rune)) {
        out.add(_charMap[rune]!);
      } else if (rune <= 0x7F) {
        out.add(rune);
      } else {
        out.add(0x3F); // '?' para cualquier otro Unicode no mapeado
      }
    }
    return out;
  }

  /// Convierte un img.Image a bytes ESC/POS raster (GS v 0).
  /// Escala al ancho máximo de la impresora (384 dots) y binariza con umbral 50%.
  static List<int> _imagenAEscPosRaster(img.Image src) {
    const int maxW = 384;
    const int maxH = 160; // limitar alto del logo para no saturar buffer
    final int targetW = src.width > maxW ? maxW : src.width;
    img.Image resized = img.copyResize(
      src,
      width: targetW,
      interpolation: img.Interpolation.average,
    );
    if (resized.height > maxH) {
      resized = img.copyResize(
        resized,
        height: maxH,
        interpolation: img.Interpolation.average,
      );
    }
    final img.Image gray = img.grayscale(resized);
    final int widthBytes = (gray.width + 7) ~/ 8;
    final int height = gray.height;
    // GS v 0: modo 0x00 (compatible con todos los clones POS-58)
    final List<int> bytes = [
      0x1D,
      0x76,
      0x30,
      0x00,
      widthBytes & 0xFF,
      (widthBytes >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
    ];
    for (int y = 0; y < height; y++) {
      for (int xb = 0; xb < widthBytes; xb++) {
        int b = 0;
        for (int bit = 0; bit < 8; bit++) {
          final int x = xb * 8 + bit;
          if (x < gray.width) {
            final pixel = gray.getPixel(x, y);
            if (pixel.r.toDouble() < 128.0) {
              b |= (0x80 >> bit);
            }
          }
        }
        bytes.add(b);
      }
    }
    return bytes;
  }

  // Formatear texto multilínea
  List<int> _formatearTextoMultilinea(String texto, int maxCaracteres) {
    List<int> bytes = [];
    List<String> palabras = texto.split(' ');
    String lineaActual = '';

    for (String palabra in palabras) {
      if (('$lineaActual $palabra').length <= maxCaracteres) {
        if (lineaActual.isEmpty) {
          lineaActual = palabra;
        } else {
          lineaActual += ' $palabra';
        }
      } else {
        if (lineaActual.isNotEmpty) {
          bytes.addAll(_toBytes('$lineaActual\n'));
        }
        lineaActual = palabra;
      }
    }

    if (lineaActual.isNotEmpty) {
      bytes.addAll(_toBytes('$lineaActual\n'));
    }

    return bytes;
  }

  // Enviar datos a la impresora (USB/COM en Windows, Bluetooth en Android)
  Future<void> _enviarABluetooth(List<int> bytes) async {
    if (_conexionTipo == 'usb' && _conexionPuerto != null) {
      final puerto = _conexionPuerto!;
      if (_serialPort != null) {
        // Puerto COM serie: escritura directa
        try {
          await _serialPort!.writeFrom(Uint8List.fromList(bytes));
          await Future.delayed(const Duration(milliseconds: 300));
          print('\u2705 ${bytes.length} bytes enviados por $puerto (serial)');
        } catch (e) {
          print('\u274c Error enviando por $puerto: $e');
          rethrow;
        }
      } else {
        // Puerto USB/LPT: Windows WritePrinter API via PowerShell + C# inline.
        // USA @'...'@ (single-quote here-string) para evitar escaping de "" en C#.
        // DocInfo va como clase de nivel superior en namespace para evitar error
        // "Se esperaba )" del compilador Add-Type con clases anidadas.
        try {
          final tmp = File('${Directory.systemTemp.path}\\escpos_ticket.bin');
          await tmp.writeAsBytes(bytes, flush: true);

          // IMPORTANTE: usar comillas simples r''' en Dart para que @'...'@ llegue
          // literalmente al .ps1. En el here-string de PowerShell @'...'@, las
          // comillas dobles NO necesitan escaparse con "".
          const ps1Content = r'''
param([string]$Port, [string]$Bin)
$ErrorActionPreference = 'Stop'
$pName = (Get-Printer | Where-Object {
    ($_.PortName -replace ':','').Trim().ToUpper() -eq $Port.Trim().ToUpper()
} | Select-Object -First 1).Name
if (-not $pName) { Write-Error "No printer found on port $Port"; exit 1 }
$bytes = [System.IO.File]::ReadAllBytes($Bin)
if (-not ('EscPosRaw.Api' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace EscPosRaw {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public class DocInfo {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }
    public class Api {
        [DllImport("winspool.drv", EntryPoint = "OpenPrinterA",
            CharSet = CharSet.Ansi, SetLastError = true)]
        public static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
        [DllImport("winspool.drv", EntryPoint = "ClosePrinter")]
        public static extern bool ClosePrinter(IntPtr handle);
        [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA",
            CharSet = CharSet.Ansi, SetLastError = true)]
        public static extern int StartDocPrinter(IntPtr handle, int level, [In] DocInfo info);
        [DllImport("winspool.drv", EntryPoint = "EndDocPrinter")]
        public static extern bool EndDocPrinter(IntPtr handle);
        [DllImport("winspool.drv", EntryPoint = "StartPagePrinter")]
        public static extern bool StartPagePrinter(IntPtr handle);
        [DllImport("winspool.drv", EntryPoint = "EndPagePrinter")]
        public static extern bool EndPagePrinter(IntPtr handle);
        [DllImport("winspool.drv", EntryPoint = "WritePrinter", SetLastError = true)]
        public static extern bool WritePrinter(IntPtr handle, IntPtr data, int count, out int written);
        public static int Send(string printer, byte[] data) {
            IntPtr h;
            if (!OpenPrinter(printer, out h, IntPtr.Zero)) return -1;
            var di = new DocInfo { pDocName = "RAW", pDataType = "RAW" };
            if (StartDocPrinter(h, 1, di) == 0) { ClosePrinter(h); return -2; }
            if (!StartPagePrinter(h)) { EndDocPrinter(h); ClosePrinter(h); return -3; }
            IntPtr p = Marshal.AllocCoTaskMem(data.Length);
            Marshal.Copy(data, 0, p, data.Length);
            int w = 0;
            bool ok = WritePrinter(h, p, data.Length, out w);
            Marshal.FreeCoTaskMem(p);
            EndPagePrinter(h); EndDocPrinter(h); ClosePrinter(h);
            return (ok && w > 0) ? w : -4;
        }
    }
}
'@
}
$r = [EscPosRaw.Api]::Send($pName, $bytes)
if ($r -le 0) { Write-Error "Send failed: $r"; exit 1 }
Write-Output "OK:$r"
''';
          final ps1File = File(
            '${Directory.systemTemp.path}\\escpos_rawprint.ps1',
          );
          await ps1File.writeAsString(ps1Content);

          final result = await Process.run('powershell', [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            ps1File.path,
            '-Port',
            puerto,
            '-Bin',
            tmp.path,
          ], runInShell: false);

          await tmp.delete().catchError((_) => tmp);
          await ps1File.delete().catchError((_) => ps1File);

          if (result.exitCode != 0) {
            throw Exception(
              'WritePrinter fall\u00f3 (${result.exitCode}): ${result.stderr}',
            );
          }
          print(
            '\u2705 ${bytes.length} bytes enviados por $puerto (WritePrinter): ${(result.stdout as String).trim()}',
          );
        } catch (e) {
          print('\u274c Error enviando por $puerto: $e');
          rethrow;
        }
      }
      return;
    }

    // Para Android, validar conexión real
    final bool connected = (await _printer.isConnected) ?? false;
    if (!connected) {
      print("❌ Error: Conexión Bluetooth no disponible");
      throw Exception(
        "Conexión Bluetooth no disponible. Reconecte la impresora.",
      );
    }

    try {
      // Convertir a Uint8List
      final data = Uint8List.fromList(bytes);
      print(
        "📤 Enviando ${bytes.length} bytes por Bluetooth (blue_thermal_printer)...",
      );

      // Enviar en un solo writeBytes (el plugin se encarga del buffer)
      await _printer.writeBytes(data);

      // Pequeña espera para asegurarse de que la impresora procese
      await Future.delayed(Duration(milliseconds: 500));
      print("✅ Datos enviados correctamente");
    } on TimeoutException catch (e) {
      print("❌ Error de timeout: $e");
      rethrow;
    } catch (e) {
      print("❌ Error enviando datos Bluetooth: $e");
      rethrow;
    }
  }

  // ==================== MÉTODOS DE UTILIDAD ====================

  // Solicitar permisos
  Future<bool> solicitarPermisos() async {
    try {
      // Para Android 6.0+ necesitamos permisos de ubicación para Bluetooth
      var status = await Permission.location.request();

      if (!status.isGranted) {
        return false;
      }

      // Para Android 12+
      if (await Permission.bluetoothConnect.request().isGranted &&
          await Permission.bluetoothScan.request().isGranted) {
        return true;
      }

      return true;
    } catch (e) {
      print("Error en permisos: $e");
      return false;
    }
  }

  // Verificar estado Bluetooth
  Future<Map<String, dynamic>> verificarEstado() async {
    try {
      final bool? isOnNullable = await _printer.isOn;
      final bool isOn = isOnNullable ?? false;
      final List<BluetoothDevice> dispositivos = await _printer
          .getBondedDevices();

      return {
        'bluetoothActivo': isOn,
        'dispositivosEmparejados': dispositivos.length,
        'conectado': estaConectado,
        'imprimiendo': _imprimiendo,
        'dispositivoConectado': 'Conectada',
      };
    } catch (e) {
      return {'bluetoothActivo': false, 'error': e.toString()};
    }
  }
}
