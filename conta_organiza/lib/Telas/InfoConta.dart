import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class InfoConta extends StatefulWidget {
  final DocumentSnapshot directory;

  InfoConta({required this.directory});

  @override
  _InfoContaState createState() => _InfoContaState();
}

class _InfoContaState extends State<InfoConta> {
  List<Map<String, dynamic>> _files = [];
  User? _currentUser;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    initializeDateFormatting('pt_BR', null).then((_) {
      _loadFiles();
    });
  }

  Future<void> _loadFiles() async {
    if (_currentUser != null) {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('directories')
          .doc(widget.directory.id)
          .collection('files')
          .get();

      List<Map<String, dynamic>> files = querySnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'description': doc['description'],
          'date': doc['date'].toDate(),
          'type': doc['type'],
          'url': doc['url'],
        };
      }).toList();

      files.sort((a, b) =>
          b['date'].compareTo(a['date'])); // Ordena os arquivos pela data

      setState(() {
        _files = files;
      });
    }
  }

  Future<void> _pickFiles() async {
    if (_isUploading) return; // Evitar múltiplos uploads simultâneos

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null) {
      File pickedFile = File(result.files.single.path!);
      await _showFileInfoDialog(pickedFile);
    }
  }

  Future<void> _pickImage() async {
    if (_isUploading) return; // Evitar múltiplos uploads simultâneos

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      await _showFileInfoDialog(imageFile);
    }
  }

  Future<void> _showFileInfoDialog(File file) async {
    String description = '';
    DateTime date = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Informações do arquivo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) {
                  description = value;
                },
                decoration: InputDecoration(labelText: 'Descrição'),
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Text('Vencimento: '),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          locale: const Locale('pt', 'BR'),
                        );
                        if (pickedDate != null) {
                          setState(() {
                            date = pickedDate;
                          });
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.access_time),
                          SizedBox(width: 5),
                          Text(
                            DateFormat('dd/MM/yyyy').format(date),
                            style:
                                TextStyle(decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _uploadFile(file, description, date);
            },
            child: Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadFile(File file, String description, DateTime date) async {
    setState(() {
      _isUploading = true;
    });

    try {
      String sanitizedDescription =
          description.replaceAll(RegExp(r'[\/:*?"<>|]'), '');
      final fileName =
          '${sanitizedDescription}_${DateFormat('yyyy-MM-dd').format(date)}_${file.path.split('.').last}';

      // Upload do arquivo para o Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(
          'users/${_currentUser!.uid}/directories/${widget.directory.id}/$fileName');
      await storageRef.putFile(file);
      final fileUrl = await storageRef.getDownloadURL();

      // Salvar metadados no Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('directories')
          .doc(widget.directory.id)
          .collection('files')
          .add({
        'description': sanitizedDescription,
        'date': date,
        'type': file.path.split('.').last,
        'url': fileUrl,
      });

      // Carregue os arquivos novamente para atualizar a lista
      await _loadFiles();
    } catch (e) {
      // Tratar erros de upload
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao fazer upload do arquivo: $e'),
        ),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> fileData) async {
    if (_currentUser != null) {
      // Deletar o arquivo do Firebase Storage
      final storageRef = FirebaseStorage.instance.refFromURL(fileData['url']);
      await storageRef.delete();

      // Deletar metadados do Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('directories')
          .doc(widget.directory.id)
          .collection('files')
          .doc(fileData['id'])
          .delete();

      _loadFiles();
    }
  }

  Future<void> _openFileInBrowser(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  void _editFileDetails(Map<String, dynamic> fileData) {
    String description = fileData['description'];
    DateTime date = fileData['date'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar Detalhes do Arquivo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) {
                  description = value;
                },
                controller: TextEditingController(text: description),
                decoration: InputDecoration(labelText: 'Descrição'),
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Text('Vencimento: '),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          locale: const Locale('pt', 'BR'),
                        );
                        if (pickedDate != null) {
                          setState(() {
                            date = pickedDate;
                          });
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.access_time),
                          SizedBox(width: 5),
                          Text(
                            DateFormat('dd/MM/yyyy').format(date),
                            style:
                                TextStyle(decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(_currentUser!.uid)
                  .collection('directories')
                  .doc(widget.directory.id)
                  .collection('files')
                  .doc(fileData['id'])
                  .update({
                'description': description,
                'date': date,
              });
              await _loadFiles();
            },
            child: Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: FutureBuilder(
            future: _loadImage(url),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erro ao carregar a imagem'));
                }
                return Image.network(url);
              } else {
                return Center(child: CircularProgressIndicator());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadImage(String url) async {
    try {
      final response = await Dio().get(url);
      if (response.statusCode != 200) {
        throw Exception('Erro ao carregar a imagem');
      }
    } catch (e) {
      throw Exception('Erro ao carregar a imagem: $e');
    }
  }

  void _showPdfPreview(String url) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: FutureBuilder<File>(
            future: _downloadPdf(url),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Não foi possível exibir o PDF. Por favor, tente novamente mais tarde.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                try {
                  return PDFView(filePath: snapshot.data!.path);
                } catch (e) {
                  return Center(
                    child: Text(
                      'Erro ao carregar o PDF. Por favor, tente novamente mais tarde.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
              } else {
                return Center(child: CircularProgressIndicator());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<File> _downloadPdf(String url) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/${url.split('/').last}';
      final file = File(filePath);

      if (await file.exists()) {
        return file;
      }

      final response = await Dio().get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      await file.writeAsBytes(response.data);
      return file;
    } catch (e) {
      throw Exception('Erro ao baixar o PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, Map<String, List<Map<String, dynamic>>>> groupedFiles = {};

    for (var fileData in _files) {
      final description = fileData['description'];
      final date = fileData['date'];
      final type = fileData['type'];

      String year = DateFormat('yyyy').format(date);
      String month = DateFormat('MMMM', 'pt_BR').format(date);

      if (!groupedFiles.containsKey(year)) {
        groupedFiles[year] = {};
      }

      if (!groupedFiles[year]!.containsKey(month)) {
        groupedFiles[year]![month] = [];
      }

      groupedFiles[year]![month]!.add(fileData);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.directory['name']),
        actions: [
          IconButton(
            icon: Icon(Icons.add_a_photo),
            onPressed: _pickImage,
          ),
          IconButton(
            icon: Icon(Icons.attach_file),
            onPressed: _pickFiles,
          ),
        ],
      ),
      body: _isUploading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              children: groupedFiles.entries.map((yearEntry) {
                String year = yearEntry.key;
                Map<String, List<Map<String, dynamic>>> months =
                    yearEntry.value;

                return ExpansionTile(
                  leading: Container(
                    width: 4,
                    color: Colors.grey,
                  ),
                  title: Text(year,
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  children: months.entries.map((monthEntry) {
                    String month = monthEntry.key;
                    List<Map<String, dynamic>> files = monthEntry.value;

                    return ExpansionTile(
                      leading: Container(
                        width: 4,
                        color: Colors.grey,
                      ),
                      title: Text(month, style: TextStyle(fontSize: 18)),
                      children: files.map((fileData) {
                        final description = fileData['description'];
                        final date = fileData['date'];
                        final type = fileData['type'];
                        final url = fileData['url'];

                        IconData iconData;
                        if (type == 'pdf') {
                          iconData = Icons.picture_as_pdf;
                        } else if (type == 'jpg' ||
                            type == 'jpeg' ||
                            type == 'png') {
                          iconData = Icons.image;
                        } else {
                          iconData = Icons.insert_drive_file;
                        }

                        return ListTile(
                          leading: Icon(iconData),
                          title: Text(description),
                          subtitle: Text(
                              'Vencimento: ${DateFormat('dd/MM/yyyy').format(date)}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              switch (value) {
                                case 'view':
                                  if (type == 'pdf') {
                                    _showPdfPreview(url);
                                  } else {
                                    _showImagePreview(url);
                                  }
                                  break;
                                case 'download':
                                  await _openFileInBrowser(url);
                                  break;
                                case 'edit':
                                  _editFileDetails(fileData);
                                  break;
                                case 'delete':
                                  _deleteFile(fileData);
                                  break;
                              }
                            },
                            itemBuilder: (BuildContext context) {
                              return [
                                if (type != 'pdf')
                                  PopupMenuItem(
                                    value: 'view',
                                    child: Text('Visualizar'),
                                  ),
                                PopupMenuItem(
                                  value: 'download',
                                  child: Text('Download'),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Excluir'),
                                ),
                              ];
                            },
                          ),
                          onTap: () {
                            if (type == 'pdf') {
                              _showPdfPreview(url);
                            } else {
                              _showImagePreview(url);
                            }
                          },
                        );
                      }).toList(),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
    );
  }
}
