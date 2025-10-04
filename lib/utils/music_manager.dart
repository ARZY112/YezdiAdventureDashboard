import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nowplaying/nowplaying.dart';

class MusicManager extends ChangeNotifier {
  final NowPlaying _nowPlaying = NowPlaying();
  NowPlayingTrack? _currentTrack;
  bool _isPlaying = false;
  StreamSubscription<NowPlayingTrack>? _trackSubscription;
  
  NowPlayingTrack? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  
  String get title => _currentTrack?.title ?? "No Music Playing";
  String get artist => _currentTrack?.artist ?? "Unknown";
  String get album => _currentTrack?.album ?? "Unknown Album";

  MusicManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      bool enabled = await _nowPlaying.requestPermissions();
      
      if (!enabled) {
        print("❌ Notification listener permission denied");
        print("ℹ️ Go to Settings > Apps > Special Access > Notification Access");
        return;
      }

      await _nowPlaying.start();
      
      _trackSubscription = _nowPlaying.stream.listen((track) {
        _currentTrack = track;
        _isPlaying = track.state == NowPlayingState.playing;
        
        print("🎵 Now Playing: ${track.title} by ${track.artist}");
        notifyListeners();
      });
      
    } catch (e) {
      print("❌ Music Manager Error: $e");
    }
  }

  Future<void> requestPermission() async {
    bool enabled = await _nowPlaying.requestPermissions();
    if (!enabled) {
      print("Opening settings...");
    }
  }

  @override
  void dispose() {
    _trackSubscription?.cancel();
    _nowPlaying.stop();
    super.dispose();
  }
}
