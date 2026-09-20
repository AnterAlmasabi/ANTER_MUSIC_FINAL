import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

const Color accent = Color(0xFF22E06B);
const Color accent2 = Color(0xFF2E7CF6);
const Color panelBg = Color(0xDD0A1C12);
const Color panelBorder = Color(0x6622E06B);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('UI ERROR:\n${details.exception}', style: const TextStyle(color: Colors.red, fontSize: 12)),
      );
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'anter.music.audio',
      androidNotificationChannelName: 'ANTER MUSIC',
      androidNotificationChannelDescription: 'Music playback controls',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    );
  } catch (_) {}
  runApp(const AnterMusicApp());
}

class Track {
  final String path;
  final String title;
  final Duration duration;
  Track(this.path, this.title, this.duration);
}

enum AppView { home, search, library, timer }

class AnterMusicApp extends StatelessWidget {
  const AnterMusicApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ANTER MUSIC',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF04100A),
        colorScheme: ColorScheme.dark(primary: accent),
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

class _MusicHomeState extends State<MusicHome> with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _searchCtrl = TextEditingController();
  final List<Track> _tracks = [];
  late final AnimationController _eq;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  int _currentIndex = -1;
  bool _playing = false;
  bool _loading = true;
  AppView _view = AppView.home;

  static const _skipDirs = {'Android', 'data', 'cache', 'Cache', 'temp', 'Temp', '.thumbnails'};
  static const _audioExts = ['.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', '.wma'];

  @override
  void initState() {
    super.initState();
    _eq = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _player.currentIndexStream.listen((i) {
      if (mounted && i != null) setState(() => _currentIndex = i);
    });
    _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLibrary());
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _eq.dispose();
    _searchCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    try {
      var s = await Permission.audio.status;
      if (!s.isGranted) s = await Permission.audio.request();
      if (s.isGranted) return true;
      var s2 = await Permission.storage.status;
      if (!s2.isGranted) s2 = await Permission.storage.request();
      return s2.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadLibrary() async {
    setState(() => _loading = true);
    final List<Track> list = [];
    if (await _ensurePermission()) {
      final stack = <String>['/storage/emulated/0'];
      while (stack.isNotEmpty && list.length < 3000) {
        final dir = Directory(stack.removeLast());
        try {
          await for (final e in dir.list(followLinks: false)) {
            if (e is Directory) {
              final name = e.path.split('/').last;
              if (name.startsWith('.') || _skipDirs.contains(name)) continue;
              stack.add(e.path);
            } else if (e is File) {
              final p = e.path.toLowerCase();
              if (_audioExts.any((x) => p.endsWith(x))) {
                final file = e.path.split('/').last;
                list.add(Track(e.path, file.replaceFirst(RegExp(r'\.[^.]+$'), ''), Duration.zero));
              }
            }
          }
        } catch (_) {}
      }
      list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    if (mounted) {
      setState(() {
        _tracks.clear();
        _tracks.addAll(list);
        _loading = false;
      });
    }
  }

  Track? get _current => (_currentIndex >= 0 && _currentIndex < _tracks.length) ? _tracks[_currentIndex] : null;

  Future<void> _playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final sources = _tracks.asMap().entries.map((e) {
      return AudioSource.file(e.value.path, tag: MediaItem(id: '${e.key}', title: e.value.title, album: 'ANTER MUSIC'));
    }).toList();
    await _player.setAudioSources(sources, initialIndex: index);
    await _player.play();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else if (_player.sequence != null) {
      await _player.play();
    } else if (_tracks.isNotEmpty) {
      await _playTrack(_currentIndex >= 0 ? _currentIndex : 0);
    }
  }

  Future<void> _next() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> _previous() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  void _setSleep(Duration? duration) {
    _sleepTimer?.cancel();
    setState(() => _sleepRemaining = duration);
    if (duration == null) return;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final r = (_sleepRemaining ?? Duration.zero) - const Duration(seconds: 1);
      if (r <= Duration.zero) {
        timer.cancel();
        _player.pause();
        setState(() => _sleepRemaining = null);
      } else {
        setState(() => _sleepRemaining = r);
      }
    });
  }

  String _fmt(Duration? d) {
    if (d == null) return '0:00';
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Decoration get _panelDeco => BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: panelBg,
        border: Border.all(color: panelBorder, width: 1),
        boxShadow: const [BoxShadow(color: Color(0x3322E06B), blurRadius: 26)],
      );

  Widget _logo(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFF3AF07E), Color(0xFF0FA84E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: size / 2.5)],
      ),
      child: Icon(Icons.music_note_rounded, color: Colors.black, size: size * 0.55),
    );
  }

  Widget _railButton(AppView v, IconData icon) {
    final active = _view == v;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 3, height: 22, margin: const EdgeInsets.only(right: 6), color: active ? Colors.white : Colors.transparent),
          GestureDetector(
            onTap: () => setState(() => _view = v),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active ? const Color(0x33FFFFFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: active ? Colors.white : Colors.white54, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rail() {
    return Container(
      width: 86,
      decoration: _panelDeco,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          _logo(46),
          const SizedBox(height: 20),
          _railButton(AppView.home, Icons.home_outlined),
          _railButton(AppView.search, Icons.search_rounded),
          _railButton(AppView.library, Icons.library_music_outlined),
          _railButton(AppView.timer, Icons.timer_outlined),
          const Spacer(),
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 32),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [accent, accent2])),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(AppView v, IconData icon, String label, {Widget? trailing}) {
    final active = _view == v;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _view = v),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active ? const Color(0x14FFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 20, margin: const EdgeInsets.only(right: 10), color: active ? Colors.white : Colors.transparent),
                Icon(icon, color: active ? Colors.white : Colors.white70, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? Colors.white : Colors.white70)),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
        Container(height: 1, color: const Color(0x14FFFFFF)),
      ],
    );
  }

  Widget _eqBars() {
    const heights = <double>[22, 40, 58, 32, 62, 30, 44];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _eq,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(heights.length, (i) {
              final wave = _playing ? (math.sin(_eq.value * 2 * math.pi + i * 1.15) * 0.5 + 0.5) : 0.25;
              return Container(
                width: 6,
                height: heights[i] * (0.35 + 0.65 * wave),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _trackRow(Track tr, int index) {
    final active = index == _currentIndex;
    return ListTile(
      onTap: () => _playTrack(index),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? const Color(0x3322E06B) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(active ? Icons.equalizer_rounded : Icons.music_note_rounded, color: active ? accent : Colors.white54, size: 20),
      ),
      title: Text(tr.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? accent : Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(tr.duration == Duration.zero ? '--:--' : _fmt(tr.duration), style: const TextStyle(color: Colors.white38, fontSize: 11)),
    );
  }

  Widget _listOf(List<int> indexes) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (indexes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off_outlined, size: 44, color: Colors.white24),
            const SizedBox(height: 10),
            const Text('No songs found', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 10),
            TextButton.icon(onPressed: _loadLibrary, icon: const Icon(Icons.refresh), label: const Text('Rescan')),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: indexes.length,
      itemBuilder: (context, n) => _trackRow(_tracks[indexes[n]], indexes[n]),
    );
  }

  List<int> _searchIndexes() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return List.generate(_tracks.length, (i) => i);
    return [for (int i = 0; i < _tracks.length; i++) if (_tracks[i].title.toLowerCase().contains(q)) i];
  }

  Widget _timerView() {
    const names = ['Off', '5 minutes', '10 minutes', '15 minutes', '30 minutes', '60 minutes'];
    const values = <Duration?>[null, Duration(minutes: 5), Duration(minutes: 10), Duration(minutes: 15), Duration(minutes: 30), Duration(minutes: 60)];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (int i = 0; i < names.length; i++)
          ListTile(
            onTap: () => _setSleep(values[i]),
            leading: Icon(_sleepRemaining == values[i] ? Icons.radio_button_checked : Icons.radio_button_off, color: accent),
            title: Text(names[i], style: const TextStyle(color: Colors.white)),
          ),
      ],
    );
  }

  Widget _viewContent() {
    switch (_view) {
      case AppView.home:
        return Column(
          children: [
            _menuRow(AppView.home, Icons.home_outlined, 'Home', trailing: const Icon(Icons.chevron_right, color: Colors.white54)),
            _menuRow(AppView.search, Icons.search_rounded, 'Search'),
            _menuRow(AppView.library, Icons.library_music_outlined, 'Your library'),
            _menuRow(AppView.timer, Icons.timer_outlined, 'Sleep timer', trailing: _sleepRemaining != null ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: accent, shape: BoxShape.circle)) : null),
            const Spacer(),
          ],
        );
      case AppView.search:
        return Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search songs...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _listOf(_searchIndexes())),
          ],
        );
      case AppView.library:
        return _listOf(List.generate(_tracks.length, (i) => i));
      case AppView.timer:
        return _timerView();
    }
  }

  Widget _nowPlaying() {
    return Column(
      children: [
        const SizedBox(height: 6),
        _eqBars(),
        const SizedBox(height: 10),
        Text(_current?.title ?? 'ANTER MUSIC', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (context, snap) {
            final dur = _player.duration ?? Duration.zero;
            final pos = snap.data ?? Duration.zero;
            final max = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
            final value = pos.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
            return SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: const Color(0x33FFFFFF),
                thumbColor: Colors.white,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(value: value, max: max, onChanged: (v) => _player.seek(Duration(milliseconds: v.round()))),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(onPressed: _previous, icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 28)),
            const SizedBox(width: 18),
            GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 34),
              ),
            ),
            const SizedBox(width: 18),
            IconButton(onPressed: _next, icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 28)),
          ],
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: const Color(0x14FFFFFF)),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(
            children: [
              Container(width: 36, height: 36, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [accent, accent2]))),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ANTER MUSIC', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    Text('Offline Player', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              if (_sleepRemaining != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('⏱ ${_fmt(_sleepRemaining)}', style: const TextStyle(color: accent, fontSize: 12)),
                ),
              IconButton(onPressed: _loadLibrary, icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 20)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panel() {
    return Expanded(
      child: Container(
        decoration: _panelDeco,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: Column(
          children: [
            Row(children: [_logo(34), const SizedBox(width: 10), const Text('ANTER MUSIC', style: TextStyle(color: accent, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.5))]),
            const SizedBox(height: 14),
            const Align(alignment: Alignment.centerLeft, child: Text('MENU', style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.white38))),
            const SizedBox(height: 6),
            Expanded(child: _viewContent()),
            _nowPlaying(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(colors: [Color(0xFF0C2417), Color(0xFF04100A)], center: Alignment(-0.7, -0.5), radius: 1.5),
        ),
        padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
        child: Row(
          children: [
            _rail(),
            const SizedBox(width: 12),
            _panel(),
          ],
        ),
      ),
    );
  }
}
