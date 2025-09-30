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

class AddCollectionPage2 extends StatefulWidget {
  @override
  _AddCollectionPage2State createState() => _AddCollectionPage2State();
}

class _AddCollectionPage2State extends State<AddCollectionPage2> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _coverController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();

  // novos controllers
  final TextEditingController _linksController = TextEditingController();
  final TextEditingController _namesController = TextEditingController();
  List<String> _links = [];
  List<String> _instruments = [];
  Map<String, String> _selectedInstruments = {}; // link -> instrumento

  Future<void> _openAssignModal() async {
    _links = _linksController.text
        .split(RegExp(r',|\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _instruments = _namesController.text
        .split("\n")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // inicializa o mapa com vazio
    _selectedInstruments = {for (var link in _links) link: ''};

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Associe cada link a um instrumento'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _links.length,
            itemBuilder: (context, index) {
              final link = _links[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(child: Text(link, style: TextStyle(fontSize: 12))),
                    SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _selectedInstruments[link]?.isEmpty ?? true
                            ? null
                            : _selectedInstruments[link],
                        hint: Text('Selecione instrumento'),
                        isExpanded: true,
                        items: _instruments.map((instrument) {
                          return DropdownMenuItem(
                            value: instrument,
                            child: Text(instrument),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedInstruments[link] = val!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              // valida se todos foram selecionados
              if (_selectedInstruments.values.any((v) => v.isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Selecione todos os instrumentos!'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context);
              _saveCollectionWithAssigned(); // salvar no Firestore
            },
            child: Text('Salvar'),
          ),
        ],
      ),
    );
  }

  bool _isSaving = false;

  Future<void> _saveCollectionWithAssigned() async {
    setState(() => _isSaving = true);
    try {
      // pega links e instrumentos
      final links = _linksController.text
          .split(RegExp(r',|\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final instruments =
          _namesController.text
              .split("\n")
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
            ..sort(
              (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
            ); // ordem alfabética

      if (links.length != instruments.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("A quantidade de links e instrumentos não é igual!"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
        return;
      }

      // associa link[i] -> instrumento[i]
      final files = List.generate(links.length, (i) {
        return {'link': links[i], 'name': instruments[i]};
      });

      final now = DateTime.now();
      final timestamp = now
          .toIso8601String(); // formato ISO, ex: 2025-09-21T14:30:00.000
      final collectionName = _nameController.text.trim();

      // opcional: remover espaços do nome para o ID
      final safeCollectionName = collectionName.replaceAll(' ', '_');

      // cria o ID como timestamp + nome da coleção
      final docId = "${timestamp}_$safeCollectionName";

      await FirebaseFirestore.instance
          .collection("multitracks")
          .doc(docId)
          .set({
            "name": collectionName,
            "cover": _coverController.text.trim(),
            "author": _authorController.text.trim(),
            "duration": _durationController.text.trim(),
            "trackCount": files.length,
            "files": files,
            "createdAt": FieldValue.serverTimestamp(),
          });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Coleção '$collectionName' criada!"),
          backgroundColor: Colors.green,
        ),
      );

      // limpa campos
      _nameController.clear();
      _coverController.clear();
      _authorController.clear();
      _durationController.clear();
      _linksController.clear();
      _namesController.clear();
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
              // Nome da coleção
              TextFormField(
                controller: _nameController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Nome da Coleção",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              SizedBox(height: 16),

              // Autor
              TextFormField(
                controller: _authorController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Autor",
                  labelStyle: TextStyle(color: Colors.white70),
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
                ),
              ),
              SizedBox(height: 16),

              // URL da capa
              TextFormField(
                controller: _coverController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "URL da Capa",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 12),

              if (_coverController.text.trim().isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _coverController.text.trim(),
                    height: 150,
                    fit: BoxFit.cover,
                  ),
                ),
              SizedBox(height: 16),

              // Campo Links
              TextFormField(
                controller: _linksController,
                maxLines: 6,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Cole os links (separados por vírgula ou enter)",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              SizedBox(height: 16),

              // Campo Nomes
              TextFormField(
                controller: _namesController,
                maxLines: 6,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Cole os nomes (um por linha)",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              SizedBox(height: 20),

              _isSaving
                  ? CircularProgressIndicator(color: Colors.white)
                  : ElevatedButton(
                      onPressed:
                          _saveCollectionWithAssigned, // <<< aqui chama o modal
                      child: Text("Salvar Coleção"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
