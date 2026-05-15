import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options:
        DefaultFirebaseOptions.currentPlatform,
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
        primarySwatch: Colors.blue,
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
  State<MQTTPage> createState() =>
      _MQTTPageState();
}

class _MQTTPageState
    extends State<MQTTPage> {

  // =====================================================
  // FIREBASE
  // =====================================================
  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  // =====================================================
  // MQTT CLIENT
  // =====================================================
  final client = MqttServerClient(
    '007d3469a2244841a48f1259a6b6494e.s1.eu.hivemq.cloud',
    'flutter_client',
  );

  // =====================================================
  // MQTT STATUS
  // =====================================================
  String connectionStatus =
      "Disconnected";

  // =====================================================
  // SYSTEM STATUS
  // =====================================================
  String systemStatus =
      "DISCONNECT";

  // =====================================================
  // SENSOR VALUE
  // =====================================================
  String suhu = "-";
  String ph = "-";
  String dissolvedOxygen = "-";

  // =====================================================
  // SYSTEM MODE
  // =====================================================
  bool autoMode = false;

  // =====================================================
  // RELAY STATUS
  // =====================================================
  bool aeratorUtama = true;
  bool aeratorBackup = false;
  bool pengadukDolomit = false;
  bool pompaDolomit = false;
  bool solenoidIn = false;
  bool solenoidOut = false;

  // =====================================================
  // TIMER DATA LOG
  // =====================================================
  DateTime? lastLogTime;

  // =====================================================
  // INIT
  // =====================================================
  @override
  void initState() {

    super.initState();

    connectMQTT();
  }

  // =====================================================
  // CONNECT MQTT
  // =====================================================
  Future<void> connectMQTT() async {

    client.port = 8883;

    client.secure = true;

    client.securityContext =
        SecurityContext.defaultContext;

    client.keepAlivePeriod = 20;

    client.autoReconnect = true;

    client.logging(on: false);

    client.onConnected =
        onConnected;

    client.onDisconnected =
        onDisconnected;

    client.setProtocolV311();

    client.connectionMessage =
        MqttConnectMessage()
            .withClientIdentifier(
                'flutter_client')
            .authenticateAs(
              'Test123',
              'Test1234',
            )
            .startClean();

    try {

      await client.connect();

    } catch (e) {

      print("MQTT ERROR: $e");

      client.disconnect();
    }

    // ===================================================
    // SUBSCRIBE
    // ===================================================
    if (client.connectionStatus!.state ==
        MqttConnectionState.connected) {

      // SENSOR
      client.subscribe(
        'kolam1/sensor/#',
        MqttQos.atLeastOnce,
      );

      // STATUS
      client.subscribe(
        'kolam1/status/#',
        MqttQos.atLeastOnce,
      );

      print("MQTT Connected");
    }

    // ===================================================
    // LISTENER
    // ===================================================
    client.updates?.listen(

      (
        List<
            MqttReceivedMessage<
                MqttMessage>> messages,
      ) {

        final recMess =
            messages[0].payload
                as MqttPublishMessage;

        final payload =
            MqttPublishPayload
                .bytesToStringAsString(
          recMess.payload.message,
        );

        final topic =
            messages[0].topic;

        print(topic);
        print(payload);

        try {

          final data =
              jsonDecode(payload);

          setState(() {

            // =========================================
            // SENSOR SUHU
            // =========================================
            if (topic ==
                'kolam1/sensor/suhu') {

              suhu =
                  data['value']
                      .toStringAsFixed(2);
            }

            // =========================================
            // SENSOR PH
            // =========================================
            if (topic ==
                'kolam1/sensor/ph') {

              ph =
                  data['value']
                      .toStringAsFixed(2);
            }

            // =========================================
            // SENSOR DO
            // =========================================
            if (topic ==
                'kolam1/sensor/do') {

              dissolvedOxygen =
                  data['value']
                      .toStringAsFixed(2);
            }

            // =========================================
            // MODE STATUS
            // =========================================
            if (topic ==
                'kolam1/status/mode') {

              autoMode =
                  data['mode'] ==
                      "AUTO";
            }

            // =========================================
            // SYSTEM STATUS
            // =========================================
            if (topic ==
                'kolam1/status/system') {

              systemStatus =
                  data['status'];
            }

            // =========================================
            // AERATOR BACKUP
            // =========================================
            if (topic ==
                'kolam1/status/aerator_backup') {

              aeratorBackup =
                  data['state'];
            }

            // =========================================
            // PENGADUK DOLOMIT
            // =========================================
            if (topic ==
                'kolam1/status/pengaduk_dolomit') {

              pengadukDolomit =
                  data['state'];
            }

            // =========================================
            // POMPA DOLOMIT
            // =========================================
            if (topic ==
                'kolam1/status/pompa_dolomit') {

              pompaDolomit =
                  data['state'];
            }

            // =========================================
            // SOLENOID IN
            // =========================================
            if (topic ==
                'kolam1/status/solenoid_in') {

              solenoidIn =
                  data['state'];
            }

            // =========================================
            // SOLENOID OUT
            // =========================================
            if (topic ==
                'kolam1/status/solenoid_out') {

              solenoidOut =
                  data['state'];
            }
          });

          // =============================================
          // AUTO SAVE FIREBASE
          // =============================================
          if (
              lastLogTime == null ||
              DateTime.now()
                      .difference(
                          lastLogTime!)
                      .inMinutes >=
                  1
             ) {

            saveSensorData();

            lastLogTime =
                DateTime.now();
          }

        } catch (e) {

          print(
              "JSON ERROR: $e");
        }
      },
    );
  }

  // =====================================================
  // SAVE SENSOR DATA
  // =====================================================
  Future<void> saveSensorData()
      async {

    try {

      await firestore
          .collection(
              'sensor_log')
          .add({

        'timestamp':
            Timestamp.now(),

        'suhu':
            double.tryParse(
                    suhu) ??
                0,

        'ph':
            double.tryParse(
                    ph) ??
                0,

        'do':
            double.tryParse(
                    dissolvedOxygen) ??
                0,

        'status':
            systemStatus,

        'auto_mode':
            autoMode,
      });

      print("DATA SAVED");

    } catch (e) {

      print(
          "FIREBASE ERROR: $e");
    }
  }

  // =====================================================
  // CONNECTED
  // =====================================================
  void onConnected() {

    setState(() {

      connectionStatus =
          "Connected";
    });

    print("CONNECTED");
  }

  // =====================================================
  // DISCONNECTED
  // =====================================================
  void onDisconnected() {

    setState(() {

      connectionStatus =
          "Disconnected";

      systemStatus =
          "DISCONNECT";
    });

    print("DISCONNECTED");
  }

  // =====================================================
  // PUBLISH RELAY
  // =====================================================
  void publishRelay(
    String topic,
    bool state,
  ) {

    final builder =
        MqttClientPayloadBuilder();

    final payload =
        jsonEncode({
      "state": state,
    });

    builder.addString(payload);

    client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  // =====================================================
  // PUBLISH MODE
  // =====================================================
  void publishMode(
      String mode) {

    final builder =
        MqttClientPayloadBuilder();

    final payload =
        jsonEncode({
      "mode": mode,
    });

    builder.addString(payload);

    client.publishMessage(
      'kolam1/system/mode',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  // =====================================================
  // STATUS COLOR
  // =====================================================
  Color getStatusColor() {

    switch (systemStatus) {

      case "NORMAL":
        return Colors.green;

      case "LOW_DO":
        return Colors.blue;

      case "LOW_PH":
        return Colors.orange;

      case "HIGH_PH":
        return Colors.deepOrange;

      case "FAILSAFE":
        return Colors.red;

      case "DISCONNECT":
        return Colors.grey;

      default:
        return Colors.black;
    }
  }

  // =====================================================
  // DISPOSE
  // =====================================================
  @override
  void dispose() {

    client.disconnect();

    super.dispose();
  }

  // =====================================================
  // UI
  // =====================================================
  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: const Text(
          "IoT Kolam Ikan",
        ),

        centerTitle: true,
      ),

      body:
          SingleChildScrollView(

        child: Padding(

          padding:
              const EdgeInsets.all(
                  20),

          child: Column(

            crossAxisAlignment:
                CrossAxisAlignment
                    .start,

            children: [

              // =======================================
              // MQTT STATUS
              // =======================================
              Text(
                "MQTT Status : $connectionStatus",

                style:
                    const TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                  height: 20),

              // =======================================
              // SYSTEM STATUS
              // =======================================
              Container(

                width:
                    double.infinity,

                padding:
                    const EdgeInsets
                        .all(20),

                decoration:
                    BoxDecoration(

                  color:
                      getStatusColor(),

                  borderRadius:
                      BorderRadius
                          .circular(
                              15),
                ),

                child: Column(

                  children: [

                    const Text(
                      "STATUS MONITORING",

                      style:
                          TextStyle(
                        color: Colors
                            .white,

                        fontSize:
                            18,

                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),

                    const SizedBox(
                        height: 10),

                    Text(
                      systemStatus,

                      style:
                          const TextStyle(
                        color: Colors
                            .white,

                        fontSize:
                            32,

                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                  height: 30),

              // =======================================
              // SENSOR
              // =======================================
              const Text(
                "Monitoring Sensor",

                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                  height: 20),

              sensorCard(
                "Suhu",
                "$suhu °C",
                Icons.thermostat,
              ),

              sensorCard(
                "pH",
                ph,
                Icons.science,
              ),

              sensorCard(
                "DO",
                "$dissolvedOxygen mg/L",
                Icons.water_drop,
              ),

              const SizedBox(
                  height: 30),

              // =======================================
              // AUTO MODE
              // =======================================
              Card(

                child:
                    SwitchListTile(

                  title:
                      const Text(
                    "AUTO MODE",

                    style:
                        TextStyle(
                      fontSize:
                          22,

                      fontWeight:
                          FontWeight
                              .bold,
                    ),
                  ),

                  value:
                      autoMode,

                  onChanged:
                      (value) {

                    if (value) {

                      publishMode(
                          "AUTO");

                    } else {

                      publishMode(
                          "MANUAL");
                    }
                  },
                ),
              ),

              const SizedBox(
                  height: 30),

              // =======================================
              // CONTROL
              // =======================================
              const Text(
                "Kontrol Aktuator",

                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                  height: 20),

              actuatorSwitch(
                "Aerator Utama (24 Jam)",
                aeratorUtama,
                null,
              ),

              actuatorSwitch(
                "Aerator Backup",
                aeratorBackup,
                autoMode
                    ? null
                    : (value) {

                        publishRelay(
                          'kolam1/control/aerator_backup',
                          value,
                        );
                      },
              ),

              actuatorSwitch(
                "Pengaduk Dolomit",
                pengadukDolomit,
                autoMode
                    ? null
                    : (value) {

                        publishRelay(
                          'kolam1/control/pengaduk_dolomit',
                          value,
                        );
                      },
              ),

              actuatorSwitch(
                "Pompa Dolomit",
                pompaDolomit,
                autoMode
                    ? null
                    : (value) {

                        publishRelay(
                          'kolam1/control/pompa_dolomit',
                          value,
                        );
                      },
              ),

              actuatorSwitch(
                "Solenoid Air Masuk",
                solenoidIn,
                autoMode
                    ? null
                    : (value) {

                        publishRelay(
                          'kolam1/control/solenoid_in',
                          value,
                        );
                      },
              ),

              actuatorSwitch(
                "Solenoid Air Keluar",
                solenoidOut,
                autoMode
                    ? null
                    : (value) {

                        publishRelay(
                          'kolam1/control/solenoid_out',
                          value,
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // SENSOR CARD
  // =====================================================
  Widget sensorCard(
    String title,
    String value,
    IconData icon,
  ) {

    return Card(

      elevation: 4,

      margin:
          const EdgeInsets.only(
              bottom: 15),

      child: ListTile(

        leading: Icon(
          icon,
          size: 35,
        ),

        title: Text(
          title,

          style:
              const TextStyle(
            fontSize: 22,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        trailing: Text(
          value,

          style:
              const TextStyle(
            fontSize: 22,
          ),
        ),
      ),
    );
  }

  // =====================================================
  // ACTUATOR SWITCH
  // =====================================================
  Widget actuatorSwitch(
    String title,
    bool value,
    Function(bool)?
        onChanged,
  ) {

    return Card(

      elevation: 4,

      margin:
          const EdgeInsets.only(
              bottom: 15),

      child:
          SwitchListTile(

        title: Text(
          title,

          style:
              const TextStyle(
            fontSize: 20,
          ),
        ),

        value: value,

        onChanged:
            onChanged,
      ),
    );
  }
}
