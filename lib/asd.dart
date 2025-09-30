import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_pad/add%20copy.dart';
import 'package:audio_pad/add.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o Firebase ANTES de rodar o app
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(child: Text("Erro ao inicializar Firebase")),
            ),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Multitracks',
          theme: ThemeData.dark(),
          home: GoogleDriveDownloaderPage(),
        );
      },
    );
  }
}

class GoogleDriveDownloaderPage extends StatefulWidget {
  const GoogleDriveDownloaderPage({super.key});

  @override
  _GoogleDriveDownloaderPageState createState() =>
      _GoogleDriveDownloaderPageState();
}

class _GoogleDriveDownloaderPageState extends State<GoogleDriveDownloaderPage> {
  Map<String, dynamic> multitracksData = {};
  Map<String, dynamic> originalMultitracksData = {};

  Future<void> _loadMultitracks() async {
    final data = await getMultitracks();
    setState(() {
      multitracksData = data;
      originalMultitracksData = Map.from(data);
    });
    _checkDownloadedFolders();
  }

  @override
  void initState() {
    super.initState();
    _loadMultitracks();
    _loadSavedPresets();
  }

  Map<String, bool> _isDownloading = {};

  Future<Map<String, dynamic>> getMultitracks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("multitracks")
        .get();

    Map<String, dynamic> result = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      result[doc.id] = {
        "cover": data["cover"] ?? "",
        "files": (data["files"] as List)
            .map((file) => {"name": file["name"], "link": file["link"]})
            .toList(),
        "author": data["author"] ?? "Autor desconhecido",
        "duration": data["duration"] ?? "00:00",
        "trackCount": data["trackCount"] ?? 0,
      };
    }

    return result;
  }

  Map<String, bool> _alreadyDownloadedFolders = {};
  Map<String, bool> _downloadingFolders = {};
  Map<String, String> _statusByFolder = {};
  List<Map<String, dynamic>> savedPresets = [];
  final _presetsKey = 'audio_pad_presets';
  String? _selectedFolder;

  // Variáveis para controle de áudio
  List<XFile> selectedFiles = [];
  List<bool> isMutedList = [];
  List<double> panValues = [];
  List<double> volumeValues = [];
  List<double> currentPitchValues = [];
  double globalPitch = 0.0;
  Duration currentPosition = Duration.zero;
  bool isPlaying = false;
  String _multitrackName = "MultiX";
  int? _selectedPresetIndex;
  bool _isPresetUnsaved = false;

  Future<void> _loadSavedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> presets = prefs.getStringList(_presetsKey) ?? [];

    setState(() {
      savedPresets = presets
          .map((json) {
            try {
              final decoded = jsonDecode(json) as Map<String, dynamic>;
              if (decoded['files'] == null || decoded['name'] == null) {
                return null;
              }
              return {
                'id': decoded['id'] ?? _generateUniqueId(),
                'name': decoded['name'],
                'fileCount': (decoded['files'] as List).length,
                'timestamp':
                    decoded['timestamp'] ?? DateTime.now().toIso8601String(),
              };
            } catch (e) {
              return null;
            }
          })
          .where((preset) => preset != null)
          .toList()
          .cast<Map<String, dynamic>>();
    });
  }

  String _generateUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<void> _checkDownloadedFolders() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    final Map<String, bool> downloaded = {};

    for (var folderName in multitracksData.keys) {
      Directory folderDir = Directory(
        '${appDocDir.path}/downloaded/$folderName',
      );

      if (await folderDir.exists()) {
        final existingFiles = folderDir
            .listSync()
            .whereType<File>()
            .where(
              (file) => [
                'mp3',
                'wav',
                'm4a',
                'aac',
              ].contains(file.path.split('.').last.toLowerCase()),
            )
            .toList();

        downloaded[folderName] = existingFiles.isNotEmpty;
      } else {
        downloaded[folderName] = false;
      }
    }

    setState(() {
      _alreadyDownloadedFolders = downloaded;
    });
  }

  Future<void> downloadFilesForFolder(
    String folderName,
    List<Map<String, dynamic>> files,
  ) async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    Directory folderDir = Directory('${appDocDir.path}/downloaded/$folderName');

    if (await folderDir.exists()) {
      final existingFiles = folderDir
          .listSync()
          .whereType<File>()
          .where(
            (file) => [
              'mp3',
              'wav',
              'm4a',
              'aac',
            ].contains(file.path.split('.').last.toLowerCase()),
          )
          .toList();

      if (existingFiles.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A pasta "$folderName" já foi baixada.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } else {
      await folderDir.create(recursive: true);
    }

    setState(() {
      _downloadingFolders[folderName] = true;
      _statusByFolder[folderName] = 'Baixando $folderName...';
    });

    List<String> failedFiles = [];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final link = file["link"];
      final fileName = file["name"] ?? "file_$i.mp3";

      final regex = RegExp(r'/d/([a-zA-Z0-9_-]+)');
      final match = regex.firstMatch(link);
      if (match == null) {
        failedFiles.add(fileName);
        continue;
      }
      final fileId = match.group(1);
      final url = 'https://drive.google.com/uc?export=download&id=$fileId';
      String savePath = '${folderDir.path}/$fileName';

      setState(() {
        _statusByFolder[folderName] = 'Baixando $fileName em $folderName...';
        _downloadingFolders[folderName] = true;
        _downloadProgress[folderName] = i / files.length;
      });

      try {
        await Dio().download(url, savePath);

        // 🔹 Verifica se o arquivo foi baixado de verdade
        final f = File(savePath);
        if (!await f.exists() || await f.length() == 0) {
          failedFiles.add(fileName);
          if (await f.exists()) await f.delete(); // remove arquivo corrompido
        }
      } catch (e) {
        print('Erro ao baixar arquivo: $e');
        failedFiles.add(fileName);
      }

      setState(() {
        _downloadProgress[folderName] = (i + 1) / files.length;
      });
    }

    if (failedFiles.isNotEmpty) {
      setState(() {
        _downloadingFolders[folderName] = false;
        _alreadyDownloadedFolders[folderName] = false;
        _statusByFolder[folderName] = '';
      });

      // 🔥 Remove a pasta inteira em caso de falha
      if (await folderDir.exists()) {
        try {
          await folderDir.delete(recursive: true);
        } catch (e) {
          print("Erro ao excluir pasta incompleta: $e");
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Download incompleto. "
            "${files.length - failedFiles.length} de ${files.length} arquivos baixados.\n"
            "Falharam: ${failedFiles.join(', ')}",
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return; // ❌ não cria preset se falhou algo
    }

    setState(() {
      _downloadingFolders[folderName] = false;
      _alreadyDownloadedFolders[folderName] = true;
      _statusByFolder[folderName] = '';
    });

    if (!mounted) return;

    // 🔹 Criar automaticamente o preset após o download
    final presetIndex = await createPresetFromFolder(folderName);
    if (presetIndex != null && mounted) {
      await loadPreset(presetIndex, context);
    }

    if (Platform.isAndroid) {
      await OpenFile.open(folderDir.path);
    }
  }

  Future<int?> createPresetFromFolder(String folderName) async {
    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList(_presetsKey) ?? [];

    final exists = presets.any((presetJson) {
      final preset = jsonDecode(presetJson) as Map<String, dynamic>;
      return preset['name'] == folderName;
    });

    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Preset '$folderName' já existe!"),
          backgroundColor: Colors.orange,
        ),
      );
      return null;
    }

    Directory appDir = await getApplicationDocumentsDirectory();
    Directory folderDir = Directory('${appDir.path}/downloaded/$folderName');

    if (!await folderDir.exists()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Pasta $folderName não existe!')));
      return null;
    }

    List<FileSystemEntity> allFiles = folderDir.listSync();
    List<File> audioFiles = allFiles
        .whereType<File>()
        .where(
          (file) => [
            'mp3',
            'wav',
            'm4a',
            'aac',
          ].contains(file.path.split('.').last.toLowerCase()),
        )
        .toList();

    if (audioFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não há arquivos de áudio na pasta $folderName'),
        ),
      );
      return null;
    }

    final List<String> internalPaths = [];
    final Set<String> addedBaseNames = {};

    for (final file in audioFiles) {
      final baseName = p.basename(file.path);
      if (addedBaseNames.contains(baseName)) continue;

      try {
        final internalPath = await _copyFileToInternal(file);
        internalPaths.add(internalPath);
        addedBaseNames.add(baseName);
      } catch (e, st) {
        print('Erro ao copiar arquivo $baseName: $e\n$st');
      }
    }

    if (internalPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao copiar arquivos para o preset')),
      );
      return null;
    }

    final preset = {
      'id': _generateUniqueId(),
      'name': folderName,
      'files': internalPaths,
      'panValues': List.generate(internalPaths.length, (_) => 0.0),
      'volumeValues': List.generate(internalPaths.length, (_) => 0.7),
      'pitchValues': List.generate(internalPaths.length, (_) => 0.0),
      'globalPitch': 0.0,
      'isMutedList': List.generate(internalPaths.length, (_) => false),
      'selectedIcons': List.generate(internalPaths.length, (_) => 'guitar.png'),
      'timestamp': DateTime.now().toIso8601String(),
      'coverImage': multitracksData[folderName]["cover"],
      'author': multitracksData[folderName]["author"] ?? "Autor desconhecido",
      'duration': multitracksData[folderName]["duration"] ?? "00:00",
    };

    presets.add(jsonEncode(preset));
    await prefs.setStringList(_presetsKey, presets);
    await _loadSavedPresets();

    return savedPresets.length - 1;
  }

  Future<String> _copyFileToInternal(File file) async {
    final audioDir = await _internalAudioDir;
    final uniqueName =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
    final newPath = '${audioDir.path}/$uniqueName';

    try {
      await file.copy(newPath);
      return newPath;
    } catch (e) {
      print('Erro ao copiar arquivo: $e');
      rethrow;
    }
  }

  Future<void> _showEditDialog(String folderName) async {
    final track = multitracksData[folderName];

    final TextEditingController nameController = TextEditingController(
      text: track["name"] ?? folderName,
    );
    final TextEditingController authorController = TextEditingController(
      text: track["author"],
    );
    final TextEditingController durationController = TextEditingController(
      text: track["duration"],
    );
    final TextEditingController coverController = TextEditingController(
      text: track["cover"],
    );
    final TextEditingController trackCountController = TextEditingController(
      text: track["trackCount"]?.toString() ?? "0",
    );

    // 🔹 Copia os arquivos para edição
    List<Map<String, dynamic>> files = List<Map<String, dynamic>>.from(
      track["files"] ?? [],
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text("Editar Multitrack"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: "Nome"),
                  ),
                  TextField(
                    controller: authorController,
                    decoration: InputDecoration(labelText: "Autor"),
                  ),
                  TextField(
                    controller: durationController,
                    decoration: InputDecoration(labelText: "Duração"),
                  ),
                  TextField(
                    controller: coverController,
                    decoration: InputDecoration(labelText: "URL da Capa"),
                  ),
                  TextField(
                    controller: trackCountController,
                    decoration: InputDecoration(labelText: "Número de faixas"),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Arquivos",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...files.asMap().entries.map((entry) {
                    int index = entry.key;
                    Map<String, dynamic> file = entry.value;

                    final nameFileController = TextEditingController(
                      text: file["name"],
                    );
                    final linkFileController = TextEditingController(
                      text: file["link"],
                    );

                    return Column(
                      children: [
                        TextField(
                          controller: nameFileController,
                          decoration: InputDecoration(
                            labelText: "Nome do arquivo ${index + 1}",
                          ),
                          onChanged: (val) => file["name"] = val,
                        ),
                        TextField(
                          controller: linkFileController,
                          decoration: InputDecoration(
                            labelText: "Link do arquivo ${index + 1}",
                          ),
                          onChanged: (val) => file["link"] = val,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                files.removeAt(index);
                              });
                            },
                          ),
                        ),
                        Divider(),
                      ],
                    );
                  }).toList(),
                  TextButton.icon(
                    onPressed: () {
                      setDialogState(() {
                        files.add({"name": "", "link": ""});
                      });
                    },
                    icon: Icon(Icons.add),
                    label: Text("Adicionar arquivo"),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancelar"),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final updatedData = {
                      "name": nameController.text,
                      "author": authorController.text,
                      "duration": durationController.text,
                      "cover": coverController.text,
                      "trackCount":
                          int.tryParse(trackCountController.text) ??
                          files.length,
                      "files": files,
                    };

                    // 🔹 Atualiza no Firestore
                    await FirebaseFirestore.instance
                        .collection("multitracks")
                        .doc(folderName)
                        .update(updatedData);

                    // 🔹 Atualiza localmente para refletir na tela
                    setState(() {
                      multitracksData[folderName] = updatedData;
                    });

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Multitrack atualizada!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Erro ao atualizar: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text("Salvar"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Directory> get _internalAudioDir async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/savedpresets');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  Future<void> loadPreset(int index, BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presets = prefs.getStringList(_presetsKey) ?? [];

      if (index < 0 || index >= presets.length) return;

      final presetJson = presets[index];
      final preset = jsonDecode(presetJson) as Map<String, dynamic>;

      final files = List<String>.from(preset['files'] ?? []);

      setState(() {
        selectedFiles = files.map((path) => XFile(path)).toList();
        panValues = List<double>.from(preset['panValues'] ?? []);
        volumeValues = List<double>.from(preset['volumeValues'] ?? []);
        currentPitchValues = List<double>.from(preset['pitchValues'] ?? []);
        isMutedList = List<bool>.from(preset['isMutedList'] ?? []);
        _selectedPresetIndex = index;
        _multitrackName = preset['name'] ?? 'Unnamed Preset';
        globalPitch = (preset['globalPitch'] as double?) ?? 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preset "${preset['name']}" carregado!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Erro ao carregar preset: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar preset'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleFolderTap(String folderName) async {
    final existingIndex = savedPresets.indexWhere(
      (preset) => preset['name'] == folderName,
    );

    final isDownloaded = _alreadyDownloadedFolders[folderName] ?? false;

    if (isDownloaded && existingIndex != -1) {
      await loadPreset(existingIndex, context);
      return;
    }

    if (!isDownloaded) {
      final files = multitracksData[folderName]["files"] as List;
      await downloadFilesForFolder(
        folderName,
        List<Map<String, dynamic>>.from(files),
      );
      // A pergunta sobre criar preset agora está dentro de downloadFilesForFolder
      return;
    }

    // Se já está baixado mas não tem preset, pergunte se quer criar
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Criar Preset"),
        content: Text(
          "Deseja criar um novo preset para a pasta '$folderName'?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Confirmar"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final presetIndex = await createPresetFromFolder(folderName);
    if (presetIndex == null || !mounted) return;

    // Resto do código para carregar os arquivos...
    Directory appDir = await getApplicationDocumentsDirectory();
    Directory folderDir = Directory('${appDir.path}/downloaded/$folderName');

    List<FileSystemEntity> allFiles = folderDir.listSync();
    List<XFile> audioFiles = allFiles
        .whereType<File>()
        .where(
          (file) => [
            'mp3',
            'wav',
            'm4a',
            'aac',
          ].contains(file.path.split('.').last.toLowerCase()),
        )
        .map((file) => XFile(file.path))
        .toList();

    if (audioFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não há arquivos de áudio nesta pasta')),
      );
      return;
    }

    setState(() {
      selectedFiles = audioFiles;
      isMutedList = List.generate(audioFiles.length, (_) => false);
      panValues = List.generate(audioFiles.length, (_) => 0.0);
      volumeValues = List.generate(audioFiles.length, (_) => 0.7);
      currentPitchValues = List.generate(audioFiles.length, (_) => 0.0);
      globalPitch = 0.0;
      currentPosition = Duration.zero;
      isPlaying = false;
      _selectedPresetIndex = presetIndex;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        content: Text(
          '${audioFiles.length} arquivo(s) adicionad${audioFiles.length > 1 ? 'os' : 'o'}',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String? _overlayFolder;

  void _showOverlay(String folderName) {
    setState(() {
      _overlayFolder = folderName;
    });
  }

  void _closeOverlay() {
    setState(() {
      _overlayFolder = null;
    });
  }

  Map<String, double> _downloadProgress = {};
  String cleanedOverlayFolder(String folderName) {
    if (folderName == null || folderName.isEmpty) return "";

    // 1. Remove tudo até o primeiro "_"
    int firstUnderscore = folderName.indexOf('_');
    String cleanedName = firstUnderscore != -1
        ? folderName.substring(firstUnderscore + 1)
        : folderName;

    // 2. Substitui underscores restantes por espaço
    cleanedName = cleanedName.replaceAll('_', ' ');

    return cleanedName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddCollectionPage2()),
          );
        },
        backgroundColor: Colors.blueAccent,
        child: Icon(Icons.add, color: Colors.white),
        tooltip: "Adicionar nova coleção",
      ),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false, // remove o botão padrão
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_downloadingFolders[_overlayFolder] ?? false) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Download em andamento, aguarde..."),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
            } else {
              Navigator.pop(context, true);
            }
          },
        ),
        title: Text(
          'Catálogo de MultiTracks',
          style: TextStyle(color: Colors.white),
        ),
      ),

      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: multitracksData.isEmpty
                ? Center(child: CircularProgressIndicator(color: Colors.white))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Buscar track...",
                          hintStyle: TextStyle(color: Colors.white54),
                          prefixIcon: Icon(Icons.search, color: Colors.white),
                          filled: true,
                          fillColor: Colors.grey[900],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (query) {
                          setState(() {
                            if (query.isEmpty) {
                              multitracksData = Map.from(
                                originalMultitracksData,
                              );
                            } else {
                              multitracksData =
                                  originalMultitracksData.map((key, value) {
                                    if (key.toLowerCase().contains(
                                          query.toLowerCase(),
                                        ) ||
                                        (value["author"] ?? "")
                                            .toLowerCase()
                                            .contains(query.toLowerCase())) {
                                      return MapEntry(key, value);
                                    }
                                    return MapEntry(key, null);
                                  }).cast<String, dynamic>()..removeWhere(
                                    (key, value) => value == null,
                                  );
                            }
                          });
                        },
                      ),
                      SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          children: [
                            _buildSection(
                              title: "Todas as Multitracks",
                              items: multitracksData.keys.toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (_overlayFolder != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  if (_downloadingFolders[_overlayFolder] ?? false) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Download em andamento, aguarde..."),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  } else {
                    _closeOverlay();
                  }
                },
                child: Container(
                  color: Colors.black.withOpacity(0.8),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // não fecha se clicar no card
                      child: Stack(
                        children: [
                          // 🔹 Card com borda
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white24,
                                width: 2,
                              ),
                            ),
                            padding: EdgeInsets.all(16),
                            child: AnimatedScale(
                              scale: 1.0,
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(
                                      multitracksData[_overlayFolder]?["cover"] ??
                                          'https://via.placeholder.com/200',
                                      height: 200,
                                      width: 200,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (_downloadingFolders[_overlayFolder] ??
                                      false)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Column(
                                        children: [
                                          // Container de fundo (borda e fundo)
                                          Container(
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: Colors.purple[900]!
                                                  .withOpacity(
                                                    0.3,
                                                  ), // fundo roxo escuro translúcido
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Stack(
                                              children: [
                                                // Barra de progresso animada com gradiente
                                                AnimatedContainer(
                                                  duration: Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  width:
                                                      ((_downloadProgress[_overlayFolder] ??
                                                                  0.0) *
                                                              MediaQuery.of(
                                                                context,
                                                              ).size.width *
                                                              0.6) // largura proporcional
                                                          .clamp(
                                                            0.0,
                                                            MediaQuery.of(
                                                                  context,
                                                                ).size.width *
                                                                0.6,
                                                          ),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.purpleAccent,
                                                        Colors.purple[800]!,
                                                      ],
                                                      begin:
                                                          Alignment.centerLeft,
                                                      end: Alignment
                                                          .centerRight, // vai da esquerda para a direita
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            "${((_downloadProgress[_overlayFolder] ?? 0.0) * 100).toStringAsFixed(0)}%",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  SizedBox(height: 16),

                                  // No seu widget:
                                  Text(
                                    cleanedOverlayFolder(_overlayFolder ?? ""),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  SizedBox(height: 8),
                                  Text(
                                    multitracksData[_overlayFolder]?["author"] ??
                                        "Autor desconhecido",
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (!(_alreadyDownloadedFolders[_overlayFolder] ??
                                              false) &&
                                          !(_downloadingFolders[_overlayFolder] ??
                                              false)) // 👈 esconde se estiver baixando
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blueAccent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                          ),
                                          onPressed: () async {
                                            setState(() {
                                              _downloadingFolders[_overlayFolder!] =
                                                  true;
                                            });

                                            final files =
                                                multitracksData[_overlayFolder]?["files"]
                                                    as List;
                                            await downloadFilesForFolder(
                                              _overlayFolder!,
                                              List<Map<String, dynamic>>.from(
                                                files,
                                              ),
                                            );

                                            setState(() {
                                              _alreadyDownloadedFolders[_overlayFolder!] =
                                                  true;
                                              _downloadingFolders[_overlayFolder!] =
                                                  false;
                                            });

                                            _closeOverlay();
                                          },
                                          icon: Icon(
                                            Icons.download,
                                            color: Colors.white,
                                          ),
                                          label: Text(
                                            "Baixar",
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 🔹 Botão de fechar
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 26,
                                ),
                                onPressed: () {
                                  if (_downloadingFolders[_overlayFolder] ??
                                      false) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Download em andamento, aguarde...",
                                        ),
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  } else {
                                    _closeOverlay();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<String> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            "$title (${items.length})", // 🔹 número de tracks visíveis
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(), // usa o scroll do pai
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 24,
            mainAxisSpacing: 8,
            childAspectRatio: 3 / 4,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final folderName = items[index];
            final coverUrl =
                multitracksData[folderName]?["cover"] ??
                'https://via.placeholder.com/150';
            final author =
                multitracksData[folderName]?["author"] ?? "Desconhecido";
            final duration =
                multitracksData[folderName]?["duration"] ?? "00:00";
            final isDownloaded = _alreadyDownloadedFolders[folderName] ?? false;
            // separa pelo underscore e pega tudo depois do primeiro _
            // Remove prefixo numérico seguido de underscore
            // 1. Remove tudo até o primeiro "_"
            int firstUnderscore = folderName.indexOf('_');
            String cleanedName = firstUnderscore != -1
                ? folderName.substring(firstUnderscore + 1)
                : folderName;

            // 2. Substitui underscores restantes por espaço
            cleanedName = cleanedName.replaceAll('_', ' ');

            print(cleanedName);

            bool isPressed = false;

            return StatefulBuilder(
              builder: (context, setInnerState) {
                return GestureDetector(
                  onLongPress: () {
                    _showEditDialog(folderName);
                  },
                  onTapDown: (_) {
                    setInnerState(() => isPressed = true);
                  },
                  onTapUp: (_) async {
                    setInnerState(() => isPressed = false);
                    _showOverlay(folderName);
                  },
                  onTapCancel: () {
                    setInnerState(() => isPressed = false);
                  },
                  child: AnimatedScale(
                    scale: isPressed ? 0.95 : 1.0,
                    duration: Duration(milliseconds: 150),
                    curve: Curves.easeInOut,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey[900],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                    child: Image.network(
                                      coverUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color: Colors.grey[800],
                                                child: Icon(
                                                  Icons.music_note,
                                                  color: Colors.white,
                                                  size: 40,
                                                ),
                                              ),
                                    ),
                                  ),
                                ),
                                if (_downloadingFolders[folderName] == true)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(12),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.blueAccent,
                                                ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            _statusByFolder[folderName] ??
                                                'Baixando...',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (isDownloaded)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Colors.greenAccent,
                                      size: 22,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cleanedName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                Text(
                                  author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  duration,
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// AudioMeter.dart
// AudioMeterIndicator.dart
