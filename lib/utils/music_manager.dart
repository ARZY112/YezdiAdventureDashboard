import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nowplaying/nowplaying.dart';

class MusicManager extends ChangeNotifier {
  StreamSubscription<NowPlayingTrack>? _trackSubscription;
  NowPlayingTrack _currentTrack = NowPlayingTrack.notPlaying;
  
  NowPlayingTrack get currentTrack => _currentTrack;
  bool get isPlaying => !_currentTrack.isStopped && _currentTrack.isPlaying;
  
  String get title => _currentTrack.title?.trim() ?? "No Music Playing";
  String get artist => _currentTrack.artist?.trim() ?? "Unknown";
  String get album => _currentTrack.album?.trim() ?? "Unknown Album";

  MusicManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      // Check if enabled
      final enabled = await NowPlaying.instance.isEnabled();
      
      if (!enabled) {
        print("❌ Notification listener permission denied");
        // Request permissions
        await NowPlaying.instance.requestPermissions();
        print("ℹ️ Go to Settings > Apps > Special Access > Notification Access");
        return;
      }

      // Start service
      await NowPlaying.instance.start();
      
      // Listen to stream
      _trackSubscription = NowPlaying.instance.stream.listen((track) {
        _currentTrack = track;
        print("🎵 Now Playing: ${track.title} by ${track.artist}");
        notifyListeners();
      });
      
    } catch (e) {
      print("❌ Music Manager Error: $e");
    }
  }

  @override
  void dispose() {
    _trackSubscription?.cancel();
    super.dispose();
  }
}
