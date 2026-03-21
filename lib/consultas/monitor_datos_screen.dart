import 'dart:async';
import 'package:estacionamientotarifado/servicios/monitorDatos.dart';
import 'package:estacionamientotarifado/servicios/servicioWebSocket.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MonitorDatosScreen extends StatefulWidget {
  const MonitorDatosScreen({super.key});

  @override
  State<MonitorDatosScreen> createState() => _MonitorDatosScreenState();
}

class _MonitorDatosScreenState extends State<MonitorDatosScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF0A1628);
  static const Color _accent = Color(0xFF1565C0);
  static const Color _fondo = Color(0xFFF0F4FF);

  final MonitorDatos _monitor = MonitorDatos.instancia;
  late TabController _tabController;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _sub = _monitor.onCambio.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  void _mostrarInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A1628), Color(0xFF000000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Información',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Monitor de Consumo',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Muestra estadísticas de uso de red, solicitudes HTTP y estado del WebSocket en tiempo real.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendido'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Monitor de Consumo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A1628), Color(0xFF000000)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Información',
            onPressed: () => _mostrarInfo(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) async {
              if (v == 'reset_sesion') {
                _monitor.resetearSesion();
              } else if (v == 'reset_todo') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reiniciar todo'),
                    content: const Text(
                      '¿Eliminar todos los datos de consumo acumulados?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reiniciar'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await _monitor.resetearTodo();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'reset_sesion',
                child: Text('Reiniciar sesión'),
              ),
              PopupMenuItem(value: 'reset_todo', child: Text('Reiniciar todo')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Resumen', icon: Icon(Icons.pie_chart_rounded, size: 20)),
            Tab(text: 'Historial', icon: Icon(Icons.history_rounded, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildResumen(), _buildHistorial()],
      ),
    );
  }

  // ── Tab Resumen ───────────────────────────────────────────────────────────

  Widget _buildResumen() {
    final wsStatus = ServicioWebSocket.instancia.conectado;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Estado de conexión
          _buildEstadoConexion(wsStatus),
          const SizedBox(height: 16),

          // Tarjeta principal: consumo sesión
          _buildTarjetaConsumo(
            titulo: 'Esta sesión',
            icono: Icons.timer_rounded,
            color: _accent,
            enviados: _monitor.bytesEnviadosSesion,
            recibidos: _monitor.bytesRecibidosSesion,
            total: _monitor.totalBytesSesion,
          ),
          const SizedBox(height: 12),

          // Tarjeta: consumo acumulado
          _buildTarjetaConsumo(
            titulo: 'Acumulado total',
            icono: Icons.data_usage_rounded,
            color: _primary,
            enviados: _monitor.bytesEnviadosTotal,
            recibidos: _monitor.bytesRecibidosTotal,
            total: _monitor.totalBytesTotal,
          ),
          const SizedBox(height: 16),

          // Métricas detalladas
          const Text(
            'Detalles de la sesión',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _primary,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _buildMetricaCard(
                  'Requests HTTP',
                  _monitor.requestsSesion.toString(),
                  Icons.http_rounded,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricaCard(
                  'Mensajes WS',
                  _monitor.wsMessagesSesion.toString(),
                  Icons.cable_rounded,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricaCard(
                  'HTTP recibido',
                  MonitorDatos.formatBytes(
                    _monitor.bytesRecibidosSesion -
                        _monitor.wsBytesRecibidosSesion,
                  ),
                  Icons.download_rounded,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricaCard(
                  'WS recibido',
                  MonitorDatos.formatBytes(_monitor.wsBytesRecibidosSesion),
                  Icons.cable_rounded,
                  Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricaCard(
                  'Requests totales',
                  _monitor.requestsTotal.toString(),
                  Icons.storage_rounded,
                  Colors.deepPurple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricaCard(
                  'Total enviado',
                  MonitorDatos.formatBytes(_monitor.bytesEnviadosTotal),
                  Icons.upload_rounded,
                  Colors.indigo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoConexion(bool wsConectado) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: wsConectado ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: wsConectado ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            wsConectado ? Icons.cable_rounded : Icons.http_rounded,
            color: wsConectado ? Colors.green.shade700 : Colors.orange.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wsConectado
                      ? 'WebSocket activo — Bajo consumo'
                      : 'Modo HTTP polling — Mayor consumo',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: wsConectado
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
                Text(
                  wsConectado
                      ? 'Los datos se reciben en tiempo real sin polling'
                      : 'Se hacen consultas periódicas al servidor',
                  style: TextStyle(
                    fontSize: 11,
                    color: wsConectado
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: wsConectado ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (wsConectado ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaConsumo({
    required String titulo,
    required IconData icono,
    required Color color,
    required int enviados,
    required int recibidos,
    required int total,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Text(
                MonitorDatos.formatBytes(total),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Barra de proporción enviados/recibidos
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (total > 0)
                    Flexible(
                      flex: enviados > 0 ? enviados : 1,
                      child: Container(color: Colors.blue.shade400),
                    ),
                  if (total > 0)
                    Flexible(
                      flex: recibidos > 0 ? recibidos : 1,
                      child: Container(color: Colors.green.shade400),
                    ),
                  if (total == 0)
                    Expanded(child: Container(color: Colors.grey.shade200)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Enviados: ${MonitorDatos.formatBytes(enviados)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Recibidos: ${MonitorDatos.formatBytes(recibidos)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricaCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab Historial ─────────────────────────────────────────────────────────

  Widget _buildHistorial() {
    final historial = _monitor.historial;
    if (historial.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Sin actividad de red registrada',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: historial.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) => _buildHistorialItem(historial[i]),
    );
  }

  Widget _buildHistorialItem(RegistroDatos reg) {
    final esWs = reg.tipo == TipoDato.websocket;
    final color = esWs ? Colors.green : Colors.blue;
    final hora = DateFormat('HH:mm:ss').format(reg.timestamp);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                esWs ? 'WS' : reg.metodo.substring(0, 1),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reg.endpoint,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hora,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                MonitorDatos.formatBytes(reg.totalBytes),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (!esWs && reg.statusCode > 0)
                Text(
                  '${reg.statusCode}',
                  style: TextStyle(
                    fontSize: 10,
                    color: reg.statusCode >= 400
                        ? Colors.red.shade600
                        : Colors.grey.shade500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
