import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// Web : la vidéo privée est téléchargée en mémoire et lue depuis une adresse locale au navigateur.
Future<VideoPlayerController> privateVideo(
    String path, Future<Uint8List> Function() fetch) async {
  final bytes = await fetch();
  final type = path.toLowerCase().endsWith('.webm')
      ? 'video/webm'
      : path.toLowerCase().endsWith('.mov')
          ? 'video/quicktime'
          : 'video/mp4';
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type));
  return VideoPlayerController.networkUrl(Uri.parse(web.URL.createObjectURL(blob)));
}
