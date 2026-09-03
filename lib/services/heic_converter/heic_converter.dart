import 'dart:typed_data';

import 'heic_converter_stub.dart'
    if (dart.library.js_interop) 'heic_converter_web.dart' as impl;

/// Convierte una foto HEIC (el formato que usa la cámara del iPhone por
/// default) a JPEG, para que cualquier navegador la pueda mostrar.
///
/// Solo está implementado en la Web (`heic_converter_web.dart`, vía la
/// librería JS `heic2any` cargada en `web/index.html`). En cualquier otra
/// plataforma tira [UnsupportedError] -no hace falta ahí: en un iPhone
/// nativo, iOS ya sabe mostrar HEIC sin conversión-.
Future<Uint8List> convertirHeicAJpeg(Uint8List heicBytes) {
  return impl.convertirHeicAJpeg(heicBytes);
}

/// Si es `false`, esta plataforma no puede convertir HEIC y hay que
/// rechazar el archivo en vez de intentarlo.
bool get puedeConvertirHeic => impl.puedeConvertirHeic;
