import 'package:estacionamientotarifado/core/colores.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CampoBusquedaApp extends StatelessWidget {
  const CampoBusquedaApp({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSearch,
    this.labelText,
    this.onChanged,
    this.onClear,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.filledColor,
    this.enabled = true,
    this.autofocus = false,
    this.compacto = true,
  });

  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final VoidCallback onSearch;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Color? filledColor;
  final bool enabled;
  final bool autofocus;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final tieneTexto = controller.text.trim().isNotEmpty;
    final radio = compacto ? 12.0 : 14.0;
    final paddingHorizontal = compacto ? 14.0 : 16.0;
    final paddingVertical = compacto ? 12.0 : 14.0;
    final anchoSufijo = tieneTexto ? (compacto ? 88.0 : 96.0) : 52.0;
    final iconoTamano = compacto ? 20.0 : 22.0;

    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 16),
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        isDense: compacto,
        labelText: labelText,
        hintText: hintText,
        filled: true,
        fillColor: filledColor ?? AppColores.acentoFondo,
        contentPadding: EdgeInsets.symmetric(
          horizontal: paddingHorizontal,
          vertical: paddingVertical,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radio),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radio),
          borderSide: BorderSide(color: AppColores.borde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radio),
          borderSide: const BorderSide(color: AppColores.acentoAdmin, width: 2),
        ),
        suffixIcon: SizedBox(
          width: anchoSufijo,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tieneTexto)
                IconButton(
                  tooltip: 'Limpiar',
                  icon: const Icon(
                    Icons.clear_rounded,
                    color: AppColores.textoTerciario,
                  ),
                  iconSize: iconoTamano,
                  splashRadius: compacto ? 18 : 20,
                  onPressed: () {
                    controller.clear();
                    if (onClear != null) {
                      onClear!();
                    } else if (onChanged != null) {
                      onChanged!('');
                    }
                  },
                ),
              IconButton(
                tooltip: 'Buscar',
                icon: const Icon(
                  Icons.search_rounded,
                  color: AppColores.acentoAdmin,
                ),
                iconSize: iconoTamano,
                splashRadius: compacto ? 18 : 20,
                onPressed: enabled ? onSearch : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
