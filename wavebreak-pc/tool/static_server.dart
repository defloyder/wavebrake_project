// Minimal static file server for previewing build/web without any Node or
// Python dependency (only the bundled Dart SDK), since this box lacks both.
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 5099;
  final root = Directory(args.length > 1 ? args[1] : 'build/web');
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Serving ${root.path} on http://localhost:$port');

  await for (final request in server) {
    var path = request.uri.path;
    if (path == '/') path = '/index.html';
    var file = File('${root.path}$path');
    if (!file.existsSync()) file = File('${root.path}/index.html');

    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }

    final ext = file.path.split('.').last;
    request.response.headers.contentType = _contentType(ext);
    await request.response.addStream(file.openRead());
    await request.response.close();
  }
}

ContentType _contentType(String ext) {
  switch (ext) {
    case 'html':
      return ContentType.html;
    case 'js':
      return ContentType('application', 'javascript');
    case 'json':
      return ContentType.json;
    case 'css':
      return ContentType('text', 'css');
    case 'wasm':
      return ContentType('application', 'wasm');
    case 'png':
      return ContentType('image', 'png');
    case 'ico':
      return ContentType('image', 'x-icon');
    default:
      return ContentType.binary;
  }
}
