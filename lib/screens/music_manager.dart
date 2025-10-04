import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

class MusicManager extends ChangeNotifier {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  
  SongModel? _currentSong;
  bool _isPlaying = false;
  
  SongModel? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;

  Future<bool> requestPermission() async {
    return await _audioQuery.permissionsRequest();
  }

  Future<void> getCurrentPlayingSong() async {
    bool hasPermission = await requestPermission();
    if (!hasPermission) {
      print("❌ Music permission denied");
      return;
    }
    
    // Get last played song
    List<SongModel> songs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
    );
    
    if (songs.isNotEmpty) {
      _currentSong = songs.first;
      _isPlaying = true;
      notifyListeners();
      print("🎵 Now Playing: ${_currentSong!.title}");
    }
  }
  
  void stopPlaying() {
    _isPlaying = false;
    notifyListeners();
  }
}
