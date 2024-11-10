import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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
      } else {
        await _audioPlayer.setClip(
          start: Duration(seconds: _startTime.toInt()),
          end: Duration(seconds: _endTime.toInt()),
        );
        await _audioPlayer.play();
      }

      setState(() {
        _isPlaying = !_isPlaying;
      });

      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlaying = false;
          });
        }
      });
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  // 이름 입력 다이얼로그 추가
  Future<String?> _showNameInputDialog() async {
    String? name;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Enter sound effect name'),
          content: TextField(
            autofocus: true,
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
    return name;
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

      var status = await Permission.storage.request();
      if (!status.isGranted) {
        throw 'Storage permission denied';
      }

      final dir = await getTemporaryDirectory();
      final tempWavPath = '${dir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.wav';
      final editedPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.aac';  // aac 형식으로 변경

      // FFmpeg 명령어를 두 단계로 나누어 실행
      final FlutterFFmpeg flutterFFmpeg = FlutterFFmpeg();

      // 1단계: FLAC를 WAV로 변환
      int rc = await flutterFFmpeg.execute(
          '-i "$_audioPath" -acodec pcm_s16le "$tempWavPath"'
      );

      if (rc != 0) throw 'Failed to convert to WAV';

      // 2단계: WAV 파일을 자르고 AAC로 변환
      rc = await flutterFFmpeg.execute(
          '-i "$tempWavPath" -ss ${_startTime.toInt()} -t ${(_endTime - _startTime).toInt()} '
              '-c:a aac -b:a 192k "$editedPath"'
      );

      // 임시 WAV 파일 삭제
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
        SnackBar(content: Text('Failed to save edited audio')),
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
                divisions: _maxDuration.toInt(),
                labels: RangeLabels(
                  _startTime.toInt().toString(),
                  _endTime.toInt().toString(),
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