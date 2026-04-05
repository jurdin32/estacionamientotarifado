import 'package:flutter/material.dart';

class ManualUsuarioScreen extends StatefulWidget {
  const ManualUsuarioScreen({super.key});

  @override
  State<ManualUsuarioScreen> createState() => _ManualUsuarioScreenState();
}

class _ManualUsuarioScreenState extends State<ManualUsuarioScreen> {
  final ScrollController _scrollController = ScrollController();
  int _seccionActiva = 0;

  static const _azulPrimario = Color(0xFF1565C0);
  static const _azulOscuro = Color(0xFF0A1628);

  final List<_SeccionManual> _secciones = [
    _SeccionManual(
      titulo: 'Inicio de Sesión',
      icono: Icons.login,
      colorIlustracion: const Color(0xFF1565C0),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.person_outline, etiqueta: 'Usuario'),
        _ElementoIlustracion(icono: Icons.lock_outline, etiqueta: 'Contraseña'),
        _ElementoIlustracion(icono: Icons.login, etiqueta: 'Ingresar'),
      ],
      pasos: [
        _Paso(
          titulo: 'Ingresar credenciales',
          descripcion:
              'Abra la aplicación e ingrese su nombre de usuario y contraseña proporcionados por el administrador.',
          icono: Icons.person,
        ),
        _Paso(
          titulo: 'Presionar "Iniciar sesión"',
          descripcion:
              'Toque el botón azul para acceder al sistema. Si las credenciales son incorrectas, se mostrará un mensaje de error.',
          icono: Icons.touch_app,
        ),
        _Paso(
          titulo: '¿Olvidó su contraseña?',
          descripcion:
              'Toque el enlace "¿Olvidé mi contraseña?" para generar un código temporal. Luego deberá crear una nueva contraseña al iniciar sesión.',
          icono: Icons.lock_reset,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Panel Principal',
      icono: Icons.dashboard,
      colorIlustracion: const Color(0xFF0D47A1),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.account_circle, etiqueta: 'Perfil'),
        _ElementoIlustracion(icono: Icons.bar_chart, etiqueta: 'Métricas'),
        _ElementoIlustracion(icono: Icons.menu, etiqueta: 'Menú'),
      ],
      pasos: [
        _Paso(
          titulo: 'Vista general',
          descripcion:
              'Al iniciar sesión verá el panel principal con su nombre, correo y las métricas del mes actual: infracciones y tarjetas registradas.',
          icono: Icons.analytics,
        ),
        _Paso(
          titulo: 'Menú lateral',
          descripcion:
              'Deslice desde el borde izquierdo de la pantalla o toque el ícono de menú (☰) para acceder a todas las secciones de la aplicación.',
          icono: Icons.menu,
        ),
        _Paso(
          titulo: 'Actualizar datos',
          descripcion:
              'Los datos se actualizan en tiempo real. También puede deslizar hacia abajo para refrescar manualmente.',
          icono: Icons.refresh,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Control de Tarjetas',
      icono: Icons.credit_card,
      colorIlustracion: const Color(0xFF2E7D32),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.grid_view, etiqueta: 'Estaciones'),
        _ElementoIlustracion(icono: Icons.directions_car, etiqueta: 'Placa'),
        _ElementoIlustracion(icono: Icons.check_circle, etiqueta: 'Liberar'),
      ],
      pasos: [
        _Paso(
          titulo: 'Ver estaciones',
          descripcion:
              'Se muestra una cuadrícula con todas las estaciones de estacionamiento. Verde = disponible, Rojo = ocupado, Amarillo = reservado.',
          icono: Icons.grid_view,
        ),
        _Paso(
          titulo: 'Registrar vehículo',
          descripcion:
              'Toque una estación disponible (verde), ingrese la placa del vehículo y el número de tarjeta, luego confirme el registro.',
          icono: Icons.directions_car,
        ),
        _Paso(
          titulo: 'Liberar estación',
          descripcion:
              'Toque una estación ocupada (roja) y seleccione "Liberar" para finalizar el estacionamiento y liberar la plaza.',
          icono: Icons.check_circle,
        ),
        _Paso(
          titulo: 'Filtrar estaciones',
          descripcion:
              'Use las pestañas superiores (Todos, Ocupados, Disponibles, Reservados) para filtrar las estaciones visibles.',
          icono: Icons.filter_list,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Emitir Multa',
      icono: Icons.receipt_long,
      colorIlustracion: const Color(0xFFC62828),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.edit_note, etiqueta: 'Formulario'),
        _ElementoIlustracion(icono: Icons.camera_alt, etiqueta: '3 Fotos'),
        _ElementoIlustracion(icono: Icons.save, etiqueta: 'Guardar'),
      ],
      pasos: [
        _Paso(
          titulo: 'Abrir formulario',
          descripcion:
              'Desde el menú lateral, seleccione "Notificaciones" para abrir el formulario de nueva multa.',
          icono: Icons.note_add,
        ),
        _Paso(
          titulo: 'Completar datos',
          descripcion:
              'Seleccione el tipo de multa, ingrese la placa del vehículo (formato ABC1234), la ubicación, número de comprobante y observaciones.',
          icono: Icons.edit_note,
        ),
        _Paso(
          titulo: 'Agregar evidencias',
          descripcion:
              'Debe tomar o seleccionar 3 fotografías como evidencia de la infracción. Las 3 fotos son obligatorias.',
          icono: Icons.camera_alt,
        ),
        _Paso(
          titulo: 'Guardar e imprimir',
          descripcion:
              'Toque "Guardar" para registrar la multa. Luego puede imprimir el ticket por Bluetooth o generar un PDF.',
          icono: Icons.print,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Reimprimir Ticket',
      icono: Icons.print,
      colorIlustracion: const Color(0xFF6A1B9A),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.history, etiqueta: 'Hoy'),
        _ElementoIlustracion(icono: Icons.search, etiqueta: 'Buscar'),
        _ElementoIlustracion(icono: Icons.print, etiqueta: 'Imprimir'),
      ],
      pasos: [
        _Paso(
          titulo: 'Acceder a reimpresión',
          descripcion:
              'Desde la pantalla de Notificaciones, toque el botón de reimpresión para ver las multas emitidas hoy.',
          icono: Icons.history,
        ),
        _Paso(
          titulo: 'Buscar y reimprimir',
          descripcion:
              'Busque la multa por placa o comprobante y toque "Reimprimir" para imprimir por Bluetooth o generar un PDF.',
          icono: Icons.search,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Consultar Multas',
      icono: Icons.search,
      colorIlustracion: const Color(0xFFE65100),
      elementosIlustracion: const [
        _ElementoIlustracion(
          icono: Icons.manage_search,
          etiqueta: 'Placa/Cédula',
        ),
        _ElementoIlustracion(icono: Icons.filter_alt, etiqueta: 'Filtros'),
        _ElementoIlustracion(icono: Icons.info_outline, etiqueta: 'Detalle'),
      ],
      pasos: [
        _Paso(
          titulo: 'Buscar multas',
          descripcion:
              'Ingrese una placa o número de cédula para buscar todas las multas asociadas.',
          icono: Icons.manage_search,
        ),
        _Paso(
          titulo: 'Filtrar resultados',
          descripcion:
              'Use los filtros para ver: todas, pendientes, pagadas o impugnadas.',
          icono: Icons.filter_alt,
        ),
        _Paso(
          titulo: 'Ver detalle',
          descripcion:
              'Toque una multa para expandir su información completa: datos del infractor, ubicación, evidencias y estado.',
          icono: Icons.info_outline,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Mis Notificaciones',
      icono: Icons.notifications,
      colorIlustracion: const Color(0xFF00838F),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.list_alt, etiqueta: 'Historial'),
        _ElementoIlustracion(icono: Icons.tab, etiqueta: 'Estados'),
        _ElementoIlustracion(icono: Icons.date_range, etiqueta: 'Período'),
      ],
      pasos: [
        _Paso(
          titulo: 'Ver historial',
          descripcion:
              'Muestra todas las multas que usted ha emitido, organizadas por estado: Pagadas, Impagas e Impugnadas.',
          icono: Icons.list_alt,
        ),
        _Paso(
          titulo: 'Filtrar por período',
          descripcion:
              'Active el interruptor para ver solo las multas del mes actual o desactívelo para ver el historial completo.',
          icono: Icons.date_range,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Datos de Vehículos',
      icono: Icons.directions_car,
      colorIlustracion: const Color(0xFF37474F),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.search, etiqueta: 'Buscar placa'),
        _ElementoIlustracion(icono: Icons.directions_car, etiqueta: 'Datos'),
      ],
      pasos: [
        _Paso(
          titulo: 'Consultar vehículo',
          descripcion:
              'Ingrese la placa del vehículo (formato ABC1234) y toque "Buscar" para consultar los datos registrados del vehículo.',
          icono: Icons.search,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Beneficio Adulto Mayor',
      icono: Icons.elderly,
      colorIlustracion: const Color(0xFF558B2F),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.search, etiqueta: 'Consultar'),
        _ElementoIlustracion(icono: Icons.person_add, etiqueta: 'Registrar'),
        _ElementoIlustracion(icono: Icons.edit, etiqueta: 'Editar'),
      ],
      pasos: [
        _Paso(
          titulo: 'Consultar beneficiarios',
          descripcion:
              'Busque por nombre, cédula o placa. Filtre por tipo: Adulto Mayor, Discapacitado, Activos o Inactivos.',
          icono: Icons.search,
        ),
        _Paso(
          titulo: 'Registrar beneficiario',
          descripcion:
              'Toque el botón "+" para registrar un nuevo beneficiario. Complete los datos personales y el tipo de beneficio.',
          icono: Icons.person_add,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Credencial Digital',
      icono: Icons.badge,
      colorIlustracion: const Color(0xFF4527A0),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.badge, etiqueta: 'Frente'),
        _ElementoIlustracion(icono: Icons.flip, etiqueta: 'Voltear'),
      ],
      pasos: [
        _Paso(
          titulo: 'Ver credencial',
          descripcion:
              'Muestra su carnet digital con foto, nombre, cargo y cédula. Toque la tarjeta para voltearla y ver información adicional.',
          icono: Icons.flip,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Impresora Bluetooth',
      icono: Icons.bluetooth,
      colorIlustracion: const Color(0xFF0277BD),
      elementosIlustracion: const [
        _ElementoIlustracion(
          icono: Icons.bluetooth_searching,
          etiqueta: 'Buscar',
        ),
        _ElementoIlustracion(
          icono: Icons.bluetooth_connected,
          etiqueta: 'Conectar',
        ),
        _ElementoIlustracion(icono: Icons.receipt, etiqueta: 'Ticket'),
      ],
      pasos: [
        _Paso(
          titulo: 'Conectar impresora',
          descripcion:
              'Toque el ícono de impresora (esquina inferior) para buscar impresoras Bluetooth disponibles cercanas.',
          icono: Icons.bluetooth_searching,
        ),
        _Paso(
          titulo: 'Seleccionar dispositivo',
          descripcion:
              'Seleccione su impresora térmica de la lista. El ícono se pondrá verde cuando esté conectada.',
          icono: Icons.bluetooth_connected,
        ),
        _Paso(
          titulo: 'Imprimir',
          descripcion:
              'Con la impresora conectada, use los botones de imprimir en las pantallas de multas y tarjetas para generar tickets.',
          icono: Icons.receipt,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Cambiar Contraseña',
      icono: Icons.lock,
      colorIlustracion: const Color(0xFF455A64),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.lock_open, etiqueta: 'Actual'),
        _ElementoIlustracion(icono: Icons.vpn_key, etiqueta: 'Nueva'),
        _ElementoIlustracion(icono: Icons.check, etiqueta: 'Confirmar'),
      ],
      pasos: [
        _Paso(
          titulo: 'Cambiar contraseña',
          descripcion:
              'Ingrese su contraseña actual, la nueva contraseña y confírmela. Toque "Cambiar contraseña" para guardar.',
          icono: Icons.vpn_key,
        ),
      ],
    ),
    _SeccionManual(
      titulo: 'Administración',
      icono: Icons.admin_panel_settings,
      colorIlustracion: const Color(0xFFBF360C),
      elementosIlustracion: const [
        _ElementoIlustracion(icono: Icons.people, etiqueta: 'Usuarios'),
        _ElementoIlustracion(
          icono: Icons.local_parking,
          etiqueta: 'Estaciones',
        ),
        _ElementoIlustracion(icono: Icons.security, etiqueta: 'Permisos'),
      ],
      pasos: [
        _Paso(
          titulo: 'Gestión de Accesos',
          descripcion:
              'Solo administradores. Permite habilitar/deshabilitar usuarios, cambiar roles y asignar permisos individuales a cada operador.',
          icono: Icons.people,
        ),
        _Paso(
          titulo: 'Gestión de Estaciones',
          descripcion:
              'Solo administradores. Crear, editar y eliminar estaciones de estacionamiento. Puede crear estaciones individuales o por rango.',
          icono: Icons.local_parking,
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text(
          'Manual de Usuario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _azulOscuro,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Selector de sección compacto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Botón anterior
                IconButton(
                  onPressed: _seccionActiva > 0
                      ? () {
                          setState(() => _seccionActiva--);
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  color: _azulPrimario,
                  iconSize: 28,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                // Dropdown de secciones
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _azulPrimario.withValues(alpha: 0.3),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _seccionActiva,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.expand_more,
                          color: _azulPrimario,
                        ),
                        style: const TextStyle(
                          color: _azulOscuro,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        items: _secciones.asMap().entries.map((entry) {
                          return DropdownMenuItem<int>(
                            value: entry.key,
                            child: Row(
                              children: [
                                Icon(
                                  entry.value.icono,
                                  size: 18,
                                  color: _azulPrimario,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.value.titulo,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _seccionActiva = value);
                            _scrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
                // Botón siguiente
                IconButton(
                  onPressed: _seccionActiva < _secciones.length - 1
                      ? () {
                          setState(() => _seccionActiva++);
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  color: _azulPrimario,
                  iconSize: 28,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),
          // Contador de sección
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_seccionActiva + 1} de ${_secciones.length}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
          // Contenido de la sección
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // Encabezado de sección
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_azulOscuro, Color(0xFF1A2A4A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _secciones[_seccionActiva].icono,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _secciones[_seccionActiva].titulo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Ilustración visual de la sección
                if (_secciones[_seccionActiva].elementosIlustracion.isNotEmpty)
                  _buildIlustracion(_secciones[_seccionActiva]),
                if (_secciones[_seccionActiva].elementosIlustracion.isNotEmpty)
                  const SizedBox(height: 16),
                // Pasos
                ..._secciones[_seccionActiva].pasos.asMap().entries.map((
                  entry,
                ) {
                  final index = entry.key;
                  final paso = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildPasoCard(index + 1, paso),
                  );
                }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIlustracion(_SeccionManual seccion) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: seccion.colorIlustracion.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: seccion.colorIlustracion.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Mockup de pantalla
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  seccion.colorIlustracion.withValues(alpha: 0.08),
                  seccion.colorIlustracion.withValues(alpha: 0.03),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Barra superior simulada
                Container(
                  height: 6,
                  width: 50,
                  decoration: BoxDecoration(
                    color: seccion.colorIlustracion.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                // Ícono principal grande
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: seccion.colorIlustracion.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    seccion.icono,
                    size: 48,
                    color: seccion.colorIlustracion,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  seccion.titulo,
                  style: TextStyle(
                    color: seccion.colorIlustracion,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                // Elementos de la ilustración
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: seccion.elementosIlustracion.map((elem) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: seccion.colorIlustracion.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            elem.icono,
                            size: 24,
                            color: seccion.colorIlustracion,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          elem.etiqueta,
                          style: TextStyle(
                            fontSize: 10,
                            color: seccion.colorIlustracion,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vista previa ilustrativa',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[400],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasoCard(int numero, _Paso paso) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _azulPrimario.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Número del paso
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _azulPrimario,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '$numero',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Contenido
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(paso.icono, size: 18, color: _azulPrimario),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          paso.titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _azulOscuro,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    paso.descripcion,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeccionManual {
  final String titulo;
  final IconData icono;
  final List<_Paso> pasos;
  final Color colorIlustracion;
  final List<_ElementoIlustracion> elementosIlustracion;

  const _SeccionManual({
    required this.titulo,
    required this.icono,
    required this.pasos,
    this.colorIlustracion = const Color(0xFF1565C0),
    this.elementosIlustracion = const [],
  });
}

class _Paso {
  final String titulo;
  final String descripcion;
  final IconData icono;

  const _Paso({
    required this.titulo,
    required this.descripcion,
    required this.icono,
  });
}

class _ElementoIlustracion {
  final IconData icono;
  final String etiqueta;

  const _ElementoIlustracion({required this.icono, required this.etiqueta});
}
