# Tama Melody brand

Tama Melody is the piano-learning member of the Tama family, so it borrows
Tama-Tama's identity outright rather than inventing a second one.

## Palette

Copied verbatim from `tama-tama/app/globals.css` (`@theme` block). The single
source of truth in this repo is `app/lib/theme/tama_theme.dart`, and
`app/test/theme/tama_theme_test.dart` asserts these exact values so a future
edit cannot silently drift.

| Token | Hex | Role (same semantics as Tama-Tama) |
| --- | --- | --- |
| `blue` | `#7DD3FC` | Scaffold / page background |
| `purple` | `#A855F7` | Primary — app bar, buttons, target-note text |
| `pink` | `#FF8EAF` | Secondary accent, the pet's body |
| `white` | `#FAFAFA` | Card / surface fill |
| `ink` | `#334155` | Text and outlines |
| `rose` | `#F43F5E` | Cheeks, listening/alert indicator |
| `amber` | `#FBBF24` | Stars |
| `orange` | `#FB923C` | "Wrong note" coaching, detected key |
| `emerald` | `#34D399` | "Correct note" coaching, target key |
| `lavender` | `#C4B5FD` | Reserved tint |

The seven piano-key colors in `app/lib/widgets/piano_keyboard.dart` and
`illustrated_keyboard.dart` are **not** branding. They are a note-identification
aid (C is always red, D always yellow, …) and deliberately stay off the Tama
palette so they remain distinguishable from one another.

## Logo

`tama-melody.svg` is the master artwork: the Tama pet hatching out of a shell,
re-drawn so the shell is a piano keyboard and the pet is singing an eighth note.
Background, sparkles, body, and outlines use the palette above.

The checked-in PNGs are generated, not authored. To regenerate every platform
icon after editing the SVG:

```bash
pip install cairosvg pillow
python3 docs/brand/generate_icons.py
```

The script writes Android `mipmap-*/ic_launcher.png`, the iOS and macOS asset
catalogs, `app/web/favicon.png` + `app/web/icons/`, and the Windows
`app_icon.ico`. iOS icons are rendered full-bleed and opaque because Xcode
rejects alpha in an `AppIcon` set; web `Icon-maskable-*` files keep the artwork
inside the central safe zone that Android launchers mask to.

## Naming

`Tama Melody` is the user-facing name: `MaterialApp.title`, the adventure-map
app bar, the mic-permission copy, the Android `applicationLabel`, iOS
`CFBundleDisplayName`/`CFBundleName`, `app/web/manifest.json`, and `index.html`.
Dart code reads it from `kTamaMelodyAppName` rather than re-typing the string.

The engineering identifiers stay `melody_app` / `dev.melody.melody_app`
(pubspec `name`, Gradle `namespace`, `applicationId`, Kotlin package, iOS bundle
id, release-please `component`, and the `melody-<version>.apk` artifact name).
Renaming those changes the installed app's identity on existing devices, which
is a separate, deliberate migration.
