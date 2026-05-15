#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

#include <OneWire.h>
#include <DallasTemperature.h>

// =====================================================
// WIFI
// =====================================================
const char* ssid = "WATON";
const char* password = "yalalwaton";

// =====================================================
// MQTT
// =====================================================
const char* mqtt_server =
"007d3469a2244841a48f1259a6b6494e.s1.eu.hivemq.cloud";

const int mqtt_port = 8883;

const char* mqtt_user = "Test123";
const char* mqtt_password = "Test1234";

// =====================================================
// SENSOR PIN
// =====================================================
#define PH_PIN          34
#define DO_PIN          35
#define SUHU_PIN        4

// =====================================================
// RELAY PIN
// =====================================================
#define RELAY_AERATOR_UTAMA     16
#define RELAY_AERATOR_BACKUP    17
#define RELAY_PENGADUK_DOLOMIT  5
#define RELAY_POMPA_DOLOMIT     18
#define RELAY_SOLENOID_IN       19
#define RELAY_SOLENOID_OUT      23

// =====================================================
// I2C PIN
// =====================================================
#define SDA_PIN 21
#define SCL_PIN 22

// =====================================================
// PH CALIBRATION
// =====================================================
float calibration_value = 21.34 + 0.6;

// =====================================================
// DS18B20
// =====================================================
OneWire oneWire(SUHU_PIN);

DallasTemperature sensors(&oneWire);

// =====================================================
// MQTT CLIENT
// =====================================================
WiFiClientSecure espClient;

PubSubClient client(espClient);

// =====================================================
// TIMER
// =====================================================
unsigned long lastPublish = 0;

// =====================================================
// SYSTEM MODE
// =====================================================
bool autoMode = false;

// =====================================================
// SAFE MODE
// =====================================================
bool safeMode = false;

// =====================================================
// RELAY STATUS
// =====================================================
bool aeratorBackupState = false;
bool pengadukDolomitState = false;
bool pompaDolomitState = false;
bool solenoidInState = false;
bool solenoidOutState = false;

// =====================================================
// DOSING STATE MACHINE
// =====================================================
enum DosingState {

  IDLE,
  MIXING,
  DOSING,
  AERATION
};

DosingState dosingState = IDLE;

// =====================================================
// DOSING TIMER
// =====================================================
unsigned long mixingStartTime = 0;

unsigned long dosingStartTime = 0;

unsigned long aerationStartTime = 0;

// =====================================================
// DOSING DURATION
// =====================================================
const unsigned long MIXING_DURATION =
60000;

const unsigned long DOSING_DURATION =
20000;

const unsigned long AERATION_DURATION =
900000;

// =====================================================
// DOSING LOCK
// =====================================================
bool dosingProcessActive = false;

// =====================================================
// CONNECT WIFI
// =====================================================
void setup_wifi() {

  delay(10);

  Serial.println();

  Serial.print("Connecting WiFi: ");

  Serial.println(ssid);

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {

    delay(500);

    Serial.print(".");
  }

  Serial.println();

  Serial.println("WiFi Connected");

  Serial.println(WiFi.localIP());
}

// =====================================================
// PUBLISH RELAY STATUS
// =====================================================
void publishRelayStatus(
  const char* topic,
  bool state
) {

  StaticJsonDocument<200> doc;

  doc["state"] = state;

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish(topic, buffer, true);
}

// =====================================================
// PUBLISH MODE STATUS
// =====================================================
void publishModeStatus() {

  StaticJsonDocument<200> doc;

  doc["mode"] = autoMode ? "AUTO" : "MANUAL";

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish(
    "kolam1/status/mode",
    buffer,
    true
  );
}

// =====================================================
// PUBLISH SAFE MODE STATUS
// =====================================================
void publishSafeModeStatus() {

  StaticJsonDocument<200> doc;

  doc["safe_mode"] = safeMode;

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish(
    "kolam1/status/safe_mode",
    buffer,
    true
  );
}

// =====================================================
// PUBLISH SYSTEM STATUS
// =====================================================
void publishSystemStatus(
  String status
) {

  StaticJsonDocument<200> doc;

  doc["status"] = status;

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish(
    "kolam1/status/system",
    buffer,
    true
  );

  Serial.print("SYSTEM STATUS : ");

  Serial.println(status);
}

// =====================================================
// PUBLISH SENSOR
// =====================================================
void publishSensor(
  const char* topic,
  float value,
  const char* unit
) {

  StaticJsonDocument<200> doc;

  doc["value"] = value;

  doc["unit"] = unit;

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish(topic, buffer, true);
}

// =====================================================
// SAFE MODE
// =====================================================
void activateSafeMode() {

  safeMode = true;

  Serial.println("SAFE MODE ACTIVE");

  // =========================================
  // AERATOR BACKUP ON
  // =========================================
  aeratorBackupState = true;

  digitalWrite(
    RELAY_AERATOR_BACKUP,
    LOW
  );

  publishRelayStatus(
    "kolam1/status/aerator_backup",
    true
  );

  // =========================================
  // AKTUATOR LAIN OFF
  // =========================================
  pengadukDolomitState = false;

  pompaDolomitState = false;

  solenoidInState = false;

  solenoidOutState = false;

  digitalWrite(
    RELAY_PENGADUK_DOLOMIT,
    HIGH
  );

  digitalWrite(
    RELAY_POMPA_DOLOMIT,
    HIGH
  );

  digitalWrite(
    RELAY_SOLENOID_IN,
    HIGH
  );

  digitalWrite(
    RELAY_SOLENOID_OUT,
    HIGH
  );

  publishRelayStatus(
    "kolam1/status/pengaduk_dolomit",
    false
  );

  publishRelayStatus(
    "kolam1/status/pompa_dolomit",
    false
  );

  publishRelayStatus(
    "kolam1/status/solenoid_in",
    false
  );

  publishRelayStatus(
    "kolam1/status/solenoid_out",
    false
  );

  publishSafeModeStatus();
}

// =====================================================
// MQTT CALLBACK
// =====================================================
void callback(
  char* topic,
  byte* payload,
  unsigned int length
) {

  String message;

  for (int i = 0; i < length; i++) {

    message += (char)payload[i];
  }

  StaticJsonDocument<200> doc;

  DeserializationError error =
  deserializeJson(doc, message);

  if (error) {

    return;
  }

  // ===================================================
  // SYSTEM MODE
  // ===================================================
  if (String(topic) ==
      "kolam1/system/mode") {

    String mode = doc["mode"];

    autoMode = (mode == "AUTO");

    publishModeStatus();

    return;
  }

  // ===================================================
  // MANUAL MODE ONLY
  // ===================================================
  if (!autoMode && !safeMode) {

    bool state = doc["state"];

    // ===============================================
    // AERATOR BACKUP
    // ===============================================
    if (String(topic) ==
        "kolam1/control/aerator_backup") {

      aeratorBackupState = state;

      digitalWrite(
        RELAY_AERATOR_BACKUP,
        state ? LOW : HIGH
      );

      publishRelayStatus(
        "kolam1/status/aerator_backup",
        state
      );
    }

    // ===============================================
    // PENGADUK DOLOMIT
    // ===============================================
    if (String(topic) ==
        "kolam1/control/pengaduk_dolomit") {

      pengadukDolomitState = state;

      digitalWrite(
        RELAY_PENGADUK_DOLOMIT,
        state ? LOW : HIGH
      );

      publishRelayStatus(
        "kolam1/status/pengaduk_dolomit",
        state
      );
    }

    // ===============================================
    // POMPA DOLOMIT
    // ===============================================
    if (String(topic) ==
        "kolam1/control/pompa_dolomit") {

      pompaDolomitState = state;

      digitalWrite(
        RELAY_POMPA_DOLOMIT,
        state ? LOW : HIGH
      );

      publishRelayStatus(
        "kolam1/status/pompa_dolomit",
        state
      );
    }
  }
}

// =====================================================
// MQTT RECONNECT
// =====================================================
void reconnect() {

  while (!client.connected()) {

    String clientId = "ESP32_KOLAM_";

    clientId += String(random(0xffff), HEX);

    if (client.connect(
          clientId.c_str(),
          mqtt_user,
          mqtt_password)) {

      client.subscribe(
        "kolam1/control/#"
      );

      client.subscribe(
        "kolam1/system/#"
      );

      publishModeStatus();

      publishSafeModeStatus();

    } else {

      delay(5000);
    }
  }
}

// =====================================================
// AUTO CONTROL SYSTEM
// =====================================================
void autoControl(
  float ph,
  float doValue
) {

  // ===================================================
  // DO SAFETY
  // ===================================================
  if (doValue < 4.0) {

    aeratorBackupState = true;

    digitalWrite(
      RELAY_AERATOR_BACKUP,
      LOW
    );

    publishRelayStatus(
      "kolam1/status/aerator_backup",
      true
    );

    return;
  }

  // ===================================================
  // START DOSING
  // ===================================================
  if (
      ph < 7.0 &&
      !dosingProcessActive &&
      dosingState == IDLE
     ) {

    dosingProcessActive = true;

    dosingState = MIXING;

    mixingStartTime = millis();

    // ===============================================
    // AGITATOR ON
    // ===============================================
    pengadukDolomitState = true;

    digitalWrite(
      RELAY_PENGADUK_DOLOMIT,
      LOW
    );

    publishRelayStatus(
      "kolam1/status/pengaduk_dolomit",
      true
    );
  }

  // ===================================================
  // MIXING
  // ===================================================
  if (dosingState == MIXING) {

    if (
        millis() - mixingStartTime >=
        MIXING_DURATION
       ) {

      pengadukDolomitState = false;

      digitalWrite(
        RELAY_PENGADUK_DOLOMIT,
        HIGH
      );

      publishRelayStatus(
        "kolam1/status/pengaduk_dolomit",
        false
      );

      // =============================================
      // POMPA ON
      // =============================================
      pompaDolomitState = true;

      digitalWrite(
        RELAY_POMPA_DOLOMIT,
        LOW
      );

      publishRelayStatus(
        "kolam1/status/pompa_dolomit",
        true
      );

      dosingState = DOSING;

      dosingStartTime = millis();
    }
  }

  // ===================================================
  // DOSING
  // ===================================================
  if (dosingState == DOSING) {

    if (
        millis() - dosingStartTime >=
        DOSING_DURATION
       ) {

      pompaDolomitState = false;

      digitalWrite(
        RELAY_POMPA_DOLOMIT,
        HIGH
      );

      publishRelayStatus(
        "kolam1/status/pompa_dolomit",
        false
      );

      // =============================================
      // AERATOR BACKUP ON
      // =============================================
      aeratorBackupState = true;

      digitalWrite(
        RELAY_AERATOR_BACKUP,
        LOW
      );

      publishRelayStatus(
        "kolam1/status/aerator_backup",
        true
      );

      dosingState = AERATION;

      aerationStartTime = millis();
    }
  }

  // ===================================================
  // AERATION
  // ===================================================
  if (dosingState == AERATION) {

    if (
        millis() - aerationStartTime >=
        AERATION_DURATION
       ) {

      aeratorBackupState = false;

      digitalWrite(
        RELAY_AERATOR_BACKUP,
        HIGH
      );

      publishRelayStatus(
        "kolam1/status/aerator_backup",
        false
      );

      dosingState = IDLE;

      dosingProcessActive = false;
    }
  }
}

// =====================================================
// READ PH
// =====================================================
float readPH() {

  const int samples = 10;

  float total = 0;

  for (int i = 0; i < samples; i++) {

    int adcValue = analogRead(PH_PIN);

    float voltage =
        adcValue * (3.3 / 4095.0);

    float phValue =
        calibration_value - (voltage * 5.70);

    total += phValue;

    delay(20);
  }

  return total / samples;
}

// =====================================================
// READ DO
// =====================================================
float readDO() {

  const int samples = 10;

  float total = 0;

  for (int i = 0; i < samples; i++) {

    int adcValue = analogRead(DO_PIN);

    float voltage =
        adcValue * (3.3 / 4095.0);

    float doValue =
        voltage * 3.0;

    total += doValue;

    delay(20);
  }

  return total / samples;
}

// =====================================================
// READ TEMPERATURE
// =====================================================
float readTemperature() {

  const int samples = 3;

  float total = 0;

  for (int i = 0; i < samples; i++) {

    sensors.requestTemperatures();

    float temp =
        sensors.getTempCByIndex(0);

    total += temp;

    delay(100);
  }

  return total / samples;
}

// =====================================================
// SETUP
// =====================================================
void setup() {

  Serial.begin(115200);

  sensors.begin();

  pinMode(RELAY_AERATOR_UTAMA, OUTPUT);
  pinMode(RELAY_AERATOR_BACKUP, OUTPUT);
  pinMode(RELAY_PENGADUK_DOLOMIT, OUTPUT);
  pinMode(RELAY_POMPA_DOLOMIT, OUTPUT);
  pinMode(RELAY_SOLENOID_IN, OUTPUT);
  pinMode(RELAY_SOLENOID_OUT, OUTPUT);

  // ===================================================
  // AERATOR UTAMA ON
  // ===================================================
  digitalWrite(
    RELAY_AERATOR_UTAMA,
    LOW
  );

  // ===================================================
  // RELAY OFF
  // ===================================================
  digitalWrite(RELAY_AERATOR_BACKUP, HIGH);
  digitalWrite(RELAY_PENGADUK_DOLOMIT, HIGH);
  digitalWrite(RELAY_POMPA_DOLOMIT, HIGH);
  digitalWrite(RELAY_SOLENOID_IN, HIGH);
  digitalWrite(RELAY_SOLENOID_OUT, HIGH);

  setup_wifi();

  espClient.setInsecure();

  client.setServer(
    mqtt_server,
    mqtt_port
  );

  client.setCallback(callback);
}

// =====================================================
// LOOP
// =====================================================
void loop() {

  if (!client.connected()) {

    reconnect();
  }

  client.loop();

  // ===================================================
  // INTERVAL 5 DETIK
  // ===================================================
  if (millis() - lastPublish > 5000) {

    lastPublish = millis();

    // =================================================
    // READ SENSOR
    // =================================================
    float suhu =
        readTemperature();

    float ph =
        readPH();

    float doValue =
        readDO();

    // =================================================
    // SENSOR VALIDATION
    // =================================================
    if (
        isnan(suhu) ||
        isnan(ph) ||
        isnan(doValue) ||

        suhu < 0 ||
        suhu > 50 ||

        ph < 0 ||
        ph > 14 ||

        doValue < 0 ||
        doValue > 20
       ) {

      activateSafeMode();

    } else {

      safeMode = false;

      publishSafeModeStatus();
    }

    // =================================================
    // AUTO MODE
    // =================================================
    if (autoMode && !safeMode) {

      autoControl(
        ph,
        doValue
      );
    }

    // =================================================
    // SYSTEM STATUS
    // =================================================
    if (safeMode) {

      publishSystemStatus(
        "SAFE_MODE"
      );
    }

    else if (doValue < 4.0) {

      publishSystemStatus(
        "LOW_DO"
      );
    }

    else if (ph < 7.0) {

      publishSystemStatus(
        "LOW_PH"
      );
    }

    else if (ph > 8.0) {

      publishSystemStatus(
        "HIGH_PH"
      );
    }

    else if (
             dosingProcessActive
            ) {

      publishSystemStatus(
        "DOSING"
      );
    }

    else {

      publishSystemStatus(
        "NORMAL"
      );
    }

    // =================================================
    // PUBLISH SENSOR
    // =================================================
    publishSensor(
      "kolam1/sensor/suhu",
      suhu,
      "C"
    );

    publishSensor(
      "kolam1/sensor/ph",
      ph,
      "pH"
    );

    publishSensor(
      "kolam1/sensor/do",
      doValue,
      "mg/L"
    );

    // =================================================
    // SERIAL MONITOR
    // =================================================
    Serial.println("==============");

    Serial.print("Suhu : ");
    Serial.println(suhu);

    Serial.print("pH : ");
    Serial.println(ph);

    Serial.print("DO : ");
    Serial.println(doValue);

    Serial.println("==============");
  }
}