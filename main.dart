// =======================================================
// IMPORT
// =======================================================
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

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
// ESP32 CONNECTION STATUS ENUM
// =======================================================
enum Esp32Status {
  connecting,   // MQTT belum terhubung
  wifiOk,       // ESP32 WiFi terhubung (dari topic)
  mqttOk,       // MQTT terhubung ke broker
  online,       // keduanya terhubung & data mengalir
  offline,      // terputus
}

// =======================================================
// MAIN
// =======================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.tealMid,
          brightness: Brightness.light,
        ),
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
      home: const MQTTPage(),
    );
  }
}

// =======================================================
// MQTT PAGE
// =======================================================
class MQTTPage extends StatefulWidget {
  const MQTTPage({super.key});

  @override
  State<MQTTPage> createState() => _MQTTPageState();
}

class _MQTTPageState extends State<MQTTPage> {

  // =====================================================
  // FIREBASE
  // =====================================================
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // =====================================================
  // MQTT CLIENT
  // =====================================================
  final client = MqttServerClient(
    '007d3469a2244841a48f1259a6b6494e.s1.eu.hivemq.cloud',
    'flutter_client',
  );

  // =====================================================
  // STATE — MQTT & SENSOR
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
  // Status gabungan: MQTT + WiFi ESP32 (dari topic)
  Esp32Status _esp32Status   = Esp32Status.connecting;
  bool        _esp32WifiOk   = false;   // dari kolam1/status/wifi
  bool        _mqttConnected = false;   // dari onConnected / onDisconnected
  String      _esp32Ip       = "";      // opsional: IP ESP32 jika dikirim

  // Overlay "Connecting" — fullscreen blocking
  OverlayEntry? _connectingOverlay;
  // Apakah toast "Connected" sudah pernah ditampilkan (hindari duplikat)
  bool _connectedToastShown = false;

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
    // Tampilkan overlay connecting langsung saat app buka
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showConnectingOverlay();
    });
    connectMQTT();
    loadHistoryData();
  }

  @override
  void dispose() {
    _connectingOverlay?.remove();
    client.disconnect();
    super.dispose();
  }

  // =====================================================
  // UPDATE ESP32 STATUS
  // Dipanggil setiap kali ada perubahan _mqttConnected
  // atau _esp32WifiOk agar status gabungan selalu sinkron
  // =====================================================
  void _updateEsp32Status() {
    Esp32Status newStatus;

    if (!_mqttConnected) {
      // MQTT belum/tidak terhubung → pasti connecting/offline
      newStatus = Esp32Status.connecting;
    } else if (_mqttConnected && !_esp32WifiOk) {
      // MQTT terhubung tapi belum terima konfirmasi WiFi ESP32
      newStatus = Esp32Status.mqttOk;
    } else {
      // MQTT terhubung + WiFi ESP32 terkonfirmasi
      newStatus = Esp32Status.online;
    }

    final wasConnecting = _esp32Status == Esp32Status.connecting ||
                          _esp32Status == Esp32Status.offline;
    final nowOnline     = newStatus == Esp32Status.mqttOk ||
                          newStatus == Esp32Status.online;

    setState(() => _esp32Status = newStatus);

    // Transisi dari offline/connecting → online: tutup overlay, tampilkan toast
    if (wasConnecting && nowOnline) {
      _removeConnectingOverlay();
      if (!_connectedToastShown) {
        _connectedToastShown = true;
        _showConnectedToast();
        // Reset flag setelah 5 detik supaya toast bisa muncul lagi jika putus-konek ulang
        Future.delayed(const Duration(seconds: 5), () => _connectedToastShown = false);
      }
    }

    // Transisi dari online → offline: tampilkan overlay connecting
    if (!wasConnecting && newStatus == Esp32Status.connecting) {
      _connectedToastShown = false;
      _showConnectingOverlay();
    }
  }

  // =====================================================
  // CONNECT MQTT
  // =====================================================
  Future<void> connectMQTT() async {
    client.port = 8883;
    client.secure = true;
    client.securityContext = SecurityContext.defaultContext;
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.logging(on: false);
    client.onConnected    = onConnected;
    client.onDisconnected = onDisconnected;
    client.setProtocolV311();

    // ── Last Will Testament ───────────────────────────
    // Broker otomatis publish pesan ini jika ESP32 putus
    // (diset dari sisi ESP32, bukan Flutter)
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .authenticateAs('Test123', 'Test1234')
        .startClean();

    try {
      await client.connect();
    } catch (e) {
      debugPrint("MQTT ERROR: $e");
      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      client.subscribe('kolam1/sensor/#',    MqttQos.atLeastOnce);
      client.subscribe('kolam1/status/#',    MqttQos.atLeastOnce);
      // ── Subscribe status WiFi ESP32 ──────────────────
      // ESP32 harus publish ke topic ini saat WiFi terhubung
      // Payload: {"connected": true, "ssid": "NamaWifi", "ip": "192.168.x.x"}
      client.subscribe('kolam1/device/wifi', MqttQos.atLeastOnce);
    }

    client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      final recMess = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      final topic = messages[0].topic;

      try {
        final data = jsonDecode(payload);
        setState(() {
          if (topic == 'kolam1/sensor/suhu')              suhu = data['value'].toStringAsFixed(2);
          if (topic == 'kolam1/sensor/ph')                ph   = data['value'].toStringAsFixed(2);
          if (topic == 'kolam1/sensor/do')                dissolvedOxygen = data['value'].toStringAsFixed(2);
          if (topic == 'kolam1/status/mode')              autoMode = data['mode'] == "AUTO";
          if (topic == 'kolam1/status/system')            systemStatus = data['status'];
          if (topic == 'kolam1/status/aerator_backup')    aeratorBackup = data['state'];
          if (topic == 'kolam1/status/pengaduk_dolomit')  pengadukDolomit = data['state'];
          if (topic == 'kolam1/status/pompa_dolomit')     pompaDolomit = data['state'];
          if (topic == 'kolam1/status/solenoid_in')       solenoidIn   = data['state'];
          if (topic == 'kolam1/status/solenoid_out')      solenoidOut  = data['state'];

          // ── Opsi A: terima status WiFi ESP32 ───────────
          if (topic == 'kolam1/device/wifi') {
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
      } catch (e) {
        debugPrint("JSON ERROR: $e");
      }
    });
  }

  // =====================================================
  // ON CONNECTED — Opsi B: MQTT terhubung
  // =====================================================
  void onConnected() {
    setState(() {
      connectionStatus = "Connected";
      _mqttConnected   = true;
    });
    _updateEsp32Status();
  }

  // =====================================================
  // ON DISCONNECTED — Opsi B: MQTT putus
  // =====================================================
  void onDisconnected() {
    setState(() {
      connectionStatus = "Disconnected";
      systemStatus     = "DISCONNECT";
      _mqttConnected   = false;
      _esp32WifiOk     = false;
    });
    _updateEsp32Status();
  }

  // =====================================================
  // OVERLAY: CONNECTING — fullscreen, tidak bisa ditutup
  // =====================================================
  void _showConnectingOverlay() {
    if (_connectingOverlay != null) return; // jangan dobel

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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ikon ESP32 / perangkat
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: AppColors.grayLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.developer_board_rounded,
                    size: 34,
                    color: AppColors.grayMid,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Menghubungkan perangkat",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Menunggu ESP32 terhubung\nke jaringan WiFi...",
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.grayText,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Step indikator
                _connectingSteps(),
                const SizedBox(height: 24),
                // Spinner
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.grayMid),
                  ),
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

  // ── Step indikator di dalam overlay ──
  Widget _connectingSteps() {
    return Column(
      children: [
        _stepRow(
          icon: Icons.wifi_rounded,
          label: "ESP32 → WiFi",
          done: _esp32WifiOk,
          active: !_esp32WifiOk,
        ),
        const SizedBox(height: 8),
        _stepRow(
          icon: Icons.cloud_rounded,
          label: "ESP32 → Broker MQTT",
          done: _mqttConnected,
          active: _esp32WifiOk && !_mqttConnected,
        ),
      ],
    );
  }

  Widget _stepRow({
    required IconData icon,
    required String label,
    required bool done,
    required bool active,
  }) {
    final color = done
        ? AppColors.tealMid
        : active
            ? AppColors.amberBorder
            : AppColors.grayMid;
    final bg = done
        ? AppColors.tealLight
        : active
            ? AppColors.amberLight
            : AppColors.grayLight;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(
            done ? Icons.check_rounded : icon,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  // =====================================================
  // HAPUS OVERLAY CONNECTING
  // =====================================================
  void _removeConnectingOverlay() {
    _connectingOverlay?.remove();
    _connectingOverlay = null;
  }

  // =====================================================
  // TOAST: CONNECTED — slide dari atas, auto-dismiss
  // =====================================================
  void _showConnectedToast() {
    final isFullyOnline = _esp32Status == Esp32Status.online;

    OverlayEntry? toast;
    toast = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 14,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Transform.translate(
              offset: Offset(0, -28 * (1 - v)),
              child: Opacity(opacity: v, child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isFullyOnline ? AppColors.tealLight : AppColors.amberLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFullyOnline ? AppColors.tealBorder : AppColors.amberBorder,
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isFullyOnline ? AppColors.tealMid : AppColors.amberBorder)
                        .withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Ikon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isFullyOnline ? AppColors.tealIcon : AppColors.amberIcon,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFullyOnline
                          ? Icons.developer_board_rounded
                          : Icons.cloud_done_rounded,
                      size: 20,
                      color: isFullyOnline
                          ? AppColors.tealIconText
                          : AppColors.amberIconText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Teks
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isFullyOnline
                              ? "ESP32 terhubung"
                              : "Broker MQTT terhubung",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isFullyOnline
                                ? AppColors.tealDark
                                : AppColors.amberDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isFullyOnline
                              ? "WiFi & MQTT aktif${_esp32Ip.isNotEmpty ? ' · $_esp32Ip' : ''}"
                              : "Menunggu konfirmasi WiFi ESP32...",
                          style: TextStyle(
                            fontSize: 12,
                            color: isFullyOnline
                                ? AppColors.tealLabel
                                : AppColors.amberText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Dot status
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isFullyOnline ? AppColors.tealMid : AppColors.amberBorder,
                      shape: BoxShape.circle,
                    ),
                  ),
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
  // SAVE SENSOR DATA
  // =====================================================
  Future<void> saveSensorData() async {
    try {
      await firestore.collection('sensor_log').add({
        'timestamp': Timestamp.now(),
        'suhu': double.tryParse(suhu) ?? 0,
        'ph':   double.tryParse(ph)   ?? 0,
        'do':   double.tryParse(dissolvedOxygen) ?? 0,
        'status': systemStatus,
        'auto_mode': autoMode,
      });
      setState(() => logCount++);
    } catch (e) {
      debugPrint("FIREBASE ERROR: $e");
    }
  }

  // =====================================================
  // LOAD FIREBASE HISTORY
  // =====================================================
  Future<void> loadHistoryData() async {
    try {
      final oneHourAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      final snapshot = await firestore
          .collection('sensor_log')
          .where('timestamp', isGreaterThan: oneHourAgo)
          .orderBy('timestamp')
          .get();

      suhuHistory.clear();
      phHistory.clear();
      doHistory.clear();
      timeLabels.clear();

      int index = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        suhuHistory.add(FlSpot(index.toDouble(), (data['suhu'] ?? 0).toDouble()));
        phHistory.add(FlSpot(index.toDouble(),   (data['ph']   ?? 0).toDouble()));
        doHistory.add(FlSpot(index.toDouble(),   (data['do']   ?? 0).toDouble()));
        final ts = (data['timestamp'] as Timestamp).toDate();
        timeLabels.add(DateFormat('HH:mm').format(ts));
        index++;
      }
      setState(() => logCount = snapshot.docs.length);
    } catch (e) {
      debugPrint("LOAD HISTORY ERROR: $e");
    }
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
    client.publishMessage('kolam1/system/mode', MqttQos.atLeastOnce, builder.payload!);
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
      case "NORMAL":     return "Semua parameter normal";
      case "LOW_DO":     return "Oksigen terlarut rendah";
      case "LOW_PH":     return "pH berada di bawah ambang batas";
      case "HIGH_PH":    return "pH berada di atas ambang batas";
      case "FAILSAFE":   return "Mode failsafe aktif";
      case "DISCONNECT": return "ESP32 tidak terhubung";
      default:           return "-";
    }
  }

  // ── Label & warna badge ESP32 di header ──
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
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.tealMid,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.water, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "IoT Kolam Ikan",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                "Kolam 1 · Monitoring real-time",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        // ── Badge status ESP32 (gabungan WiFi + MQTT) ──
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _esp32BadgeBg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: _esp32BadgeFg.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Spinner saat connecting, ikon biasa saat lainnya
              _esp32Status == Esp32Status.connecting
                  ? SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(_esp32BadgeFg),
                      ),
                    )
                  : Icon(_esp32BadgeIcon, size: 13, color: _esp32BadgeFg),
              const SizedBox(width: 6),
              Text(
                _esp32BadgeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _esp32BadgeFg,
                ),
              ),
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              systemStatus == "NORMAL"
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  systemStatus == "DISCONNECT"
                      ? "ESP32 tidak terhubung"
                      : systemStatus.replaceAll('_', ' '),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              "$now WIB",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: statusColor,
              ),
            ),
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
        Expanded(child: _sensorCard(
          label: "Suhu", value: suhu, unit: "°C",
          icon: Icons.thermostat_outlined,
          bgColor: AppColors.coralLight, borderColor: AppColors.coralBorder,
          accentColor: AppColors.coralMid, labelColor: AppColors.coralLabel,
          iconBg: AppColors.coralIcon, iconColor: AppColors.coralIconText,
          valueColor: AppColors.coralDark, unitColor: AppColors.coralUnit,
          statusText: _getSuhuStatus(), statusBg: _getSuhuStatusBg(), statusFg: _getSuhuStatusFg(),
        )),
        const SizedBox(width: 10),
        Expanded(child: _sensorCard(
          label: "pH", value: ph, unit: "pH level",
          icon: Icons.science_outlined,
          bgColor: AppColors.purpleLight, borderColor: AppColors.purpleBorder,
          accentColor: AppColors.purpleMid, labelColor: AppColors.purpleLabel,
          iconBg: AppColors.purpleIcon, iconColor: AppColors.purpleIconText,
          valueColor: AppColors.purpleDark, unitColor: AppColors.purpleUnit,
          statusText: _getPhStatus(), statusBg: _getPhStatusBg(), statusFg: _getPhStatusFg(),
        )),
        const SizedBox(width: 10),
        Expanded(child: _sensorCard(
          label: "DO", value: dissolvedOxygen, unit: "mg/L",
          icon: Icons.water_drop_outlined,
          bgColor: AppColors.tealLight, borderColor: AppColors.tealBorder,
          accentColor: AppColors.tealMid, labelColor: AppColors.tealLabel,
          iconBg: AppColors.tealIcon, iconColor: AppColors.tealIconText,
          valueColor: AppColors.tealDark, unitColor: AppColors.tealUnit,
          statusText: _getDoStatus(), statusBg: _getDoStatusBg(), statusFg: _getDoStatusFg(),
        )),
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

  Widget _sensorCard({
    required String label, required String value, required String unit,
    required IconData icon,
    required Color bgColor, required Color borderColor, required Color accentColor,
    required Color labelColor, required Color iconBg, required Color iconColor,
    required Color valueColor, required Color unitColor,
    required String statusText, required Color statusBg, required Color statusFg,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.5),
      ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelColor, letterSpacing: 0.5)),
                      Container(width: 28, height: 28, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor, size: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: valueColor, height: 1)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(unit, style: TextStyle(fontSize: 11, color: unitColor)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(99)),
                        child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: statusFg)),
                      ),
                    ],
                  ),
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
      'suhu': (spots: suhuHistory, color: AppColors.coralMid,  minY: 20.0, maxY: 40.0, unit: '°C',   label: 'Suhu', icon: Icons.thermostat_outlined, activeBg: AppColors.coralLight,  activeFg: AppColors.coralIconText),
      'ph':   (spots: phHistory,   color: AppColors.purpleMid, minY:  0.0, maxY: 14.0, unit: 'pH',   label: 'pH',   icon: Icons.science_outlined,     activeBg: AppColors.purpleLight, activeFg: AppColors.purpleIconText),
      'do':   (spots: doHistory,   color: AppColors.tealMid,   minY:  0.0, maxY: 10.0, unit: 'mg/L', label: 'DO',   icon: Icons.water_drop_outlined,  activeBg: AppColors.tealLight,   activeFg: AppColors.tealIconText),
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
                    decoration: BoxDecoration(
                      color: isActive ? c.activeBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                      border: isActive ? Border.all(color: c.color.withOpacity(0.3), width: 0.5) : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.icon, size: 13, color: isActive ? c.activeFg : Colors.grey.shade400),
                        const SizedBox(width: 5),
                        Text(c.label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? c.activeFg : Colors.grey.shade500)),
                      ],
                    ),
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
          Row(
            children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.auto_mode, size: 15, color: AppColors.purpleMid)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Mode operasi", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                Text(autoMode ? "Auto-kontrol" : "Kontrol manual", style: const TextStyle(fontSize: 11, color: AppColors.grayText)),
              ])),
              Switch(value: autoMode, onChanged: (v) => publishMode(v ? "AUTO" : "MANUAL"), activeColor: AppColors.tealMid, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ],
          ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _cardSectionTitle("Kontrol aktuator"),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: autoMode ? AppColors.greenLight : AppColors.blueLight, borderRadius: BorderRadius.circular(99)),
                child: Text(autoMode ? "Auto" : "Manual", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: autoMode ? AppColors.greenText : AppColors.blueText)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _actuatorRow(label: "Aerator utama",   value: aeratorUtama,    isFixed: true, fixedLabel: "24 jam"),
          _actuatorRow(label: "Aerator backup",  value: aeratorBackup,   onChanged: autoMode ? null : (v) => publishRelay('kolam1/control/aerator_backup', v)),
          _actuatorRow(label: "Pengaduk dolomit",value: pengadukDolomit, onChanged: autoMode ? null : (v) => publishRelay('kolam1/control/pengaduk_dolomit', v)),
          _actuatorRow(label: "Pompa dolomit",   value: pompaDolomit,    onChanged: autoMode ? null : (v) => publishRelay('kolam1/control/pompa_dolomit', v)),
          _actuatorRow(label: "Solenoid masuk",  value: solenoidIn,      onChanged: autoMode ? null : (v) => publishRelay('kolam1/control/solenoid_in', v)),
          _actuatorRow(label: "Solenoid keluar", value: solenoidOut, isLast: true, onChanged: autoMode ? null : (v) => publishRelay('kolam1/control/solenoid_out', v)),
        ],
      ),
    );
  }

  Widget _cardSectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));

  Widget _actuatorRow({
    required String label, required bool value,
    bool isFixed = false, String? fixedLabel, bool isLast = false,
    ValueChanged<bool>? onChanged,
  }) {
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
