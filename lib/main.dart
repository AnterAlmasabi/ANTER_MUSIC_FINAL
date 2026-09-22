import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

const MethodChannel scanChannel = MethodChannel('anter.music/scan');

const Color accent = Color(0xFF22E06B);
const Color bgTop = Color(0xFF0C2417);
const Color bgBottom = Color(0xFF04100A);
const Color card = Color(0xDD0A1C12);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class AnterMusicApp extends StatelessWidget {
  const AnterMusicApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ANTER MUSIC',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: bgBottom,
        colorScheme: ColorScheme.dark(primary: accent),
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _search = TextEditingController();
  final List<Track> _tracks = [];
  late final AnimationController _eq;
  Timer? _sleepTimer;
  Duration? _sleepLeft;
  int _current = -1;
  bool _playing = false;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _eq = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _player.currentIndexStream.listen((i) {
      if (mounted && i != null) setState(() => _current = i);
    });
    _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _eq.dispose();
    _search.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = <Track>[];
    try {
      var s = await Permission.audio.status;
      if (!s.isGranted) s = await Permission.audio.request();
      if (!s.isGranted) {
        var s2 = await Permission.storage.status;
        if (!s2.isGranted) s2 = await Permission.storage.request();
      }
      final raw = await scanChannel.invokeMethod<List>('scanSongs');
      for (final e in raw ?? const []) {
        final m = Map<String, dynamic>.from(e as Map);
        list.add(Track(
          m['path'] as String,
          (m['title'] as String?) ?? 'Unknown',
          Duration(milliseconds: (m['duration'] as int?) ?? 0),
        ));
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _tracks
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    }
  }

  Track? get _cur => (_current >= 0 && _current < _tracks.length) ? _tracks[_current] : null;

  Future<void> _play(int i) async {
    if (i < 0 || i >= _tracks.length) return;
    try {
      final sources = _tracks
          .asMap()
          .entries
          .map((e) => AudioSource.file(e.value.path, tag: MediaItem(id: '${e.key}', title: e.value.title, album: 'ANTER MUSIC')))
          .toList();
      await _player.setAudioSources(sources, initialIndex: i);
      await _player.play();
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else if (_player.sequence != null) {
      await _player.play();
    } else if (_tracks.isNotEmpty) {
      await _play(_current >= 0 ? _current : 0);
    }
  }

  void _setSleep(Duration? d) {
    _sleepTimer?.cancel();
    setState(() => _sleepLeft = d);
    if (d == null) return;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final r = (_sleepLeft ?? Duration.zero) - const Duration(seconds: 1);
      if (r <= Duration.zero) {
        t.cancel();
        _player.pause();
        setState(() => _sleepLeft = null);
      } else {
        setState(() => _sleepLeft = r);
      }
    });
  }

  String _fmt(Duration? d) {
    if (d == null) return '0:00';
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  List<int> _indexes() {
    final q = _search.text.trim().toLowerCase();
    if (_tab == 0 || q.isEmpty) return List.generate(_tracks.length, (i) => i);
    return [for (int i = 0; i < _tracks.length; i++) if (_tracks[i].title.toLowerCase().contains(q)) i];
  }

  Widget _eqBars() {
    const hs = <double>[10, 18, 26, 14, 22];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _eq,
        builder: (c, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < hs.length; i++)
              Container(
                width: 3,
                height: hs[i] * (_playing ? 0.4 + 0.6 * (math.sin(_eq.value * 2 * math.pi + i * 1.3) * 0.5 + 0.5) : 0.3),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                color: accent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _playerCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x6622E06B))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _eqBars(),
              const SizedBox(width: 10),
              Expanded(child: Text(_cur?.title ?? 'ANTER MUSIC', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (_sleepLeft != null) Text(_fmt(_sleepLeft), style: const TextStyle(color: accent, fontSize: 12)),
            ],
          ),
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snap) {
              final dur = _player.duration ?? Duration.zero;
              final pos = snap.data ?? Duration.zero;
              final max = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
              final val = pos.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  inactiveTrackColor: const Color(0x33FFFFFF),
                  thumbColor: accent,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
                ),
                child: Slider(value: val, max: max, onChanged: (v) => _player.seek(Duration(milliseconds: v.round()))),
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: () => _player.hasPrevious ? _player.seekToPrevious() : _player.seek(Duration.zero), icon: const Icon(Icons.skip_previous_rounded, size: 30)),
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 32),
                ),
              ),
              IconButton(onPressed: () => _player.hasNext ? _player.seekToNext() : null, icon: const Icon(Icons.skip_next_rounded, size: 30)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _list(List<int> idx) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: accent));
    if (idx.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 56, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('لا توجد أغاني', style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 8),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة الفحص')),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: idx.length,
      itemBuilder: (context, n) {
        final i = idx[n];
        final t = _tracks[i];
        final active = i == _current;
        return ListTile(
          onTap: () => _play(i),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: active ? const Color(0x3322E06B) : const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(12)),
            child: Icon(active ? Icons.equalizer_rounded : Icons.music_note_rounded, color: active ? accent : Colors.white54, size: 20),
          ),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? accent : Colors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(_fmt(t.duration), style: const TextStyle(color: Colors.white38, fontSize: 11)),
        );
      },
    );
  }

  Widget _timerTab() {
    const names = ['إيقاف المؤقت', '5 دقائق', '10 دقائق', '15 دقيقة', '30 دقيقة', '60 دقيقة'];
    const vals = <Duration?>[null, Duration(minutes: 5), Duration(minutes: 10), Duration(minutes: 15), Duration(minutes: 30), Duration(minutes: 60)];
    return ListView(
      children: [
        for (int i = 0; i < names.length; i++)
          ListTile(
            onTap: () => _setSleep(vals[i]),
            leading: Icon(_sleepLeft == vals[i] ? Icons.radio_button_checked : Icons.radio_button_off, color: accent),
            title: Text(names[i], style: const TextStyle(color: Colors.white)),
          ),
      ],
    );
  }

  Widget _body() {
    if (_tab == 2) return _timerTab();
    if (_tab == 1) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ابحث عن أغنية...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(child: _list(_indexes())),
        ],
      );
    }
    return _list(_indexes());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [bgTop, bgBottom], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF3AF07E), Color(0xFF0FA84E)]), boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 14)]),
                      child: const Icon(Icons.music_note_rounded, color: Colors.black, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text('ANTER MUSIC', style: TextStyle(color: accent, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const Spacer(),
                    Text('${_tracks.length}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
              Expanded(child: _body()),
              _playerCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        backgroundColor: const Color(0xFF07130C),
        selectedItemColor: accent,
        unselectedItemColor: Colors.white38,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: 'المكتبة'),
          BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'بحث'),
          BottomNavigationBarItem(icon: Icon(Icons.timer_outlined), label: 'المؤقت'),
        ],
      ),
    );
  }
}
