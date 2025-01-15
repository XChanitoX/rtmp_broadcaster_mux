// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rtmp_broadcaster/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock/wakelock.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraExampleHome extends StatefulWidget {
  const CameraExampleHome({super.key});

  @override
  CameraExampleHomeState createState() {
    return CameraExampleHomeState();
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection? direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
    default:
      return Icons.camera;
  }
}

void logError(String code, String message) =>
    debugPrint('Error: $code\nError Message: $message');

class CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver {
  static const String DEFAULT_RTMP_URL = "rtmp://global-live.mux.com:5222/app";
  static const String DEFAULT_RTMPS_URL = "rtmps://global-live.mux.com:443/app";
  static const String SRT_URL = "srt://global-live.mux.com:6001";
  static const String VIDEO_DIRECTORY = "Movies/flutter_test";
  static const String PHOTO_DIRECTORY = "Pictures/flutter_test";

  final TextEditingController _textFieldController =
      TextEditingController(text: DEFAULT_RTMP_URL);
  final TextEditingController _streamKeyController = TextEditingController();

  CameraController? controller;
  String? imagePath;
  String? videoPath;
  String? url;
  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  bool enableAudio = true;
  bool useOpenGL = true;

  bool get isStreaming => controller?.value.isStreamingVideoRtmp ?? false;
  bool isVisible = true;

  bool get isControllerInitialized => controller?.value.isInitialized ?? false;

  bool get isStreamingVideoRtmp =>
      controller?.value.isStreamingVideoRtmp ?? false;

  bool get isRecordingVideo => controller?.value.isRecordingVideo ?? false;

  bool get isRecordingPaused => controller?.value.isRecordingPaused ?? false;

  bool get isStreamingPaused => controller?.value.isStreamingPaused ?? false;

  bool get isTakingPicture => controller?.value.isTakingPicture ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Liberar recursos
    controller?.dispose();
    videoController?.dispose();
    _textFieldController.dispose();
    _streamKeyController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    Wakelock.disable();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    // App state changed before we got the chance to initialize.
    if (controller == null || !isControllerInitialized) {
      return;
    }
    if (state == AppLifecycleState.paused) {
      isVisible = false;
      if (isStreaming) {
        await pauseVideoStreaming();
      }
    } else if (state == AppLifecycleState.resumed) {
      isVisible = true;
      if (controller != null) {
        if (isStreaming) {
          await resumeVideoStreaming();
        } else {
          onNewCameraSelected(controller!.description);
        }
      }
    }
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;

    if (controller != null) {
      if (controller!.value.isRecordingVideo ?? false) {
        color = Colors.redAccent;
      } else if (controller!.value.isStreamingVideoRtmp ?? false) {
        color = Colors.blueAccent;
      }
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Camera example'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color: color,
                  width: 3.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: Center(
                  child: _cameraPreviewWidget(),
                ),
              ),
            ),
          ),
          _captureControlRowWidget(),
          _toggleAudioWidget(),
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                _cameraTogglesRowWidget(),
                _thumbnailWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !isControllerInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller!.value.aspectRatio,
      child: CameraPreview(controller!),
    );
  }

  /// Toggle recording audio
  Widget _toggleAudioWidget() {
    return Padding(
      padding: const EdgeInsets.only(left: 25),
      child: Row(
        children: <Widget>[
          const Text('Enable Audio:'),
          Switch(
            value: enableAudio,
            onChanged: (bool value) {
              enableAudio = value;
              if (controller != null) {
                onNewCameraSelected(controller!.description);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Display the thumbnail of the captured image or video.
  Widget _thumbnailWidget() {
    return Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            videoController == null && imagePath == null
                ? Container()
                : SizedBox(
                    width: 64.0,
                    height: 64.0,
                    child: (videoController == null)
                        ? Image.file(File(imagePath!))
                        : Container(
                            decoration: BoxDecoration(
                                border: Border.all(color: Colors.pink)),
                            child: Center(
                              child: AspectRatio(
                                  aspectRatio:
                                      videoController!.value.aspectRatio,
                                  child: VideoPlayer(videoController!)),
                            ),
                          ),
                  ),
          ],
        ),
      ),
    );
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    if (controller == null) return Container();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.camera_alt),
          color: Colors.blue,
          onPressed: controller != null && isControllerInitialized
              ? onTakePictureButtonPressed
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.videocam),
          color: Colors.blue,
          onPressed:
              controller != null && isControllerInitialized && !isRecordingVideo
                  ? onVideoRecordButtonPressed
                  : null,
        ),
        IconButton(
          icon: const Icon(Icons.watch),
          color: Colors.blue,
          onPressed: controller != null &&
                  isControllerInitialized &&
                  !isStreamingVideoRtmp
              ? onVideoStreamingButtonPressed
              : null,
        ),
        IconButton(
          icon: controller != null && (isRecordingPaused || isStreamingPaused)
              ? const Icon(Icons.play_arrow)
              : const Icon(Icons.pause),
          color: Colors.blue,
          onPressed: controller != null &&
                  isControllerInitialized &&
                  (isRecordingVideo || isStreamingVideoRtmp)
              ? (controller != null && (isRecordingPaused || isStreamingPaused)
                  ? onResumeButtonPressed
                  : onPauseButtonPressed)
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.stop),
          color: Colors.red,
          onPressed: controller != null &&
                  isControllerInitialized &&
                  (isRecordingVideo || isStreamingVideoRtmp)
              ? onStopButtonPressed
              : null,
        )
      ],
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    final List<Widget> toggles = <Widget>[];

    if (cameras.isEmpty) {
      return const Text('No camera found');
    } else {
      for (CameraDescription cameraDescription in cameras) {
        toggles.add(
          SizedBox(
            width: 90.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: (CameraDescription? cld) =>
                  isRecordingVideo ? null : onNewCameraSelected(cld),
            ),
          ),
        );
      }
    }

    return Row(children: toggles);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onNewCameraSelected(CameraDescription? cameraDescription) async {
    if (cameraDescription == null) return;

    if (controller != null) {
      await stopVideoStreaming();
      await controller?.dispose();
    }
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: enableAudio,
      androidUseOpenGL: useOpenGL,
    );

    // If the controller is updated then update the UI.
    controller!.addListener(() async {
      if (mounted) setState(() {});

      if (controller != null) {
        if (controller!.value.hasError) {
          showInSnackBar('Camera error ${controller!.value.errorDescription}');
          await stopVideoStreaming();
        } else {
          try {
            final Map<dynamic, dynamic> event =
                controller!.value.event as Map<dynamic, dynamic>;
            debugPrint('Event $event');
            final String eventType = event['eventType'] as String;
            if (isVisible && isStreaming && eventType == 'rtmp_retry') {
              showInSnackBar('BadName received, endpoint in use.');
              await stopVideoStreaming();
            }
          } catch (e) {
            debugPrint(e.toString());
          }
        }
      }
    });

    try {
      await controller!.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((String? filePath) {
      if (mounted) {
        setState(() {
          imagePath = filePath;
          videoController?.dispose();
          videoController = null;
        });
        showInSnackBar('Picture saved to $filePath');
      }
    });
  }

  void onVideoRecordButtonPressed() {
    startVideoRecording().then((String? filePath) {
      if (mounted) setState(() {});
      showInSnackBar('Saving video to $filePath');
      Wakelock.enable();
    });
  }

  void onVideoStreamingButtonPressed() {
    startVideoStreaming().then((String? url) {
      if (mounted) setState(() {});
      showInSnackBar('Streaming video to $url');
      Wakelock.enable();
    });
  }

  void onRecordingAndVideoStreamingButtonPressed() {
    startRecordingAndVideoStreaming().then((String? url) {
      if (mounted) setState(() {});
      showInSnackBar('Recording streaming video to $url');
      Wakelock.enable();
    });
  }

  void onStopButtonPressed() {
    if (isStreamingVideoRtmp) {
      stopVideoStreaming().then((_) {
        if (mounted) setState(() {});
        showInSnackBar('Video streamed to: $url');
      });
    } else {
      stopVideoRecording().then((_) {
        if (mounted) setState(() {});
        showInSnackBar('Video recorded to: $videoPath');
      });
    }
    Wakelock.disable();
  }

  void onPauseButtonPressed() {
    pauseVideoRecording().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video recording paused');
    });
  }

  void onResumeButtonPressed() {
    resumeVideoRecording().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video recording resumed');
    });
  }

  void onStopStreamingButtonPressed() {
    stopVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video not streaming to: $url');
    });
  }

  void onPauseStreamingButtonPressed() {
    pauseVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video streaming paused');
    });
  }

  void onResumeStreamingButtonPressed() {
    resumeVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video streaming resumed');
    });
  }

  Future<String?> startVideoRecording() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    final Directory? extDir = await getExternalStorageDirectory();
    if (extDir == null) return null;

    final String dirPath = '${extDir.path}/Movies/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.mp4';

    if (isRecordingVideo) {
      // A recording is already started, do nothing.
      return null;
    }

    try {
      videoPath = filePath;
      await controller!.startVideoRecording(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  Future<void> stopVideoRecording() async {
    if (!isRecordingVideo) {
      return;
    }

    try {
      await controller!.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }

    await _startVideoPlayer();
  }

  Future<void> pauseVideoRecording() async {
    try {
      if (controller!.value.isRecordingVideo!) {
        await controller!.pauseVideoRecording();
      }
      if (controller!.value.isStreamingVideoRtmp!) {
        await controller!.pauseVideoStreaming();
      }
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> resumeVideoRecording() async {
    try {
      if (controller!.value.isRecordingVideo!) {
        await controller!.resumeVideoRecording();
      }
      if (controller!.value.isStreamingVideoRtmp!) {
        await controller!.resumeVideoStreaming();
      }
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<String> _getUrl() async {
    String result = _textFieldController.text;

    return await showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Streaming Configuration'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: result,
                      decoration: const InputDecoration(
                        labelText: 'RTMP URL',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: DEFAULT_RTMP_URL,
                          child: Text('RTMP ($DEFAULT_RTMP_URL)'),
                        ),
                        DropdownMenuItem(
                          value: DEFAULT_RTMPS_URL,
                          child: Text('RTMPS (more secure)'),
                        ),
                      ],
                      onChanged: (value) => result = value!,
                    ),
                    TextField(
                      controller: _streamKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Stream Key',
                        hintText: 'Enter your Mux Stream Key',
                      ),
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel),
                    onPressed: () => Navigator.of(context).pop(result),
                  ),
                  TextButton(
                    child:
                        Text(MaterialLocalizations.of(context).okButtonLabel),
                    onPressed: () {
                      // Combinar URL y Stream Key
                      final completeUrl =
                          '$result/${_streamKeyController.text}';
                      Navigator.pop(context, completeUrl);
                    },
                  )
                ],
              );
            }) ??
        result;
  }

  Future<String?> startRecordingAndVideoStreaming() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (controller!.value.isStreamingVideoRtmp == true ||
        controller!.value.isStreamingVideoRtmp == true) {
      return null;
    }

    String myUrl = await _getUrl();

    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Movies/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.mp4';

    try {
      url = myUrl;
      videoPath = filePath;
      await controller!.startVideoRecordingAndStreaming(videoPath!, url!);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return url;
  }

  Future<String?> startVideoStreaming() async {
    await stopVideoStreaming();
    if (controller == null || !isControllerInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (isStreamingVideoRtmp) {
      return null;
    }

    try {
      String myUrl = await _getUrl();

      // Validar formato URL RTMP/RTMPS
      if (!myUrl.startsWith('rtmp://') && !myUrl.startsWith('rtmps://')) {
        showInSnackBar('Error: Invalid streaming URL format');
        return null;
      }

      // Validar Stream Key
      if (!myUrl.contains(_streamKeyController.text) ||
          _streamKeyController.text.isEmpty) {
        showInSnackBar('Error: Stream Key is required');
        return null;
      }

      url = myUrl;
      await controller!.startVideoStreaming(url!);

      // Mostrar información útil
      showInSnackBar(
          'Streaming started to Mux\nStream Key: ${_streamKeyController.text}');
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return url;
  }

  Future<void> stopVideoStreaming() async {
    if (controller == null || !isControllerInitialized) {
      return;
    }
    if (!isStreamingVideoRtmp) {
      return;
    }

    try {
      await controller!.stopVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  Future<void> pauseVideoStreaming() async {
    if (!isStreamingVideoRtmp) {
      return;
    }

    try {
      await controller!.pauseVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> resumeVideoStreaming() async {
    if (!isStreamingVideoRtmp) {
      return;
    }

    try {
      await controller!.resumeVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> _startVideoPlayer() async {
    final VideoPlayerController vcontroller =
        VideoPlayerController.file(File(videoPath!));
    videoPlayerListener = () {
      if (videoController != null) {
        // Refreshing the state to update video player with the correct ratio.
        if (mounted) setState(() {});
        videoController!.removeListener(videoPlayerListener ?? () {});
      }
    };
    vcontroller.addListener(videoPlayerListener ?? () {});
    await vcontroller.setLooping(true);
    await vcontroller.initialize();
    await videoController?.dispose();
    if (mounted) {
      setState(() {
        imagePath = null;
        videoController = vcontroller;
      });
    }
    await vcontroller.play();
  }

  Future<String?> takePicture() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }
    final Directory? extDir = await getExternalStorageDirectory();
    final String dirPath = '${extDir?.path}/Pictures/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';

    if (isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      await controller!.takePicture(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description ?? "No description found");
    showInSnackBar(
        'Error: ${e.code}\n${e.description ?? "No description found"}');
  }
}

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

List<CameraDescription> cameras = [];

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Verificar permisos de cámara
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.camera.request();
      if (status.isDenied) {
        throw CameraException('PERMISSION_DENIED',
            'Camera permission is required to use this app.');
      }
    }

    cameras = await availableCameras();
  } on CameraException catch (e) {
    logError(e.code, e.description ?? "No description found");
  }
  runApp(const CameraApp());
}
