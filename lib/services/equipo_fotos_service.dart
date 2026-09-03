import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

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

  /// Un iPhone guarda las fotos en HEIC por default. Ningún navegador sabe
  /// mostrar ese formato (ni tampoco, después, WhatsApp al mandarla a un
  /// Android desde el bot), así que se rechaza antes de subir en vez de
  /// dejar una foto rota en el equipo. El propio `imageQuality` del picker
  /// no la convierte: en la web no hay forma de decodificar HEIC para
  /// recomprimirla, porque el navegador tampoco puede leerla.
  bool esFormatoNoSoportado(XFile archivo) {
    final mime = archivo.mimeType?.toLowerCase() ?? '';
    if (mime.contains('heic') || mime.contains('heif')) return true;
    final nombre = archivo.name.toLowerCase();
    return nombre.endsWith('.heic') || nombre.endsWith('.heif');
  }

  /// Sube una foto ya elegida y devuelve la URL pública de descarga.
  Future<String> subirFoto({required String carpeta, required XFile archivo}) async {
    final bytes = await archivo.readAsBytes();
    final extension = _extensionDe(archivo.name);
    final ref = _storage.ref('equipos/$carpeta/${_uuid.v4()}.$extension');

    await ref.putData(
      bytes,
      SettableMetadata(contentType: archivo.mimeType ?? 'image/jpeg'),
    );
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
