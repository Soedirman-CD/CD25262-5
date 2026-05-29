#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

#include <OneWire.h>
#include <DallasTemperature.h>

// Library LCD I2C
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
#define PH_PIN   34
#define DO_PIN   35
#define SUHU_PIN  4

// =====================================================
// RELAY PIN
// =====================================================
#define RELAY_AERATOR_UTAMA     16
#define RELAY_AERATOR_BACKUP    17
#define RELAY_PENGADUK_DOLOMIT   5
#define RELAY_POMPA_DOLOMIT     18
#define RELAY_SOLENOID_IN       19
#define RELAY_SOLENOID_OUT      23

// =====================================================
// I2C PIN
// =====================================================
#define SDA_PIN 21
#define SCL_PIN 22

// =====================================================
// LCD I2C SETUP (20 kolom, 4 baris)
// =====================================================
LiquidCrystal_I2C lcd(0x27, 20, 4);

// =====================================================
// PH CALIBRATION
// =====================================================
float calibration_value = 21.34 + 0.6;

// =====================================================
// DO CALIBRATION & SETTINGS
// =====================================================
#define VREF    3300.0   // Tegangan referensi ESP32 (mV)
#define ADC_RES 4095.0   // Resolusi ADC ESP32 (12-bit)

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
// LAST WILL TESTAMENT PAYLOAD
// Broker akan publish ini otomatis jika ESP32 putus
// =====================================================
const char* LWT_TOPIC   = "kolam1/device/wifi";
const char* LWT_PAYLOAD = "{\"connected\":false}";

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
bool aeratorBackupState   = false;
bool pengadukDolomitState = false;
bool pompaDolomitState    = false;
bool solenoidInState      = false;
bool solenoidOutState     = false;

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
unsigned long mixingStartTime  = 0;
unsigned long dosingStartTime  = 0;
unsigned long aerationStartTime = 0;

// =====================================================
// DOSING DURATION
// =====================================================
const unsigned long MIXING_DURATION   =  60000;   //  1 menit
const unsigned long DOSING_DURATION   =  20000;   // 20 detik
const unsigned long AERATION_DURATION = 900000;   // 15 menit

// =====================================================
// DOSING LOCK
// =====================================================
bool dosingProcessActive = false;

// =====================================================
// CONNECT WIFI WITH LCD LOADING
// =====================================================
void setup_wifi() {
  delay(10);
  Serial.println();
  Serial.print("Connecting WiFi: ");
  Serial.println(ssid);

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("  CONNECTING WIFI   ");
  lcd.setCursor(0, 1);
  lcd.print(ssid);
  lcd.setCursor(0, 2);
  lcd.print("Loading ");

  WiFi.begin(ssid, password);

  int dotCount = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    lcd.setCursor(8 + dotCount, 2);
    lcd.print(".");
    dotCount++;
    if (dotCount > 10) {
      lcd.setCursor(8, 2);
      lcd.print("          ");
      dotCount = 0;
    }
  }

  Serial.println();
  Serial.println("WiFi Connected");
  Serial.println(WiFi.localIP());

  lcd.setCursor(0, 2);
  lcd.print("   Loading Done!    ");
  lcd.setCursor(0, 3);
  lcd.print("    CONNECTED OK    ");
  delay(2000);
  lcd.clear();
}

// =====================================================
// PUBLISH RELAY STATUS
// =====================================================
void publishRelayStatus(const char* topic, bool state) {
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
  client.publish("kolam1/status/mode", buffer, true);
}

// =====================================================
// PUBLISH SAFE MODE STATUS
// =====================================================
void publishSafeModeStatus() {
  StaticJsonDocument<200> doc;
  doc["safe_mode"] = safeMode;
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish("kolam1/status/safe_mode", buffer, true);
}

// =====================================================
// PUBLISH WIFI STATUS
// Dipanggil saat MQTT berhasil connect.
// LWT otomatis dikirim broker saat ESP32 putus.
// =====================================================
void publishWifiStatus(bool connected) {
  StaticJsonDocument<200> doc;
  doc["connected"] = connected;
  if (connected) {
    doc["ssid"] = ssid;
    doc["ip"]   = WiFi.localIP().toString();
  }
  char buffer[200];
  serializeJson(doc, buffer);
  // retained = true agar Flutter yang baru buka app
  // langsung dapat status terakhir tanpa menunggu publish berikutnya
  client.publish(LWT_TOPIC, buffer, true);

  Serial.print("WIFI STATUS PUBLISHED : connected=");
  Serial.print(connected);
  if (connected) {
    Serial.print("  IP=");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println();
  }
}

// =====================================================
// PUBLISH SYSTEM STATUS
// =====================================================
void publishSystemStatus(String status) {
  StaticJsonDocument<200> doc;
  doc["status"] = status;
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish("kolam1/status/system", buffer, true);

  Serial.print("SYSTEM STATUS : ");
  Serial.println(status);
}

// =====================================================
// PUBLISH SENSOR
// =====================================================
void publishSensor(const char* topic, float value, const char* unit) {
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
  digitalWrite(RELAY_POMPA_DOLOMIT,    HIGH);
  digitalWrite(RELAY_SOLENOID_IN,      HIGH);
  digitalWrite(RELAY_SOLENOID_OUT,     HIGH);

  publishRelayStatus("kolam1/status/pengaduk_dolomit", false);
  publishRelayStatus("kolam1/status/pompa_dolomit",    false);
  publishRelayStatus("kolam1/status/solenoid_in",      false);
  publishRelayStatus("kolam1/status/solenoid_out",     false);

  publishSafeModeStatus();
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

    // =================================================
    // RESET SISTEM SAAT MASUK MODE MANUAL
    // =================================================
    if (!autoMode) {

      // Reset state machine
      dosingState = IDLE;
      dosingProcessActive = false;

      // Reset timer
      mixingStartTime = 0;
      dosingStartTime = 0;
      aerationStartTime = 0;

      // Matikan semua aktuator auto
      aeratorBackupState   = false;
      pengadukDolomitState = false;
      pompaDolomitState    = false;
      solenoidInState      = false;
      solenoidOutState     = false;

      // Relay OFF (active low)
      digitalWrite(RELAY_AERATOR_BACKUP, HIGH);
      digitalWrite(RELAY_PENGADUK_DOLOMIT, HIGH);
      digitalWrite(RELAY_POMPA_DOLOMIT, HIGH);
      digitalWrite(RELAY_SOLENOID_IN, HIGH);
      digitalWrite(RELAY_SOLENOID_OUT, HIGH);

      // Publish status relay
      publishRelayStatus("kolam1/status/aerator_backup", false);
      publishRelayStatus("kolam1/status/pengaduk_dolomit", false);
      publishRelayStatus("kolam1/status/pompa_dolomit", false);
      publishRelayStatus("kolam1/status/solenoid_in", false);
      publishRelayStatus("kolam1/status/solenoid_out", false);

      // Reset safe mode
      safeMode = false;
      publishSafeModeStatus();

      Serial.println("SYSTEM RESET TO MANUAL MODE");
    }

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
  while (!client.connected()) {
    String clientId = "ESP32_KOLAM_";
    clientId += String(random(0xffff), HEX);

    Serial.print("Menghubungkan ke MQTT broker...");

    // connect() overload dengan LWT:
    // connect(clientId, user, pass, willTopic, willQos, willRetain, willMsg)
    if (client.connect(
          clientId.c_str(),
          mqtt_user,
          mqtt_password,
          LWT_TOPIC,   // will topic
          1,           // will QoS
          true,        // will retain
          LWT_PAYLOAD  // will payload → {"connected":false}
        )) {
      Serial.println(" terhubung!");

      client.subscribe("kolam1/control/#");
      client.subscribe("kolam1/system/#");

      publishModeStatus();
      publishSafeModeStatus();

      // Beritahu Flutter bahwa ESP32 sudah online
      // (WiFi + MQTT keduanya terhubung)
      publishWifiStatus(true);

    } else {
      Serial.print(" gagal, rc=");
      Serial.print(client.state());
      Serial.println(" → coba lagi 5 detik");
      delay(5000);
    }
  }
}

// =====================================================
// AUTO CONTROL SYSTEM
// =====================================================
void autoControl(float ph, float doValue) {

  // =================================================
  // PRIORITAS DO
  // Jika DO rendah:
  // - hentikan seluruh proses injeksi pH
  // - nyalakan aerator backup
  // =================================================
  if (doValue < 4.0) {

    // Reset dosing process
    dosingState = IDLE;
    dosingProcessActive = false;

    // Reset timer
    mixingStartTime = 0;
    dosingStartTime = 0;
    aerationStartTime = 0;

    // Matikan mixing & dosing
    pengadukDolomitState = false;
    pompaDolomitState    = false;

    digitalWrite(RELAY_PENGADUK_DOLOMIT, HIGH);
    digitalWrite(RELAY_POMPA_DOLOMIT, HIGH);

    publishRelayStatus("kolam1/status/pengaduk_dolomit", false);
    publishRelayStatus("kolam1/status/pompa_dolomit", false);

    // Nyalakan aerator backup
    aeratorBackupState = true;
    digitalWrite(RELAY_AERATOR_BACKUP, LOW);
    publishRelayStatus("kolam1/status/aerator_backup", true);

    Serial.println("LOW DO PRIORITY ACTIVE");

    return;
  }

  // =================================================
  // DO NORMAL
  // Matikan aerator backup jika tidak sedang aerasi
  // =================================================
  if (dosingState == IDLE) {
    aeratorBackupState = false;
    digitalWrite(RELAY_AERATOR_BACKUP, HIGH);
    publishRelayStatus("kolam1/status/aerator_backup", false);
  }

  if (ph < 7.0 && !dosingProcessActive && dosingState == IDLE) {
    dosingProcessActive = true;
    dosingState         = MIXING;
    mixingStartTime     = millis();

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

      dosingState      = DOSING;
      dosingStartTime  = millis();
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

      dosingState       = AERATION;
      aerationStartTime = millis();
    }
  }

  if (dosingState == AERATION) {
    if (millis() - aerationStartTime >= AERATION_DURATION) {
      aeratorBackupState = false;
      digitalWrite(RELAY_AERATOR_BACKUP, HIGH);
      publishRelayStatus("kolam1/status/aerator_backup", false);

      dosingState         = IDLE;
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
    int adcValue   = analogRead(PH_PIN);
    float voltage  = adcValue * (3.3 / 4095.0);
    float phValue  = calibration_value - (voltage * 5.70);
    total += phValue;
    delay(20);
  }
  return total / samples;
}

// =====================================================
// READ DO
// =====================================================
float readDO(float tempC) {
  int   rawADC  = analogRead(DO_PIN);
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
  lcd.begin();        // gunakan begin() untuk library Arduino-LiquidCrystal-I2C
  lcd.backlight();

  lcd.setCursor(0, 0);
  lcd.print("  MONITORING SYSTEM ");
  lcd.setCursor(0, 1);
  lcd.print("     KOLAM NILA     ");
  lcd.setCursor(0, 2);
  lcd.print("    UNSOED 2026     ");
  lcd.setCursor(0, 3);
  lcd.print("====================");
  delay(2000);
  lcd.clear();

  pinMode(RELAY_AERATOR_UTAMA,     OUTPUT);
  pinMode(RELAY_AERATOR_BACKUP,    OUTPUT);
  pinMode(RELAY_PENGADUK_DOLOMIT,  OUTPUT);
  pinMode(RELAY_POMPA_DOLOMIT,     OUTPUT);
  pinMode(RELAY_SOLENOID_IN,       OUTPUT);
  pinMode(RELAY_SOLENOID_OUT,      OUTPUT);

  // HIGH = relay OFF (active-low relay)
  // Aerator utama terhubung ke terminal NC → tetap MENYALA
  digitalWrite(RELAY_AERATOR_UTAMA,    HIGH);
  digitalWrite(RELAY_AERATOR_BACKUP,   HIGH);
  digitalWrite(RELAY_PENGADUK_DOLOMIT, HIGH);
  digitalWrite(RELAY_POMPA_DOLOMIT,    HIGH);
  digitalWrite(RELAY_SOLENOID_IN,      HIGH);
  digitalWrite(RELAY_SOLENOID_OUT,     HIGH);

  setup_wifi();

  espClient.setInsecure();
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);
  // Catatan: LWT di-set di dalam reconnect() melalui parameter connect()
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

    float suhu    = readTemperature();
    float ph      = readPH();
    float doValue = readDO(suhu);

    // =================================================
    // SENSOR VALIDATION
    // =================================================
    if (isnan(suhu) || isnan(ph) || isnan(doValue) ||
        suhu    <  0 || suhu    > 50 ||
        ph      <  0 || ph      > 14 ||
        doValue <  0 || doValue > 20) {
      activateSafeMode();
    } else {
      safeMode = false;
      publishSafeModeStatus();
    }

    // =================================================
    // AUTO MODE
    // =================================================
    if (autoMode && !safeMode) {
      autoControl(ph, doValue);
    }

    // =================================================
    // LOGIKA NOTIFIKASI STATUS
    // =================================================
    String textStatus = "READY";

    if (safeMode) {
      publishSystemStatus("SAFE_MODE");
      textStatus = "SAFE MODE";
    } else if (pengadukDolomitState) {
      publishSystemStatus("MIXING_DOLOMIT");
      textStatus = "MIX DOLOMIT";
    } else if (pompaDolomitState) {
      publishSystemStatus("INJEKSI_PH");
      textStatus = "INJEKSI pH";
    } else if (solenoidInState) {
      publishSystemStatus("SOLENOID_IN_ON");
      textStatus = "SOL IN ON";
    } else if (solenoidOutState) {
      publishSystemStatus("SOLENOID_OUT_ON");
      textStatus = "SOL OUT ON";
    } else if (aeratorBackupState) {
      publishSystemStatus("AERATOR_BACKUP_ON");
      textStatus = "AERASI";
    } else if (doValue < 4.0) {
      publishSystemStatus("LOW_DO");
      textStatus = "LOW DO";
    } else if (ph < 7.0) {
      publishSystemStatus("LOW_PH");
      textStatus = "LOW pH";
    } else if (ph > 8.0) {
      publishSystemStatus("HIGH_PH");
      textStatus = "HIGH pH";
    } else {
      publishSystemStatus("NORMAL");
    }

    publishSensor("kolam1/sensor/suhu", suhu,    "C");
    publishSensor("kolam1/sensor/ph",   ph,      "pH");
    publishSensor("kolam1/sensor/do",   doValue, "mg/L");

    Serial.println("==============");
    Serial.print("Suhu   : "); Serial.println(suhu);
    Serial.print("pH     : "); Serial.println(ph);
    Serial.print("DO     : "); Serial.println(doValue);
    Serial.println("==============");

    // =================================================
    // UPDATE TAMPILAN LCD 20x4
    // =================================================
    lcd.clear();

    // Baris 1: Suhu & pH
    lcd.setCursor(0, 0);
    lcd.print("Suhu: ");
    lcd.print(suhu, 1);
    lcd.print("C pH: ");
    lcd.print(ph, 1);

    // Baris 2: DO
    lcd.setCursor(0, 1);
    lcd.print("DO: ");
    lcd.print(doValue, 2);
    lcd.print(" mg/L");

    // Baris 3: Mode sistem
    lcd.setCursor(0, 2);
    lcd.print("Mode Sistem: ");
    lcd.print(autoMode ? "AUTO" : "MANUAL");

    // =================================================
    // COUNTDOWN AKTUATOR
    // =================================================
    unsigned long remainingTime = 0;

    if (dosingState == MIXING) {

      remainingTime =
        (MIXING_DURATION - (millis() - mixingStartTime)) / 1000;

    }

    else if (dosingState == DOSING) {

      remainingTime =
        (DOSING_DURATION - (millis() - dosingStartTime)) / 1000;

    }

    else if (dosingState == AERATION) {

      remainingTime =
        (AERATION_DURATION - (millis() - aerationStartTime)) / 1000;

    }

    // Hindari nilai minus
    if ((long)remainingTime < 0) {
      remainingTime = 0;
    }

    // =================================================
    // LCD BARIS 4
    // =================================================
    lcd.setCursor(0, 3);

    // Bersihkan baris
    lcd.print("                    ");

    lcd.setCursor(0, 3);

    if (dosingState != IDLE) {

      lcd.print("Sts:");
      lcd.print(textStatus);
      lcd.print(" ");

      // =================================================
      // KHUSUS AERATION → tampil menit
      // =================================================
      if (dosingState == AERATION) {

        unsigned long minutePart = remainingTime / 60;
        unsigned long secondPart = remainingTime % 60;

        lcd.print(minutePart);
        lcd.print(".");

        // Tambahkan leading zero
        if (secondPart < 10) {
          lcd.print("0");
        }

        lcd.print(secondPart);
        lcd.print("s");

      }

      // =================================================
      // MIXING & DOSING → tetap detik
      // =================================================
      else {

        lcd.print(remainingTime);
        lcd.print("s");

      }

    } else {

      lcd.print("Sts:");
      lcd.print(textStatus);

    }
  }
}
