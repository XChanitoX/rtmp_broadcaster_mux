import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock/wakelock.dart';
import 'package:rtmp_broadcaster/camera.dart';
import 'package:flutter/services.dart';

List<CameraDescription> cameras = [];

class AppColors {
  static const background = Color(0xFF2C2C2C);
  static const foreground = Color(0xFFF0EDE5);
  static const accent = Color(0xFFBFA98F);
  static const liveRed = Color(0xFFD32F2F);
  static const buttonColor = Color(0xFF444444);
}

// ─────────────────────────────────────────────────────────────────────────────
//                     PANTALLA INICIAL (STREAM KEY)
// ─────────────────────────────────────────────────────────────────────────────
class StartStreamPage extends StatefulWidget {
  const StartStreamPage({super.key});

  @override
  State<StartStreamPage> createState() => _StartStreamPageState();
}

class _StartStreamPageState extends State<StartStreamPage> {
  final TextEditingController _streamKeyController = TextEditingController();
  static const String defaultRtmpUrl = "rtmp://global-live.mux.com:5222/app";

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    try {
      final cameraStatus = await Permission.camera.status;
      final micStatus = await Permission.microphone.status;

      debugPrint(
          'Estado inicial - Cámara: $cameraStatus, Micrófono: $micStatus');

      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        final statuses = await [
          Permission.camera,
          Permission.microphone,
        ].request();

        debugPrint('Nuevos estados - Cámara: ${statuses[Permission.camera]}, '
            'Micrófono: ${statuses[Permission.microphone]}');

        if (statuses[Permission.camera]!.isDenied ||
            statuses[Permission.microphone]!.isDenied) {
          _showInSnackBar(
              'Se requieren permisos de cámara y micrófono para usar la app');
          // Opcionalmente abrir configuración
          await openAppSettings();
        }
      }
    } catch (e) {
      debugPrint('Error al solicitar permisos: $e');
      _showInSnackBar('Error al solicitar permisos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Pantalla Inicial"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Inicia tu stream",
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _streamKeyController,
                style: const TextStyle(color: AppColors.foreground),
                decoration: InputDecoration(
                  labelText: 'Stream Key',
                  labelStyle: const TextStyle(color: AppColors.accent),
                  hintText: 'Ej: 24ff56bf-8214-xxxx-xxxx-f0d518a72a96',
                  hintStyle: TextStyle(
                    color: AppColors.foreground.withOpacity(0.3),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                onPressed: () {
                  final streamKey = _streamKeyController.text.trim();
                  if (streamKey.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('La Stream Key no puede estar vacía'),
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CameraExampleHome(
                        baseUrl: defaultRtmpUrl,
                        streamKey: streamKey,
                      ),
                    ),
                  );
                },
                child: const Text(
                  "Ir a Cámara",
                  style: TextStyle(color: AppColors.foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA DE CÁMARA: Se fuerza 9:16 en portrait y 16:9 en landscape
// ─────────────────────────────────────────────────────────────────────────────
class CameraExampleHome extends StatefulWidget {
  final String baseUrl;
  final String streamKey;

  const CameraExampleHome({
    super.key,
    required this.baseUrl,
    required this.streamKey,
  });

  @override
  CameraExampleHomeState createState() => CameraExampleHomeState();
}

class CameraExampleHomeState extends State<CameraExampleHome> {
  CameraController? controller;
  CameraDescription? selectedCamera;

  final ResolutionPreset _resolutionPreset = ResolutionPreset.max;

  bool get isControllerInitialized => controller?.value.isInitialized ?? false;
  bool get isStreaming => controller?.value.isStreamingVideoRtmp ?? false;

  Timer? _timer;
  Duration _broadcastDuration = Duration.zero;
  DateTime? _streamStartTime;

  @override
  void initState() {
    super.initState();
    _initCameraWithDelay();
  }

  Future<void> _initCameraWithDelay() async {
    // Evita pantalla negra
    await Future.delayed(const Duration(milliseconds: 500));
    await _initFirstCamera();
  }

  Future<void> _initFirstCamera() async {
    if (cameras.isEmpty) {
      debugPrint("No hay cámaras disponibles");
      return;
    }
    // Por defecto la trasera
    selectedCamera = cameras.firstWhere(
      (desc) => desc.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    await _initializeCamera(selectedCamera!);
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    try {
      final wasStreaming = isStreaming;
      if (wasStreaming) {
        await _stopVideoStreaming();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      await controller?.dispose();

      controller = CameraController(
        cameraDescription,
        _resolutionPreset,
        androidUseOpenGL: false,
        enableAudio: true,
      );

      controller?.addListener(() {
        if (controller != null && controller!.value.hasError) {
          debugPrint(
              'Error en la cámara: ${controller!.value.errorDescription}');
          _showInSnackBar(
              'Error en la cámara: ${controller!.value.errorDescription}');
        }
      });

      await controller?.initialize();
      setState(() {});

      selectedCamera = cameraDescription;
      if (wasStreaming && isControllerInitialized) {
        await _startVideoStreaming();
      }
    } on CameraException catch (e) {
      debugPrint('Error al inicializar cámara: ${e.code}\n${e.description}');
      _showCameraException(e);
    } catch (e) {
      debugPrint('Error inesperado al inicializar cámara: $e');
      _showInSnackBar('Error inesperado: $e');
    }
  }

  @override
  void dispose() {
    if (isStreaming) {
      controller?.stopVideoStreaming();
    }
    controller?.dispose();
    _timer?.cancel();
    Wakelock.disable();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                              UI
  // ───────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Bloquear retroceso si streaming
    return PopScope(
      canPop: !isStreaming,
      child: Scaffold(
        appBar: isStreaming
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                title: const Text("Cámara con 9:16 ó 16:9"),
              ),
        backgroundColor: AppColors.background,
        body: OrientationBuilder(
          builder: (context, orientation) {
            return Stack(
              children: [
                _buildCameraPreviewWidget(orientation),
                if (isStreaming) _buildLiveIndicator(),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: _buildBottomControls(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Forzamos 9:16 en portrait y 16:9 en landscape:
  Widget _buildCameraPreviewWidget(Orientation orientation) {
    if (!isControllerInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Vista del plugin
    final preview = CameraPreview(controller!);

    // Ajustamos el aspect ratio según la orientación
    double aspectRatio;
    if (orientation == Orientation.landscape) {
      aspectRatio = 16.0 / 9.0; // Cambiado a 16:9 para landscape
    } else {
      aspectRatio = 9.0 / 16.0;
    }

    // Envuelto en AspectRatio
    Widget aspectWidget = AspectRatio(
      aspectRatio: aspectRatio,
      child: preview,
    );

    // Ya no necesitamos rotar la vista en landscape
    return Center(child: aspectWidget);
  }

  Widget _buildLiveIndicator() {
    return Positioned(
      top: 16,
      left: 16,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.liveRed,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              "LIVE",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formattedDuration(_broadcastDuration),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.cameraswitch, color: Colors.white),
          onPressed: _onSwitchCamera,
        ),
        ElevatedButton.icon(
          onPressed: isControllerInitialized && !isStreaming
              ? _startVideoStreaming
              : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text("Start"),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.background,
          ),
        ),
        ElevatedButton.icon(
          onPressed: isStreaming ? _stopVideoStreaming : null,
          icon: const Icon(Icons.stop),
          label: const Text("Stop"),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.liveRed,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                        STREAMING: START / STOP
  // ───────────────────────────────────────────────────────────────────────────
  String get _fullRtmpUrl => "${widget.baseUrl}/${widget.streamKey}";

  Future<void> _startVideoStreaming() async {
    if (!isControllerInitialized) {
      debugPrint('Error: la cámara no está lista.');
      _showInSnackBar('Error: la cámara no está lista.');
      return;
    }
    if (isStreaming) return;

    try {
      await controller!.startVideoStreaming(_fullRtmpUrl);
      debugPrint('Stream iniciado exitosamente');
      _showInSnackBar('¡Stream iniciado!');
      Wakelock.enable();

      _broadcastDuration = Duration.zero;
      _streamStartTime = DateTime.now();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), _updateTimer);

      setState(() {});
    } on CameraException catch (e) {
      debugPrint('Error al iniciar streaming: ${e.code}\n${e.description}');
      if (e.description?.contains('BadName') ?? false) {
        _showInSnackBar('Error: endpoint en uso. Prueba otra Stream Key.');
      } else {
        _showCameraException(e);
      }
    } catch (e) {
      debugPrint('Error inesperado al iniciar streaming: $e');
      _showInSnackBar('Error al iniciar streaming: $e');
    }
  }

  Future<void> _stopVideoStreaming() async {
    if (!isStreaming) return;

    try {
      await controller!.stopVideoStreaming();
      debugPrint('Streaming detenido exitosamente');
      _showInSnackBar('Streaming detenido.');
      Wakelock.disable();

      _timer?.cancel();
      _broadcastDuration = Duration.zero;
      setState(() {});
    } on CameraException catch (e) {
      debugPrint('Error al detener streaming: ${e.code}\n${e.description}');
      _showCameraException(e);
    } catch (e) {
      debugPrint('Error inesperado al detener streaming: $e');
      _showInSnackBar('Error al detener streaming: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                  ROTAR CÁMARA (FRONT/BACK)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _onSwitchCamera() async {
    if (cameras.length < 2) {
      _showInSnackBar('No hay múltiples cámaras disponibles.');
      return;
    }
    final currentIndex = cameras.indexOf(selectedCamera!);
    final nextIndex = (currentIndex + 1) % cameras.length;
    final nextCamera = cameras[nextIndex];
    await _initializeCamera(nextCamera);
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                             TIMER
  // ───────────────────────────────────────────────────────────────────────────
  void _updateTimer(Timer timer) {
    if (!isStreaming || _streamStartTime == null) {
      timer.cancel();
      return;
    }
    final diff = DateTime.now().difference(_streamStartTime!);
    setState(() => _broadcastDuration = diff);
  }

  String _formattedDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
    } else {
      return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
    }
  }

  String _twoDigits(int n) => n >= 10 ? '$n' : '0$n';

  // ───────────────────────────────────────────────────────────────────────────
  //                             UTILS
  // ───────────────────────────────────────────────────────────────────────────
  void _showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showCameraException(CameraException e) {
    debugPrint('Error de cámara ${e.code}: ${e.description}');
    _showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                                  MAIN
// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Permitir todas las orientaciones
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Obtenemos las cámaras
  try {
    cameras = await availableCameras();
    debugPrint('Cámaras disponibles: ${cameras.length}');
  } on CameraException catch (e) {
    debugPrint("Error al obtener cámaras: ${e.description}");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forzar 9:16 / 16:9',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.accent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: AppColors.foreground,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: AppColors.foreground,
          ),
        ),
      ),
      home: const StartStreamPage(),
    );
  }
}
