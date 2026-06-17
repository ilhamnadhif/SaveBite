# PRD — SaveBite

**Product Requirements Document**
Versi: 1.0
Tanggal: Juni 2026
Penyusun: Ilham
Status: Draft (untuk Tugas Aplikasi Kewirausahaan)

---

## 1. Ringkasan Eksekutif

**SaveBite** adalah aplikasi marketplace yang menghubungkan merchant makanan (resto, bakery, kafe, supermarket) yang memiliki stok makanan surplus di akhir hari dengan konsumen yang ingin membeli makanan berkualitas dengan harga jauh lebih murah.

Mekanismenya: merchant menjual makanan surplus dalam bentuk **"Surprise Bag"** (paket kejutan berisi makanan yang masih layak tapi tidak terjual hari itu) dengan harga diskon 50–70%. Konsumen membeli lewat aplikasi, lalu **mengambil sendiri** (self pickup) ke toko pada jam yang ditentukan menjelang tutup.

Model bisnis ini **asset-light** dan **tanpa logistik** — SaveBite tidak mengantar atau menjemput apa pun, sehingga unit economics jauh lebih sehat dibanding model pengelolaan sampah/makanan yang mengandalkan armada kurir.

> Terinspirasi dari Too Good To Go (Denmark, 2015) yang kini beroperasi di banyak negara termasuk Amerika Serikat.

---

## 2. Latar Belakang & Masalah

### 2.1 Masalah

- **Food waste tinggi.** Banyak makanan layak konsumsi terbuang setiap hari dari toko makanan karena tidak terjual sebelum tutup. Makanan ini sudah menyerap biaya bahan baku dan tenaga, namun memberi return nol — bahkan menambah biaya pembuangan sampah.
- **Merchant rugi.** Makanan yang tidak terjual = kerugian penuh bagi merchant. Tidak ada kanal yang mudah untuk "menyelamatkan" nilai sisa tersebut.
- **Konsumen butuh opsi hemat.** Banyak konsumen (mahasiswa, pekerja muda) mencari makanan berkualitas dengan harga terjangkau.
- **Kesadaran lingkungan & nilai mubazir.** Ada dorongan kultural dan lingkungan yang kuat untuk tidak menyia-nyiakan makanan.

### 2.2 Peluang

Mempertemukan ketiga kebutuhan di atas dalam satu platform: merchant dapat *recovery revenue* + exposure, konsumen dapat makanan murah, dan dampak lingkungan (food waste turun) menjadi nilai jual tambahan.

---

## 3. Tujuan & Sasaran

### 3.1 Tujuan Produk

1. Mengurangi food waste dengan menyalurkan makanan surplus ke konsumen.
2. Memberi merchant kanal monetisasi atas stok yang tidak terjual.
3. Memberi konsumen akses makanan berkualitas dengan harga hemat.

### 3.2 Sasaran (MVP / untuk tugas)

- Aplikasi fungsional dengan dua role (Konsumen & Merchant) yang dapat didemokan.
- Alur lengkap end-to-end: merchant membuat bag → konsumen beli & bayar → ambil dengan QR → selesai & rating.
- Fokus area awal: satu cluster geografis (mis. sekitar kampus / area Depok–Cibinong).

### 3.3 Metrik Keberhasilan (KPI)

| Kategori | Metrik |
|---|---|
| Dampak | Jumlah Surprise Bag terselamatkan (terjual) |
| Pertumbuhan | Jumlah merchant aktif, jumlah konsumen terdaftar |
| Transaksi | GMV (total nilai transaksi), jumlah order/hari |
| Engagement | Repeat purchase rate, rating rata-rata merchant |
| Operasional | Pickup success rate (order diambil vs no-show) |

---

## 4. Target Pengguna (Persona)

### 4.1 Konsumen

- **Mahasiswa hemat** — cari makan murah dekat kampus/kos.
- **Pekerja muda urban** — mau makanan berkualitas dengan diskon, suka kejutan.
- **Eco-conscious** — peduli lingkungan, ingin mengurangi food waste.

### 4.2 Merchant

- **Bakery & toko roti** — banyak stok roti sisa harian.
- **Kafe & coffee shop** — pastry, sandwich, menu harian tak terjual.
- **Restoran** — porsi/menu sisa di akhir operasional.
- **Supermarket / toko bahan** — produk mendekati best-before.

---

## 5. Role & Hak Akses

| Role | Deskripsi | Akses utama |
|---|---|---|
| **Konsumen** | Membeli Surprise Bag | Browse, beli, bayar, pickup, rating |
| **Merchant** | Menjual makanan surplus | Buat & kelola bag, lihat order, redeem QR, lihat earnings |
| **Admin** (opsional) | Mengelola platform | Verifikasi merchant, moderasi, lihat report |

> **Satu aplikasi, dua cabang ekosistem.** SaveBite adalah satu aplikasi (bukan dua app terpisah) dengan **dua cabang besar**: ekosistem **Pembeli** dan ekosistem **Penjual**. Setelah install, user melihat **onboarding global**, lalu memilih **"mau beli atau jual"** (fork) **sebelum** login. Login **hanya via Google** (tombol sama untuk kedua cabang). **Satu akun Google bisa menjadi pembeli sekaligus penjual** — peran adalah *mode* yang dapat diganti kapan saja lewat Profil ("Beralih ke Mode Merchant/Konsumen") **tanpa login ulang**, bukan akun terpisah. Pengguna lama langsung masuk ke ekosistem terakhir tanpa mengulang onboarding/fork.
>
> Untuk MVP tugas, Admin bisa diwakili akses database/dashboard sederhana dan tidak wajib jadi aplikasi penuh.

---

## 6. Functional Requirements (Fitur)

### 6.1 Umum (Shared)

- **F-G1** Onboarding global (carousel perkenalan saat pertama install; tidak diulang untuk pengguna lama).
- **F-G2** Fork pemilihan cabang ("mau beli / mau jual") **sebelum** login; menentukan masuk ekosistem Pembeli atau Penjual.
- **F-G3** Login/registrasi **via Google (OAuth)** dalam satu langkah — tombol sama untuk kedua cabang, tanpa email/password.
- **F-G4** Setup toko untuk akun yang pertama kali masuk mode Penjual (data yang tak disediakan Google).
- **F-G5** Ganti mode (Pembeli ⇄ Penjual) via Profil tanpa login ulang; satu akun bisa keduanya.
- **F-G6** Manajemen profil.
- **F-G7** Push notification (status order, bag baru di sekitar).

### 6.2 Konsumen

- **F-C1** Lihat daftar Surprise Bag di sekitar lokasi (sorted by jarak / waktu pickup).
- **F-C2** Pencarian & filter (kategori makanan, jarak, harga, jam pickup).
- **F-C3** Tampilan peta (bag di-plot pada map).
- **F-C4** Detail bag: info merchant, deskripsi isi, harga (asli vs diskon), jumlah tersisa, window pickup, rating merchant.
- **F-C5** Halaman profil merchant/toko.
- **F-C6** Checkout & pembayaran in-app.
- **F-C7** Voucher/order aktif dengan **kode QR** untuk pickup.
- **F-C8** Riwayat order.
- **F-C9** Favorit (simpan merchant favorit).
- **F-C10** Beri rating & review setelah pickup.

### 6.3 Merchant

- **F-M1** Setup profil toko (nama, alamat, jam operasional, foto, kategori).
- **F-M2** Buat Surprise Bag (judul, deskripsi, harga asli, harga jual, jumlah, window pickup).
- **F-M3** Kelola bag (edit, aktif/nonaktif, duplikat untuk hari berikutnya).
- **F-M4** Lihat daftar order masuk (real-time).
- **F-M5** **Scan/redeem QR** konsumen saat pickup.
- **F-M6** Dashboard penjualan (hari ini, ringkasan, history).
- **F-M7** Earnings & settlement (saldo, riwayat, penarikan dana).

### 6.4 Pembayaran & Settlement (Inti Teknis)

- **F-P1** Integrasi payment gateway (mis. Midtrans/Xendit) — VA, e-wallet, kartu.
- **F-P2** Pembayaran di depan (prepaid) oleh konsumen.
- **F-P3** Split dana: nilai bag dikurangi komisi platform → sisanya ke saldo merchant.
- **F-P4** Pencatatan transaksi & ledger (audit trail).
- **F-P5** Settlement/penarikan saldo merchant ke rekening.

> **Catatan:** F-P (payment & settlement) adalah jantung teknis SaveBite dan selaras dengan keahlian DCB/payment gateway. Ini bagian yang paling layak dibuat solid untuk membedakan dari kelompok lain.

---

## 7. User Flow Utama

### 7.0 Flow Onboarding & Login (Pertama Install)

```
Splash → Onboarding global (carousel)
→ Fork "Mau beli atau jual?"
→ Login "Lanjutkan dengan Google" (tombol sama untuk kedua cabang)
   • Pembeli  → (priming lokasi) → Home          ── ekosistem Pembeli
   • Penjual  → (pertama kali: Setup Toko) → Dashboard ── ekosistem Penjual

(Pengguna lama: Splash → langsung ke ekosistem terakhir, skip onboarding & fork)
(Ganti mode kapan saja lewat Profil, tanpa login ulang)
```

### 7.1 Flow Pembelian (Konsumen)

```
Buka app → Lihat bag di sekitar → Pilih bag → Lihat detail
→ Checkout → Pilih metode bayar → Bayar → Dapat voucher + QR
→ Datang ke toko (jam pickup) → Tunjukkan QR → Merchant scan
→ Ambil bag → Selesai → Beri rating
```

### 7.2 Flow Buat Bag (Merchant)

```
Login merchant → Dashboard → Buat Surprise Bag
→ Isi detail (judul, deskripsi, harga, jumlah, window pickup)
→ Publish → Bag tampil ke konsumen di sekitar
```

### 7.3 Flow Redeem (Pickup)

```
Konsumen datang → Buka voucher (QR) → Merchant scan QR
→ Sistem validasi (order valid, dalam window) → Status: Selesai
→ Dana masuk ke saldo merchant (dikurangi komisi)
```

---

## 8. Non-Functional Requirements

| Aspek | Kebutuhan |
|---|---|
| **Performa** | Response API < 500ms untuk operasi umum; daftar bag termuat cepat |
| **Keamanan** | Login via Google OAuth 2.0; verifikasi ID token Google di backend; session pakai JWT; HTTPS; validasi input. Tidak menyimpan password (tak ada email/password) |
| **Skalabilitas** | Arsitektur modular, siap di-scale horizontal |
| **Ketersediaan** | Target uptime tinggi; graceful error handling |
| **Konsistensi data** | Transaksi pembayaran harus ACID (tidak boleh double-charge / saldo bocor) |
| **Privasi** | Data pengguna & lokasi dilindungi; akses sesuai role |

---

## 9. Tech Stack & Arsitektur

### 9.1 Stack

| Layer | Teknologi | Alasan |
|---|---|---|
| **Mobile** | **Flutter (Dart)** | Single codebase iOS + Android, UI cepat, cocok untuk MVP |
| **Backend** | **Golang** | Performa tinggi, konkuren, ideal untuk API & payment logic |
| **Database** | **PostgreSQL** | Relasional, ACID, andal untuk transaksi keuangan |
| **Auth** | Google Sign-In (OAuth 2.0) + JWT | Login satu langkah, tanpa kelola password |
| **Cache/Session** | Redis *(opsional)* | Session, rate limiting, cache daftar bag |
| **Object Storage** | S3-compatible / Cloud Storage *(opsional)* | Simpan foto bag/toko |
| **Payment** | Midtrans / Xendit | Payment gateway lokal (VA, e-wallet, kartu) |
| **Notifikasi** | Firebase Cloud Messaging (FCM) | Push notification |
| **Maps** | Google Maps SDK / Mapbox | Tampilan peta & geolokasi |

### 9.2 Arsitektur (High-Level)

```
┌─────────────────┐         ┌──────────────────────┐
│  Flutter App    │  HTTPS  │   Golang API         │
│  (Konsumen &    │ ──────► │   (REST)             │
│   Merchant)     │ ◄────── │                      │
└─────────────────┘  JSON   │  ┌────────────────┐  │
                            │  │ Auth Service   │  │
       ▲                    │  │ Bag Service    │  │
       │ FCM                │  │ Order Service  │  │
       │                    │  │ Payment Service│  │
┌──────┴───────┐            │  └────────────────┘  │
│  Firebase    │            └───────┬──────┬───────┘
│  (Push)      │                    │      │
└──────────────┘            ┌───────▼──┐ ┌─▼──────────┐
                            │PostgreSQL│ │  Redis     │
                            └──────────┘ └────────────┘
                                    │
                            ┌───────▼────────┐
                            │ Payment Gateway│
                            │ (Midtrans/     │
                            │  Xendit)       │
                            └────────────────┘
```

> Untuk MVP, backend cukup **modular monolith** (satu service Golang dengan modul terpisah), bukan microservices penuh — lebih cepat dibangun dan didemokan.

---

## 10. Data Model (High-Level Schema)

Tabel-tabel inti:

**users**
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID (PK) | |
| google_id | varchar (unique) | ID dari Google (sub) |
| name | varchar | dari Google |
| email | varchar (unique) | dari Google |
| avatar_url | varchar | foto profil dari Google |
| phone | varchar | opsional (diisi saat checkout/setup) |
| role | enum(consumer, merchant) | peran aktif, bisa diganti |
| created_at | timestamp | |

**merchants**
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID (PK) | |
| user_id | UUID (FK → users) | |
| store_name | varchar | |
| description | text | |
| address | varchar | |
| latitude | decimal | |
| longitude | decimal | |
| category | varchar | bakery, cafe, resto, dll |
| open_time / close_time | time | |
| logo_url | varchar | |
| status | enum(pending, active, suspended) | |

**surprise_bags**
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID (PK) | |
| merchant_id | UUID (FK) | |
| title | varchar | |
| description | text | |
| original_price | decimal | |
| sale_price | decimal | |
| quantity_total | int | |
| quantity_left | int | |
| pickup_start | timestamp | |
| pickup_end | timestamp | |
| image_url | varchar | |
| status | enum(active, sold_out, inactive, expired) | |
| created_at | timestamp | |

**orders**
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID (PK) | |
| consumer_id | UUID (FK → users) | |
| bag_id | UUID (FK → surprise_bags) | |
| merchant_id | UUID (FK) | |
| quantity | int | |
| total_amount | decimal | |
| commission_amount | decimal | |
| merchant_amount | decimal | |
| pickup_code | varchar | kode unik / QR payload |
| status | enum(pending_payment, paid, redeemed, cancelled, expired) | |
| created_at | timestamp | |

**transactions** (ledger pembayaran)
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID (PK) | |
| order_id | UUID (FK) | |
| payment_method | varchar | |
| gateway_ref | varchar | referensi dari payment gateway |
| amount | decimal | |
| status | enum(pending, success, failed, refunded) | |
| paid_at | timestamp | |

**reviews**
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID (PK) | |
| order_id | UUID (FK) | |
| consumer_id | UUID (FK) | |
| merchant_id | UUID (FK) | |
| rating | int (1–5) | |
| comment | text | |
| created_at | timestamp | |

**favorites**
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID (PK) | |
| consumer_id | UUID (FK) | |
| merchant_id | UUID (FK) | |

**merchant_balances** (saldo merchant)
| Kolom | Tipe | Keterangan |
|---|---|---|
| merchant_id | UUID (FK) | |
| balance | decimal | |
| updated_at | timestamp | |

---

## 11. API Endpoints (High-Level)

### Auth
- `POST /auth/google` — login/daftar via Google ID token, return JWT
- `POST /auth/role` — set/ganti peran (consumer/merchant)
- `GET /auth/me` — profil user aktif

### Konsumen
- `GET /bags?lat=&lng=&radius=&category=` — daftar bag di sekitar
- `GET /bags/:id` — detail bag
- `GET /merchants/:id` — profil merchant
- `POST /orders` — buat order (checkout)
- `POST /orders/:id/pay` — inisiasi pembayaran
- `GET /orders` — riwayat order konsumen
- `GET /orders/:id` — detail order + QR
- `POST /reviews` — beri rating
- `GET /favorites` / `POST /favorites` / `DELETE /favorites/:id`

### Merchant
- `POST /merchant/store` — setup/update toko
- `POST /merchant/bags` — buat bag
- `GET /merchant/bags` — daftar bag milik merchant
- `PUT /merchant/bags/:id` — edit/aktif-nonaktif
- `GET /merchant/orders` — order masuk
- `POST /merchant/orders/:id/redeem` — validasi QR / redeem
- `GET /merchant/dashboard` — ringkasan penjualan
- `GET /merchant/balance` — saldo & riwayat
- `POST /merchant/withdraw` — penarikan dana

### Webhook
- `POST /webhooks/payment` — callback dari payment gateway (update status order)

---

## 12. Scope MVP vs Pengembangan Lanjutan

### MVP (untuk tugas — wajib)
- Onboarding global + fork (beli/jual) sebelum login + login via Google (satu app, dua cabang ekosistem)
- Konsumen: lihat daftar bag, detail, checkout + bayar (bisa pakai sandbox payment), voucher QR, rating
- Merchant: setup toko, buat bag, lihat order, redeem QR, dashboard sederhana
- Notifikasi dasar

### Nice-to-have (jika sempat)
- Tampilan peta interaktif
- Filter & pencarian lanjutan
- Favorit
- Settlement/penarikan dana otomatis

### Future (di luar tugas)
- Admin panel penuh & verifikasi merchant
- Program loyalitas/poin
- Rekomendasi berbasis preferensi
- Ekspansi multi-kota
- Laporan dampak lingkungan (CO₂/food waste tersave)

---

## 13. Milestone & Timeline

Disesuaikan dengan jadwal mata kuliah:

| Milestone | Deliverable | Target |
|---|---|---|
| M1 | BMC + Proposal Bisnis | **Pertemuan 8** |
| M2 | Desain UI/UX (Claude Design) + skema DB | Setelah proposal |
| M3 | Backend API (auth, bag, order) | — |
| M4 | Integrasi payment + frontend Flutter | — |
| M5 | Testing end-to-end | — |
| M6 | **Show Product** (demo) | Akhir |

---

## 14. Risiko & Asumsi

| Risiko | Mitigasi |
|---|---|
| **Chicken-and-egg** (butuh merchant & konsumen bersamaan) | Fokus 1 cluster dulu (sekitar kampus/area tertentu), rekrut beberapa merchant sekaligus, baru tarik konsumen di radius itu |
| **Food safety** (makanan layak?) | Window pickup ketat menjelang tutup; makanan surplus *hari itu*; rating merchant jaga kualitas |
| **No-show** (sudah bayar, tak diambil) | Prepaid — risiko di konsumen (dana hangus jika tak diambil); policy jelas |
| **Kompetitor** (sudah ada Surplus di Indonesia) | Posisikan beda (fokus area kampus / fitur spesifik); jangan klaim "pertama di Indonesia" |
| **Adopsi merchant rendah** | Friction rendah lewat konsep Surprise Bag (tak perlu listing per item) |

### Asumsi
- Konsumen bersedia ambil sendiri (self pickup) demi harga murah.
- Merchant melihat recovery revenue + exposure lebih baik daripada membuang.
- Ada payment gateway yang bisa diintegrasikan (sandbox cukup untuk demo).

---

## 15. Lampiran

- **Design Spec per-halaman:** lihat `design-spec.md`
- **Referensi model:** Too Good To Go (global), Surplus (Indonesia)

---

*Dokumen ini adalah draft untuk Tugas Aplikasi Kewirausahaan dan dapat diperbarui seiring pengembangan.*
