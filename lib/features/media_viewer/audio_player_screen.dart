// features/media_viewer/audio_player_screen.dart
//
// Player audio sederhana (MP3/WAV/OGG/M4A/FLAC/AAC/WMA) — kekurangan
// yang ditemukan Damar, Media Viewer Fase 3 sebelumnya cuma nangenin
// gambar & video. Pakai just_audio (package Flutter paling matang
// buat local file playback).
//
// SCOPE v1: single-track doang (nggak ada "lanjut ke lagu berikutnya
// di folder yang sama" — kalau nanti dibutuhin, itu scope tambahan
// terpisah). Player berhenti otomatis begitu screen ditutup (tidak
// ada playback di background/notification — itu butuh foreground
// service Android + media session, jauh lebih kompleks, di luar
// scope kekurangan yang dilaporkan).

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

const _dalxAccent = Color(0xFF0A84FF);

class AudioPlayerScreen extends StatefulWidget {
  final String path;
  const AudioPlayerScreen({super.key, required this.path});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late final AudioPlayer _player;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _load();
  }

  Future<void> _load() async {
    try {
      await _player.setFilePath(widget.path);
      await _player.play();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    // WAJIB — kalau nggak di-dispose, audio TERUS main di background
    // walau screen ini udah ditutup (just_audio nggak otomatis stop
    // sendiri pas widget di-dispose).
    _player.dispose();
    super.dispose();
  }

  String get _fileName => widget.path.split('/').last;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_fileName, overflow: TextOverflow.ellipsis),
      ),
      body: _error != null ? _buildError() : _buildPlayer(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack_outlined, size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            Text('Gagal memutar file audio:\n$_error',
                style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: _dalxAccent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.music_note, size: 80, color: _dalxAccent),
          ),
          const SizedBox(height: 28),
          Text(
            _fileName,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 28),
          StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (context, durationSnapshot) {
              final duration = durationSnapshot.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, positionSnapshot) {
                  var position = positionSnapshot.data ?? Duration.zero;
                  if (position > duration) position = duration;
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _dalxAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: _dalxAccent,
                          overlayColor: _dalxAccent.withOpacity(0.2),
                          trackHeight: 2.5,
                        ),
                        child: Slider(
                          min: 0,
                          max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                          value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                          onChanged: (value) => _player.seek(Duration(milliseconds: value.toInt())),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position), style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                            Text(_formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              final processingState = snapshot.data?.processingState;
              final isLoading = processingState == ProcessingState.loading ||
                  processingState == ProcessingState.buffering;

              return IconButton(
                iconSize: 64,
                color: _dalxAccent,
                icon: isLoading
                    ? const SizedBox(
                        width: 40, height: 40, child: CircularProgressIndicator(color: _dalxAccent, strokeWidth: 3),
                      )
                    : Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                onPressed: isLoading
                    ? null
                    : () => playing ? _player.pause() : _player.play(),
              );
            },
          ),
        ],
      ),
    );
  }
}
