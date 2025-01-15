import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock/wakelock.dart';
import 'package:rtmp_broadcaster/camera.dart';

// Lista de cámaras disponible global
List<CameraDescription> cameras = [];

// Colores sobrios
class AppColors {
  static const background = Color(0xFF2C2C2C);
  static const foreground = Color(0xFFF0EDE5);
  static const accent = Color(0xFFBFA98F);
  static const liveRed = Color(0xFFD32F2F);
  static const buttonColor = Color(0xFF444444);
}

// ─────────────────────────────────────────────────────────────────────────────
//                         PANTALLA INICIAL (STREAM KEY)
// ─────────────────────────────────────────────────────────────────────────────
class StartStreamPage extends StatefulWidget {
  const StartStreamPage({Key? key}) : super(key: key);

  @override
  State<StartStreamPage> createState() => _StartStreamPageState();
}

class _StartStreamPageState extends State<StartStreamPage> {
  final TextEditingController _streamKeyController = TextEditingController();

  static const String defaultRtmpUrl = "rtmp://global-live.mux.com:5222/app";

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
              Text(
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
                child: Text(
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
}

// ─────────────────────────────────────────────────────────────────────────────
//                    PANTALLA DE CÁMARA Y CONTROL DE STREAM
// ─────────────────────────────────────────────────────────────────────────────
class CameraExampleHome extends StatefulWidget {
  final String baseUrl; // p. ej. "rtmp://global-live.mux.com:5222/app"
  final String streamKey; // p. ej. "xxxxx-xxxx-xxxx"

  const CameraExampleHome({
    Key? key,
    required this.baseUrl,
    required this.streamKey,
  }) : super(key: key);

  @override
  CameraExampleHomeState createState() => CameraExampleHomeState();
}

class CameraExampleHomeState extends State<CameraExampleHome> {
  CameraController? controller;

  // Cámara seleccionada (front o back).
  CameraDescription? selectedCamera;

  // Máxima resolución disponible
  final ResolutionPreset _resolutionPreset = ResolutionPreset.max;

  bool get isControllerInitialized => controller?.value.isInitialized ?? false;
  bool get isStreaming => controller?.value.isStreamingVideoRtmp ?? false;

  // Timer para el tiempo de transmisión
  Timer? _timer;
  Duration _broadcastDuration = Duration.zero;
  DateTime? _streamStartTime;

  @override
  void initState() {
    super.initState();
    _initFirstCamera();
  }

  /// Inicializa la cámara por defecto (trasera).
  Future<void> _initFirstCamera() async {
    if (cameras.isEmpty) {
      debugPrint("No hay cámaras disponibles");
      return;
    }

    selectedCamera = cameras.firstWhere(
      (desc) => desc.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    await _initializeCamera(selectedCamera!);
  }

  /// Inicializa el controlador sin OpenGL (para evitar eglContext null).
  /// Ahora, agregamos un pequeño `Future.delayed` cuando se cambia de cámara
  /// y se estaba streameando, para dar tiempo a la librería a liberar la Surface.
  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    final wasStreaming = isStreaming;
    if (wasStreaming) {
      // Detenemos streaming si estaba activo
      await _stopVideoStreaming();
      // Pequeña espera para que la Surface se libere antes de recrearse
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Liberar controlador previo
    await controller?.dispose();

    controller = CameraController(
      cameraDescription,
      _resolutionPreset,
      androidUseOpenGL: false, // Evitar crash en la librería de Pedro
    );

    // Listener de errores
    controller?.addListener(() {
      if (controller != null && controller!.value.hasError) {
        _showInSnackBar(
          'Error en la cámara: ${controller!.value.errorDescription}',
        );
      }
    });

    try {
      await controller?.initialize();
      setState(() {});
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }

    // Reanudamos stream automáticamente si lo detenimos al cambiar de cámara
    if (wasStreaming && isControllerInitialized) {
      await _startVideoStreaming();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    controller?.dispose();
    Wakelock.disable();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                                 UI
  // ───────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final borderColor = isStreaming ? AppColors.accent : Colors.grey.shade700;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Cámara en vivo"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _onSwitchCamera,
            icon: const Icon(Icons.cameraswitch),
            tooltip: "Rotar cámara",
          ),
        ],
      ),
      body: Column(
        children: [
          // Vista de la cámara
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 2.0),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    _cameraPreviewWidget(),
                    if (isStreaming)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            // Logo placeholder
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.buttonColor,
                              ),
                              child: const Center(
                                child: Icon(Icons.video_camera_front,
                                    color: AppColors.foreground),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // LIVE
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.liveRed,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                "LIVE",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Tiempo
                            Expanded(
                              child: Text(
                                _formattedDuration(_broadcastDuration),
                                style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Botones Start / Stop
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.buttonColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraPreviewWidget() {
    if (!isControllerInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.foreground),
      );
    }
    return AspectRatio(
      aspectRatio: controller!.value.aspectRatio,
      child: CameraPreview(controller!),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                STREAM: START / STOP (MANUAL)
  // ───────────────────────────────────────────────────────────────────────────
  String get _fullRtmpUrl => "${widget.baseUrl}/${widget.streamKey}";

  Future<void> _startVideoStreaming() async {
    if (!isControllerInitialized) {
      _showInSnackBar('Error: cámara no lista.');
      return;
    }
    if (isStreaming) return;

    try {
      await controller!.startVideoStreaming(_fullRtmpUrl);
      _showInSnackBar('¡Stream iniciado correctamente!');
      Wakelock.enable();
      _broadcastDuration = Duration.zero;
      _streamStartTime = DateTime.now();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), _updateTimer);
      setState(() {});
    } on CameraException catch (e) {
      if (e.description?.contains('BadName') ?? false) {
        _showInSnackBar('Error: Endpoint en uso. Prueba otra Stream Key.');
      } else {
        _showCameraException(e);
      }
    } catch (e) {
      _showInSnackBar('Error al iniciar streaming: $e');
    }
  }

  Future<void> _stopVideoStreaming() async {
    if (!isStreaming) return;

    try {
      await controller!.stopVideoStreaming();
      _showInSnackBar('Streaming detenido.');
      Wakelock.disable();
      _timer?.cancel();
      _broadcastDuration = Duration.zero;
      setState(() {});
    } on CameraException catch (e) {
      _showCameraException(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                         ROTAR CÁMARA
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _onSwitchCamera() async {
    if (cameras.length < 2) {
      _showInSnackBar('No hay múltiples cámaras disponibles.');
      return;
    }

    final currentIndex = cameras.indexOf(selectedCamera!);
    final nextIndex = (currentIndex + 1) % cameras.length;
    final nextCamera = cameras[nextIndex];
    selectedCamera = nextCamera;

    await _initializeCamera(nextCamera);
  }

  // ───────────────────────────────────────────────────────────────────────────
  //                               TIMER
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
  //                                UTILS
  // ───────────────────────────────────────────────────────────────────────────
  void _showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showCameraException(CameraException e) {
    debugPrint('Camera error: ${e.code}\n${e.description}');
    _showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                                  MAIN
// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pedir permisos de cámara
  if (Platform.isAndroid || Platform.isIOS) {
    final status = await Permission.camera.request();
    if (status.isDenied) {
      throw CameraException(
        'PERMISSION_DENIED',
        'Se requiere el permiso de cámara para usar esta app.',
      );
    }
  }

  // Obtener cámaras
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint("Error al obtener cámaras: ${e.description}");
  }

  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────────────────────
//                                 MyApp
// ─────────────────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'High Quality Stream',
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
