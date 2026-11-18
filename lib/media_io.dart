import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

/// Android : la vidéo privée est téléchargée une fois dans le cache, puis lue depuis le fichier.
Future<VideoPlayerController> privateVideo(
    String path, Future<Uint8List> Function() fetch) async {
  final f = File('${Directory.systemTemp.path}/bim-${path.replaceAll('/', '_')}');
  if (!await f.exists() || await f.length() == 0) await f.writeAsBytes(await fetch());
  return VideoPlayerController.file(f);
}
