import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

class AddCollectionPage extends StatefulWidget {
  @override
  _AddCollectionPageState createState() => _AddCollectionPageState();
}

class _AddCollectionPageState extends State<AddCollectionPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _coverController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final List<Map<String, TextEditingController>> _fileControllers = [];
  bool _isSaving = false;

  void _addFileField() {
    setState(() {
      _fileControllers.add({
        'name': TextEditingController(),
        'link': TextEditingController(),
      });
    });
  }

  void _removeFileField(int index) {
    setState(() {
      _fileControllers.removeAt(index);
    });
  }

  Future<void> _saveCollection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Prepara lista de arquivos
      final files = _fileControllers.map((fc) {
        return {
          "name": fc['name']!.text.trim(),
          "link": fc['link']!.text.trim(),
        };
      }).toList();

      final collectionName = _nameController.text.trim();

      // Salva no Firestore
      await FirebaseFirestore.instance
          .collection("multitracks")
          .doc(collectionName)
          .set({
            "name": collectionName,
            "cover": _coverController.text.trim(),
            "author": _authorController.text.trim(),
            "duration": _durationController.text.trim(),
            "trackCount": files.length, // calculado automaticamente
            "files": files,
            "createdAt": FieldValue.serverTimestamp(),
          });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Coleção '$collectionName' criada!"),
          backgroundColor: Colors.green,
        ),
      );

      // Limpa campos
      _nameController.clear();
      _coverController.clear();
      _authorController.clear();
      _durationController.clear();
      _fileControllers.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro ao criar coleção: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _coverController.dispose();
    for (var fc in _fileControllers) {
      fc['name']!.dispose();
      fc['link']!.dispose();
    }
    super.dispose();
  }

  // dentro do _AddCollectionPageState

  Future<void> _addPresetCollections() async {
    setState(() => _isSaving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // exemplo: cria 10 coleções do Gabriel Guedes
      for (int i = 1; i <= 10; i++) {
        final docRef = FirebaseFirestore.instance
            .collection("multitracks")
            .doc("Gabriel_Guedes_$i");

        batch.set(docRef, {
          "name": "Gabriel Guedes $i",
          "author": "Gabriel Guedes",
          "cover": "https://i.ytimg.com/vi/k7tGP-vidwc/maxresdefault.jpg",
          "duration": "10:22",
          "files": [
            {
              "name": "AG.mp3",
              "link":
                  "https://drive.google.com/file/d/17nCK0Ler9mBEW3oPU_gCQZT8Z6ZCvX_v/view?usp=drive_link",
            },
            {
              "name": "BASS.mp3",
              "link":
                  "https://drive.google.com/file/d/1lgsOBY9nBIQVJXNgLADTUafC0kqbLcDF/view?usp=drive_link",
            },
            {
              "name": "CLICK.mp3",
              "link":
                  "https://drive.google.com/file/d/1a6-cwWGIzI7LUVfqld8eDluItUNCjo5S/view?usp=drive_link",
            },
            {
              "name": "DRUMS.mp3",
              "link":
                  "https://drive.google.com/file/d/1q3heVnlA48MdAzHXzogn0gIL1MgFz7LD/view?usp=drive_link",
            },
          ],
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      // adiciona coleção "Vitorioso É"
      final docVitorioso = FirebaseFirestore.instance
          .collection("multitracks")
          .doc("Vitorioso_Es");
      batch.set(docVitorioso, {
        "name": "Vitorioso É",
        "author": "Vinicius",
        "cover":
            "https://i.scdn.co/image/ab67616d0000b273c0ae28e23f63f132bb7b2bd2",
        "duration": "4:30",
        "files": [
          {
            "name": "click.mp3",
            "link":
                "https://drive.google.com/file/d/1v0pb6_qI2ipIC7ufe6k93aR2c0-O_0ly/view",
          },
          {
            "name": "baixo.mp3",
            "link":
                "https://drive.google.com/file/d/1rVjayhwqu2V1oteBqizejBVg6FWBUjQo/view",
          },
        ],
        "createdAt": FieldValue.serverTimestamp(),
      });

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Coleções automáticas criadas com sucesso!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro ao criar coleções: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Adicionar Coleção"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Nome da Coleção",
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: "Ex: Vitorioso é",
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Informe o nome da coleção";
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _addPresetCollections,
                icon: Icon(Icons.library_add),
                label: Text("Adicionar Coleções Automáticas"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              // Autor
              TextFormField(
                controller: _authorController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Autor",
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: "Ex: Diante do Trono",
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Duração
              TextFormField(
                controller: _durationController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Duração",
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: "Ex: 4:32",
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Capa
              TextFormField(
                controller: _coverController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "URL da Capa",
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: "Ex: https://i.scdn.co/image/...",
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) =>
                    setState(() {}), // atualiza preview ao digitar
              ),
              SizedBox(height: 12),

              // Preview da capa
              if (_coverController.text.trim().isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _coverController.text.trim(),
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 150,
                        color: Colors.grey[800],
                        alignment: Alignment.center,
                        child: Text(
                          "URL inválida",
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      );
                    },
                  ),
                ),
              SizedBox(height: 16),

              // Lista de arquivos
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _fileControllers.length,
                itemBuilder: (context, index) {
                  final fc = _fileControllers[index];
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: fc['name'],
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: "Nome do arquivo",
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white38),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.blueAccent,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Informe o nome do arquivo";
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: fc['link'],
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: "Link do arquivo",
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white38),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.blueAccent,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Informe o link do arquivo";
                                }
                                return null;
                              },
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.remove_circle,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _removeFileField(index),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                    ],
                  );
                },
              ),
              SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _addFileField,
                icon: Icon(Icons.add),
                label: Text("Adicionar Arquivo"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                ),
              ),
              SizedBox(height: 20),
              _isSaving
                  ? CircularProgressIndicator(color: Colors.white)
                  : ElevatedButton(
                      onPressed: _saveCollection,
                      child: Text("Salvar Coleção"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
