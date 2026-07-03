# download-organizer

[![Read in English](https://img.shields.io/badge/Documentation-English-blue?style=flat-square)](README.md)

Script bash Linux-native yang secara otomatis mengurutkan file di folder Downloads ke dalam subfolder berdasarkan ekstensi file.

Proyek ini merupakan fork dari implementasi macOS asli, [download-organizer](https://github.com/m4sbay/download-organizer?utm_source=chatgpt.com). Seluruh komponen yang bergantung pada macOS telah dihapus, kemudian proyek ini ditulis ulang dari awal agar berjalan secara native pada distribusi Linux modern seperti Arch, CachyOS, Fedora, Ubuntu, Debian, dan openSUSE.

---

## Cara kerjanya

- Hanya memindai **root** folder Downloads — subfolder yang sudah ada tidak pernah disentuh.
- Melewati **dotfile**, **partial download** (`.crdownload`, `.part`, `.tmp`, dll.), dan **file yang baru saja dimodifikasi** (default: dimodifikasi dalam 10 menit terakhir).
- Mengarahkan setiap file ke subfolder yang tepat berdasarkan ekstensinya, menggunakan **mapping yang bisa dikonfigurasi** di `config/extensions.conf`.
- Membuat subfolder tujuan **sesuai kebutuhan** — tidak ada folder yang dibuat terlebih dahulu.
- Mencegah **tabrakan nama file** dengan menambahkan ` (1)`, ` (2)`, dst.
- Mencatat setiap pemindahan di `logs/rename-map.csv` — audit trail permanen.
- Mendukung **undo**: balik N pemindahan terakhir dari audit trail.
- Menggunakan **flock** untuk mencegah dua instance berjalan bersamaan dan saling bertabrakan.

---

## Struktur folder

Setelah pertama kali dijalankan, Downloads akan terlihat seperti ini (hanya kategori yang menerima file yang dibuat):

```
Downloads/
├── 01 Images/
│   ├── png/
│   ├── jpg-jpeg/
│   ├── webp/
│   ├── heic/
│   ├── raw/
│   └── ...
├── 02 Videos/
│   ├── mkv/
│   ├── mp4/
│   ├── webm/
│   └── ...
├── 03 Audio/
│   ├── mp3/
│   ├── flac/
│   ├── opus/
│   └── ...
├── 04 Documents/
│   ├── pdf/
│   ├── word/
│   ├── spreadsheet/
│   ├── ebooks/
│   └── ...
├── 05 Archives/
│   ├── zip/
│   ├── tar/
│   └── ...
├── 06 Installers/
│   ├── deb/
│   ├── rpm/
│   ├── appimage/
│   ├── iso/
│   └── ...
├── 07 Design/
│   ├── svg/
│   ├── photoshop/
│   └── ...
├── 08 Code/
│   ├── scripts/
│   ├── python/
│   └── ...
├── 09 Fonts/
├── 10 Certs/
└── 07 Misc/
    ├── no-extension/
    ├── unknown/
    └── partial/       ← file yang masih dalam proses download masuk sini jika bocor
```

Daftar ekstensi lengkap: lihat `config/extensions.conf`.

---

## Persyaratan

- bash ≥ 4.0 (dibutuhkan untuk associative array)
- GNU coreutils: `stat`, `date`, `find`, `mktemp`, `realpath`
- `flock` (bagian dari util-linux, sudah terpasang secara default di semua distro target)
- `xdg-user-dirs` (untuk menentukan lokasi `~/Downloads` via XDG)

Semua persyaratan ini sudah tersedia secara default di Arch, CachyOS, Fedora, Ubuntu, Debian, dan openSUSE.

---

## Setup

```sh
git clone https://github.com/budi-imam-prasetyo/download-organizer
cd download-organizer
chmod +x organize-downloads.sh tests/run-tests.sh
```

Jalankan test suite untuk memverifikasi semuanya berjalan normal di sistem kamu:

```sh
bash tests/run-tests.sh
```

---

## Penggunaan manual

Preview file yang akan dipindahkan (tidak ada yang berubah):

```sh
./organize-downloads.sh --dry-run
```

Preview dengan output verbose (menampilkan setiap file yang dilewati juga):

```sh
./organize-downloads.sh --dry-run --verbose
```

Jalankan organizer:

```sh
./organize-downloads.sh
```

Shell alias opsional (`~/.bashrc` atau `~/.zshrc`):

```sh
alias d-o='/path/to/organize-downloads.sh'
alias d-p='/path/to/organize-downloads.sh --dry-run'
```

---

## Opsi

| Opsi | Default | Keterangan |
|---|---|---|
| `--dry-run` | — | Preview pemindahan, tidak ada yang berubah |
| `--verbose` | — | Tampilkan setiap file yang dilewati (default: diam) |
| `--downloads-dir PATH` | `xdg-user-dir DOWNLOAD` | Ganti folder target |
| `--min-age-minutes N` | `10` | Lewati file yang dimodifikasi dalam N menit terakhir |
| `--keep-logs-months N` | `3` | Rotasi log bulanan yang lebih tua dari N bulan. `0` menonaktifkan cleanup |
| `-h, --help` | — | Tampilkan bantuan |

### Environment variable

Semua flag memiliki environment variable yang setara (prioritas paling rendah):

| Variable | Flag yang setara |
|---|---|
| `DOWNLOADS_DIR` | `--downloads-dir` |
| `MIN_AGE_MINUTES` | `--min-age-minutes` |
| `KEEP_LOGS_MONTHS` | `--keep-logs-months` |
| `LOG_DIR` | Direktori log (default: `<repo>/logs`) |
| `EXTENSIONS_CONF` | File konfigurasi ekstensi (default: `<repo>/config/extensions.conf`) |

---

## Undo

Setiap pemindahan dicatat di `logs/rename-map.csv`. Untuk membalik pemindahan:

```sh
# Undo semua pemindahan dari run terakhir (urutan LIFO):
./organize-downloads.sh undo

# Preview undo tanpa mengubah apapun:
./organize-downloads.sh undo --dry-run

# Undo hanya 5 pemindahan terakhir:
./organize-downloads.sh undo --last 5

# Preview 3 undo terakhir:
./organize-downloads.sh undo --last 3 --dry-run
```

Undo memvalidasi setiap pemindahan sebelum membaliknya: jika file sudah tidak ada di tujuan, atau path asal sudah ditempati file lain, entri tersebut dilewati dan peringatan dicatat ke log.

---

## Menambah atau mengubah mapping ekstensi

Edit `config/extensions.conf` — tidak perlu menyentuh kode shell apapun:

```
# Format: extension=Category/subfolder
mkv=02 Videos/mkv
flac=03 Audio/flac
```

Aturan:
- Ekstensi harus huruf kecil, tanpa tanda titik di depan.
- Path bersifat relatif terhadap folder Downloads.
- Baris yang diawali `#` adalah komentar.
- Jika ada ekstensi duplikat, entri terakhir yang berlaku.
- Cukup jalankan ulang script untuk mengambil perubahan — tidak perlu reload.

---

## Otomasi dengan systemd

Direktori `systemd/` berisi user service dan timer yang menjalankan organizer setiap hari pukul 06:00. Jika mesin sedang mati saat jadwal itu tiba, timer akan mengejar dan menjalankannya saat boot berikutnya.

### Install

Edit `systemd/download-organizer.service` dan perbarui path `ExecStart` sesuai lokasi repo yang kamu clone. Kemudian:

```sh
# Salin unit ke direktori systemd user.
mkdir -p ~/.config/systemd/user
cp systemd/download-organizer.service ~/.config/systemd/user/
cp systemd/download-organizer.timer   ~/.config/systemd/user/

# Aktifkan dan mulai timer.
systemctl --user daemon-reload
systemctl --user enable --now download-organizer.timer
```

### Cek status

```sh
# Apakah timer aktif?
systemctl --user status download-organizer.timer

# Kapan timer akan jalan berikutnya?
systemctl --user list-timers download-organizer.timer

# Lihat log dari run terakhir:
journalctl --user -u download-organizer -n 50

# Ikuti log secara live:
journalctl --user -u download-organizer -f
```

### Jalankan sekali secara manual via systemd

```sh
systemctl --user start download-organizer.service
```

### Uninstall

```sh
systemctl --user disable --now download-organizer.timer
rm ~/.config/systemd/user/download-organizer.service
rm ~/.config/systemd/user/download-organizer.timer
systemctl --user daemon-reload
```

---

## Log

| File | Keterangan |
|---|---|
| `logs/organize-YYYY-MM.log` | Log bulanan yang bisa dibaca manusia (dirotasi otomatis) |
| `logs/rename-map.csv` | Audit trail permanen dari setiap pemindahan (tidak pernah dihapus) |

Log bulanan yang lebih tua dari `--keep-logs-months` (default: 3) dihapus di setiap run. File CSV tidak pernah dihapus secara otomatis.

---

## Struktur proyek

```
download-organizer/
├── organize-downloads.sh     # Main entry point
├── lib/
│   ├── core.sh               # Logging, die, CSV primitives
│   ├── routing.sh            # Extension → folder routing
│   └── undo.sh               # Undo subcommand
├── config/
│   └── extensions.conf       # Editable extension-to-folder mapping
├── systemd/
│   ├── download-organizer.service
│   └── download-organizer.timer
├── tests/
│   ├── run-tests.sh
│   ├── test-routing.sh
│   ├── test-age.sh
│   └── test-undo.sh
└── logs/                     # Dibuat saat pertama kali dijalankan
    ├── organize-YYYY-MM.log
    └── rename-map.csv
```

---

## Catatan

- File hanya **dipindahkan**, tidak pernah dihapus.
- Subfolder di root Downloads tidak pernah disentuh.
- Jika nama file tujuan sudah ada, counter ditambahkan: `file (1).pdf`, `file (2).pdf`, dst.
- Partial download (`.crdownload`, `.part`, `.tmp`, dll.) selalu dilewati.
- File yang dimodifikasi dalam `--min-age-minutes` terakhir dilewati untuk menghindari pemindahan file yang masih ditulis.
- Lock file disimpan di `$XDG_RUNTIME_DIR` (biasanya `/run/user/$(id -u)/`) sehingga dibersihkan secara otomatis saat logout.
