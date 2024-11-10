import 'dart:io';
import 'dart:typed_data';
import 'package:effectsoundplayer/audio_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'dart:convert';
import 'package:wakelock/wakelock.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();  // 이 줄이 없다면 추가
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

class _SoundEffectHomePageState extends State<SoundEffectHomePage> with SingleTickerProviderStateMixin {
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
                    itemBuilder: (context, soundIndex) {
                      final sound = filteredSounds[soundIndex];
                      final isPlaying = currentlyPlayingSoundId == sound.id;
                      return AnimatedContainer(
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
                            onLongPress: () => _showSoundOptions(sound),
                            borderRadius: BorderRadius.circular(15),
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
                                        color: isPlaying ? Colors.white : tabColors[index],
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
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }),
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
  }
}