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
