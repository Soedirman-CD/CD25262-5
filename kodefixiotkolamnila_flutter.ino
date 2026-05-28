#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

#include <OneWire.h>
#include <DallasTemperature.h>

#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// =====================================================
// WIFI
// =====================================================
const char* ssid     = "WATON1";
const char* password = "yalalwaton";

// =====================================================
// MQTT
// =====================================================
const char* mqtt_server   = "007d3469a2244841a48f1259a6b6494e.s1.eu.hivemq.cloud";
const int   mqtt_port     = 8883;
const char* mqtt_user     = "Test123";
const char* mqtt_password = "Test1234";

// =====================================================
// SENSOR PIN
// =====================================================
#define PH_PIN    34
#define DO_PIN    35
#define SUHU_PIN   4

// =====================================================
// RELAY PIN
// =====================================================
#define RELAY_AERATOR_UTAMA      16
#define RELAY_AERATOR_BACKUP     17
#define RELAY_PENGADUK_DOLOMIT    5
#define RELAY_POMPA_DOLOMIT      18
#define RELAY_SOLENOID_IN        19
#define RELAY_SOLENOID_OUT       23

// =====================================================
// I2C PIN
// =====================================================
#define SDA_PIN 21
#define SCL_PIN 22

// =====================================================
// LCD
// =====================================================
LiquidCrystal_I2C lcd(0x27, 20, 4);

// =====================================================
// PH CALIBRATION
// =====================================================
float calibration_value = 21.34 + 0.6;

// =====================================================
// DO CALIBRATION
// =====================================================
#define VREF    3300.0
#define ADC_RES 4095.0

float CALIBRATION_VOLTAGE = 1294.2;
float CALIBRATION_DO      = 8.1366;

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
// LAST WILL
// =====================================================
const char* LWT_TOPIC   = "kolam1/device/wifi";
const char* LWT_PAYLOAD = "{\"connected\":false}";

// =====================================================
// TIMER
// =====================================================
unsigned long lastPublish = 0;

// =====================================================
// LCD BLINK TIMER
// =====================================================
unsigned long lcdBlinkTimer = 0;
bool showReconnectMessage = false;

// =====================================================
// LCD MODE TRACKER
// =====================================================
bool lastReconnectScreen = false;

// =====================================================
// LCD BLINK TIME
// =====================================================
const unsigned long SENSOR_DISPLAY_TIME    = 5000;
const unsigned long RECONNECT_DISPLAY_TIME = 3000;

// =====================================================
// GLOBAL SENSOR VARIABLE
// =====================================================
float suhuGlobal = 0;
float phGlobal   = 0;
float doGlobal   = 0;

String textStatusGlobal = "NORMAL";

// =====================================================
// SYSTEM MODE
// =====================================================
bool autoMode = false;
bool safeMode = false;

// =====================================================
// RELAY STATUS
// =====================================================
bool aeratorBackupState   = false;
bool pengadukDolomitState = false;
bool pompaDolomitState    = false;
bool solenoidInState      = false;
bool solenoidOutState     = false;

// =====================================================
// DOSING STATE
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
unsigned long mixingStartTime   = 0;
unsigned long dosingStartTime   = 0;
unsigned long aerationStartTime = 0;

// =====================================================
// DOSING DURATION
// =====================================================
const unsigned long MIXING_DURATION   = 60000;
const unsigned long DOSING_DURATION   = 20000;
const unsigned long AERATION_DURATION = 900000;

// =====================================================
// DOSING LOCK
// =====================================================
bool dosingProcessActive = false;

// =====================================================
// WIFI CONNECT
// =====================================================
void setup_wifi() {

  delay(10);

  Serial.println();
  Serial.print("Connecting WiFi: ");
  Serial.println(ssid);

  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print(" CONNECTING WIFI ");

  lcd.setCursor(0, 1);
  lcd.print(ssid);

  WiFi.mode(WIFI_STA);

  WiFi.setAutoReconnect(true);
  WiFi.persistent(true);

  WiFi.begin(ssid, password);

  int retry = 0;

  while (WiFi.status() != WL_CONNECTED && retry < 30) {

    delay(500);

    Serial.print(".");

    lcd.setCursor(retry % 20, 2);
    lcd.print(".");

    retry++;
  }

  if (WiFi.status() == WL_CONNECTED) {

    Serial.println();
    Serial.println("WiFi Connected");
    Serial.println(WiFi.localIP());

    lcd.clear();

    lcd.setCursor(0, 0);
    lcd.print(" WIFI CONNECTED ");

    lcd.setCursor(0, 1);
    lcd.print(WiFi.localIP());

    delay(2000);

    lcd.clear();

  } else {

    Serial.println();
    Serial.println("WiFi Failed!");

    lcd.clear();

    lcd.setCursor(0, 0);
    lcd.print(" WIFI FAILED ");

    delay(2000);

    lcd.clear();
  }
}

// =====================================================
// WIFI RECONNECT CHECK
// =====================================================
void checkWiFiConnection() {

  static unsigned long lastReconnectAttempt = 0;

  if (WiFi.status() != WL_CONNECTED) {

    // reconnect tiap 5 detik
    if (millis() - lastReconnectAttempt > 5000) {

      lastReconnectAttempt = millis();

      Serial.println("WiFi disconnected!");
      Serial.println("Trying reconnect WiFi...");

      WiFi.disconnect();
      WiFi.begin(ssid, password);
    }

    // =================================================
    // LCD BLINK MODE
    // =================================================
    if (!showReconnectMessage) {

      if (millis() - lcdBlinkTimer >= SENSOR_DISPLAY_TIME) {

        lcdBlinkTimer = millis();

        showReconnectMessage = true;
      }

    } else {

      if (millis() - lcdBlinkTimer >= RECONNECT_DISPLAY_TIME) {

        lcdBlinkTimer = millis();

        showReconnectMessage = false;
      }
    }

  } else {

    showReconnectMessage = false;
  }
}

// =====================================================
// PUBLISH RELAY STATUS
// =====================================================
void publishRelayStatus(const char* topic, bool state) {

  if (!client.connected()) return;

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

  if (!client.connected()) return;

  StaticJsonDocument<200> doc;

  doc["mode"] = autoMode ? "AUTO" : "MANUAL";

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish("kolam1/status/mode", buffer, true);
}

// =====================================================
// PUBLISH SAFE MODE STATUS
// =====================================================
void publishSafeModeStatus() {

  if (!client.connected()) return;

  StaticJsonDocument<200> doc;

  doc["safe_mode"] = safeMode;

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish("kolam1/status/safe_mode", buffer, true);
}

// =====================================================
// WIFI STATUS
// =====================================================
void publishWifiStatus(bool connected) {

  if (!client.connected()) return;

  StaticJsonDocument<200> doc;

  doc["connected"] = connected;

  if (connected) {

    doc["ssid"] = ssid;
    doc["ip"]   = WiFi.localIP().toString();
  }

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish(LWT_TOPIC, buffer, true);
}

// =====================================================
// PUBLISH SYSTEM STATUS
// =====================================================
void publishSystemStatus(String status) {

  if (!client.connected()) return;

  StaticJsonDocument<200> doc;

  doc["status"] = status;

  char buffer[200];

  serializeJson(doc, buffer);

  client.publish("kolam1/status/system", buffer, true);
}

// =====================================================
// PUBLISH SENSOR
// =====================================================
void publishSensor(const char* topic, float value, const char* unit) {

  if (!client.connected()) return;

  StaticJsonDocument<200> doc;

  doc["value"] = value;
  doc["unit"]  = unit;

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

  aeratorBackupState = true;

  digitalWrite(RELAY_AERATOR_BACKUP, LOW);

  publishRelayStatus("kolam1/status/aerator_backup", true);

  pengadukDolomitState = false;
  pompaDolomitState    = false;
  solenoidInState      = false;
  solenoidOutState     = false;

  digitalWrite(RELAY_PENGADUK_DOLOMIT, HIGH);
  digitalWrite(RELAY_POMPA_DOLOMIT, HIGH);
  digitalWrite(RELAY_SOLENOID_IN, HIGH);
  digitalWrite(RELAY_SOLENOID_OUT, HIGH);
}

// =====================================================
// MQTT CALLBACK
// =====================================================
void callback(char* topic, byte* payload, unsigned int length) {

  String message;

  for (int i = 0; i < length; i++) {
    message += (char)payload[i];
  }

  StaticJsonDocument<200> doc;

  DeserializationError error = deserializeJson(doc, message);

  if (error) return;

  if (String(topic) == "kolam1/system/mode") {

    String mode = doc["mode"];

    autoMode = (mode == "AUTO");

    publishModeStatus();

    return;
  }

  if (!autoMode && !safeMode) {

    bool state = doc["state"];

    if (String(topic) == "kolam1/control/aerator_backup") {

      aeratorBackupState = state;

      digitalWrite(RELAY_AERATOR_BACKUP, state ? LOW : HIGH);

      publishRelayStatus("kolam1/status/aerator_backup", state);
    }

    if (String(topic) == "kolam1/control/pengaduk_dolomit") {

      pengadukDolomitState = state;

      digitalWrite(RELAY_PENGADUK_DOLOMIT, state ? LOW : HIGH);

      publishRelayStatus("kolam1/status/pengaduk_dolomit", state);
    }

    if (String(topic) == "kolam1/control/pompa_dolomit") {

      pompaDolomitState = state;

      digitalWrite(RELAY_POMPA_DOLOMIT, state ? LOW : HIGH);

      publishRelayStatus("kolam1/status/pompa_dolomit", state);
    }
  }
}

// =====================================================
// MQTT RECONNECT
// =====================================================
void reconnect() {

  while (!client.connected() && WiFi.status() == WL_CONNECTED) {

    String clientId = "ESP32_KOLAM_";
    clientId += String(random(0xffff), HEX);

    Serial.print("Connecting MQTT...");

    if (client.connect(
          clientId.c_str(),
          mqtt_user,
          mqtt_password,
          LWT_TOPIC,
          1,
          true,
          LWT_PAYLOAD
        )) {

      Serial.println(" connected!");

      client.subscribe("kolam1/control/#");
      client.subscribe("kolam1/system/#");

      publishModeStatus();
      publishSafeModeStatus();
      publishWifiStatus(true);

    } else {

      Serial.print(" failed rc=");
      Serial.println(client.state());

      delay(5000);
    }
  }
}

// =====================================================
// AUTO CONTROL
// =====================================================
void autoControl(float ph, float doValue) {

  if (doValue < 4.0) {

    aeratorBackupState = true;

    digitalWrite(RELAY_AERATOR_BACKUP, LOW);

    publishRelayStatus("kolam1/status/aerator_backup", true);

    return;
  }

  if (ph < 7.0 && !dosingProcessActive && dosingState == IDLE) {

    dosingProcessActive = true;

    dosingState = MIXING;

    mixingStartTime = millis();

    pengadukDolomitState = true;

    digitalWrite(RELAY_PENGADUK_DOLOMIT, LOW);

    publishRelayStatus("kolam1/status/pengaduk_dolomit", true);
  }

  if (dosingState == MIXING) {

    if (millis() - mixingStartTime >= MIXING_DURATION) {

      pengadukDolomitState = false;

      digitalWrite(RELAY_PENGADUK_DOLOMIT, HIGH);

      publishRelayStatus("kolam1/status/pengaduk_dolomit", false);

      pompaDolomitState = true;

      digitalWrite(RELAY_POMPA_DOLOMIT, LOW);

      publishRelayStatus("kolam1/status/pompa_dolomit", true);

      dosingState = DOSING;

      dosingStartTime = millis();
    }
  }

  if (dosingState == DOSING) {

    if (millis() - dosingStartTime >= DOSING_DURATION) {

      pompaDolomitState = false;

      digitalWrite(RELAY_POMPA_DOLOMIT, HIGH);

      publishRelayStatus("kolam1/status/pompa_dolomit", false);

      aeratorBackupState = true;

      digitalWrite(RELAY_AERATOR_BACKUP, LOW);

      publishRelayStatus("kolam1/status/aerator_backup", true);

      dosingState = AERATION;

      aerationStartTime = millis();
    }
  }

  if (dosingState == AERATION) {

    if (millis() - aerationStartTime >= AERATION_DURATION) {

      aeratorBackupState = false;

      digitalWrite(RELAY_AERATOR_BACKUP, HIGH);

      publishRelayStatus("kolam1/status/aerator_backup", false);

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

    float voltage = adcValue * (3.3 / 4095.0);

    float phValue = calibration_value - (voltage * 5.70);

    total += phValue;

    delay(20);
  }

  return total / samples;
}

// =====================================================
// READ DO
// =====================================================
float readDO(float tempC) {

  int rawADC = analogRead(DO_PIN);

  float voltage = rawADC * (VREF / ADC_RES);

  float doValue = (voltage / CALIBRATION_VOLTAGE) * CALIBRATION_DO;

  return doValue;
}

// =====================================================
// READ TEMPERATURE
// =====================================================
float readTemperature() {

  const int samples = 3;

  float total = 0;

  for (int i = 0; i < samples; i++) {

    sensors.requestTemperatures();

    float temp = sensors.getTempCByIndex(0);

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

  analogReadResolution(12);

  sensors.begin();

  Wire.begin(SDA_PIN, SCL_PIN);

  lcd.begin();
  lcd.backlight();

  pinMode(RELAY_AERATOR_UTAMA, OUTPUT);
  pinMode(RELAY_AERATOR_BACKUP, OUTPUT);
  pinMode(RELAY_PENGADUK_DOLOMIT, OUTPUT);
  pinMode(RELAY_POMPA_DOLOMIT, OUTPUT);
  pinMode(RELAY_SOLENOID_IN, OUTPUT);
  pinMode(RELAY_SOLENOID_OUT, OUTPUT);

  digitalWrite(RELAY_AERATOR_UTAMA, HIGH);
  digitalWrite(RELAY_AERATOR_BACKUP, HIGH);
  digitalWrite(RELAY_PENGADUK_DOLOMIT, HIGH);
  digitalWrite(RELAY_POMPA_DOLOMIT, HIGH);
  digitalWrite(RELAY_SOLENOID_IN, HIGH);
  digitalWrite(RELAY_SOLENOID_OUT, HIGH);

  setup_wifi();

  espClient.setInsecure();

  client.setServer(mqtt_server, mqtt_port);

  client.setCallback(callback);
}

// =====================================================
// LOOP
// =====================================================
void loop() {

  checkWiFiConnection();

  if (WiFi.status() == WL_CONNECTED) {

    if (!client.connected()) {
      reconnect();
    }

    client.loop();
  }

  // ===================================================
  // SENSOR UPDATE EVERY 5 SEC
  // ===================================================
  if (millis() - lastPublish > 5000) {

    lastPublish = millis();

    suhuGlobal = readTemperature();
    phGlobal   = readPH();
    doGlobal   = readDO(suhuGlobal);

    // =================================================
    // SENSOR VALIDATION
    // =================================================
    if (isnan(suhuGlobal) || isnan(phGlobal) || isnan(doGlobal) ||
        suhuGlobal < 0 || suhuGlobal > 50 ||
        phGlobal < 0 || phGlobal > 14 ||
        doGlobal < 0 || doGlobal > 20) {

      activateSafeMode();

    } else {

      safeMode = false;

      publishSafeModeStatus();
    }

    // =================================================
    // AUTO MODE
    // =================================================
    if (autoMode && !safeMode) {
      autoControl(phGlobal, doGlobal);
    }

    // =================================================
    // STATUS SYSTEM
    // =================================================
    textStatusGlobal = "NORMAL";

    if (safeMode) {

      publishSystemStatus("SAFE_MODE");
      textStatusGlobal = "SAFE MODE";

    }
    else if (pengadukDolomitState) {

      publishSystemStatus("MIXING_DOLOMIT");
      textStatusGlobal = "AGITATOR";

    }
    else if (pompaDolomitState) {

      publishSystemStatus("INJEKSI_DOLOMIT");
      textStatusGlobal = "INJEKSI";

    }
    else if (solenoidInState) {

      publishSystemStatus("SOLENOID_IN_ON");
      textStatusGlobal = "SOL IN";

    }
    else if (solenoidOutState) {

      publishSystemStatus("SOLENOID_OUT_ON");
      textStatusGlobal = "SOL OUT";

    }
    else if (aeratorBackupState) {

      publishSystemStatus("AERATOR_BACKUP_ON");
      textStatusGlobal = "AERASI BACK";

    }
    else if (doGlobal < 4.0) {

      publishSystemStatus("LOW_DO");
      textStatusGlobal = "LOW DO";

    }
    else if (phGlobal < 7.0) {

      publishSystemStatus("LOW_PH");
      textStatusGlobal = "LOW pH";

    }
    else if (phGlobal > 8.0) {

      publishSystemStatus("HIGH_PH");
      textStatusGlobal = "HIGH pH";

    }
    else {

      publishSystemStatus("NORMAL");
      textStatusGlobal = "NORMAL";
    }

    // =================================================
    // PUBLISH SENSOR
    // =================================================
    publishSensor("kolam1/sensor/suhu", suhuGlobal, "C");
    publishSensor("kolam1/sensor/ph", phGlobal, "pH");
    publishSensor("kolam1/sensor/do", doGlobal, "mg/L");
  }

  // ===================================================
  // LCD REALTIME UPDATE
  // ===================================================

  // ===================================================
  // MODE WIFI RECONNECT MESSAGE
  // ===================================================
  if (WiFi.status() != WL_CONNECTED && showReconnectMessage) {

    if (!lastReconnectScreen) {

      lcd.clear();

      lastReconnectScreen = true;
    }

    lcd.setCursor(0, 0);
    lcd.print(" WIFI RECONNECT ");

    lcd.setCursor(0, 1);
    lcd.print(" Connecting.... ");

    lcd.setCursor(0, 2);
    lcd.print("SSID:            ");

    lcd.setCursor(6, 2);
    lcd.print(ssid);

    lcd.setCursor(0, 3);
    lcd.print(" Please Wait... ");
  }

  // ===================================================
  // MODE SENSOR DISPLAY
  // ===================================================
  else {

    static unsigned long lcdRefresh = 0;

    if (lastReconnectScreen) {

      lcd.clear();

      lastReconnectScreen = false;
    }

    if (millis() - lcdRefresh > 1000) {

      lcdRefresh = millis();

      // =================================================
      // LINE 1
      // =================================================
      lcd.setCursor(0, 0);

      char line1[21];

      snprintf(line1, sizeof(line1),
               "S:%-4.1fC pH:%-4.1f",
               suhuGlobal,
               phGlobal);

      lcd.print(line1);

      // =================================================
      // LINE 2
      // =================================================
      lcd.setCursor(0, 1);

      char line2[21];

      snprintf(line2, sizeof(line2),
               "DO:%-5.2f mg/L    ",
               doGlobal);

      lcd.print(line2);

      // =================================================
      // LINE 3
      // =================================================
      lcd.setCursor(0, 2);

      char line3[21];

      snprintf(line3, sizeof(line3),
               "Mode:%-11s",
               autoMode ? "AUTO" : "MANUAL");

      lcd.print(line3);

      // =================================================
      // LINE 4
      // =================================================
      lcd.setCursor(0, 3);

      char line4[21];

      snprintf(line4, sizeof(line4),
               "Status:%-12s",
               textStatusGlobal.c_str());

      lcd.print(line4);
    }
  }
}
