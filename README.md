# ANTER MUSIC

Real Flutter music player for Android.

## Included
- Pick multiple audio files from the phone.
- Real play/pause, previous/next and seeking.
- Playlist and automatic next track.
- Background playback and notification controls.
- Sleep timer: 5 / 10 / 15 / 30 / 60 minutes or end of current song.
- Offline playback.

## Build
GitHub Actions builds a release APK automatically from `main`.

Artifact:
`build/app/outputs/flutter-apk/app-release.apk`

## Important Android Gradle fix
`android/settings.gradle` includes Flutter's Gradle build:
`includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`
This line must be inside `pluginManagement {}` before the `plugins {}` block.
