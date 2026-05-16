# Download Organizer

Project kecil untuk merapikan folder `Downloads` di Mac secara otomatis. File baru tetap masuk ke root `Downloads`; organizer berjalan harian, memindahkan file lepas berdasarkan format, dan tidak menyentuh folder project yang sudah ada.

## Struktur Hasil

```text
Downloads/
  00 Baru - Inbox/
  01 Images/
    png/
    jpg-jpeg/
    heic/
    gif-webp-avif/
  02 Videos/
    mov/
    mp4/
  03 Documents/
    pdf/
    docx/
    csv/
  04 Audio/
    mp3/
    wav/
  05 Design/
    psd/
    svg/
  06 Installers/
    dmg/
    pkg/
  07 Misc/
    no-extension/
    pkpass/
    unknown/
```

## Cara Pakai Manual

Preview tanpa memindahkan file:

```sh
./organize-downloads.sh --dry-run
```

Jalankan organizer:

```sh
./organize-downloads.sh
```

Gunakan folder lain untuk testing:

```sh
./organize-downloads.sh --dry-run --downloads-dir /path/to/test-folder
./organize-downloads.sh --downloads-dir /path/to/test-folder
```

Secara default script melewati file yang dimodifikasi dalam 10 menit terakhir agar tidak mengganggu download yang belum selesai. Ubah batasnya dengan:

```sh
./organize-downloads.sh --min-age-minutes 30
```

## Shortcut Terminal

Jika shortcut sudah ditambahkan ke `~/.zshrc`, buka terminal baru atau jalankan:

```sh
source ~/.zshrc
```

Preview tanpa memindahkan file:

```sh
d-p
```

Jalankan organizer:

```sh
d-o
```

## Install Automation macOS

Pastikan script executable:

```sh
chmod +x organize-downloads.sh
```

Copy plist ke folder LaunchAgents:

```sh
cp com.maulana.download-organizer.plist ~/Library/LaunchAgents/
```

Load job:

```sh
launchctl load ~/Library/LaunchAgents/com.maulana.download-organizer.plist
```

Organizer akan berjalan setiap hari pukul `06:00`.

## Test Automation

Jalankan sekali lewat `launchd`:

```sh
launchctl start com.maulana.download-organizer
```

Cek log:

```sh
tail -f logs/organize-$(date '+%Y-%m').log
tail -f logs/launchd.out.log
tail -f logs/launchd.err.log
```

## Uninstall Automation

Unload job:

```sh
launchctl unload ~/Library/LaunchAgents/com.maulana.download-organizer.plist
```

Hapus plist dari LaunchAgents:

```sh
rm ~/Library/LaunchAgents/com.maulana.download-organizer.plist
```

## Catatan Keamanan

- Tidak ada file yang dihapus.
- Folder di root `Downloads` tidak dipindahkan.
- Jika nama file tujuan sudah ada, script menambahkan nomor seperti `file (1).pdf`.
- Semua aksi dicatat di `logs/organize-YYYY-MM.log`.
- Jejak pemindahan CSV tersedia di `logs/rename-map.csv`.
- `GitHub Actions` tidak dipakai karena tidak bisa mengakses folder lokal `Downloads` di Mac.
