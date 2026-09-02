/// Configuración específica de este despliegue.
///
/// Al clonar la app para un negocio nuevo, este es el único archivo Dart
/// que hace falta tocar para que se vea como "su" app (nombre en el
/// login, el menú y la pestaña del navegador) -el resto del código es el
/// mismo para todos los clones-.
///
/// Ojo: `web/manifest.json` y `web/index.html` son archivos estáticos que
/// el navegador lee ANTES de que arranque Flutter (el ícono al agregar a
/// pantalla de inicio, el <title> de la pestaña), así que esos dos hay que
/// editarlos aparte -no leen este archivo-.
class AppConfig {
  static const nombreApp = 'iPhone Stock Manager';
}
