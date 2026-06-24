// =======================================================
// IMPORT
// =======================================================
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_client_factory.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'user_config.dart';
import 'auth_page.dart';
import 'qr_generator_page.dart';
// =======================================================
// THEME COLORS
// =======================================================
class AppColors {
  static const coralLight    = Color(0xFFFAECE7);
  static const coralBorder   = Color(0xFFF0997B);
  static const coralMid      = Color(0xFFD85A30);
  static const coralDark     = Color(0xFF4A1B0C);
  static const coralIcon     = Color(0xFFF5C4B3);
  static const coralIconText = Color(0xFF712B13);
  static const coralLabel    = Color(0xFF993C1D);
  static const coralUnit     = Color(0xFFD85A30);

  static const purpleLight    = Color(0xFFEEEDFE);
  static const purpleBorder   = Color(0xFFAFA9EC);
  static const purpleMid      = Color(0xFF534AB7);
  static const purpleDark     = Color(0xFF26215C);
  static const purpleIcon     = Color(0xFFCECBF6);
  static const purpleIconText = Color(0xFF26215C);
  static const purpleLabel    = Color(0xFF3C3489);
  static const purpleUnit     = Color(0xFF7F77DD);

  static const tealLight    = Color(0xFFE1F5EE);
  static const tealBorder   = Color(0xFF5DCAA5);
  static const tealMid      = Color(0xFF1D9E75);
  static const tealDark     = Color(0xFF04342C);
  static const tealIcon     = Color(0xFF9FE1CB);
  static const tealIconText = Color(0xFF085041);
  static const tealLabel    = Color(0xFF0F6E56);
  static const tealUnit     = Color(0xFF1D9E75);

  static const amberLight    = Color(0xFFFAEEDA);
  static const amberBorder   = Color(0xFFEF9F27);
  static const amberIcon     = Color(0xFFFAC775);
  static const amberIconText = Color(0xFF412402);
  static const amberText     = Color(0xFF854F0B);
  static const amberDark     = Color(0xFF412402);

  static const greenLight = Color(0xFFEAF3DE);
  static const greenText  = Color(0xFF27500A);

  static const blueLight = Color(0xFFE6F1FB);
  static const blueText  = Color(0xFF0C447C);

  static const grayLight = Color(0xFFF1EFE8);
  static const grayMid   = Color(0xFFB4B2A9);
  static const grayText  = Color(0xFF5F5E5A);

  static const surface = Color(0xFFF8F8F8);
  static const border  = Color(0xFFE8E8E8);

  static const redLight = Color(0xFFFCEBEB);
  static const redMid   = Color(0xFFE24B4A);
  static const redText  = Color(0xFF7A1F1E);
}

// =======================================================
// ESP32 STATUS ENUM
// =======================================================
enum Esp32Status { connecting, wifiOk, mqttOk, online, offline }

// =======================================================
// DOSING STATE ENUM — sama dengan ESP32
// =======================================================
enum DosingState { idle, mixing, dosing, aeration }

// =======================================================
// MAIN
// =======================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Set callback navigasi dari KolamListPage → MQTTPage
  // (menghindari circular import antara main.dart dan auth_page.dart)
  onKolamTap = (context, config) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => MQTTPage(config: config)));
  };

  runApp(const MyApp());
}

// =======================================================
// MAIN APP
// =======================================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.tealMid, brightness: Brightness.light),
        useMaterial3: true,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: AppColors.surface,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 0.5),
          ),
          color: Colors.white,
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// =======================================================
// MQTT PAGE
// =======================================================
class MQTTPage extends StatefulWidget {
  final KolamConfig config;
  const MQTTPage({super.key, required this.config});
  @override
  State<MQTTPage> createState() => _MQTTPageState();
}

class _MQTTPageState extends State<MQTTPage> {

  // =====================================================
  // CONFIG KOLAM
  // =====================================================
  KolamConfig get _cfg => widget.config;

  // =====================================================
  // FIREBASE
  // =====================================================
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // =====================================================
  // MQTT CLIENT
  // =====================================================
  late final MqttClient client;

  // =====================================================
  // STATE — SENSOR & SISTEM
  // =====================================================
  String connectionStatus = "Disconnected";
  String systemStatus     = "DISCONNECT";
  String suhu             = "-";
  String ph               = "-";
  String dissolvedOxygen  = "-";
  bool   autoMode         = false;
  bool   aeratorUtama     = true;
  bool   aeratorBackup    = false;
  bool   pengadukDolomit  = false;
  bool   pompaDolomit     = false;
  bool   solenoidIn       = false;
  bool   solenoidOut      = false;
  DateTime? lastLogTime;
  int    logCount         = 0;
  String _selectedChart   = 'suhu';

  // =====================================================
  // STATE — ESP32 CONNECTION
  // =====================================================
  Esp32Status _esp32Status   = Esp32Status.connecting;
  bool        _esp32WifiOk   = false;
  bool        _mqttConnected = false;
  String      _esp32Ip       = "";
  OverlayEntry? _connectingOverlay;
  bool _connectedToastShown = false;

  // =====================================================
  // STATE — COUNTDOWN DOSING
  // Durasi total (ms) sama dengan konstanta di ESP32
  // =====================================================
  static const int _mixingTotal   = 60;    // detik
  static const int _dosingTotal   = 20;    // detik
  static const int _aerationTotal = 900;   // detik (15 menit)

  DosingState _dosingState      = DosingState.idle;
  int         _countdownSeconds = 0;   // sisa waktu dari ESP32
  Timer?      _countdownTimer;         // timer lokal 1 detik

  // Flag: apakah aerasi backup adalah bagian dari sequence dosing pH
  // (MIXING → DOSING → AERATION). Jika true, countdown 15 menit tampil.
  // Jika false (aerasi karena DO rendah), tidak ada countdown.
  bool _dosingSequenceActive = false;

  // =====================================================
  // HISTORY DATA
  // =====================================================
  List<FlSpot> suhuHistory = [];
  List<FlSpot> phHistory   = [];
  List<FlSpot> doHistory   = [];
  List<String> timeLabels  = [];

  // =====================================================
  // INIT & DISPOSE
  // =====================================================
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showConnectingOverlay());
    connectMQTT();
    loadHistoryData();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _connectingOverlay?.remove();
    client.disconnect();
    super.dispose();
  }

  // =====================================================
  // UPDATE DOSING STATE & COUNTDOWN
  //
  // Sequence dosing pH (mode AUTO):
  //   MIXING_DOLOMIT  → countdown 60 detik  (ungu)
  //   INJEKSI_PH      → countdown 20 detik  (amber)
  //   AERATOR_BACKUP_ON setelah injeksi
  //                   → countdown 15 menit  (teal)
  //
  // AERATOR_BACKUP_ON karena DO rendah → TIDAK ada countdown
  // Mode MANUAL → selalu idle, tidak ada countdown
  // =====================================================
  void _updateDosingState(String status) {
    DosingState newState;
    int totalSeconds;

    // Mode manual -> paksa idle
    if (!autoMode) {
      _dosingSequenceActive = false;
      _stopCountdown();
      return;
    }

    switch (status) {
      case "MIXING_DOLOMIT":
        // Awal sequence dosing pH
        _dosingSequenceActive = true;
        newState     = DosingState.mixing;
        totalSeconds = _mixingTotal;
        break;

      case "INJEKSI_PH":
        // Lanjutan sequence — pastikan flag aktif
        _dosingSequenceActive = true;
        newState     = DosingState.dosing;
        totalSeconds = _dosingTotal;
        break;

      case "AERATOR_BACKUP_ON":
        if (_dosingSequenceActive) {
          // Aerasi backup sebagai bagian akhir sequence dosing → countdown 15 menit
          newState     = DosingState.aeration;
          totalSeconds = _aerationTotal;
        } else {
          // Aerasi backup karena DO rendah → tidak ada countdown
          _stopCountdown();
          return;
        }
        break;

      default:
        // Status lain (NORMAL, LOW_PH, HIGH_PH, dll) → reset sequence & countdown
        _dosingSequenceActive = false;
        newState     = DosingState.idle;
        totalSeconds = 0;
    }

    // Jika state berubah, reset countdown & timer
    if (newState != _dosingState) {
      _dosingState      = newState;
      _countdownSeconds = totalSeconds;
      _countdownTimer?.cancel();

      if (newState != DosingState.idle) {
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            if (_countdownSeconds > 0) {
              _countdownSeconds--;
            } else {
              // Countdown habis
              _countdownTimer?.cancel();
              if (_dosingState == DosingState.aeration) {
                // Sequence selesai, reset flag
                _dosingSequenceActive = false;
              }
              _dosingState      = DosingState.idle;
              _countdownSeconds = 0;
            }
          });
        });
      }
    }
  }

  // =====================================================
  // STOP COUNTDOWN — reset ke idle
  // =====================================================
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _dosingSequenceActive = false;
    if (_dosingState == DosingState.idle) return;
    setState(() {
      _dosingState      = DosingState.idle;
      _countdownSeconds = 0;
    });
  }

  // Format countdown: mm:ss atau ss tergantung durasi
  String _formatCountdown(int seconds) {
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${seconds}s';
  }

  // Warna & label countdown berdasarkan state
  Color get _countdownColor {
    switch (_dosingState) {
      case DosingState.mixing:   return AppColors.purpleMid;
      case DosingState.dosing:   return AppColors.amberBorder;
      case DosingState.aeration: return AppColors.tealMid;
      default:                   return AppColors.grayMid;
    }
  }

  Color get _countdownBg {
    switch (_dosingState) {
      case DosingState.mixing:   return AppColors.purpleLight;
      case DosingState.dosing:   return AppColors.amberLight;
      case DosingState.aeration: return AppColors.tealLight;
      default:                   return AppColors.grayLight;
    }
  }

  IconData get _countdownIcon {
    switch (_dosingState) {
      case DosingState.mixing:   return Icons.rotate_right_rounded;
      case DosingState.dosing:   return Icons.science_outlined;
      case DosingState.aeration: return Icons.air_rounded;
      default:                   return Icons.check_circle_outline;
    }
  }

  String get _countdownLabel {
    switch (_dosingState) {
      case DosingState.mixing:   return "Pengadukan dolomit";
      case DosingState.dosing:   return "Injeksi pH";
      case DosingState.aeration: return "Aerasi backup";
      default:                   return "";
    }
  }

  int get _countdownTotal {
    switch (_dosingState) {
      case DosingState.mixing:   return _mixingTotal;
      case DosingState.dosing:   return _dosingTotal;
      case DosingState.aeration: return _aerationTotal;
      default:                   return 1;
    }
  }

  // =====================================================
  // UPDATE ESP32 STATUS
  // =====================================================
  void _updateEsp32Status() {
    Esp32Status newStatus;
    if (!_mqttConnected) {
      newStatus = Esp32Status.connecting;
    } else if (!_esp32WifiOk) {
      newStatus = Esp32Status.mqttOk;
    } else {
      newStatus = Esp32Status.online;
    }

    final wasConnecting = _esp32Status == Esp32Status.connecting || _esp32Status == Esp32Status.offline;
    final nowOnline     = newStatus == Esp32Status.mqttOk || newStatus == Esp32Status.online;

    setState(() => _esp32Status = newStatus);

    if (wasConnecting && nowOnline) {
      _removeConnectingOverlay();
      if (!_connectedToastShown) {
        _connectedToastShown = true;
        _showConnectedToast();
        Future.delayed(const Duration(seconds: 5), () => _connectedToastShown = false);
      }
    }
    if (!wasConnecting && newStatus == Esp32Status.connecting) {
      _connectedToastShown = false;
      _showConnectingOverlay();
    }
  }

  // =====================================================
  // CONNECT MQTT
  // =====================================================
  Future<void> connectMQTT() async {
    // Init client dengan broker dari config akun.
    // createMqttClient() otomatis pilih implementasi sesuai
    // platform: MqttServerClient (native, TCP+TLS port 8883)
    // atau MqttBrowserClient (web, WebSocket/TLS port 8884).
    client = createMqttClient(
      _cfg.mqttBroker,
      'flutter_${_cfg.kolamId.substring(0, 8)}',
    );
    client.onConnected    = onConnected;
    client.onDisconnected = onDisconnected;
    client.setProtocolV311();
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .authenticateAs(_cfg.mqttUser, _cfg.mqttPassword)
        .startClean();

    try { await client.connect(); }
    catch (e) { debugPrint("MQTT ERROR: $e"); client.disconnect(); }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      client.subscribe(_cfg.topic('sensor/#'),    MqttQos.atLeastOnce);
      client.subscribe(_cfg.topic('status/#'),    MqttQos.atLeastOnce);
      client.subscribe(_cfg.topic('device/wifi'), MqttQos.atLeastOnce);
    }

    client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      final recMess = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      final topic   = messages[0].topic;

      try {
        final data = jsonDecode(payload);
        setState(() {
          if (topic == _cfg.topic('sensor/suhu'))             suhu = data['value'].toStringAsFixed(2);
          if (topic == _cfg.topic('sensor/ph'))               ph   = data['value'].toStringAsFixed(2);
          if (topic == _cfg.topic('sensor/do'))               dissolvedOxygen = data['value'].toStringAsFixed(2);
          if (topic == _cfg.topic('status/mode')) {
            autoMode = data['mode'] == "AUTO";
            // Jika beralih ke MANUAL, hentikan countdown
            if (!autoMode) _stopCountdown();
          }
          if (topic == _cfg.topic('status/aerator_backup'))   aeratorBackup = data['state'];
          if (topic == _cfg.topic('status/pengaduk_dolomit')) pengadukDolomit = data['state'];
          if (topic == _cfg.topic('status/pompa_dolomit'))    pompaDolomit = data['state'];
          if (topic == _cfg.topic('status/solenoid_in'))      solenoidIn = data['state'];
          if (topic == _cfg.topic('status/solenoid_out'))     solenoidOut = data['state'];

          if (topic == _cfg.topic('status/system')) {
            systemStatus = data['status'];
            // ── Update countdown berdasarkan status sistem ──
            _updateDosingState(systemStatus);
          }

          if (topic == _cfg.topic('device/wifi')) {
            _esp32WifiOk = data['connected'] == true;
            _esp32Ip     = data['ip'] ?? "";
            _updateEsp32Status();
          }
        });

        if (lastLogTime == null ||
            DateTime.now().difference(lastLogTime!).inMinutes >= 1) {
          saveSensorData();
          loadHistoryData();
          lastLogTime = DateTime.now();
        }
      } catch (e) { debugPrint("JSON ERROR: $e"); }
    });
  }

  void onConnected() {
    setState(() { connectionStatus = "Connected"; _mqttConnected = true; });
    _updateEsp32Status();
  }

  void onDisconnected() {
    setState(() {
      connectionStatus = "Disconnected";
      systemStatus     = "DISCONNECT";
      _mqttConnected   = false;
      _esp32WifiOk     = false;
    });
    _countdownTimer?.cancel();
    setState(() { _dosingState = DosingState.idle; _countdownSeconds = 0; });
    _updateEsp32Status();
  }

  // =====================================================
  // LOGOUT
  // =====================================================
  Future<void> _logout() async {
    // Konfirmasi logout
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Keluar", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          "Apakah Anda yakin ingin keluar dari akun Anda?",
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Batal", style: TextStyle(color: Color(0xFF5F5E5A))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE24B4A),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Keluar"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Putuskan MQTT
    try { client.disconnect(); } catch (_) {}

    // Hapus sesi Firebase Auth
    await FirebaseAuth.instance.signOut();

    // MQTTPage ini berada di atas stack Navigator (di-push dari
    // KolamListPage), sehingga StreamBuilder di AuthWrapper yang
    // sudah rebuild ke AuthPage tidak akan terlihat selama route
    // ini masih ada di atas. Pop semua route sampai balik ke root
    // (AuthWrapper) agar AuthPage langsung terlihat.
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // =====================================================
  // OVERLAY CONNECTING
  // =====================================================
  void _showConnectingOverlay() {
    if (_connectingOverlay != null) return;
    _connectingOverlay = OverlayEntry(
      builder: (_) => Material(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 36),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 32, offset: const Offset(0, 8))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68, height: 68,
                  decoration: const BoxDecoration(color: AppColors.grayLight, shape: BoxShape.circle),
                  child: const Icon(Icons.developer_board_rounded, size: 34, color: AppColors.grayMid),
                ),
                const SizedBox(height: 20),
                const Text("Menghubungkan perangkat", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 8),
                const Text("Menunggu ESP32 terhubung\nke jaringan WiFi...", style: TextStyle(fontSize: 13, color: AppColors.grayText, height: 1.5), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                _stepRow(icon: Icons.wifi_rounded,  label: "ESP32 → WiFi",        done: _esp32WifiOk,   active: !_esp32WifiOk),
                const SizedBox(height: 8),
                _stepRow(icon: Icons.cloud_rounded, label: "ESP32 → Broker MQTT", done: _mqttConnected, active: _esp32WifiOk && !_mqttConnected),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(AppColors.grayMid)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Overlay.of(context).insert(_connectingOverlay!);
    });
  }

  Widget _stepRow({required IconData icon, required String label, required bool done, required bool active}) {
    final color = done ? AppColors.tealMid : active ? AppColors.amberBorder : AppColors.grayMid;
    final bg    = done ? AppColors.tealLight : active ? AppColors.amberLight : AppColors.grayLight;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 30, height: 30, decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(done ? Icons.check_rounded : icon, size: 16, color: color)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }

  void _removeConnectingOverlay() { _connectingOverlay?.remove(); _connectingOverlay = null; }

  void _showConnectedToast() {
    final isOnline = _esp32Status == Esp32Status.online;
    OverlayEntry? toast;
    toast = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 14, left: 16, right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Transform.translate(offset: Offset(0, -28 * (1 - v)), child: Opacity(opacity: v, child: child)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isOnline ? AppColors.tealLight : AppColors.amberLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isOnline ? AppColors.tealBorder : AppColors.amberBorder, width: 0.5),
                boxShadow: [BoxShadow(color: (isOnline ? AppColors.tealMid : AppColors.amberBorder).withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: isOnline ? AppColors.tealIcon : AppColors.amberIcon, shape: BoxShape.circle),
                    child: Icon(isOnline ? Icons.developer_board_rounded : Icons.cloud_done_rounded, size: 20, color: isOnline ? AppColors.tealIconText : AppColors.amberIconText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(isOnline ? "ESP32 terhubung" : "Broker MQTT terhubung",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isOnline ? AppColors.tealDark : AppColors.amberDark)),
                      const SizedBox(height: 2),
                      Text(isOnline ? "WiFi & MQTT aktif${_esp32Ip.isNotEmpty ? ' · $_esp32Ip' : ''}" : "Menunggu konfirmasi WiFi ESP32...",
                          style: TextStyle(fontSize: 12, color: isOnline ? AppColors.tealLabel : AppColors.amberText)),
                    ]),
                  ),
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: isOnline ? AppColors.tealMid : AppColors.amberBorder, shape: BoxShape.circle)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Overlay.of(context).insert(toast!);
        Future.delayed(const Duration(seconds: 4), () => toast?.remove());
      }
    });
  }

  // =====================================================
  // FIREBASE
  // =====================================================
  Future<void> saveSensorData() async {
    try {
      await firestore.collection('kolam/${_cfg.kolamId}/sensor_log').add({
        'timestamp': Timestamp.now(),
        'suhu': double.tryParse(suhu) ?? 0,
        'ph':   double.tryParse(ph)   ?? 0,
        'do':   double.tryParse(dissolvedOxygen) ?? 0,
        'status': systemStatus,
        'auto_mode': autoMode,
      });
      setState(() => logCount++);
    } catch (e) { debugPrint("FIREBASE ERROR: $e"); }
  }

  Future<void> loadHistoryData() async {
    try {
      final oneHourAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1)));
      final snapshot = await firestore
          .collection('kolam/${_cfg.kolamId}/sensor_log')
          .where('timestamp', isGreaterThan: oneHourAgo)
          .orderBy('timestamp')
          .get();

      suhuHistory.clear(); phHistory.clear(); doHistory.clear(); timeLabels.clear();
      int index = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        suhuHistory.add(FlSpot(index.toDouble(), (data['suhu'] ?? 0).toDouble()));
        phHistory.add(FlSpot(index.toDouble(),   (data['ph']   ?? 0).toDouble()));
        doHistory.add(FlSpot(index.toDouble(),   (data['do']   ?? 0).toDouble()));
        timeLabels.add(DateFormat('HH:mm').format((data['timestamp'] as Timestamp).toDate()));
        index++;
      }
      setState(() => logCount = snapshot.docs.length);
    } catch (e) { debugPrint("LOAD HISTORY ERROR: $e"); }
  }

  // =====================================================
  // PUBLISH
  // =====================================================
  void publishRelay(String topic, bool state) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({"state": state}));
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void publishMode(String mode) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({"mode": mode}));
    client.publishMessage(_cfg.topic('system/mode'), MqttQos.atLeastOnce, builder.payload!);
  }

  // =====================================================
  // STATUS HELPERS
  // =====================================================
  Color get statusColor {
    switch (systemStatus) {
      case "NORMAL":   return AppColors.tealMid;
      case "LOW_DO":   return const Color(0xFF185FA5);
      case "LOW_PH":   return AppColors.amberBorder;
      case "HIGH_PH":  return const Color(0xFFD85A30);
      case "FAILSAFE": return AppColors.redMid;
      default:         return AppColors.grayMid;
    }
  }

  Color get statusBgColor {
    switch (systemStatus) {
      case "NORMAL":   return AppColors.tealLight;
      case "LOW_DO":   return AppColors.blueLight;
      case "LOW_PH":   return AppColors.amberLight;
      case "HIGH_PH":  return AppColors.coralLight;
      case "FAILSAFE": return AppColors.redLight;
      default:         return AppColors.grayLight;
    }
  }

  String get statusLabel {
    switch (systemStatus) {
      case "NORMAL":          return "Semua parameter normal";
      case "LOW_DO":          return "Oksigen terlarut rendah";
      case "LOW_PH":          return "pH berada di bawah ambang batas";
      case "HIGH_PH":         return "pH berada di atas ambang batas";
      case "FAILSAFE":        return "Mode failsafe aktif";
      case "MIXING_DOLOMIT":  return "Sedang mengaduk dolomit";
      case "INJEKSI_PH":      return "Sedang injeksi pH";
      case "AERATOR_BACKUP_ON": return "Aerasi backup aktif";
      case "DISCONNECT":      return "ESP32 tidak terhubung";
      default:                return "-";
    }
  }

  String get _esp32BadgeLabel {
    switch (_esp32Status) {
      case Esp32Status.connecting: return "Connecting...";
      case Esp32Status.mqttOk:     return "MQTT OK";
      case Esp32Status.wifiOk:     return "WiFi OK";
      case Esp32Status.online:     return "ESP32 Online";
      case Esp32Status.offline:    return "Offline";
    }
  }

  Color get _esp32BadgeBg {
    switch (_esp32Status) {
      case Esp32Status.connecting: return AppColors.grayLight;
      case Esp32Status.mqttOk:     return AppColors.amberLight;
      case Esp32Status.wifiOk:     return AppColors.blueLight;
      case Esp32Status.online:     return AppColors.greenLight;
      case Esp32Status.offline:    return AppColors.redLight;
    }
  }

  Color get _esp32BadgeFg {
    switch (_esp32Status) {
      case Esp32Status.connecting: return AppColors.grayText;
      case Esp32Status.mqttOk:     return AppColors.amberText;
      case Esp32Status.wifiOk:     return AppColors.blueText;
      case Esp32Status.online:     return AppColors.greenText;
      case Esp32Status.offline:    return AppColors.redMid;
    }
  }

  IconData get _esp32BadgeIcon {
    switch (_esp32Status) {
      case Esp32Status.connecting: return Icons.sync_rounded;
      case Esp32Status.mqttOk:     return Icons.cloud_rounded;
      case Esp32Status.wifiOk:     return Icons.wifi_rounded;
      case Esp32Status.online:     return Icons.developer_board_rounded;
      case Esp32Status.offline:    return Icons.developer_board_off_rounded;
    }
  }

  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildAlertBanner(),
              const SizedBox(height: 14),
              // ── Countdown card — hanya tampil saat dosing aktif ──
              if (_dosingState != DosingState.idle) ...[
                _buildCountdownCard(),
                const SizedBox(height: 14),
              ],
              _buildSensorGrid(),
              const SizedBox(height: 14),
              _buildChartCard(),
              const SizedBox(height: 14),
              _buildBottomSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // HEADER
  // =====================================================
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: AppColors.tealMid, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.water, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("IoT Kolam Ikan", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
              Text("${_cfg.kolamName}${_cfg.isOwner ? "" : " · Tamu"}", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ),
        // ── Tombol Logout ──
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded, size: 20),
          color: const Color(0xFFB4B2A9),
          tooltip: "Keluar",
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF1EFE8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: 8),
        // ── Tombol QR (hanya untuk pemilik) ──
        if (_cfg.isOwner)
          IconButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => QRGeneratorPage(config: _cfg))),
            icon: const Icon(Icons.qr_code_rounded, size: 20),
            color: const Color(0xFFB4B2A9),
            tooltip: "Bagikan akses kolam",
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1EFE8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              minimumSize: const Size(36, 36), padding: EdgeInsets.zero,
            ),
          ),
        const SizedBox(width: 6),
        // ── Tombol kembali ke daftar kolam ──
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.grid_view_rounded, size: 20),
          color: const Color(0xFFB4B2A9),
          tooltip: "Daftar kolam",
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF1EFE8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size(36, 36), padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _esp32BadgeBg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: _esp32BadgeFg.withOpacity(0.3), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _esp32Status == Esp32Status.connecting
                  ? SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(_esp32BadgeFg)))
                  : Icon(_esp32BadgeIcon, size: 13, color: _esp32BadgeFg),
              const SizedBox(width: 6),
              Text(_esp32BadgeLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _esp32BadgeFg)),
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================
  // ALERT BANNER
  // =====================================================
  Widget _buildAlertBanner() {
    final now = DateFormat('HH:mm').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
            child: Icon(systemStatus == "NORMAL" ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  systemStatus == "DISCONNECT" ? "ESP32 tidak terhubung" : systemStatus.replaceAll('_', ' '),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor),
                ),
                const SizedBox(height: 2),
                Text(statusLabel, style: TextStyle(fontSize: 12, color: statusColor.withOpacity(0.8))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(99)),
            child: Text("$now WIB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: statusColor)),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // COUNTDOWN CARD — tampil saat mixing / dosing / aeration
  // =====================================================
  Widget _buildCountdownCard() {
    final progress = _countdownTotal > 0
        ? (_countdownSeconds / _countdownTotal).clamp(0.0, 1.0)
        : 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _countdownBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _countdownColor.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Ikon proses
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: _countdownColor.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(_countdownIcon, size: 18, color: _countdownColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _countdownLabel,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _countdownColor),
                    ),
                    Text(
                      "Proses otomatis sedang berjalan",
                      style: TextStyle(fontSize: 11, color: _countdownColor.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
              // Tampilan countdown waktu besar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _countdownColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatCountdown(_countdownSeconds),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: _countdownColor.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(_countdownColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Sisa ${_formatCountdown(_countdownSeconds)}",
                style: TextStyle(fontSize: 11, color: _countdownColor.withOpacity(0.7)),
              ),
              Text(
                "Total ${_formatCountdown(_countdownTotal)}",
                style: TextStyle(fontSize: 11, color: _countdownColor.withOpacity(0.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SENSOR GRID
  // =====================================================
  Widget _buildSensorGrid() {
    return Row(
      children: [
        Expanded(child: _sensorCard(label: "Suhu", value: suhu, unit: "°C", icon: Icons.thermostat_outlined, bgColor: AppColors.coralLight, borderColor: AppColors.coralBorder, accentColor: AppColors.coralMid, labelColor: AppColors.coralLabel, iconBg: AppColors.coralIcon, iconColor: AppColors.coralIconText, valueColor: AppColors.coralDark, unitColor: AppColors.coralUnit, statusText: _getSuhuStatus(), statusBg: _getSuhuStatusBg(), statusFg: _getSuhuStatusFg())),
        const SizedBox(width: 10),
        Expanded(child: _sensorCard(label: "pH", value: ph, unit: "pH level", icon: Icons.science_outlined, bgColor: AppColors.purpleLight, borderColor: AppColors.purpleBorder, accentColor: AppColors.purpleMid, labelColor: AppColors.purpleLabel, iconBg: AppColors.purpleIcon, iconColor: AppColors.purpleIconText, valueColor: AppColors.purpleDark, unitColor: AppColors.purpleUnit, statusText: _getPhStatus(), statusBg: _getPhStatusBg(), statusFg: _getPhStatusFg())),
        const SizedBox(width: 10),
        Expanded(child: _sensorCard(label: "DO", value: dissolvedOxygen, unit: "mg/L", icon: Icons.water_drop_outlined, bgColor: AppColors.tealLight, borderColor: AppColors.tealBorder, accentColor: AppColors.tealMid, labelColor: AppColors.tealLabel, iconBg: AppColors.tealIcon, iconColor: AppColors.tealIconText, valueColor: AppColors.tealDark, unitColor: AppColors.tealUnit, statusText: _getDoStatus(), statusBg: _getDoStatusBg(), statusFg: _getDoStatusFg())),
      ],
    );
  }

  String _getSuhuStatus() { final v = double.tryParse(suhu); if (v == null) return "-"; if (v >= 26 && v <= 30) return "Normal"; return v < 26 ? "Dingin" : "Panas"; }
  Color _getSuhuStatusBg() { final v = double.tryParse(suhu); if (v == null) return AppColors.grayLight; if (v >= 26 && v <= 30) return AppColors.greenLight; return AppColors.amberLight; }
  Color _getSuhuStatusFg() { final v = double.tryParse(suhu); if (v == null) return AppColors.grayText; if (v >= 26 && v <= 30) return AppColors.greenText; return AppColors.amberText; }
  String _getPhStatus() { final v = double.tryParse(ph); if (v == null) return "-"; if (v >= 7 && v <= 8.5) return "Normal"; return v < 7 ? "Rendah" : "Tinggi"; }
  Color _getPhStatusBg() { final v = double.tryParse(ph); if (v == null) return AppColors.grayLight; if (v >= 7 && v <= 8.5) return AppColors.greenLight; return AppColors.amberLight; }
  Color _getPhStatusFg() { final v = double.tryParse(ph); if (v == null) return AppColors.grayText; if (v >= 7 && v <= 8.5) return AppColors.greenText; return AppColors.amberText; }
  String _getDoStatus() { final v = double.tryParse(dissolvedOxygen); if (v == null) return "-"; return v >= 5 ? "Normal" : "Rendah"; }
  Color _getDoStatusBg() { final v = double.tryParse(dissolvedOxygen); if (v == null) return AppColors.grayLight; return v >= 5 ? AppColors.greenLight : AppColors.amberLight; }
  Color _getDoStatusFg() { final v = double.tryParse(dissolvedOxygen); if (v == null) return AppColors.grayText; return v >= 5 ? AppColors.greenText : AppColors.amberText; }

  Widget _sensorCard({required String label, required String value, required String unit, required IconData icon, required Color bgColor, required Color borderColor, required Color accentColor, required Color labelColor, required Color iconBg, required Color iconColor, required Color valueColor, required Color unitColor, required String statusText, required Color statusBg, required Color statusFg}) {
    return Container(
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor, width: 0.5)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: accentColor),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelColor, letterSpacing: 0.5)),
                    Container(width: 28, height: 28, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor, size: 15)),
                  ]),
                  const SizedBox(height: 10),
                  Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: valueColor, height: 1)),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(unit, style: TextStyle(fontSize: 11, color: unitColor)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(99)),
                      child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: statusFg)),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // CHART CARD
  // =====================================================
  Widget _buildChartCard() {
    final charts = {
      'suhu': (spots: suhuHistory, color: AppColors.coralMid,  minY: 20.0, maxY: 40.0, label: 'Suhu', icon: Icons.thermostat_outlined, activeBg: AppColors.coralLight,  activeFg: AppColors.coralIconText),
      'ph':   (spots: phHistory,   color: AppColors.purpleMid, minY:  0.0, maxY: 14.0, label: 'pH',   icon: Icons.science_outlined,     activeBg: AppColors.purpleLight, activeFg: AppColors.purpleIconText),
      'do':   (spots: doHistory,   color: AppColors.tealMid,   minY:  0.0, maxY: 10.0, label: 'DO',   icon: Icons.water_drop_outlined,  activeBg: AppColors.tealLight,   activeFg: AppColors.tealIconText),
    };
    final cur = charts[_selectedChart]!;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 0.5)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text("Grafik historis", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            Text("1 jam terakhir", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(99)),
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: charts.entries.map((e) {
                final isActive = _selectedChart == e.key;
                final c = e.value;
                return GestureDetector(
                  onTap: () => setState(() => _selectedChart = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: isActive ? c.activeBg : Colors.transparent, borderRadius: BorderRadius.circular(99), border: isActive ? Border.all(color: c.color.withOpacity(0.3), width: 0.5) : null),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(c.icon, size: 13, color: isActive ? c.activeFg : Colors.grey.shade400),
                      const SizedBox(width: 5),
                      Text(c.label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? c.activeFg : Colors.grey.shade500)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: cur.spots.isEmpty
                ? Center(child: Text("Belum ada data", style: TextStyle(fontSize: 13, color: Colors.grey.shade400)))
                : LineChart(LineChartData(
                    minY: cur.minY, maxY: cur.maxY,
                    gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade100, strokeWidth: 1)),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0), style: TextStyle(fontSize: 10, color: Colors.grey.shade400)))),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < timeLabels.length && idx % (timeLabels.length ~/ 5 + 1) == 0) {
                          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(timeLabels[idx], style: TextStyle(fontSize: 10, color: Colors.grey.shade400)));
                        }
                        return const SizedBox.shrink();
                      })),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [LineChartBarData(spots: cur.spots, isCurved: true, color: cur.color, barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: cur.color.withOpacity(0.08)))],
                  )),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // BOTTOM SECTION
  // =====================================================
  Widget _buildBottomSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: _buildModeCard()),
        const SizedBox(width: 12),
        Expanded(flex: 5, child: _buildActuatorCard()),
      ],
    );
  }

  Widget _buildModeCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 0.5)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardSectionTitle("Mode & status"),
          const SizedBox(height: 12),
          Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.auto_mode, size: 15, color: AppColors.purpleMid)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Mode operasi", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              Text(autoMode ? "Auto-kontrol" : "Kontrol manual", style: const TextStyle(fontSize: 11, color: AppColors.grayText)),
            ])),
            Switch(value: autoMode, onChanged: (v) => publishMode(v ? "AUTO" : "MANUAL"), activeColor: AppColors.tealMid, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ]),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(children: [
              _infoRow("Status sistem", systemStatus.replaceAll('_', ' '), valueColor: statusColor),
              const SizedBox(height: 6),
              _infoRow("ESP32", _esp32BadgeLabel, valueColor: _esp32BadgeFg),
              const SizedBox(height: 6),
              _infoRow("MQTT", connectionStatus),
              const SizedBox(height: 6),
              _infoRow("Data log", "$logCount entri"),
              if (_esp32Ip.isNotEmpty) ...[
                const SizedBox(height: 6),
                _infoRow("IP ESP32", _esp32Ip),
              ],
              // ── Countdown ringkas di mode card ──
              if (_dosingState != DosingState.idle) ...[
                const SizedBox(height: 8),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(_countdownIcon, size: 13, color: _countdownColor),
                      const SizedBox(width: 5),
                      Text(_countdownLabel, style: TextStyle(fontSize: 11, color: _countdownColor, fontWeight: FontWeight.w500)),
                    ]),
                    Text(
                      _formatCountdown(_countdownSeconds),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _countdownColor),
                    ),
                  ],
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.grayText)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: valueColor ?? const Color(0xFF1A1A1A))),
      ],
    );
  }

  Widget _buildActuatorCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 0.5)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _cardSectionTitle("Kontrol aktuator"),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: autoMode ? AppColors.greenLight : AppColors.blueLight, borderRadius: BorderRadius.circular(99)),
              child: Text(autoMode ? "Auto" : "Manual", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: autoMode ? AppColors.greenText : AppColors.blueText)),
            ),
          ]),
          const SizedBox(height: 10),
          _actuatorRow(label: "Aerator utama",    value: aeratorUtama,    isFixed: true, fixedLabel: "24 jam"),
          _actuatorRow(label: "Aerator backup",   value: aeratorBackup,   onChanged: autoMode ? null : (v) => publishRelay(_cfg.topic('control/aerator_backup'), v)),
          _actuatorRow(label: "Pengaduk dolomit", value: pengadukDolomit, onChanged: autoMode ? null : (v) => publishRelay(_cfg.topic('control/pengaduk_dolomit'), v)),
          _actuatorRow(label: "Pompa dolomit",    value: pompaDolomit,    onChanged: autoMode ? null : (v) => publishRelay(_cfg.topic('control/pompa_dolomit'), v)),
          _actuatorRow(label: "Solenoid masuk",   value: solenoidIn,      onChanged: autoMode ? null : (v) => publishRelay(_cfg.topic('control/solenoid_in'), v)),
          _actuatorRow(label: "Solenoid keluar",  value: solenoidOut, isLast: true, onChanged: autoMode ? null : (v) => publishRelay(_cfg.topic('control/solenoid_out'), v)),
        ],
      ),
    );
  }

  Widget _cardSectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));

  Widget _actuatorRow({required String label, required bool value, bool isFixed = false, String? fixedLabel, bool isLast = false, ValueChanged<bool>? onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: isFixed ? AppColors.amberBorder : value ? AppColors.tealMid : AppColors.grayMid, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          if (isFixed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.amberLight, borderRadius: BorderRadius.circular(99)),
              child: Text(fixedLabel ?? "Fixed", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.amberDark)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: value ? AppColors.greenLight : AppColors.grayLight, borderRadius: BorderRadius.circular(99)),
              child: Text(value ? "Aktif" : "Mati", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: value ? AppColors.greenText : AppColors.grayText)),
            ),
            const SizedBox(width: 6),
            SizedBox(height: 24, child: Switch(value: value, onChanged: onChanged, activeColor: AppColors.tealMid, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
          ],
        ],
      ),
    );
  }
}
