# Download Organizer

Script Bash untuk merapikan folder `Downloads` di macOS secara otomatis. File baru tetap masuk ke root `Downloads`; organizer berjalan harian, memindahkan file lepas berdasarkan ekstensi, dan tidak menyentuh subfolder yang sudah ada.

> Hanya untuk macOS. Bisa dijalankan manual lewat terminal, atau terjadwal otomatis menggunakan `launchd`.

---

## Struktur Folder

Setelah dijalankan, `Downloads` akan terorganisir seperti ini:

```
Downloads/
├── 00 Baru - Inbox/
├── 01 Images/
│   ├── png/
│   ├── jpg-jpeg/
│   ├── heic/
│   └── gif-webp-avif/
├── 02 Videos/
│   ├── mov/
│   └── mp4/
├── 03 Documents/
│   ├── pdf/
│   ├── docx/
│   └── csv/
├── 04 Audio/
│   ├── mp3/
│   └── wav/
├── 05 Design/
│   ├── psd/
│   └── svg/
├── 06 Installers/
│   ├── dmg/
│   └── pkg/
└── 07 Misc/
    ├── no-extension/
    ├── pkpass/
    └── unknown/
```

---

## Setup

**1. Beri izin eksekusi pada script:**

```sh
chmod +x organize-downloads.sh
```

**2. Siapkan file plist dari template:**

```sh
cp com.maulana.download-organizer.plist.example com.maulana.download-organizer.plist
```

Buka file tersebut dan ganti semua `{PROJECT_DIR}` dengan path absolut project ini. Contoh:

```
/Users/namauser/Projects/download-organizer
```

**3. (Opsional) Tambahkan shortcut ke `~/.zshrc`:**

```sh
alias d-o='/path/ke/organize-downloads.sh'
alias d-p='/path/ke/organize-downloads.sh --dry-run'
```

Reload shell setelahnya:

```sh
source ~/.zshrc
```

---

## Penggunaan Manual

Preview pergerakan file tanpa benar-benar memindahkannya:

```sh
./organize-downloads.sh --dry-run
# atau pakai shortcut
d-p
```

Jalankan organizer:

```sh
./organize-downloads.sh
# atau pakai shortcut
d-o
```

**Opsi tambahan:**

| Opsi | Default | Keterangan |
|------|---------|------------|
| `--dry-run` | — | Preview tanpa memindahkan file |
| `--downloads-dir PATH` | `~/Downloads` | Ganti folder target |
| `--min-age-minutes N` | `10` | Lewati file yang baru dimodifikasi dalam N menit terakhir |

Contoh testing dengan folder lain:

```sh
./organize-downloads.sh --dry-run --downloads-dir /path/ke/folder-test
```

---

## Automation — macOS (Opsional)

Gunakan `launchd` agar organizer berjalan terjadwal otomatis setiap hari pukul 06:00 tanpa perlu membuka terminal.

> **Catatan:** macOS akan meminta izin akses di **System Settings → Privacy & Security** saat pertama kali script dijalankan oleh `launchd`. Jika tidak ingin memberikan izin tersebut, cukup gunakan cara manual lewat terminal di atas — hasilnya sama persis.

**Install:**

```sh
cp com.maulana.download-organizer.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.maulana.download-organizer.plist
```

**Jalankan sekali untuk test:**

```sh
launchctl start com.maulana.download-organizer
```

**Cek log:**

```sh
tail -f logs/organize-$(date '+%Y-%m').log
tail -f logs/launchd.out.log
tail -f logs/launchd.err.log
```

**Uninstall:**

```sh
launchctl unload ~/Library/LaunchAgents/com.maulana.download-organizer.plist
rm ~/Library/LaunchAgents/com.maulana.download-organizer.plist
```

---

## Catatan

- Tidak ada file yang dihapus — hanya dipindahkan.
- Subfolder di root `Downloads` tidak disentuh.
- Jika nama file tujuan sudah ada, script menambahkan nomor: `file (1).pdf`.
- Semua aksi dicatat di `logs/organize-YYYY-MM.log` dan `logs/rename-map.csv`.
