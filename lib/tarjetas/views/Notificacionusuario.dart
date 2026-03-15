import 'dart:async' show unawaited;
import 'package:estacionamientotarifado/servicios/servicioNotificaciones2.dart';
import 'package:estacionamientotarifado/tarjetas/models/Notificaciones2.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificacionesUsuarioScreen extends StatefulWidget {
  final bool mostrarSoloMesActual;

  const NotificacionesUsuarioScreen({
    super.key,
    this.mostrarSoloMesActual = true,
  });

  /// Llama esto desde HomeScreen para pre-cargar las notificaciones del mes en caché.
  static Future<void> preWarmCache(int userId) async {
    final existing = await NotifMesCache.leer(userId);
    if (existing != null && existing.isNotEmpty) return; // ya hay caché
    try {
      final svc = NotificacionService();
      final todas = await svc.getNotificaciones();
      final delMes = svc.filtrarNotificacionesMesActual(todas);
      if (delMes.isNotEmpty) await NotifMesCache.guardar(userId, delMes);
    } catch (_) {
      // Silencioso — se cargará al entrar a la pantalla
    }
  }

  @override
  State<NotificacionesUsuarioScreen> createState() =>
      _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesUsuarioScreen>
    with SingleTickerProviderStateMixin {
  // ─── Design tokens ────────────────────────────────────────────────────────
  static const Color _colorPrimario = Color(0xFF001F54);
  static const Color _colorSecundario = Color(0xFF5E17EB);
  static const Color _colorFondo = Color(0xFFF0F4FF);
  static const Color _colorTexto = Color(0xFF333333);

  // ─── State ────────────────────────────────────────────────────────────────
  final NotificacionService _svc = NotificacionService();
  late TabController _tabController;

  List<Notificacion> _notificaciones = [];
  Map<String, List<Notificacion>> _grupos = {
    'pagadas': [],
    'impagas': [],
    'impugnadas': [],
  };

  bool _cargando = true;
  String? _error;
  bool _mostrarSoloMesActual = true;
  String _operador = '';

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mostrarSoloMesActual = widget.mostrarSoloMesActual;
    _cargar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Data ─────────────────────────────────────────────────────────────────

  List<Notificacion> _ordenarLista(List<Notificacion> lista) {
    final copia = List<Notificacion>.from(lista);
    copia.sort((a, b) {
      try {
        return DateTime.parse(
          b.fechaEmision,
        ).compareTo(DateTime.parse(a.fechaEmision));
      } catch (_) {
        return 0;
      }
    });
    return copia;
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final op = prefs.getString('username') ?? 'OPERADOR';
    final userId = prefs.getInt('id') ?? 0;

    if (_mostrarSoloMesActual) {
      // ── Caché primero: mostrar datos guardados al instante ────────────────
      final cached = await NotifMesCache.leer(userId);
      if (cached != null && cached.isNotEmpty) {
        final ordenadas = _ordenarLista(cached);
        if (mounted) {
          setState(() {
            _operador = op.toUpperCase();
            _notificaciones = ordenadas;
            _grupos = _svc.agruparPorEstado(ordenadas);
            _cargando = false;
          });
        }
        // Actualizar en segundo plano sin mostrar spinner
        unawaited(_refrescarSilencioso(userId));
        return;
      }
    }

    // ── Sin caché: carga completa con indicador ───────────────────────────
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      List<Notificacion> lista;
      if (_mostrarSoloMesActual) {
        final todas = await _svc.getNotificaciones();
        lista = _svc.filtrarNotificacionesMesActual(todas);
        await NotifMesCache.guardar(userId, lista);
      } else {
        lista = await _svc.getTodasNotificacionesUsuario();
      }

      lista = _ordenarLista(lista);
      if (mounted) {
        setState(() {
          _operador = op.toUpperCase();
          _notificaciones = lista;
          _grupos = _svc.agruparPorEstado(lista);
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  /// Consulta la API silenciosamente. Si hay diferencias respecto al caché
  /// (multas nuevas o cambios de estado), actualiza caché y refresca la UI.
  Future<void> _refrescarSilencioso(int userId) async {
    try {
      final todas = await _svc.getNotificaciones();
      final delMes = _svc.filtrarNotificacionesMesActual(todas);
      final enCache = await NotifMesCache.leer(userId) ?? [];
      if (NotifMesCache.tieneDiferencias(enCache, delMes)) {
        await NotifMesCache.guardar(userId, delMes);
        final ordenadas = _ordenarLista(delMes);
        if (mounted) {
          setState(() {
            _notificaciones = ordenadas;
            _grupos = _svc.agruparPorEstado(ordenadas);
          });
        }
      }
    } catch (_) {
      // Silencioso — no interrumpir la experiencia del usuario
    }
  }

  void _alternarVista() {
    setState(() => _mostrarSoloMesActual = !_mostrarSoloMesActual);
    _cargar();
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final pagadas = _grupos['pagadas']!.length;
    final impagas = _grupos['impagas']!.length;
    final impugnadas = _grupos['impugnadas']!.length;

    return AppBar(
      centerTitle: true,
      title: Text(
        _mostrarSoloMesActual ? 'Multas del Mes' : 'Historial de Multas',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _mostrarSoloMesActual ? Icons.history : Icons.calendar_month,
            color: Colors.white,
          ),
          tooltip: _mostrarSoloMesActual
              ? 'Ver historial completo'
              : 'Ver solo este mes',
          onPressed: _alternarVista,
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Actualizar',
          onPressed: _cargar,
        ),
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_colorPrimario, _colorSecundario],
          ),
        ),
      ),
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        tabs: [
          _buildTab(Icons.check_circle_outline, 'Pagadas', pagadas),
          _buildTab(Icons.pending_outlined, 'Impagas', impagas),
          _buildTab(Icons.gavel_outlined, 'Impugnadas', impugnadas),
        ],
      ),
    );
  }

  Tab _buildTab(IconData icon, String label, int count) {
    return Tab(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15),
          const SizedBox(height: 2),
          Text('$label ($count)', style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Body ─────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_cargando) return _buildCargando();
    if (_error != null) return _buildError();
    if (_notificaciones.isEmpty) return _buildVacio();

    return TabBarView(
      controller: _tabController,
      children: [
        _buildLista(_grupos['pagadas']!, 'pagadas'),
        _buildLista(_grupos['impagas']!, 'impagas'),
        _buildLista(_grupos['impugnadas']!, 'impugnadas'),
      ],
    );
  }

  // ─── Loading / Error / Empty ───────────────────────────────────────────────
  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, _colorSecundario],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'SIMERT',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _colorPrimario,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cargando notificaciones...',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(_colorSecundario),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    String msg = _error ?? 'Error desconocido';
    if (msg.contains('Null is not a subtype')) {
      msg = 'Error en el formato de datos recibidos.';
    } else if (msg.contains('No se encontró el ID')) {
      msg = 'Sesión expirada. Por favor inicie sesión nuevamente.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.red.shade400,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Error al cargar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _colorTexto,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade600, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorPrimario,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _colorPrimario.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              color: _colorPrimario,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _mostrarSoloMesActual
                ? 'Sin multas este mes'
                : 'Sin multas registradas',
            style: const TextStyle(
              color: _colorPrimario,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _operador,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ─── Lista ────────────────────────────────────────────────────────────────
  Widget _buildLista(List<Notificacion> lista, String tipo) {
    if (lista.isEmpty) return _buildVacioTab(tipo);

    return RefreshIndicator(
      color: _colorPrimario,
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: lista.length,
        itemBuilder: (_, i) => _buildCard(lista[i], tipo),
      ),
    );
  }

  Widget _buildVacioTab(String tipo) {
    final IconData icon;
    final String msg;
    final Color color;

    switch (tipo) {
      case 'pagadas':
        icon = Icons.check_circle_outline;
        msg = 'Sin multas pagadas';
        color = Colors.green;
        break;
      case 'impagas':
        icon = Icons.pending_outlined;
        msg = 'Sin multas pendientes';
        color = Colors.orange;
        break;
      default:
        icon = Icons.gavel_outlined;
        msg = 'Sin multas impugnadas';
        color = Colors.purple;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            msg,
            style: const TextStyle(
              color: _colorTexto,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Card ─────────────────────────────────────────────────────────────────
  Widget _buildCard(Notificacion n, String tipo) {
    final Color badgeColor;
    final String badgeText;
    final IconData badgeIcon;

    switch (tipo) {
      case 'pagadas':
        badgeColor = Colors.green;
        badgeText = 'PAGADO';
        badgeIcon = Icons.check_circle;
        break;
      case 'impagas':
        badgeColor = Colors.orange;
        badgeText = 'IMPAGO';
        badgeIcon = Icons.schedule;
        break;
      default:
        badgeColor = Colors.purple;
        badgeText = 'IMPUGNADO';
        badgeIcon = Icons.gavel;
    }

    final fechaHora = _formatearFechaHora(n.fechaEmision);
    final inicial = n.placa.isNotEmpty ? n.placa[0].toUpperCase() : '?';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 2,
      shadowColor: badgeColor.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: badgeColor.withValues(alpha: 0.3), width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: badgeColor.withValues(alpha: 0.12),
              child: Text(
                inicial,
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.placa,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _colorPrimario,
                    ),
                  ),
                  Text(
                    n.nombres,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    fechaHora,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, color: badgeColor, size: 11),
                            const SizedBox(width: 4),
                            Text(
                              badgeText,
                              style: TextStyle(
                                color: badgeColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'N° ${n.numero}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  String _formatearFechaHora(String fechaStr) {
    try {
      final dt = DateTime.parse(fechaStr);
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final anio = dt.year.toString();
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes/$anio  $hora:$min';
    } catch (_) {
      return fechaStr;
    }
  }
}
