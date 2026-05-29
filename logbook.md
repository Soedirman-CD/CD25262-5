## Logbook Kelompok 5

Mata kuliah: Capstone Design

Semester: Gasal 2025/2026

Anggota

1. Arga Dwi Ilyasa @argailyas
2. Farhan Ibnu Fajar @farhanibnufajar
3. Daffa Naufal @daconk

###  Rabu 6 Mei 2026

#### Yang sudah dilakukan

- Melakukan kunjungan lapangan ke peternakan ikan nila dengan sistem bioflok
- Mengamati pengelolaan kualitas air pada kolam bioflok
- Mengamati penggunaan aerator pada sistem bioflok
- Mengumpulkan informasi terkait monitoring pH, suhu air, dan dissolved oxygen (DO)

#### Masalah yang dihadapi

- Kadar dissolved oxygen (DO) pada kolam perlu dijaga agar tetap stabil
- Kondisi kualitas air dapat berubah tergantung kondisi kolam dan jumlah ikan

#### Yang akan dilakukan

- [ ]  Melakukan evaluasi dan revisi mekaniseme sistem, PIC @argailyas
- [ ]  Merevisi sistem monitoring kualitas air berbasis IoT menggunakan ESP32, @farhanibnufajar
- [ ]  Merevisi DCP laporan, @daconk

#### Catatan

- 

### 07 Mei 2026

#### Yang sudah dilakukan

- Melakukan kunjungan dan diskusi bersama mitra terkait pengembangan sistem monitoring kolam ikan berbasis IoT
- Membahas kondisi kolam ikan dan permasalahan yang sering terjadi pada budidaya ikan nila
- Membahas pentingnya monitoring pH, suhu, dan dissolved oxygen (DO)
- Melakukan revisi konsep sistem monitoring kolam bioflok

#### Masalah yang dihadapi

- Menentukan batas nilai pH untuk mengaktifkan sistem otomatis 
- Menentukan mekanisme penambahan larutan dolomit agar tidak berlebihan 
- Menentukan logika kerja aerator agar sistem tetap efisien 

#### Yang akan dilakukan

- [ ] Membuat flowchart sistem monitoring dan kontrol otomatis, PIC @argailyas
- [ ] Melakukan pengujian sensor pH, PIC @farhanibnufajar
- [ ] Melakukan pengujian sensor dissolved oxygen (DO), PIC @argailyas
- [ ] Melakukan pengujian sensor suhu, PIC @daconk
- [ ] Merevisi RAB untuk kebutuhan alat, PCI @argailyas


#### Catatan

- Hasil diskusi bersama mitra digunakan sebagai bahan evaluasi

### 14 Mei 2026

#### Yang sudah dilakukan

- Melakukan finishing desain dan perakitan PCB 
- Melakukan proses penyolderan komponen pada PCB
- Mengisi cairan NaOH pada sensor DO
- Memastikan koneksi antar komponen dan sensor berjalan dengan baik
- Merevisi RAB

#### Masalah yang dihadapi

- 

#### Yang akan dilakukan

- [ ] 
- [ ] 

#### Catatan

-


###  Rabu 20 Mei 2026

#### Yang sudah dilakukan

- Mengkalibrasi sensor pH untuk menentukan set point
- Mengkalibrasi sensor dissolved oxygen (DO) untuk memastikan set point
- Mendesain box untuk jadi panel box projek

#### Masalah yang dihadapi

- kondisi kualitas pH air yang kurang maksimal karena buffer pH kurang terlarut pada nilai tertentu
- kondisi suhu air dan keadaan alami dari malam hari sehingga kadar DO yang turun sangat drastis 

#### Yang akan dilakukan

- [ ]  Melakukan pengecekan ulang terhadap sensor di lingkungan yang tepat untuk memastikan set point, PIC @argailyas
- [ ]  Melanjutkan desain dari panel box untuk di pesan nantinya, @farhanibnufajar
- [ ]  Mencicil DCP-400, @daconk

#### Catatan

- 

###  Senin 25 Mei 2026

#### Yang sudah dilakukan

-Mengkalibrasi lagi sensor DO yang turun drastis ke 0v, alhamdulillah kembali sehat sensor DO-nya
#### Masalah yang dihadapi

- terkadang setelah di tetapkan kondisi optimal pada DO, malah anomali lagi

#### Yang akan dilakukan

- bersihin lebih bersih bagian kerak di probenya

#### Catatan

- sering-sering aja buat ngalibrasi sensor DO, bagian pucuknya agak berkerak cuy, terus umurnya sudah tua ini sensor

###  Jumat 29 Mei 2026

#### Yang sudah dilakukan

- Revisi Source code sudah bisa mode auto dan manual dengan lancar
- tampilan countdown di lcd

#### Masalah yang dihadapi

- ketika countdown di lcd sempat merusak alur sistem lain 

#### Yang akan dilakukan

- [ ]  merapikan sourcecode @farhanibnufajar

#### Catatan


###  Rabu 30 Mei 2026

#### Yang sudah dilakukan

- Revisi source code
- sudah bisa menampilkan parameter yang lebih rapi
- setiap aktuator bekerja saat mode auto, ada countdown di lcd
- countdown di lcd per 1 detik
- mengatur blinking lebih smooth
- ketika wifi terputus akan tampil tulisan wifi reconnecting selama 5 detik dengan blinking tampilan data parameter 5 detik
- ketika sistem aktif, jika wifi beljum terkoneksi, maka maksimal 10 detik untuk conecting, lebih dari itu sistem masuk ke siklus tanpa wifi dan tetap menampilkan data di lcd

#### Masalah yang dihadapi

- 
#### Yang akan dilakukan

- [ ]  Merapikan dashboard flutter @farhanibnufajar

#### Catatan

- 
