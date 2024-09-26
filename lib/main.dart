import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
//첫 업로드
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sound Effect App',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
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

  SoundEffect({
    required this.id,
    required this.name,
    this.path,
    this.bytes,
    required this.tabIndex
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'bytes': bytes != null ? base64Encode(bytes!) : null,
    'tabIndex': tabIndex,
  };

  factory SoundEffect.fromJson(Map<String, dynamic> json) => SoundEffect(
    id: json['id'],
    name: json['name'],
    path: json['path'],
    bytes: json['bytes'] != null ? base64Decode(json['bytes']) : null,
    tabIndex: json['tabIndex'],
  );
}

class SoundEffectHomePage extends StatefulWidget {
  @override
  _SoundEffectHomePageState createState() => _SoundEffectHomePageState();
}

class _SoundEffectHomePageState extends State<SoundEffectHomePage> {
  List<SoundEffect> sounds = [];
  List<String> tabs = ['All', 'Tab 1', 'Tab 2', 'Tab 3', 'Tab 4'];
  int currentTabIndex = 0;
  late AudioPlayer audioPlayer;
  TextEditingController searchController = TextEditingController();



  @override
  void initState() {
    super.initState();
    initAudioPlayer();
    loadSounds();
  }
  Future<void> initAudioPlayer() async {
    audioPlayer = AudioPlayer();
    if (!kIsWeb) {
      await audioPlayer.setReleaseMode(ReleaseMode.stop);
    }
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    searchController.dispose();
    super.dispose();
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
          tabIndex: currentTabIndex,
        );
        setState(() {
          sounds.add(newSound);
        });
        await saveSounds();
      }
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
      if (kIsWeb) {
        if (sound.bytes != null) {
          await audioPlayer.play(BytesSource(sound.bytes!));
        }
      } else {
        if (sound.path != null) {
          await audioPlayer.play(DeviceFileSource(sound.path!));
        }
      }
    } catch (e) {
      print('Error playing sound: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play sound: $e')),
      );
    }
  }

  void editSound(SoundEffect sound) async {
    String newName = await _showNameInputDialog();
    if (newName.isNotEmpty) {
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

  List<SoundEffect> getFilteredSounds() {
    return sounds.where((sound) {
      final matchesTab = currentTabIndex == 0 || sound.tabIndex == currentTabIndex;
      final matchesSearch = sound.name.toLowerCase().contains(searchController.text.toLowerCase());
      return matchesTab && matchesSearch;
    }).toList();
  }

  void addNewTab() async {
    String newTabName = await _showNameInputDialog();
    if (newTabName.isNotEmpty) {
      setState(() {
        tabs.add(newTabName);
      });
      await saveSounds();
    }
  }

  Future<String> _showNameInputDialog() async {
    String name = '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Enter name'),
          content: TextField(
            onChanged: (value) {
              name = value;
            },
            decoration: InputDecoration(
              hintText: 'Name',
              border: OutlineInputBorder(),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sound Effect App'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: addNewTab,
            tooltip: 'Add new tab',
          ),
        ],
      ),
      body: Column(
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
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Text(tabs[index]),
                    selected: currentTabIndex == index,
                    onSelected: (selected) {
                      setState(() {
                        currentTabIndex = index;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: getFilteredSounds().length,
              itemBuilder: (context, index) {
                final sound = getFilteredSounds()[index];
                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: InkWell(
                    onTap: () => playSound(sound),
                    onLongPress: () => _showSoundOptions(sound),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.music_note, size: 40, color: Theme.of(context).primaryColor),
                        SizedBox(height: 8),
                        Text(
                          sound.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addSound,
        child: Icon(Icons.add),
        tooltip: 'Add new sound',
      ),
    );
  }
}