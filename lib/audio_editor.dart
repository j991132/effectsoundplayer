import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart';

class AudioEditor extends StatefulWidget {
  final Function(String name, String path) onSoundAdded;

  const AudioEditor({Key? key, required this.onSoundAdded}) : super(key: key);

  @override
  _AudioEditorState createState() => _AudioEditorState();
}

class _AudioEditorState extends State<AudioEditor> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _audioPath;
  bool _isPlaying = false;
  bool _isLoading = false;
  double _startTime = 0;
  double _endTime = 30;
  double _maxDuration = 30;
  String _audioName = '';

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );

      if (result != null) {
        setState(() {
          _isLoading = true;
        });

        _audioPath = result.files.single.path;
        _audioName = result.files.single.name;

        // 오디오 파일 로드
        await _audioPlayer.setFilePath(_audioPath!);
        final duration = _audioPlayer.duration;

        setState(() {
          _maxDuration = duration?.inSeconds.toDouble() ?? 30;
          _endTime = _maxDuration.clamp(0, 30);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error picking audio: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load audio file')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _playPreview() async {
    if (_audioPath == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _isPlaying = false;
        });
        return;
      }

      await _audioPlayer.setFilePath(_audioPath!);
      // 끝부분 재생 제어를 위한 리스너 추가
      _audioPlayer.positionStream.listen((position) {
        if (position >= Duration(milliseconds: ((_endTime + 1) * 1000).toInt())) {
          _audioPlayer.pause();
          setState(() {
            _isPlaying = false;
          });
        }
      });

      // 끝 시간에 약간의 여유를 추가
      final endTime = _endTime + 1;  // 0.1초의 여유 추가

      await _audioPlayer.setClip(
        start: Duration(milliseconds: (_startTime * 1000).toInt()),
        end: Duration(milliseconds: (endTime * 1000).toInt()),
      );

      setState(() {
        _isPlaying = true;
      });
      await _audioPlayer.play();

    } catch (e) {
      print('Error playing audio: $e');
      setState(() {
        _isPlaying = false;
      });
    }
  }

  // 이름 입력 다이얼로그 추가
  Future<String?> _showNameInputDialog() async {
    String? name;
    String originalName = _audioPath != null ?
    _audioPath!.split('/').last.split('.').first : // 파일경로에서 파일명만 추출하고 확장자 제거
    'sound';  // 기본값

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Enter sound effect name'),
          content: TextField(
            autofocus: true,
            controller: TextEditingController(text: originalName),  // 초기값 설정
            decoration: InputDecoration(hintText: "Enter name"),
            onChanged: (value) => name = value,
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                name = null;
              },
            ),
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
    return name ?? originalName;
  }

  Future<void> _saveEditedAudio() async {
    if (_audioPath == null) return;

    try {
      // 이름 입력 받기
      final name = await _showNameInputDialog();
      if (name == null || name.isEmpty) return;

      setState(() {
        _isLoading = true;
      });

      // 권한 확인
      if (!PermissionManager().hasPermission) {
        final hasPermission = await PermissionManager().checkAndRequestPermissions();
        if (!hasPermission) {
          throw '오디오 파일 저장을 위해 권한이 필요합니다.';
        }
      }

      final dir = await getTemporaryDirectory();
      final tempWavPath = '${dir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.wav';
      final editedPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.aac';

      // FFmpeg 명령어
      final FlutterFFmpeg flutterFFmpeg = FlutterFFmpeg();

      // WAV 변환
      int rc = await flutterFFmpeg.execute(
          '-i "$_audioPath" -acodec pcm_s16le "$tempWavPath"'
      );

      if (rc != 0) throw 'Failed to convert to WAV';

      // 편집 및 AAC 변환
      rc = await flutterFFmpeg.execute(
          '-i "$tempWavPath" -ss ${_startTime.toStringAsFixed(3)} -t ${(_endTime - _startTime + 1).toStringAsFixed(3)} '
              '-c:a aac -b:a 192k -avoid_negative_ts make_zero "$editedPath"'
      );

      // 임시 파일 정리
      try {
        await File(tempWavPath).delete();
      } catch (e) {
        print('Error deleting temp file: $e');
      }

      if (rc == 0) {
        widget.onSoundAdded(name, editedPath);
        Navigator.pop(context);
      } else {
        throw 'Failed to trim audio';
      }

    } catch (e) {
      print('Error saving audio: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save audio: $e'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Audio Editor'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _pickAudio,
              child: Text('Select Audio File'),
            ),
            if (_audioPath != null) ...[
              SizedBox(height: 20),
              Text(_audioName),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Start: ${_startTime.toInt()}s'),
                  Text('End: ${_endTime.toInt()}s'),
                ],
              ),
              RangeSlider(
                values: RangeValues(_startTime, _endTime),
                max: _maxDuration,
                divisions: (_maxDuration * 10).toInt(), // 0.1초 단위로 변경
                labels: RangeLabels(
                  _startTime.toStringAsFixed(1),  // 소수점 1자리까지 표시
                  _endTime.toStringAsFixed(1),
                ),
                onChanged: (RangeValues values) {
                  setState(() {
                    _startTime = values.start;
                    _endTime = values.end;
                  });
                },
              ),
              ElevatedButton.icon(
                onPressed: _playPreview,
                icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                label: Text(_isPlaying ? 'Stop' : 'Preview'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveEditedAudio,
                child: Text('Save as Sound Effect'),
              ),
            ],
            if (_isLoading)
              Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}