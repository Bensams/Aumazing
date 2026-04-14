# Aumazing

A Flutter application for tracking and supporting your child's journey.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (≥ 3.7.2)
- [Android Studio](https://developer.android.com/studio) with an AVD configured
- Android SDK (installed via Android Studio)

## Running the App

### 1. Verify your environment

```bash
flutter doctor
```

Fix any issues before continuing.

### 2. List available emulators

```bash
flutter emulators
```

If none exist, create one in Android Studio → **Device Manager → Create Virtual Device**.

### 3. Launch the emulator

**Option A** — via Flutter:

```bash
flutter emulators --launch Medium_Phone_API_36.1
```

**Option B** — via the Android SDK directly (faster, avoids Flutter wrapper overhead):

```bash
%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe -avd Medium_Phone_API_36.1
```

> Replace `Medium_Phone_API_36.1` with your AVD name from step 2.

### 4. Wait for the emulator to finish booting

```bash
adb wait-for-device
```

This blocks until the device is online. For a full boot check:

```bash
adb shell getprop sys.boot_completed
```

It returns `1` when the device is fully ready.

### 5. Run the app

```bash
flutter run
```

If multiple devices are connected, target the emulator explicitly:

```bash
flutter devices          # find the device id
flutter run -d <device-id>
```

### 6. Useful commands while the app is running

| Key | Action              |
|-----|---------------------|
| `r` | Hot reload           |
| `R` | Hot restart          |
| `q` | Quit                 |
| `p` | Toggle debug paint   |
| `o` | Toggle platform (iOS / Android) |

## Quick One-Liner

Launch the emulator and run the app in one go (PowerShell):

```powershell
Start-Process "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -ArgumentList "-avd Medium_Phone_API_36.1"; adb wait-for-device; flutter run
```

## Project Structure

```
lib/
├── core/           # Services, utilities, themes
├── features/       # Feature modules (splash, home, etc.)
assets/
├── images/         # PNG, JPG, WebP images
```

## Resources

- [Flutter documentation](https://docs.flutter.dev/)
- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)
