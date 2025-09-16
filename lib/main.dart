import 'dart:async';
import 'dart:convert';

import 'package:audio_pad/AudioMeter.dart';
import 'package:audio_pad/AudioWaveForm.dart';
import 'package:audio_pad/ImageSldierThumb.dart';
import 'package:audio_pad/SplashScreen.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:just_waveform/just_waveform.dart';
//import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('com.example.audio_pad/audio');
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(), // Mostra o SplashScreen primeiro
    ),
  );
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Adicione no início da classe
  final _presetsKey = 'audio_pad_presets';
  List<Map<String, dynamic>> savedPresets = [];
  int? _selectedPresetIndex;

  Future<Directory> get _internalAudioDir async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/audio_presets');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  Future<String> _copyFileToInternal(XFile file) async {
    final audioDir = await _internalAudioDir;
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final newPath = '${audioDir.path}/$uniqueName';
    await File(file.path).copy(newPath);
    return newPath;
  }

  Future<void> _cleanupUnusedAudioFiles(List<String> usedPaths) async {
    final audioDir = await _internalAudioDir;
    final allFiles = await audioDir.list().toList();

    for (final file in allFiles) {
      if (file is File && !usedPaths.contains(file.path)) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint('Erro ao deletar arquivo ${file.path}: $e');
        }
      }
    }
  }

  Future<int?> saveCurrentPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList(_presetsKey) ?? [];

    try {
      // === 1) Atualizar preset existente ===
      if (_selectedPresetIndex != null &&
          _selectedPresetIndex! < presets.length) {
        final existingJson = presets[_selectedPresetIndex!];
        final existingPreset = jsonDecode(existingJson) as Map<String, dynamic>;
        final existingFiles = List<String>.from(existingPreset['files'] ?? []);

        // ADICIONE ESTA LINHA PARA GARANTIR QUE O PRESET CONTINUA SELECIONADO
        setState(() {
          _isPresetUnsaved = false;
        });

        final List<String> newInternalPaths = [];

        // Copia apenas arquivos novos
        for (final file in selectedFiles) {
          final baseName = p.basename(file.path);
          final alreadyExists = existingFiles.any(
            (f) => p.basename(f) == baseName,
          );
          if (alreadyExists) continue;

          try {
            final internalPath = await _copyFileToInternal(file);
            newInternalPaths.add(internalPath);
          } catch (e, st) {
            debugPrint('Erro ao copiar arquivo: $e\n$st');
          }
        }

        // Combina arquivos antigos + novos
        final allFiles = [...existingFiles, ...newInternalPaths];

        // Ajusta selectedIcons
        List<String> icons;
        if (existingPreset['selectedIcons'] != null &&
            (existingPreset['selectedIcons'] as List).length ==
                allFiles.length) {
          icons = List<String>.from(existingPreset['selectedIcons']);
        } else {
          icons = List.generate(allFiles.length, (i) => 'guitar.png');
        }

        final updatedPreset = {
          'id': existingPreset['id'],
          'name': existingPreset['name'],
          'files': allFiles,
          'panValues': panValues,
          'volumeValues': volumeValues,
          'isMutedList': isMutedList,
          'selectedIcons': icons,
          'timestamp': DateTime.now().toIso8601String(),
        };

        presets[_selectedPresetIndex!] = jsonEncode(updatedPreset);
        await prefs.setStringList(_presetsKey, presets);
        await _loadSavedPresets();

        // **Atualiza selectedFiles para refletir apenas os arquivos internos**
        selectedFiles = allFiles.map((path) => XFile(path)).toList();

        final newIndex = savedPresets.indexWhere(
          (p) => p['id'] == updatedPreset['id'],
        );
        setState(() {
          _selectedPresetIndex = newIndex >= 0
              ? newIndex
              : _selectedPresetIndex;
          _isPresetUnsaved = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preset atualizado com sucesso!')),
          );
        }

        return _selectedPresetIndex;
      }

      // === 2) Criar novo preset ===
      if (selectedFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum arquivo para salvar como preset'),
            ),
          );
        }
        return null;
      }

      final nameController = TextEditingController(text: _multitrackName);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nome do Preset'),
          content: TextField(controller: nameController, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  nameController.text.isNotEmpty
                      ? nameController.text
                      : 'Novo Preset',
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      );

      if (name == null) return null;

      final List<String> internalPaths = [];
      final Set<String> addedBaseNames = {};

      for (final file in selectedFiles) {
        final baseName = p.basename(file.path);
        if (addedBaseNames.contains(baseName)) continue;

        try {
          final internalPath = await _copyFileToInternal(file);
          internalPaths.add(internalPath);
          addedBaseNames.add(baseName);
        } catch (e, st) {
          debugPrint('Erro ao copiar arquivo ao criar preset: $e\n$st');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao salvar arquivo ${file.path}: $e'),
              ),
            );
          }
          return null;
        }
      }

      final newPreset = {
        'id': _generateUniqueId(),
        'name': name,
        'files': internalPaths,
        'panValues': panValues,
        'volumeValues': volumeValues,
        'isMutedList': isMutedList,
        'selectedIcons': List.generate(
          internalPaths.length,
          (i) => 'guitar.png',
        ),
        'timestamp': DateTime.now().toIso8601String(),
      };

      presets.add(jsonEncode(newPreset));
      await prefs.setStringList(_presetsKey, presets);
      await _loadSavedPresets();

      // Atualiza selectedFiles para refletir os arquivos do novo preset

      // GARANTIR QUE O ESTADO É ATUALIZADO CORRETAMENTE
      // GARANTIR QUE O ESTADO É ATUALIZADO CORRETAMENTE
      final newIndex = savedPresets.indexWhere(
        (p) => p['id'] == newPreset['id'],
      );
      setState(() {
        _selectedPresetIndex = newIndex >= 0
            ? newIndex
            : savedPresets.length - 1;
        _isPresetUnsaved = false;
        _multitrackName = name; // Atualiza o nome exibido
      });

      return _selectedPresetIndex;
    } catch (e, st) {
      debugPrint('Erro ao salvar preset: $e\n$st');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar preset: $e')));
      return null;
    }
  }

  Widget _buildBottomFloatingControls() {
    if (selectedFiles.isEmpty) {
      return SizedBox.shrink(); // Não mostra controles se não tiver arquivos
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // PLAY / PAUSE
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: isPlaying ? pauseAll : playSelected,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 24),
              label: Text(
                isPlaying ? 'PAUSE' : 'PLAY',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // STOP
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(isPlaying ? 0.3 : 0),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: isPlaying ? stopAll : null,
              icon: const Icon(Icons.stop, size: 24),
              label: const Text(
                'STOP',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isPlaying
                    ? Colors.redAccent
                    : Colors.grey[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                disabledBackgroundColor: Colors.grey[800],
                disabledForegroundColor: Colors.grey[500],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // SAVE
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await saveCurrentPreset();
                if (result != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Preset salvo com sucesso!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  // Não navegue para lugar nenhum - mantenha na mesma tela
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao salvar preset'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: Icon(Icons.save),
              label: Text('SALVAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllPresets() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: const Text(
          'Deseja realmente excluir TODOS os presets? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Excluir Tudo',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_presetsKey);

      // Limpa também os arquivos de áudio associados
      final audioDir = await _internalAudioDir;
      if (await audioDir.exists()) {
        await audioDir.delete(recursive: true);
      }

      if (mounted) {
        setState(() {
          savedPresets = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos os presets foram removidos'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadSavedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> presets = prefs.getStringList(_presetsKey) ?? [];

    // Se não houver presets salvos, gerar 25 aleatórios
    if (presets.isEmpty) {
      final randomPresets = _generateRandomPresets(0);
      presets = randomPresets.map((preset) => jsonEncode(preset)).toList();
      await prefs.setStringList(_presetsKey, presets);
    }

    setState(() {
      savedPresets = presets
          .map((json) {
            try {
              final decoded = jsonDecode(json) as Map<String, dynamic>;

              // Verificação de integridade do preset
              if (decoded['files'] == null || decoded['name'] == null) {
                print('Preset inválido encontrado: $decoded');
                return null;
              }

              // Adiciona ID se não existir
              if (decoded['id'] == null) {
                decoded['id'] = _generateUniqueId();
              }

              // Retorna apenas metadados, sem os arquivos
              return {
                'id': decoded['id'],
                'name': decoded['name'],
                'fileCount': (decoded['files'] as List).length,
                'timestamp':
                    decoded['timestamp'] ?? DateTime.now().toIso8601String(),
              };
            } catch (e) {
              print('Erro ao decodificar preset: $e\nJSON: $json');
              return null;
            }
          })
          .where((preset) => preset != null)
          .toList()
          .cast<Map<String, dynamic>>();
    });
  }

  // Função para gerar presets aleatórios
  List<Map<String, dynamic>> _generateRandomPresets(int count) {
    final random = Random();
    final List<Map<String, dynamic>> presets = [];

    // Listas para dados aleatórios
    final names = ['Rock Classics'];

    final instruments = ['Guitar'];

    final genres = ['Rock'];

    for (int i = 0; i < count; i++) {
      final fileCount = random.nextInt(1) + 1; // 1-5 arquivos por preset
      final files = List.generate(fileCount, (index) => 'file_${i}_$index.mp3');

      presets.add({
        'id': 'preset_${DateTime.now().millisecondsSinceEpoch}_$i',
        'name': '${names[random.nextInt(names.length)]} ${i + 1}',
        'files': files,
        'instruments': [
          instruments[random.nextInt(instruments.length)],
          instruments[random.nextInt(instruments.length)],
        ],
        'genre': genres[random.nextInt(genres.length)],
        'bpm': 80 + random.nextInt(100), // 80-180 BPM
        'key': ['C', 'D', 'E', 'F', 'G', 'A', 'B'][random.nextInt(7)],
        'timestamp': DateTime.now()
            .subtract(Duration(days: random.nextInt(30)))
            .toIso8601String(),
      });
    }

    return presets;
  }

  Future<Map<String, dynamic>?> _loadFullPreset(String presetId) async {
    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList(_presetsKey) ?? [];

    for (final json in presets) {
      try {
        final preset = jsonDecode(json) as Map<String, dynamic>;
        if (preset['id'] == presetId) {
          return {
            'id': preset['id'],
            'name': preset['name'],
            'files': List<String>.from(preset['files']),
            'panValues': List<double>.from(preset['panValues'] ?? []),
            'volumeValues': List<double>.from(preset['volumeValues'] ?? []),
            'isMutedList': List<bool>.from(preset['isMutedList'] ?? []),
            'selectedIcons': List<String>.from(preset['selectedIcons'] ?? []),
            'timestamp': preset['timestamp'],
          };
        }
      } catch (e) {
        debugPrint('Erro ao decodificar preset: $e');
      }
    }
    return null;
  }

  Future<void> _loadPlaylistPresets() async {
    _loadedPresets = [];

    for (final index in _selectedPresetsIndices) {
      if (index >= 0 && index < savedPresets.length) {
        final presetId = savedPresets[index]['id'];
        final fullPreset = await _loadFullPreset(presetId);
        if (fullPreset != null) {
          _loadedPresets.add(fullPreset);
        }
      }
    }
  }

  Future<int?> createBlankPreset() async {
    final nameController = TextEditingController(text: "Novo Preset");

    final name = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: StatefulBuilder(
          builder: (context, setState) => Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Preset: ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        nameController.text,
                        style: const TextStyle(
                          color: Colors.deepPurpleAccent,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Digite o nome',
                    hintStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.grey[850],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(color: Colors.grey[400], fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () {
                        final text = nameController.text.trim();
                        Navigator.pop(
                          context,
                          text.isNotEmpty ? text : 'Novo Preset',
                        );
                      },
                      child: const Text(
                        'Criar',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // SE O USUÁRIO CANCELOU, RETORNA NULL E NÃO FAZ NADA
    if (name == null) return null;

    final preset = {
      'id': _generateUniqueId(),
      'name': name,
      'files': [],
      'panValues': [],
      'volumeValues': [],
      'isMutedList': [],
      'selectedIcons': [],
      'timestamp': DateTime.now().toIso8601String(),
    };

    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList(_presetsKey) ?? [];
    presets.add(jsonEncode(preset));
    await prefs.setStringList(_presetsKey, presets);
    await _loadSavedPresets();

    // SÓ DEFINE O PRESET SELECIONADO SE O USUÁRIO REALMENTE CRIOU
    setState(() {
      _isPresetUnsaved = true;
      _selectedPresetIndex = savedPresets.length - 1; // Seleciona o novo preset
      _multitrackName = name; // ATUALIZA O NOME EXIBIDO NO TOPO
    });

    return savedPresets.length - 1;
  }

  // Adicione este método para salvar automaticamente

  Future<void> loadPresetWithDelay(int index, BuildContext oldContext) async {
    // Captura o contexto da tela principal antes de fechar o popup
    final rootContext = Navigator.of(oldContext, rootNavigator: true).context;

    // Fecha o popup atual
    Navigator.pop(oldContext);

    // Aguarda 100ms para garantir que o pop-up foi fechado
    await Future.delayed(Duration(milliseconds: 100));

    // Mostra o loading dialog usando o root context
    showDialog(
      context: rootContext,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );

    // Aguarda 2 segundos simulando carregamento
    await Future.delayed(Duration(seconds: 2));

    // Fecha o dialog de loading
    Navigator.pop(rootContext);

    // Carrega o preset com o root context ainda ativo
    await loadPreset(index, rootContext);
  }

  Future<void> loadPreset(int index, BuildContext context) async {
    if (isPlaying && _selectedPresetIndex != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Atenção'),
          content: Text('Isso irá parar a reprodução atual. Deseja continuar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Continuar'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }
    if (index < 0 || index >= savedPresets.length) return;

    try {
      // Carrega o preset completo
      final presetId = savedPresets[index]['id'];
      final fullPreset = await _loadFullPreset(presetId);

      if (fullPreset == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar o preset')));
        return;
      }

      // Parar qualquer reprodução atual
      await platform.invokeMethod('stopSounds');
      _timer?.cancel();

      // Verificar arquivos
      final List<XFile> validFiles = [];
      for (final path in fullPreset['files'] ?? []) {
        if (await File(path).exists()) {
          validFiles.add(XFile(path));
        } else {
          debugPrint('Arquivo não encontrado: $path');
        }
      }

      // Inicializar listas com valores padrão se não existirem no preset
      final panValuesFromPreset = List<double>.from(
        fullPreset['panValues'] ?? List.filled(validFiles.length, 0.0),
      );
      final volumeValuesFromPreset = List<double>.from(
        fullPreset['volumeValues'] ?? List.filled(validFiles.length, 0.7),
      );
      final isMutedListFromPreset = List<bool>.from(
        fullPreset['isMutedList'] ?? List.filled(validFiles.length, false),
      );
      final selectedIconsFromPreset = List<String>.from(
        fullPreset['selectedIcons'] ??
            List.filled(validFiles.length, 'guitar.png'),
      );

      // Atualizar estado
      // Atualizar estado
      setState(() {
        _multitrackName = fullPreset['name'];
        selectedFiles = validFiles;
        panValues = panValuesFromPreset;
        volumeValues = volumeValuesFromPreset;
        isMutedList = isMutedListFromPreset;
        selectedIcons = selectedIconsFromPreset;
        currentPosition = Duration.zero;
        isPlaying = false;
        _selectedPresetIndex = index;
      });

      // Atualiza a duração máxima após carregar o preset
      await _updateMaxDuration();

      // Configurar players nativos
      for (int i = 0; i < validFiles.length; i++) {
        await setPlayerPan(i, panValuesFromPreset[i]);
        await setPlayerVolume(i, volumeValuesFromPreset[i]);
        if (isMutedListFromPreset[i]) {
          await platform.invokeMethod('mutePlayer', {'index': i, 'mute': true});
        }
      }

      if (validFiles.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Preset carregado com sucesso!',
              style: TextStyle(color: Colors.white), // texto branco
            ),
            backgroundColor: Colors.deepPurpleAccent, // fundo roxo escuro
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior
                .floating, // opcional: para um visual mais moderno
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar preset: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar preset: ${e.toString()}')),
      );
    }
  }

  void showSafeSnackBar(String message) {
    // Use the root navigator context
    final context = Navigator.of(this.context, rootNavigator: true).context;

    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> deletePreset(int index, BuildContext context) async {
    if (index < 0 || index >= savedPresets.length) return;

    final presetId = savedPresets[index]['id']; // Obtém o ID antes de deletar

    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList(_presetsKey) ?? [];

    // Encontra o índice correto pelo ID (para garantir que estamos deletando o certo)
    final presetIndex = presets.indexWhere((p) {
      try {
        final decoded = jsonDecode(p) as Map<String, dynamic>;
        return decoded['id'] == presetId;
      } catch (e) {
        return false;
      }
    });

    if (presetIndex >= 0) {
      presets.removeAt(presetIndex);
      await prefs.setStringList(_presetsKey, presets);
      await _loadSavedPresets();

      // Use o scaffoldMessengerKey global em vez do contexto local
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Preset deletado com sucesso')),
      );
    }
  }

  void _showPresetsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header estilo Spotify
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'MINHAS PLAYLISTS',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (savedPresets.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Limpar Tudo',
                          style: TextStyle(color: Colors.red),
                        ),
                        onPressed: _deleteAllPresets,
                      ),
                    ),
                  // Lista de presets
                  Expanded(
                    child: savedPresets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.music_note,
                                  size: 48,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Nenhum preset salvo',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: savedPresets.length,
                            itemBuilder: (context, index) {
                              final preset = savedPresets[index];
                              final name = preset['name'] ?? 'Sem nome';
                              final fileCount = preset['fileCount'] ?? 0;
                              final timestamp = preset['timestamp'] != null
                                  ? DateTime.parse(preset['timestamp'])
                                  : DateTime.now();

                              // Cores aleatórias para as capas (estilo Spotify)
                              final colors = [
                                Colors.blue.shade800,
                                Colors.purple.shade800,
                                Colors.red.shade800,
                                Colors.green.shade800,
                                Colors.orange.shade800,
                              ];
                              final bgColor = colors[index % colors.length];

                              return InkWell(
                                onTap: () async {
                                  Navigator.pop(context);
                                  await loadPreset(index, this.context);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: [
                                      // Capa do álbum
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: bgColor,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.music_note,
                                            color: Colors.white.withOpacity(
                                              0.8,
                                            ),
                                            size: 30,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      // Informações da música
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '$fileCount ${fileCount == 1 ? 'faixa' : 'faixas'}',
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              timestamp.toString(),
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Botões de ação
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.play_arrow,
                                              color: Colors.greenAccent,
                                            ),
                                            onPressed: () async {
                                              Navigator.pop(context);
                                              await loadPreset(
                                                index,
                                                this.context,
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete,
                                              color: Colors.grey[500],
                                            ),
                                            onPressed: () =>
                                                _confirmDeletePreset(
                                                  index,
                                                  context,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Botão de salvar
                  Container(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    child: ElevatedButton(
                      onPressed: () async {
                        final savedIndex = await saveCurrentPreset();
                        if (savedIndex != null && mounted) {
                          Navigator.pop(context);
                          await loadPreset(savedIndex, context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        'SALVAR PRESET ATUAL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _generateUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<void> _confirmDeletePreset(int index, BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar exclusão'),
        content: Text('Deseja realmente excluir este preset?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await deletePreset(
        index,
        this.context,
      ); // Use this.context em vez do contexto do diálogo
    }
  }

  late final Timer _timera;
  String _multitrackName = "MultiX"; // Default name

  Future<void> _init() async {
    try {
      final audioBytes = await rootBundle.load('assets/eele.mp3');
      final tempDir = await getTemporaryDirectory();
      final audioFile = File(p.join(tempDir.path, 'a.mp3'));
      await audioFile.writeAsBytes(audioBytes.buffer.asUint8List());
      final waveFile = File(p.join(tempDir.path, 'a.wave'));

      JustWaveform.extract(
        audioInFile: audioFile,
        waveOutFile: waveFile,
      ).listen(progressStream.add, onError: progressStream.addError);
    } catch (e) {
      progressStream.addError(e);
      debugPrint('Erro ao carregar o áudio: $e');
    }
  }

  final progressStream = BehaviorSubject<WaveformProgress>();
  List<bool> isMutedList = [];
  List<XFile> selectedFiles = [];
  Duration currentPosition = Duration.zero;
  Duration maxDuration = Duration(seconds: 30 * 8);
  bool isPlaying = false;
  Timer? _timer;
  bool userIsSeeking = false;
  List<double> panValues = [];
  List<double> volumeValues = [];

  void _updateDateTime() {
    setState(() {});
  }

  void _showIconSelectionDialog(int trackIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          height: 600,
          child: Column(
            children: [
              Text(
                'Selecione um ícone',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: iconOptions.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedIcons[trackIndex] = iconOptions[index];
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                selectedIcons[trackIndex] == iconOptions[index]
                                ? Colors.deepPurpleAccent
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/icons/${iconOptions[index]}',
                            width: 40,
                            height: 40,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  Future<void> _updatePresetName(String newName) async {
    if (_selectedPresetIndex == null ||
        _selectedPresetIndex! < 0 ||
        _selectedPresetIndex! >= savedPresets.length) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList(_presetsKey) ?? [];

    try {
      final preset =
          jsonDecode(presets[_selectedPresetIndex!]) as Map<String, dynamic>;
      preset['name'] = newName;
      preset['timestamp'] = DateTime.now().toIso8601String();
      // O ID permanece o mesmo
      presets[_selectedPresetIndex!] = jsonEncode(preset);

      await prefs.setStringList(_presetsKey, presets);
      await _loadSavedPresets();
    } catch (e) {
      debugPrint('Erro ao atualizar nome do preset: $e');
    }
  }

  Future<void> resetToInitialState() async {
    // Parar qualquer reprodução
    await platform.invokeMethod('stopSounds');
    _timer?.cancel();

    // Limpar estado
    setState(() {
      selectedFiles = [];
      isMutedList = [];
      panValues = [];
      volumeValues = [];
      selectedIcons = [];
      currentPosition = Duration.zero;
      isPlaying = false;
      _multitrackName = "MultiX";
      _selectedPresetIndex = null;
      _loadedPresets = [];
      _selectedPresetsIndices = [];
      _isPresetUnsaved = false;
    });
  }

  Future<bool> _showNameDialog({String? initialName}) async {
    final nameController = TextEditingController(text: initialName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black, // fundo preto
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Icon(Icons.library_music, color: Colors.deepPurpleAccent),
              SizedBox(width: 8),
              Text('Nome do Multitrack', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: TextField(
            controller: nameController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[850], // fundo cinza escuro para campo
              hintText: 'Digite um nome',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.deepPurpleAccent),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.deepPurpleAccent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close, color: Colors.deepPurpleAccent),
              label: Text(
                'Cancelar',
                style: TextStyle(color: Colors.deepPurpleAccent),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, nameController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(Icons.check, color: Colors.white),
              label: Text('Salvar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty && result != initialName) {
      setState(() {
        _multitrackName = result;
      });
      return true; // Nome foi alterado
    }
    return false; // Nome não foi alterado
  }

  Future<void> pickFiles({bool skipNameDialog = false}) async {
    // Verifica se há um preset selecionado
    if (_selectedPresetIndex == null && !skipNameDialog) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selecione um preset primeiro para adicionar arquivos'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Resto do código permanece igual...
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'audio',
          extensions: ['mp3', 'wav', 'm4a', 'aac'],
          uniformTypeIdentifiers: [
            'public.audio',
            'public.mp3',
            'public.wav',
            'com.apple.m4a-audio',
            'public.aac-audio',
          ],
        ),
      ],
    );

    if (files.isEmpty) return;

    // Mostrar diálogo de nome apenas se:
    // 1. skipNameDialog for false E
    // 2. Não houver preset selecionado (_selectedPresetIndex == null)
    if (!skipNameDialog && _selectedPresetIndex == null) {
      await _showNameDialog();
    }

    setState(() {
      selectedFiles = files;
      isMutedList = List.generate(files.length, (index) => false);
      panValues = List.generate(files.length, (index) => 0.0);
      volumeValues = List.generate(files.length, (index) => 0.7);
      currentPosition = Duration.zero;
      isPlaying = false;
    });

    // Mostrar SnackBar informando quantos arquivos foram adicionados
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating, // deixa flutuante
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16), // distância das bordas da tela
        elevation: 6,
        content: Text(
          '${files.length} arquivo${files.length > 1 ? 's' : ''} adicionad${files.length > 1 ? 'os' : 'o'}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> setPlayerPan(int index, double pan) async {
    print('Setting Pan - index: $index, volume: $pan');
    try {
      await platform.invokeMethod('setPlayerPan', {'index': index, 'pan': pan});
      setState(() {
        panValues[index] = pan;
        _isPresetUnsaved = true; // Marca como não salvo
      });
      // _autoSavePreset(); // Salva automaticamente
    } on PlatformException catch (e) {
      print('Erro ao ajustar pan: ${e.message}');
    }
  }

  // Adicione esta variável
  Duration _maxDuration = Duration.zero;

  // Atualize o método para obter a duração máxima
  Future<void> _updateMaxDuration() async {
    if (selectedFiles.isEmpty) {
      setState(() {
        _maxDuration = Duration.zero;
      });
      return;
    }

    Duration max = Duration.zero;

    for (final file in selectedFiles) {
      try {
        final durationInSeconds =
            await platform.invokeMethod('getAudioDuration', {
                  'filePath': file.path,
                })
                as double;

        final duration = Duration(
          milliseconds: (durationInSeconds * 1000).round(),
        );
        if (duration > max) {
          max = duration;
        }
      } catch (e) {
        print('Erro ao obter duração para ${file.path}: $e');
      }
    }

    setState(() {
      _maxDuration = max;
    });
  }

  Future<void> setPlayerVolume(int index, double volume) async {
    print('Setting volume - index: $index, volume: $volume');
    try {
      await platform.invokeMethod('setPlayerVolume', {
        'index': index,
        'volume': volume,
      });
      setState(() {
        volumeValues[index] = volume;
        isMutedList[index] = volume == 0.0;
        _isPresetUnsaved = true; // Marca como não salvo
      });
      // _autoSavePreset(); // Salva automaticamente
    } on PlatformException catch (e) {
      print('Erro ao ajustar volume: ${e.message}');
    }
  }

  Future<void> toggleMute(int index) async {
    final newMuteState = !isMutedList[index];
    final newVolume = newMuteState ? 0.0 : volumeValues[index];

    try {
      await platform.invokeMethod('mutePlayer', {
        'index': index,
        'mute': newMuteState,
      });

      setState(() {
        isMutedList[index] = newMuteState;
        if (!newMuteState) {
          volumeValues[index] = newVolume;
        }
        _isPresetUnsaved = true; // Marca como não salvo
      });
      // _autoSavePreset(); // Salva automaticamente
    } on PlatformException catch (e) {
      print('Erro ao mutar: ${e.message}');
    }
  }

  // No método addFile():
  Future<void> addFile() async {
    if (_selectedPresetIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um preset primeiro para adicionar arquivos'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Salva a posição atual de referência
    final currentPositionBeforeAdd = currentPosition;
    final wasPlaying = isPlaying;

    // Pausa todos os players apenas se estiver tocando
    if (wasPlaying) {
      await pauseAll();
    }

    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'audio',
          extensions: ['mp3', 'wav', 'm4a', 'aac'],
          uniformTypeIdentifiers: [
            'public.audio',
            'public.mp3',
            'public.wav',
            'com.apple.m4a-audio',
            'public.aac-audio',
          ],
        ),
      ],
    );

    if (file == null) return;

    setState(() {
      selectedFiles.add(file);
      isMutedList.add(false);
      panValues.add(0.0);
      volumeValues.add(0.7);

      if (selectedIcons.length < selectedFiles.length) {
        selectedIcons.add('guitar.png');
      }

      _isPresetUnsaved = true;
    });

    // Atualiza a duração máxima
    await _updateMaxDuration();

    try {
      final newIndex = selectedFiles.length - 1;

      // Cria o novo player na mesma posição dos outros
      await platform.invokeMethod('addPlayer', {
        'filePath': file.path,
        'index': newIndex,
        'pan': 0.0,
        'volume': 0.7,
        'startPosition': currentPositionBeforeAdd.inMilliseconds / 1000.0,
      });

      // Se estava tocando antes, resume todos os players
      if (wasPlaying) {
        for (int i = 0; i <= newIndex; i++) {
          await platform.invokeMethod('startPlayer', {
            'index': i,
            'startPosition': currentPositionBeforeAdd.inMilliseconds / 1000.0,
          });
        }
      }
    } catch (e) {
      print('Erro ao configurar novo player: $e');
    }

    // Pequeno delay para iOS
    await Future.delayed(const Duration(milliseconds: 100));
  }

  void _startProgressTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!userIsSeeking && isPlaying) {
        setState(() {
          currentPosition += const Duration(milliseconds: 100);
          if (currentPosition >= _maxDuration) {
            _timer?.cancel();
            isPlaying = false;
            currentPosition = Duration.zero;
            print('Reprodução concluída');
          }
        });
      }
    });
  }

  Future<void> playSelected({bool startFromBeginning = false}) async {
    if (selectedFiles.isEmpty) {
      print('Nenhum arquivo selecionado para reprodução');
      return;
    }

    try {
      // Atualiza a duração máxima antes de iniciar a reprodução
      await _updateMaxDuration();

      final startPosition = startFromBeginning
          ? 0.0
          : currentPosition.inMilliseconds.toDouble() / 1000.0;

      List<String> filePaths = selectedFiles.map((f) => f.path).toList();

      print(
        '🎶 Iniciando reprodução de ${selectedFiles.length} arquivos a partir de $startPosition segundos...',
      );

      await platform.invokeMethod('playUploadedSounds', {
        'filePaths': filePaths,
        'pans': panValues,
        'volumes': volumeValues,
        'startPosition': startPosition,
      });

      if (startFromBeginning) currentPosition = Duration.zero;

      setState(() {
        isPlaying = true;
      });

      _startProgressTimer();
    } catch (e) {
      print('Erro ao iniciar reprodução: $e');
      setState(() {
        isPlaying = false;
      });
    }
  }

  List<String> iconOptions = [
    'accordion.png',
    'banjo.png',
    'bass_drum.png',
    'bassoon.png',
    'berimbau.png',
    'cello.png',
    'clarinet.png',
    'conga.png',
    'guitar.png',
    'harp.png',
    'pan_flute.png',
    'piano.png',
    'sitar.png',
    'snare_drum.png',
    'tabla.png',
    'trombone.png',
    'trumpet.png',
    'tuba.png',
    'melodica.png',
  ];

  List<String> selectedIcons = [];

  Future<ui.Image> loadImage(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  late ui.Image thumbImage;
  @override
  void initState() {
    super.initState();

    loadImage('assets/thumb.png').then((img) {
      setState(() {
        thumbImage = img;
      });
    });
    _init();
    _updateDateTime();
    _timera = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateDateTime(),
    );

    // Inicializar listas vazias
    selectedFiles = [];
    isMutedList = [];
    panValues = [];
    volumeValues = [];
    selectedIcons = [];

    // Carregar presets
    _loadSavedPresets().then((_) {
      _cleanupOrphanedAudioFiles();
    });

    _pageController = PageController(viewportFraction: 0.7)
      ..addListener(() {
        setState(() {
          _currentPage = _pageController.page!;
        });
      });

    // Verifique se há um preset selecionado ao iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedPresetIndex == null && selectedFiles.isNotEmpty) {
        // Se há arquivos mas nenhum preset selecionado, ofereça para salvar
        _showSavePrompt();
      }
    });
  }

  Future<void> _showSavePrompt() async {
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Preset não salvo'),
        content: Text(
          'Deseja salvar as alterações atuais como um novo preset?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Salvar'),
          ),
        ],
      ),
    );

    if (shouldSave == true) {
      await saveCurrentPreset();
    }
  }

  Future<void> _cleanupOrphanedAudioFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList(_presetsKey) ?? [];

    final allReferencedPaths = <String>{};
    for (final presetJson in presets) {
      try {
        final preset = jsonDecode(presetJson) as Map<String, dynamic>;
        final files = preset['files'] as List<dynamic>;
        allReferencedPaths.addAll(files.cast<String>());
      } catch (e) {
        print('Error parsing preset: $e');
      }
    }

    await _cleanupUnusedAudioFiles(allReferencedPaths.toList());
  }

  Future<void> clearAllFiles() async {
    try {
      await platform.invokeMethod('stopSounds');
      _timer?.cancel();
      setState(() {
        selectedFiles = [];
        isMutedList = [];
        panValues = [];
        volumeValues = [];
        selectedIcons = [];
        currentPosition = Duration.zero;
        isPlaying = false;
        _maxDuration = Duration.zero; // Reset da duração máxima
        _multitrackName = "Untitled Multitrack";
      });
    } on PlatformException catch (e) {
      print('Erro ao limpar arquivos: ${e.message}');
    }
  }

  bool _isPresetUnsaved = false; // Add this line
  Future<void> stopAll() async {
    try {
      await platform.invokeMethod('stopSounds');
      _timer?.cancel();
      setState(() {
        isPlaying = false;
        currentPosition = Duration.zero; // Isso reseta para o início
      });
    } on PlatformException catch (e) {
      print('Erro ao parar sons: ${e.message}');
    }
  }

  late PageController _pageController;
  double _currentPage = 0.0;

  List<int> _selectedPresetsIndices = []; // Índices dos presets na playlist
  // Lista de presets na playlist (apenas IDs e metadados)
  List<Map<String, dynamic>> _loadedPresets =
      []; // Presets carregados na memória

  @override
  void dispose() {
    _pageController.dispose();
    _timera.cancel();
    super.dispose();
  }

  Future<void> seekTo(Duration position) async {
    try {
      // Salva o estado atual de reprodução antes de fazer o seek
      final wasPlaying = isPlaying;

      await platform.invokeMethod('seekToPosition', {
        'seconds': position.inMilliseconds.toDouble() / 1000.0,
      });

      setState(() {
        currentPosition = position;
      });

      // Só reinicia o timer se estava tocando antes do seek
      if (wasPlaying) {
        _startProgressTimer();
      }
    } on PlatformException catch (e) {
      print('Erro ao fazer seek: ${e.message}');
    }
  }

  void _showPresetsBankDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black, // Fundo escuro
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.white24, // Cor da borda superior
                    width: 1.0,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'MultiTracks Salvas',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: savedPresets.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum preset salvo',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            itemCount: savedPresets.length,
                            itemBuilder: (context, index) {
                              final preset = savedPresets[index];
                              final isInPlaylist = _selectedPresetsIndices
                                  .contains(index);

                              return Card(
                                color: Colors.grey[900],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 50,
                                      height: 50,
                                      color: Colors.deepPurple, // Cor da "capa"
                                      child: const Icon(
                                        Icons.music_note,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    preset['name'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  trailing: IconButton(
                                    icon: Icon(
                                      isInPlaylist
                                          ? Icons.check_circle
                                          : Icons.add_circle_outline,
                                      color: isInPlaylist
                                          ? Colors.green
                                          : Colors.white70,
                                      size: 28,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (isInPlaylist) {
                                          _selectedPresetsIndices.remove(index);
                                        } else {
                                          _selectedPresetsIndices.add(index);
                                        }
                                      });
                                    },
                                  ),
                                  onTap: () {
                                    setState(() {
                                      if (isInPlaylist) {
                                        _selectedPresetsIndices.remove(index);
                                      } else {
                                        _selectedPresetsIndices.add(index);
                                      }
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Fechar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _loadPlaylistPresets();
                          Navigator.pop(context);
                          setState(() {});
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Aplicar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> pauseAll() async {
    try {
      await platform.invokeMethod('pauseSounds');
      _timer?.cancel();
      setState(() {
        isPlaying = false;
      });
    } on PlatformException catch (e) {
      print('Erro ao pausar sons: ${e.message}');
    }
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return '$minutes:$seconds';
  }

  Drawer buildPresetDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.black,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Text(
              'Menu de Presets',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: Icon(Icons.add, color: Colors.blue),
            title: Text('Novo Preset', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context); // fecha o drawer
              final index = await createBlankPreset();
              if (index != null && mounted) {
                await loadPreset(index, context);

                // Adiciona o preset na lista de carregados
                _loadedPresets.add(savedPresets[index]);

                // Marca como selecionado
                _selectedPresetIndex = index;
                if (!_selectedPresetsIndices.contains(index)) {
                  _selectedPresetsIndices.add(index);
                }

                setState(() {}); // Atualiza a UI

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Novo preset criado! Adicione arquivos.'),
                    duration: Duration(seconds: 2),
                  ),
                );

                pickFiles(skipNameDialog: true);
              }
            },
          ),
          if (_selectedPresetIndex !=
              null) // Só mostra se há preset selecionado
            if (selectedFiles.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Limpar arquivos',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  clearAllFiles();
                },
              ),
          if (selectedFiles.isNotEmpty)
            ListTile(
              leading: Icon(Icons.edit, color: Colors.indigo),
              title: Text('Renomear', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final nameChanged = await _showNameDialog(
                  initialName: _multitrackName,
                );
                if (nameChanged && _selectedPresetIndex != null) {
                  await _updatePresetName(_multitrackName);
                }
              },
            ),
          ListTile(
            leading: Icon(Icons.library_music, color: Colors.purple),
            title: Text(
              'Banco de Presets',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _showPresetsBankDialog();
            },
          ),
        ],
      ),
    );
  }

  // And in the build() method, replace the floatingActionButton section with:

  bool isSelected = true;

  Future<Object> getRealAudioDuration(String filePath) async {
    try {
      final durationInSeconds =
          await platform.invokeMethod('getAudioDuration', {
                'filePath': filePath,
              })
              as double;

      return Duration(milliseconds: (durationInSeconds * 1000).round());
    } on PlatformException catch (e) {
      print('Erro ao obter duração: ${e.message}');

      // Fallback: usar metadados do arquivo
      final file = File(filePath);
      final metadata = await MetadataRetriever.fromFile(file);
      return metadata.trackDuration ?? Duration.zero;
    }
  }

  Future<double> getAudioDuration(String filePath) async {
    try {
      final duration = await platform.invokeMethod(
        'getAudioDuration',
        filePath,
      );
      return duration as double;
    } on PlatformException catch (e) {
      print('Erro ao obter duração: ${e.message}');
      return 0.0;
    }
  }

  // Valor padrão

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF121212),
      primaryColor: Colors.deepPurpleAccent,
      colorScheme: const ColorScheme.dark().copyWith(
        primary: Colors.deepPurpleAccent,
        secondary: Colors.deepPurpleAccent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: const Color.fromARGB(255, 0, 0, 0),
        inactiveTrackColor: const Color.fromARGB(59, 86, 86, 86),
        thumbColor: Colors.deepPurpleAccent,
        overlayColor: Colors.deepPurpleAccent.withOpacity(0.2),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurpleAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: Colors.white54),
      ),
    );

    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        floatingActionButton: _buildBottomFloatingControls(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

        appBar: AppBar(
          actions: [
            // Botão de reset com ícone e texto numa Row
            GestureDetector(
              onTap: () async {
                await resetToInitialState();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    Icon(Icons.refresh, color: Colors.red),
                    SizedBox(width: 8),
                    // Text('', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),

            PopupMenuButton<int>(
              icon: const Icon(Icons.menu, color: Colors.deepPurple, size: 28),
              color: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 10,
              offset: const Offset(0, 40),
              onSelected: (value) async {
                switch (value) {
                  case 6:
                    _showPresetsBankDialog();
                    break;
                  case 7: // ADICIONE ESTA OPÇÃO
                    _showPresetsDialog();
                    break;
                  case 0:
                    final index = await createBlankPreset();
                    if (index != null && mounted) {
                      await loadPreset(index, context);

                      // Adiciona o preset na lista de carregados
                      _loadedPresets.add(savedPresets[index]);

                      // Marca como selecionado
                      _selectedPresetIndex = index;
                      if (!_selectedPresetsIndices.contains(index)) {
                        _selectedPresetsIndices.add(index);
                      }

                      setState(() {}); // Atualiza a UI

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Novo preset criado! Adicione arquivos.',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );

                      pickFiles(skipNameDialog: true);
                    }

                    break;
                  case 1:
                    pickFiles();
                    break;
                  case 2:
                    addFile();
                    break;
                  case 3:
                    _showPresetsDialog();
                    break;
                  case 4:
                    clearAllFiles();
                    break;
                  case 5:
                    final nameChanged = await _showNameDialog(
                      initialName: _multitrackName,
                    );
                    if (nameChanged && _selectedPresetIndex != null) {
                      await _updatePresetName(_multitrackName);
                    }
                    break;
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<int>(
                  value: 0,
                  child: Row(
                    children: const [
                      Icon(Icons.add, color: Colors.blue),
                      SizedBox(width: 10),
                      Text('Novo Preset'),
                    ],
                  ),
                ),

                PopupMenuItem<int>(
                  value: 6,
                  child: Row(
                    children: const [
                      Icon(Icons.library_music, color: Colors.purple),
                      SizedBox(width: 10),
                      Text('Banco de Presets'),
                    ],
                  ),
                ),
                PopupMenuItem<int>(
                  // ADICIONE ESTE ITEM
                  value: 7,
                  child: Row(
                    children: const [
                      Icon(Icons.playlist_play, color: Colors.green),
                      SizedBox(width: 10),
                      Text('Minhas Playlists'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () async {
                  final nameChanged = await _showNameDialog(
                    initialName: _multitrackName,
                  );
                  if (nameChanged && _selectedPresetIndex != null) {
                    await _updatePresetName(_multitrackName);
                  }
                },
                child: Text(
                  _multitrackName,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.deepPurpleAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_isPresetUnsaved)
                Text(
                  '(não salvo)',
                  style: TextStyle(fontSize: 10, color: Colors.orangeAccent),
                ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 0, 0, 0),
          elevation: 8,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 56),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (savedPresets.isNotEmpty && _loadedPresets.isNotEmpty) ...[
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Presets adicionados:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Spacer(),
                            IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                size: 20,
                                color: Colors.white70,
                              ),
                              onPressed: _showPresetsBankDialog,
                              tooltip: 'Adicionar mais presets',
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        SizedBox(
                          height: 60,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _loadedPresets.length,
                            separatorBuilder: (_, __) => SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final preset = _loadedPresets[index];
                              final originalIndex = savedPresets.indexWhere(
                                (p) => p['id'] == preset['id'],
                              );

                              return GestureDetector(
                                onTap: () => loadPreset(originalIndex, context),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedPresetIndex == originalIndex
                                        ? Colors.blueAccent.withOpacity(0.3)
                                        : Colors.grey[800],
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color:
                                          _selectedPresetIndex == originalIndex
                                          ? Colors.blueAccent
                                          : Colors.transparent,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.music_note,
                                            color: Colors.white70,
                                            size: 18,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            preset['name'],
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _selectedPresetsIndices.remove(
                                              originalIndex,
                                            );
                                            _loadedPresets.removeAt(index);
                                          });
                                        },
                                        child: Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                          size: 18,
                                        ),
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
                  ),
                  SizedBox(height: 12),
                  Divider(color: Colors.grey[800], height: 1),
                ],
                if (selectedFiles.isNotEmpty)
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      height: 50.0,
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 40, 40, 40),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(20.0),
                        ),
                      ),
                      padding: const EdgeInsets.all(0.0),
                      width: double.maxFinite,
                      child: StreamBuilder<WaveformProgress>(
                        stream: progressStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error: ${snapshot.error}',
                                style: Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          final progress = snapshot.data?.progress ?? 0.0;
                          final waveform = snapshot.data?.waveform;
                          if (waveform == null) {
                            return Center(
                              child: Text(
                                '${(100 * progress).toInt()}%',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            );
                          }
                          return Container(
                            height: 300.0,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 255, 5, 5),
                              borderRadius: const BorderRadius.all(
                                Radius.circular(20.0),
                              ),
                            ),
                            child: AudioWaveformWidget(
                              waveform: waveform,
                              start: Duration.zero,
                              duration: _maxDuration, // Use _maxDuration aqui
                              currentPosition: currentPosition,
                              onSeek: (duration) {
                                userIsSeeking = true;
                                seekTo(duration).then((_) {
                                  userIsSeeking = false;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: _selectedPresetIndex == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Bem vindo ao MultX',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final index = await createBlankPreset();
                                  if (index != null && mounted) {
                                    // Já está selecionado automaticamente
                                  }
                                },
                                icon: Icon(Icons.add, color: Colors.white),
                                label: Text(
                                  'Criar Novo Preset',
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurpleAccent,
                                ),
                              ),
                            ],
                          ),
                        )
                      : selectedFiles.isEmpty
                      ? Center(
                          // TELA QUANDO O PRESET ESTÁ VAZIO
                          child: GestureDetector(
                            onTap: pickFiles,
                            child: Container(
                              width: MediaQuery.of(context).size.width * 0.8,
                              height: MediaQuery.of(context).size.height * 0.4,
                              padding: EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.deepPurple.withOpacity(0.7),
                                    Colors.deepPurpleAccent.withOpacity(0.9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.deepPurple.withOpacity(0.5),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.deepPurpleAccent.withOpacity(
                                    0.3,
                                  ),
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.music_note,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    'Preset "${_multitrackName}" está vazio',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    'Toque aqui para adicionar seus primeiros arquivos de áudio',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 25),
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: pickFiles,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.deepPurple,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 30,
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'ADICIONAR ARQUIVOS',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : PageView.builder(
                          controller: _pageController,
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              selectedFiles.length +
                              1, // +1 para o card de adicionar
                          itemBuilder: (context, index) {
                            // Se for o último item (card de adicionar)
                            if (index == selectedFiles.length) {
                              return GestureDetector(
                                onTap: addFile,
                                child: Container(
                                  width: 150,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.grey[850]!,
                                        Colors.grey[900]!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.deepPurpleAccent
                                          .withOpacity(0.5),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.5),
                                        blurRadius: 12,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_circle_outline,
                                        size: 40,
                                        color: Colors.deepPurpleAccent,
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'Adicionar\nMais Tracks',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.deepPurpleAccent,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Toque para adicionar',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            // Código para renderizar as tracks normais
                            final file = selectedFiles[index];
                            final muted = isMutedList[index];
                            final pan = panValues[index];
                            double volume = volumeValues[index];
                            final scale = (1 - (_currentPage - index).abs())
                                .clamp(0.95, 1.1);

                            final trackIcon = selectedIcons.length > index
                                ? selectedIcons[index]
                                : 'guitar.png';

                            return GestureDetector(
                              onLongPress: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Remover arquivo'),
                                    content: Text(
                                      'Deseja remover "${file.name}"?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: Text('Remover'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  try {
                                    if (index >= 0 &&
                                        index < selectedFiles.length) {
                                      await platform.invokeMethod(
                                        'removePlayer',
                                        {'index': index},
                                      );

                                      setState(() {
                                        selectedFiles.removeAt(index);
                                        isMutedList.removeAt(index);
                                        panValues.removeAt(index);
                                        volumeValues.removeAt(index);
                                        if (selectedIcons.length > index) {
                                          selectedIcons.removeAt(index);
                                        }
                                      });
                                    }
                                  } on PlatformException catch (e) {
                                    print(
                                      'Erro ao remover player: ${e.message}',
                                    );
                                  }
                                }
                              },
                              child: Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 150,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.grey[850]!,
                                        Colors.grey[900]!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _isPresetUnsaved
                                          ? Colors.orangeAccent.withOpacity(0.7)
                                          : Colors.grey[800]!,
                                      width: _isPresetUnsaved ? 2 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.5),
                                        blurRadius: 12,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _showIconSelectionDialog(index),
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Image.asset(
                                              'assets/icons/$trackIcon',
                                              width: 20,
                                              height: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: muted
                                                  ? Colors.red
                                                  : Colors.green,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: muted
                                                      ? Colors.red.withOpacity(
                                                          0.8,
                                                        )
                                                      : Colors.green
                                                            .withOpacity(0.8),
                                                  spreadRadius: 2,
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          SizedBox(height: 52),
                                          Container(
                                            width: double.infinity,
                                            padding: EdgeInsets.symmetric(
                                              vertical: 16,
                                              horizontal: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: Colors.grey[800]!,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              file.name
                                                  .replaceAll(
                                                    RegExp(r'\.[^\.]+$'),
                                                    '',
                                                  ) // remove extensão
                                                  .replaceFirst(
                                                    RegExp(r'^\d+_'),
                                                    '',
                                                  ), // remove números iniciais
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),

                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8.0,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  AudioMeter(
                                                    index: index,
                                                    height: 60,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Stack(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    children: [
                                                      RotatedBox(
                                                        quarterTurns:
                                                            3, // deixa o slider vertical
                                                        child: SliderTheme(
                                                          data:
                                                              SliderTheme.of(
                                                                context,
                                                              ).copyWith(
                                                                trackHeight: 12,
                                                                thumbShape:
                                                                    ImageSliderThumb(
                                                                      size: 48,
                                                                      image:
                                                                          thumbImage!,
                                                                    ),
                                                              ),
                                                          child: Slider(
                                                            value: volume,
                                                            min: 0.0,
                                                            max: 1.0,
                                                            onChanged: (value) {
                                                              setState(() {
                                                                volumeValues[index] =
                                                                    value; // <-- atualização correta
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 40,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.grey[700]!,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${(volume * 100).round()}',
                                                style: TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 12,
                                                  fontFamily: 'Digital',
                                                ),
                                              ),
                                            ),
                                          ),

                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0,
                                              vertical: 4,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                GestureDetector(
                                                  onTap: () =>
                                                      toggleMute(index),
                                                  child: Container(
                                                    padding: EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color: muted
                                                          ? Colors.red
                                                                .withOpacity(
                                                                  0.2,
                                                                )
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      Icons.volume_off,
                                                      size: 18,
                                                      color: muted
                                                          ? Colors.redAccent
                                                          : Colors.white70,
                                                    ),
                                                  ),
                                                ),

                                                Expanded(
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceEvenly,
                                                    children: [
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            setPlayerPan(
                                                              index,
                                                              -1.0,
                                                            ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              pan == -1.0
                                                              ? Colors
                                                                    .deepPurpleAccent
                                                              : Colors
                                                                    .grey[800],
                                                        ),
                                                        child: const Text('1'),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            setPlayerPan(
                                                              index,
                                                              0,
                                                            ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              pan == 0
                                                              ? Colors
                                                                    .deepPurpleAccent
                                                              : Colors
                                                                    .grey[800],
                                                        ),
                                                        child: const Text('C'),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            setPlayerPan(
                                                              index,
                                                              1.0,
                                                            ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              pan == 1.0
                                                              ? Colors
                                                                    .deepPurpleAccent
                                                              : Colors
                                                                    .grey[800],
                                                        ),
                                                        child: const Text('2'),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8.0,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  pan < 0
                                                      ? 'L${(pan * -100).round()}'
                                                      : pan > 0
                                                      ? 'R${(pan * 100).round()}'
                                                      : 'C',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                if (selectedFiles.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 8,
                          activeTrackColor: const Color.fromARGB(
                            255,
                            51,
                            51,
                            51,
                          ),
                          inactiveTrackColor: const Color.fromARGB(
                            255,
                            0,
                            0,
                            0,
                          ),
                          thumbColor: Colors.deepPurple,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayColor: const Color.fromARGB(
                            255,
                            12,
                            255,
                            178,
                          ).withAlpha(32),
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          tickMarkShape: RoundSliderTickMarkShape(),
                          activeTickMarkColor: Colors.deepPurpleAccent,
                          inactiveTickMarkColor: Colors.grey[700],
                        ),
                        child: Slider(
                          min: 0,
                          max: _maxDuration.inMilliseconds.toDouble(),
                          value: currentPosition.inMilliseconds
                              .clamp(0, _maxDuration.inMilliseconds)
                              .toDouble(),
                          onChanged: (value) {
                            setState(() {
                              userIsSeeking = true;
                              currentPosition = Duration(
                                milliseconds: value.toInt(),
                              );
                            });
                          },
                          onChangeEnd: (value) {
                            final seekPosition = Duration(
                              milliseconds: value.toInt(),
                            );
                            seekTo(seekPosition);
                            userIsSeeking = false;
                            print(
                              "Posição alterada para: ${formatDuration(seekPosition)}",
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(currentPosition),
                              style: TextStyle(color: Colors.white70),
                            ),
                            Text(
                              formatDuration(_maxDuration),
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Adicione este widget no seu arquivo (pode ser antes da classe _MyAppState)
class PresetButton extends StatelessWidget {
  final String name;
  final int fileCount;
  final VoidCallback onPressed;
  final bool isSelected;
  final VoidCallback? onDelete;

  const PresetButton({
    Key? key,
    required this.name,
    required this.fileCount,
    required this.onPressed,
    this.isSelected = false,
    this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Material(
        color: isSelected ? Colors.deepPurple[800] : Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      '$fileCount ${fileCount == 1 ? 'arquivo' : 'arquivos'}',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
                if (onDelete != null)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(
                        child: GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            padding: EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.5),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
