import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const bool puedeConvertirHeic = true;

/// Firma JS de `heic2any({ blob, toType, quality })`, cargada como
/// `<script>` global en web/index.html. Devuelve una Promise que resuelve a
/// un Blob (o a un array de Blobs si el HEIC trae varias imágenes, como en
/// un burst de fotos -no es el caso normal al fotografiar un equipo, pero
/// se contempla igual-).
@JS('heic2any')
external JSPromise<JSAny?> _heic2any(_Heic2AnyOptions options);

extension type _Heic2AnyOptions._(JSObject _) implements JSObject {
  external factory _Heic2AnyOptions({
    web.Blob blob,
    String toType,
    num quality,
  });
}

Future<Uint8List> convertirHeicAJpeg(Uint8List heicBytes) async {
  final blobOriginal = web.Blob(
    [heicBytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/heic'),
  );

  final resultado = await _heic2any(
    _Heic2AnyOptions(blob: blobOriginal, toType: 'image/jpeg', quality: 0.8),
  ).toDart;

  if (resultado == null) {
    throw StateError('heic2any no devolvió nada.');
  }

  // Si el HEIC tenía varias imágenes adentro (ej: un burst), nos quedamos
  // con la primera: es la única que el resto de la app puede mostrar.
  final web.Blob blobConvertido = resultado.isA<JSArray>()
      ? (resultado as JSArray).toDart.first as web.Blob
      : resultado as web.Blob;

  final buffer = await blobConvertido.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
