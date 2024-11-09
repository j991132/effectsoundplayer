// youtube_editor.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class YoutubeEditor extends StatefulWidget {
  final Function(String name, String path) onSoundAdded;

  const YoutubeEditor({Key? key, required this.onSoundAdded}) : super(key: key);

  @override
  _YoutubeEditorState createState() => _YoutubeEditorState();
}

class _YoutubeEditorState extends State<YoutubeEditor> {
  final TextEditingController _searchController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();
  List<Video> _searchResults = [];
  bool _isLoading = false;
  Video? _selectedVideo;
  double _startTime = 0;
  double _endTime = 30; // 기본 30초
  double _maxDuration = 30;

  @override
  void dispose() {
    _searchController.dispose();
    _yt.close();
    super.dispose();
  }

  Future<void> _trimAudio(String inputPath, String outputPath, int startMs, int endMs) async {
    final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();

    try {
      final int rc = await _flutterFFmpeg.execute(
          '-i "$inputPath" -ss ${startMs/1000} -t ${(endMs-startMs)/1000} -c copy "$outputPath"'
      );

      if (rc != 0) {
        throw 'FFmpeg process exited with rc $rc';
      }
    } catch (e) {
      throw 'Failed to trim audio: $e';
    }
  }

  Future<void> _searchYoutube(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    try {
      var results = await _yt.search.search(query);
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAndEdit(Video video) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 권한 요청
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        throw 'Storage permission denied';
      }

      // 임시 디렉토리 가져오기
      final dir = await getTemporaryDirectory();
      final tempPath = '${dir.path}/${video.id}.mp3';

      // 비디오 정보 가져오기
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      final audioStream = manifest.audioOnly.withHighestBitrate();

      // 다운로드
      var stream = await _yt.videos.streamsClient.get(audioStream);
      var file = File(tempPath);
      var fileStream = file.openWrite();
      await stream.pipe(fileStream);
      await fileStream.flush();
      await fileStream.close();

      // 오디오 편집
      final editedPath = '${dir.path}/${video.id}_edited.mp3';
      await _trimAudio(
        tempPath,
        editedPath,
        (_startTime * 1000).toInt(),
        (_endTime * 1000).toInt(),
      );

      // 원본 파일 삭제
      await file.delete();

      // 콜백 호출
      widget.onSoundAdded(video.title, editedPath);

      setState(() {
        _isLoading = false;
        _selectedVideo = null;
      });

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process video: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('YouTube Sound Editor'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search YouTube',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () => _searchYoutube(_searchController.text),
                ),
              ],
            ),
          ),
          if (_selectedVideo != null) ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(_selectedVideo!.title),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Start: ${_startTime.toInt()}s'),
                      ),
                      Expanded(
                        child: Text('End: ${_endTime.toInt()}s'),
                      ),
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
                  ElevatedButton(
                    onPressed: () => _downloadAndEdit(_selectedVideo!),
                    child: Text('Download and Edit'),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final video = _searchResults[index];
                return ListTile(
                  title: Text(video.title),
                  subtitle: Text('${video.duration}'),
                  onTap: () {
                    setState(() {
                      _selectedVideo = video;
                      _maxDuration = video.duration?.inSeconds.toDouble() ?? 30;
                      _endTime = _maxDuration.clamp(0, 30);
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}