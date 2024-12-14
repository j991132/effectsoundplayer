import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:effectsoundplayer/audio_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reorderable_grid/reorderable_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'dart:convert';
import 'package:wakelock/wakelock.dart';
import 'package:flutter/material.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();  // 이 줄이 없다면 추가
  if (Platform.isAndroid) {
    // 앱 시작 시 권한 요청
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }
  // 권한 체크
  await PermissionManager().checkAndRequestPermissions();
  Wakelock.enable();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sound Effect App',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.light,
      ),
      home: SoundEffectHomePage(),
    );
  }
}

// main.dart 상단에 추가
class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  bool _hasPermission = false;

  bool get hasPermission => _hasPermission;

  Future<bool> checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      // 스토리지 권한 확인
      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }

      // 미디어 권한 확인
      var audioStatus = await Permission.audio.status;
      if (!audioStatus.isGranted) {
        audioStatus = await Permission.audio.request();
      }

      _hasPermission = storageStatus.isGranted || audioStatus.isGranted;
      print('Permission status - Storage: ${storageStatus.isGranted}, Audio: ${audioStatus.isGranted}');
      return _hasPermission;
    }
    return true;
  }
}

Future<bool> checkPermissions() async {
  if (Platform.isAndroid) {
    // Android API 레벨 확인
    if (await Permission.storage.request().isGranted) {
      return true;
    }

    // storage 권한이 없다면 audio 권한 요청
    final audioStatus = await Permission.audio.request();
    print('Audio permission status: $audioStatus');
    return audioStatus.isGranted;
  }
  return true;
}

Future<bool> requestPermissions() async {
  if (Platform.isAndroid) {
    // 먼저 storage 권한 시도
    var storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) {
      print('Storage permission granted');
      return true;
    }

    // storage 권한이 거부되면 audio 권한 시도
    final audioStatus = await Permission.audio.request();
    print('Audio permission status: $audioStatus');
    return audioStatus.isGranted;
  }
  return true;
}

class SoundEffect {
  final String id;
  String name;
  final String? path;
  final Uint8List? bytes;
  int tabIndex;
  final DateTime addedDate;

  SoundEffect({
    required this.id,
    required this.name,
    this.path,
    this.bytes,
    required this.tabIndex,
    DateTime? addedDate,
  }) : this.addedDate = addedDate ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'bytes': bytes != null ? base64Encode(bytes!) : null,
    'tabIndex': tabIndex,
    'addedDate': addedDate.toIso8601String(),
  };

  factory SoundEffect.fromJson(Map<String, dynamic> json) => SoundEffect(
    id: json['id'],
    name: json['name'],
    path: json['path'],
    bytes: json['bytes'] != null ? base64Decode(json['bytes']) : null,
    tabIndex: json['tabIndex'],
    addedDate: DateTime.parse(json['addedDate']),
  );
}

class SoundEffectHomePage extends StatefulWidget {
  @override
  _SoundEffectHomePageState createState() => _SoundEffectHomePageState();
}

class _SoundEffectHomePageState extends State<SoundEffectHomePage>
    with TickerProviderStateMixin {
  List<SoundEffect> sounds = [];
  int gridColumns = 2;  // 기본값 2
  List<String> tabs = ['All', 'Tab 1', 'Tab 2', 'Tab 3', 'Tab 4'];
  late TabController _tabController;
  late AudioPlayer audioPlayer;
  TextEditingController searchController = TextEditingController();
  String? currentlyPlayingSoundId;
    List<Color> tabColors = [
    Colors.teal,
    Colors.blue,
    Colors.purple,
    Colors.orange,
    Colors.pink,
  ];
  Offset? _longPressStartPosition;
  bool _isDragging = false;
  Timer? _longPressTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
    initAudioPlayer();
    loadSounds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    audioPlayer.dispose();
    searchController.dispose();
    _longPressTimer?.cancel();
    super.dispose();
  }

  Future<void> initAudioPlayer() async {
    audioPlayer = AudioPlayer();
    if (!kIsWeb) {
      await audioPlayer.setReleaseMode(ReleaseMode.stop);
    }
  }

  Future<void> loadSounds() async {
    final prefs = await SharedPreferences.getInstance();
    final soundsJson = prefs.getString('sounds');
    if (soundsJson != null) {
      final List<dynamic> decoded = jsonDecode(soundsJson);
      setState(() {
        sounds = decoded.map((item) => SoundEffect.fromJson(item)).toList();
      });
    }

    final tabsJson = prefs.getString('tabs');
    if (tabsJson != null) {
      setState(() {
        tabs = List<String>.from(jsonDecode(tabsJson));
        _tabController = TabController(length: tabs.length, vsync: this);
      });
    }
  }

  Future<void> saveSounds() async {
    final prefs = await SharedPreferences.getInstance();
    final soundsJson = jsonEncode(sounds.map((s) => s.toJson()).toList());
    await prefs.setString('sounds', soundsJson);

    final tabsJson = jsonEncode(tabs);
    await prefs.setString('tabs', tabsJson);
  }

  Future<void> playSound(SoundEffect sound) async {
    try {
      // 현재 재생 중인 효과음을 다시 눌렀을 경우
      if (currentlyPlayingSoundId == sound.id) {
        await audioPlayer.stop();
        setState(() {
          currentlyPlayingSoundId = null;
        });
        return;
      }

      // 다른 효과음이 재생 중이었다면 중지
      if (currentlyPlayingSoundId != null) {
        await audioPlayer.stop();
      }

      // 새로운 효과음 재생
      if (kIsWeb) {
        if (sound.bytes != null) {
          await audioPlayer.play(BytesSource(sound.bytes!));
        }
      } else {
        if (sound.path != null) {
          await audioPlayer.play(DeviceFileSource(sound.path!));
        }
      }

      setState(() {
        currentlyPlayingSoundId = sound.id;
      });

      // 새로 추가: 재생 완료 시 상태 초기화
      audioPlayer.onPlayerComplete.listen((_) {
        setState(() {
          currentlyPlayingSoundId = null;
        });
      });
    } catch (e) {
      print('Error playing sound: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play sound: $e')),
      );
    }
  }

  Future<void> addSound() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null) {
      String name = await _showNameInputDialog();
      if (name.isNotEmpty) {
        final newSound = SoundEffect(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          path: kIsWeb ? null : result.files.single.path,
          bytes: kIsWeb ? result.files.single.bytes : null,
          tabIndex: _tabController.index,
        );
        setState(() {
          sounds.add(newSound);
        });
        await saveSounds();
      }
    }
  }

  void editSound(SoundEffect sound) async {
    String newName = await _showNameInputDialog(initialValue: sound.name);
    if (newName.isNotEmpty && newName != sound.name) {
      setState(() {
        sound.name = newName;
      });
      await saveSounds();
    }
  }

  void deleteSound(SoundEffect sound) async {
    setState(() {
      sounds.remove(sound);
    });
    await saveSounds();
  }

  void shareSound(SoundEffect sound) async {
    if (sound.path != null) {
      await Share.shareXFiles([XFile(sound.path!)], text: 'Check out this sound effect!');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sharing is not available on web')),
      );
    }
  }

  void moveSound(SoundEffect sound, int newTabIndex) async {
    setState(() {
      sound.tabIndex = newTabIndex;
    });
    await saveSounds();
  }

  List<SoundEffect> getFilteredSounds() {
    return sounds.where((sound) {
      final matchesTab = _tabController.index == 0 || sound.tabIndex == _tabController.index;
      final matchesSearch = sound.name.toLowerCase().contains(searchController.text.toLowerCase());
      return matchesTab && matchesSearch;
    }).toList();
  }

  void addNewTab() async {
    String newTabName = await _showNameInputDialog();
    if (newTabName.isNotEmpty) {
      setState(() {
        tabs.add(newTabName);
        _tabController = TabController(length: tabs.length, vsync: this);
      });
      await saveSounds();
    }
  }

  void editTab(int index) async {
    if (index == 0) return; // Don't allow editing the "All" tab
    String newTabName = await _showNameInputDialog(initialValue: tabs[index]);
    if (newTabName.isNotEmpty && newTabName != tabs[index]) {
      setState(() {
        tabs[index] = newTabName;
      });
      await saveSounds();
    }
  }

  void deleteTab(int index) async {
    if (index == 0) return; // Don't allow deleting the "All" tab
    setState(() {
      tabs.removeAt(index);
      sounds = sounds.map((sound) {
        if (sound.tabIndex == index) {
          return SoundEffect(
            id: sound.id,
            name: sound.name,
            path: sound.path,
            bytes: sound.bytes,
            tabIndex: 1, // Move to the first tab
            addedDate: sound.addedDate,
          );
        } else if (sound.tabIndex > index) {
          return SoundEffect(
            id: sound.id,
            name: sound.name,
            path: sound.path,
            bytes: sound.bytes,
            tabIndex: sound.tabIndex - 1, // Decrease tab index
            addedDate: sound.addedDate,
          );
        }
        return sound;
      }).toList();
      _tabController = TabController(length: tabs.length, vsync: this);
    });
    await saveSounds();
  }

  Future<String> _showNameInputDialog({String? initialValue}) async {
    String name = initialValue ?? '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(initialValue == null ? 'Enter name' : 'Edit name'),
          content: TextField(
            onChanged: (value) {
              name = value;
            },
            decoration: InputDecoration(
              hintText: 'Name',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: initialValue),
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
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

  void _showSoundOptions(SoundEffect sound) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.edit),
                title: Text('Edit Name'),
                onTap: () {
                  Navigator.pop(context);
                  editSound(sound);
                },
              ),
              ListTile(
                leading: Icon(Icons.folder),
                title: Text('Move to Tab'),
                onTap: () {
                  Navigator.pop(context);
                  _showMoveToTabDialog(sound);
                },
              ),
              ListTile(
                leading: Icon(Icons.share),
                title: Text('Share'),
                onTap: () {
                  Navigator.pop(context);
                  shareSound(sound);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  deleteSound(sound);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoveToTabDialog(SoundEffect sound) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Move to Tab'),
          content: SingleChildScrollView(
            child: ListBody(
              children: tabs.asMap().entries.map((entry) {
                int index = entry.key;
                String tabName = entry.value;
                if (index == 0) return Container(); // Skip "All" tab
                return ListTile(
                  title: Text(tabName),
                  onTap: () {
                    moveSound(sound, index);
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Sound Effect App',
        theme: ThemeData(
        primarySwatch: Colors.teal,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.light,
    ),
    home: FutureBuilder<bool>(  // 타입 명시
    future: checkPermissions(),
    builder: (context, AsyncSnapshot<bool> snapshot) {  // AsyncSnapshot 타입 명시
    // 권한이 있거나 iOS인 경우 메인 화면 표시
    if (snapshot.data == true || !Platform.isAndroid) {

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade100, Colors.blue.shade100],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Sound Effect App'),
          backgroundColor: Colors.teal.withOpacity(0.7),

          actions: [
            PopupMenuButton<int>(
              icon: Icon(Icons.grid_view),
              tooltip: 'Grid columns',
              onSelected: (int count) {
                setState(() {
                  gridColumns = count;
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 2,
                  child: Text('2 줄'),
                ),
                PopupMenuItem(
                  value: 3,
                  child: Text('3 줄'),
                ),
                PopupMenuItem(
                  value: 4,
                  child: Text('4 줄'),
                ),
              ],
            ),
          ],

          bottom: PreferredSize(
            preferredSize: Size.fromHeight(48),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              tabs: tabs.asMap().entries.map((entry) {
                return Flex(
                  direction: Axis.horizontal,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onLongPress: () {
                          if (entry.key != 0) {
                            editTab(entry.key);
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: tabColors[entry.key],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                          padding: EdgeInsets.symmetric(vertical: 4),
                          alignment: Alignment.center,
                          child: Tab(
                            child: Text(
                              entry.value,
                              style: TextStyle(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
              labelColor: Colors.black,
              unselectedLabelColor: Colors.black54,
              indicator: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: List.generate(tabs.length, (index) {
            final filteredSounds = index == 0 ? sounds : sounds.where((sound) => sound.tabIndex == index).toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Search sounds',
                      suffixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.7),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
            child: filteredSounds.isEmpty
            ? Center(child: Text('No sounds in this tab'))
                : GridView.builder(
            padding: EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridColumns,
            childAspectRatio: 1,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            ),
            itemCount: filteredSounds.length,
            itemBuilder: (context, index) {
            final sound = filteredSounds[index];
            final isPlaying = currentlyPlayingSoundId == sound.id;

            return Draggable<int>(
            key: ValueKey(sound.id),
            data: index,
            feedback: Material(
            elevation: 8.0,
            borderRadius: BorderRadius.circular(15),
            child: Container(
            width: MediaQuery.of(context).size.width / gridColumns - 10,
            height: MediaQuery.of(context).size.width / gridColumns - 10,
            decoration: BoxDecoration(
            gradient: LinearGradient(
            colors: [Colors.teal.shade300, Colors.blue.shade300],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
            child: Text(
            sound.name,
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
            ),
            ),
            ),
            ),
            childWhenDragging: Container(
            decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(15),
            ),
            ),
            onDragStarted: () {
            setState(() => _isDragging = true);
            },
            onDragEnd: (details) {
            setState(() => _isDragging = false);
            },
            child: DragTarget<int>(
              onWillAccept: (data) => data != null && data != index,  // 같은 위치가 아닐 때만 허용
              onAccept: (oldIndex) {
                setState(() {
                  // 드래그한 아이템을 리스트에서 제거하고 새 위치에 삽입
                  final movedItem = filteredSounds.removeAt(oldIndex);
                  if (oldIndex < index) {
                    // 이전 위치에서 드래그할 경우, 제거된 아이템으로 인해 인덱스가 하나씩 앞으로 당겨짐
                    filteredSounds.insert(index - 1, movedItem);
                  } else {
                    // 다음 위치로 드래그할 경우
                    filteredSounds.insert(index, movedItem);
                  }
                  saveSounds();  // 변경된 순서 저장
                });
              },
              builder: (context, candidateData, rejectedData) {
                return Container(
                    decoration: BoxDecoration(
                    // 드래그된 아이템이 올라갔을 때 시각적 피드백
                    color: candidateData.isNotEmpty ? Colors.grey.withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                ),
                child: GestureDetector(
            onLongPress: () {
            if (!_isDragging) {
            _showSoundOptions(sound);
            }
            },
            onTap: () => playSound(sound),
            child: AnimatedContainer(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
            gradient: LinearGradient(
            colors: isPlaying
            ? [Colors.teal.shade300, Colors.blue.shade300]
                : [Colors.white, Colors.grey.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
            BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: isPlaying ? 3 : 1,
            blurRadius: isPlaying ? 7 : 3,
            offset: Offset(0, 3),
            ),
            ],
            ),
            child: Material(
            color: Colors.transparent,
            child: InkWell(
            onTap: () => playSound(sound),
            borderRadius: BorderRadius.circular(15),
            child: AspectRatio(
            aspectRatio: 1,
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Expanded(
            flex: 3,
            child: FittedBox(
            fit: BoxFit.contain,
            child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: isPlaying ? Colors.white : tabColors[_tabController.index],
            ),
            ),
            ),
            ),
            Expanded(
            flex: 1,
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: AutoSizeText(
            sound.name,
            textAlign: TextAlign.center,
            style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isPlaying ? Colors.white : Colors.black87,
            ),
            maxLines: 1,
            minFontSize: 8,
            maxFontSize: 14,
            overflow: TextOverflow.ellipsis,
            ), // AutoSizeText 끝
            ), // Padding 끝
            ), // Expanded flex:1 끝
            ], // Column의 children 배열 끝
            ), // Column 끝
            ), // AspectRatio 끝
            ), // InkWell 끝
            ), // Material 끝
            ), // AnimatedContainer 끝
                )
                ); // GestureDetector 끝
            },
            ),  // Padding 끝
    );  // SizedBox 반환값 끝
    },  // List.generate의 각 아이템 생성 함수 끝
    ),  // Row 끝
    ),  // Draggable 끝
    ]
            );  // itemBuilder 반환값 끝
    },  // itemBuilder 끝
    ),  // GridView.builder 끝
    ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'edit',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.9,
                    child: AudioEditor(
                      onSoundAdded: (name, path) {
                        final newSound = SoundEffect(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          name: name,
                          path: path,
                          tabIndex: _tabController.index == 0 ? 1 : _tabController.index,
                        );
                        setState(() {
                          sounds.add(newSound);
                        });
                        saveSounds();
                      },
                    ),
                  ),
                );
              },
              child: Icon(Icons.edit),
              tooltip: 'Edit Audio',
            ),
            SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'add',
              onPressed: addSound,
              child: Icon(Icons.add),
              tooltip: 'Add new sound',
            ),
          ],
        ),
      ),
    );
    } else {
// 권한이 없는 경우 권한 요청 화면 표시
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '앱 사용을 위해 저장소 권한이 필요합니다',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final granted = await requestPermissions();
                  if (granted) {
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Colors.teal.shade100, Colors.blue.shade100],
                              ),
                            ),
                            child: SoundEffectHomePage(),
                          ),
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('권한이 필요합니다. 설정에서 권한을 허용해주세요.')),
                      );
                      openAppSettings();
                    }
                  }
                },
                child: Text('권한 설정하기'),
              ),
            ],
          ),
        ),
      );
    }
    }),
    );
  }
}