import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'anter.music.audio',
    androidNotificationChannelName: 'ANTER MUSIC',
    androidNotificationChannelDescription: 'Music playback controls',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: false,
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  runApp(const AnterMusicApp());
}

class Track {
  final String path;
  final String title;
  Track(this.path, this.title);
}

class AnterMusicApp extends StatelessWidget {
  const AnterMusicApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ANTER MUSIC',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B12),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF55D6BE), brightness: Brightness.dark),
      ),
      home: const MusicHome(),
    );
  }
}

class MusicHome extends StatefulWidget {
  const MusicHome({super.key});
  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> {
  final AudioPlayer _player = AudioPlayer();
  final List<Track> _tracks = [];
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _player.currentIndexStream.listen((i) {
      if (mounted && i != null) setState(() => _currentIndex = i);
    });
    _player.sequenceStateStream.listen((s) {
      if (mounted && s.currentIndex != null) setState(() => _currentIndex = s.currentIndex!);
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickMusic() async {
    final files = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (files == null || files.isEmpty) return;
    final added = files.where((f) => f.path != null).map((f) {
      final name = f.name.trim().isEmpty ? 'Unknown song' : f.name;
      return Track(f.path!, name.replaceFirst(RegExp(r'\.[^.]+$'), ''));
    }).toList();
    if (added.isEmpty) return;
    setState(() => _tracks.addAll(added));
    await _loadPlaylist(autoPlay: _tracks.length == added.length);
  }

  Future<void> _loadPlaylist({bool autoPlay = false, int? initialIndex}) async {
    if (_tracks.isEmpty) return;
    final sources = _tracks.asMap().entries.map((e) {
      return AudioSource.file(e.value.path, tag: MediaItem(id: '${e.key}', title: e.value.title, artist: 'ANTER MUSIC'));
    }).toList();
    await _player.setAudioSources(sources, initialIndex: initialIndex ?? (_currentIndex >= 0 ? _currentIndex : 0));
    if (autoPlay) await _player.play();
    setState(() {});
  }

  Future<void> _playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    if (_player.sequence.length != _tracks.length) {
      await _loadPlaylist(initialIndex: index);
    } else {
      await _player.seek(Duration.zero, index: index);
    }
    await _player.play();
  }

  Future<void> _next() async {
    if (_tracks.isEmpty) return;
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> _previous() async {
    if (_tracks.isEmpty) return;
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  void _setSleep(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) {
      setState(() => _sleepRemaining = null);
      return;
    }
    setState(() => _sleepRemaining = duration);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final r = _sleepRemaining ?? Duration.zero;
      if (r <= const Duration(seconds: 1)) {
        timer.cancel();
        _player.pause();
        setState(() => _sleepRemaining = null);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sleep timer ended — music paused')));
      } else {
        setState(() => _sleepRemaining = r - const Duration(seconds: 1));
      }
    });
  }

  Future<void> _showTimer() async {
    final selected = await showModalBottomSheet<Duration?>(
      context: context,
      backgroundColor: const Color(0xFF101722),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(18), child: Text('مؤقت إيقاف الموسيقى', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          if (_sleepRemaining != null)
            ListTile(leading: const Icon(Icons.timer_off), title: const Text('إلغاء المؤقت'), onTap: () => Navigator.pop(context, null)),
          for (final m in [5, 10, 15, 30, 60])
            ListTile(leading: const Icon(Icons.timer_outlined), title: Text('$m دقيقة'), onTap: () => Navigator.pop(context, Duration(minutes: m))),
          ListTile(leading: const Icon(Icons.album_outlined), title: const Text('عند نهاية الأغنية الحالية'), onTap: () async {
            final d = _player.duration;
            final p = _player.position;
            Navigator.pop(context, d != null && d > p ? d - p : const Duration(seconds: 1));
          }),
        ]),
      ),
    );
    _setSleep(selected);
  }

  String _fmt(Duration? d) {
    if (d == null) return '0:00';
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = _currentIndex >= 0 && _currentIndex < _tracks.length ? _tracks[_currentIndex].title : 'اختر أغنية للبدء';
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: const LinearGradient(colors: [Color(0xFF55D6BE), Color(0xFF2E7CF6)])), child: const Icon(Icons.music_note, color: Colors.black, size: 28)),
              const SizedBox(width: 12),
              const Expanded(child: Text('ANTER MUSIC', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
              IconButton(onPressed: _showTimer, icon: Icon(_sleepRemaining == null ? Icons.timer_outlined : Icons.timer, color: _sleepRemaining == null ? Colors.white70 : const Color(0xFF55D6BE))),
              IconButton(onPressed: _pickMusic, icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
          Expanded(
            child: _tracks.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.library_music_outlined, size: 72, color: Colors.white24), const SizedBox(height: 18), const Text('لا توجد أغاني بعد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('اضغط + لاختيار الأغاني من هاتفك', style: TextStyle(color: Colors.white54)), const SizedBox(height: 22), FilledButton.icon(onPressed: _pickMusic, icon: const Icon(Icons.folder_open), label: const Text('اختيار الأغاني'))]))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    itemCount: _tracks.length,
                    itemBuilder: (context, i) => ListTile(
                      onTap: () => _playTrack(i),
                      leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: i == _currentIndex ? const Color(0xFF163B3A) : const Color(0xFF151C27), borderRadius: BorderRadius.circular(12)), child: Icon(i == _currentIndex ? Icons.equalizer : Icons.music_note, color: i == _currentIndex ? const Color(0xFF55D6BE) : Colors.white54)),
                      title: Text(_tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: i == _currentIndex ? FontWeight.bold : FontWeight.normal)),
                      subtitle: const Text('ANTER MUSIC', style: TextStyle(color: Colors.white38)),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: const BoxDecoration(color: Color(0xFF0D131D), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: Column(children: [
              Row(children: [Expanded(child: Text(currentTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))), if (_sleepRemaining != null) Text('⏱ ${_fmt(_sleepRemaining)}', style: const TextStyle(color: Color(0xFF55D6BE)))]),
              const SizedBox(height: 8),
              StreamBuilder<Duration>(stream: _player.positionStream, builder: (context, snap) {
                final duration = _player.duration ?? Duration.zero;
                final position = snap.data ?? Duration.zero;
                final max = duration.inMilliseconds.toDouble().clamp(1, double.infinity);
                final value = position.inMilliseconds.toDouble().clamp(0, max);
                return Column(children: [Slider(value: value, max: max, onChanged: (v) => _player.seek(Duration(milliseconds: v.round()))), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_fmt(position), style: const TextStyle(color: Colors.white38, fontSize: 12)), Text(_fmt(duration), style: const TextStyle(color: Colors.white38, fontSize: 12))])]);
              }),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: _previous, iconSize: 30, icon: const Icon(Icons.skip_previous_rounded)), StreamBuilder<PlayerState>(stream: _player.playerStateStream, builder: (context, snap) { final playing = snap.data?.playing ?? false; return IconButton(onPressed: () => playing ? _player.pause() : _player.play(), iconSize: 58, icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: const Color(0xFF55D6BE))); }), IconButton(onPressed: _next, iconSize: 30, icon: const Icon(Icons.skip_next_rounded))]),
            ]),
          ),
        ]),
      ),
    );
  }
}