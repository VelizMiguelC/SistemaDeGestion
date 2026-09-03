import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/equipo_fotos_service.dart';

/// Sección de fotos dentro del formulario de un equipo (iPhone o Android).
///
/// Es un campo controlado: el padre guarda la lista de URLs en su propio
/// estado (`fotos`) y este widget solo la muestra y avisa por [onChanged]
/// cuando cambia. La subida a Firebase Storage ocurre acá adentro, al
/// elegir cada foto -no al guardar el formulario-, para que el dueño vea de
/// una si una foto falló en vez de enterarse recién al tocar "Guardar".
///
/// El bot de WhatsApp lee estas mismas URLs para mandárselas a un cliente
/// que las pida: solo deberían subirse acá fotos presentables.
class EquipoFotosField extends StatefulWidget {
  final List<String> fotos;
  final ValueChanged<List<String>> onChanged;

  /// Identificador para agrupar los archivos de este equipo en Storage.
  /// No hace falta que sea el IMEI ni el ID de Firestore.
  final String carpeta;

  const EquipoFotosField({
    super.key,
    required this.fotos,
    required this.onChanged,
    required this.carpeta,
  });

  @override
  State<EquipoFotosField> createState() => _EquipoFotosFieldState();
}

class _EquipoFotosFieldState extends State<EquipoFotosField> {
  final _service = EquipoFotosService();

  /// Fotos que se están subiendo en este momento (para mostrar su spinner).
  final List<XFile> _subiendo = [];

  Future<void> _agregarFotos() async {
    final List<XFile> elegidas;
    try {
      elegidas = await _service.elegirFotos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo abrir la galería: $e')));
      }
      return;
    }
    if (elegidas.isEmpty) return;

    // Se suben de a una: así el spinner de cada tarjeta refleja el progreso
    // real en vez de que todas terminen juntas al final.
    for (final archivo in elegidas) {
      if (_service.esFormatoNoSoportado(archivo)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '"${archivo.name}" está en formato HEIC (el que usa la cámara del iPhone por '
                'default) y no se puede mostrar. Elegí "Compartir → Guardar en Archivos" y '
                'convertila a JPG, o cambiá el formato de la cámara en el iPhone: Ajustes → '
                'Cámara → Formatos → "Más compatible".',
              ),
              duration: const Duration(seconds: 8),
            ),
          );
        }
        continue;
      }
      setState(() => _subiendo.add(archivo));
      try {
        final url = await _service.subirFoto(carpeta: widget.carpeta, archivo: archivo);
        widget.onChanged([...widget.fotos, url]);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo subir "${archivo.name}": $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _subiendo.remove(archivo));
      }
    }
  }

  Future<void> _eliminarFoto(String url) async {
    // Optimista: sale de la lista al toque. Si falla el borrado remoto no
    // se revierte -preferible un archivo huérfano en Storage a que la foto
    // reaparezca sola sin que el usuario lo espere-.
    widget.onChanged(widget.fotos.where((f) => f != url).toList());
    try {
      await _service.eliminarFoto(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se quitó de la lista, pero no se pudo borrar del todo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fotos', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          'Las ve el cliente si le pide fotos por WhatsApp.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final url in widget.fotos)
              _FotoThumbnail(url: url, onEliminar: () => _eliminarFoto(url)),
            for (final _ in _subiendo) const _FotoSubiendo(),
            _BotonAgregarFoto(onTap: _agregarFotos),
          ],
        ),
      ],
    );
  }
}

const _tamanoTarjeta = 76.0;

class _FotoThumbnail extends StatelessWidget {
  final String url;
  final VoidCallback onEliminar;

  const _FotoThumbnail({required this.url, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            url,
            width: _tamanoTarjeta,
            height: _tamanoTarjeta,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(
                width: _tamanoTarjeta,
                height: _tamanoTarjeta,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              width: _tamanoTarjeta,
              height: _tamanoTarjeta,
              color: Theme.of(context).colorScheme.errorContainer,
              child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onErrorContainer),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onEliminar,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.onError),
            ),
          ),
        ),
      ],
    );
  }
}

class _FotoSubiendo extends StatelessWidget {
  const _FotoSubiendo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _tamanoTarjeta,
      height: _tamanoTarjeta,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _BotonAgregarFoto extends StatelessWidget {
  final VoidCallback onTap;

  const _BotonAgregarFoto({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: _tamanoTarjeta,
        height: _tamanoTarjeta,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Icon(Icons.add_a_photo_outlined, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
