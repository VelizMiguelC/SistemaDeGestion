import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'heic_converter/heic_converter.dart' as heic;

/// Se tira cuando una foto no se puede subir por su formato, con un mensaje
/// ya redactado para mostrárselo directo al usuario -sin `Exception:` ni
/// texto técnico adelante-.
class FormatoNoSoportadoException implements Exception {
  final String mensaje;
  FormatoNoSoportadoException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Sube y borra las fotos de un equipo (iPhone o Android) en Firebase
/// Storage.
///
/// Las fotos se guardan bajo `equipos/{carpeta}/{uuid}.jpg`. `carpeta` es un
/// identificador cualquiera para agrupar los archivos de un mismo equipo -no
/// hace falta que sea el IMEI ni el ID de Firestore, porque en Android el
/// IMEI es opcional y un equipo nuevo todavía no tiene ID hasta guardarse-.
class EquipoFotosService {
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  /// Abre el selector nativo y deja elegir varias fotos a la vez.
  /// Se comprimen acá mismo (calidad y ancho máximo) para no subir fotos de
  /// 10-15MB tal cual salen de una cámara moderna: eso demora la subida y
  /// después el bot las tiene que volver a mandar por WhatsApp.
  Future<List<XFile>> elegirFotos() {
    return _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
  }

  /// Un iPhone guarda las fotos en HEIC por default, formato que ningún
  /// navegador puede decodificar. `subirFoto` la convierte a JPEG sola
  /// antes de subirla; esto solo sirve para detectar el caso.
  bool esHeic(XFile archivo) {
    final mime = archivo.mimeType?.toLowerCase() ?? '';
    if (mime.contains('heic') || mime.contains('heif')) return true;
    final nombre = archivo.name.toLowerCase();
    return nombre.endsWith('.heic') || nombre.endsWith('.heif');
  }

  /// Sube una foto ya elegida y devuelve la URL pública de descarga.
  /// Si es HEIC, la convierte a JPEG antes -ver [heic.convertirHeicAJpeg]-.
  Future<String> subirFoto({required String carpeta, required XFile archivo}) async {
    var bytes = await archivo.readAsBytes();
    var contentType = archivo.mimeType ?? 'image/jpeg';
    var extension = _extensionDe(archivo.name);

    if (esHeic(archivo)) {
      if (!heic.puedeConvertirHeic) {
        throw FormatoNoSoportadoException(
          '"${archivo.name}" está en formato HEIC (el que usa la cámara del '
          'iPhone por default) y esta versión de la app no lo puede convertir. '
          'Cambiá el formato de cámara del iPhone a "Más compatible" en '
          'Ajustes → Cámara → Formatos, o convertila a JPG antes de subirla.',
        );
      }
      try {
        bytes = await heic.convertirHeicAJpeg(bytes);
      } catch (e) {
        throw FormatoNoSoportadoException(
          'No se pudo convertir "${archivo.name}" de HEIC a JPG ($e). '
          'Probá cambiando el formato de cámara del iPhone a "Más compatible" '
          'en Ajustes → Cámara → Formatos.',
        );
      }
      contentType = 'image/jpeg';
      extension = 'jpg';
    }

    final ref = _storage.ref('equipos/$carpeta/${_uuid.v4()}.$extension');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Borra una foto a partir de su URL de descarga.
  Future<void> eliminarFoto(String url) async {
    await _storage.refFromURL(url).delete();
  }

  String _extensionDe(String nombreArchivo) {
    final punto = nombreArchivo.lastIndexOf('.');
    if (punto == -1 || punto == nombreArchivo.length - 1) return 'jpg';
    return nombreArchivo.substring(punto + 1).toLowerCase();
  }
}
