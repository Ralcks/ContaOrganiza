import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/scheduler.dart';

class TelaInicialPage extends StatefulWidget {
  const TelaInicialPage({super.key});

  @override
  _TelaInicialPageState createState() => _TelaInicialPageState();
}

class _TelaInicialPageState extends State<TelaInicialPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _contas = [];
  List<String> _diretorios = [];
  Map<String, String> _diretoriosMap = {};
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadContas();
    _loadDirectories();
  }

  Future<void> _loadContas() async {
    try {
      _currentUser = FirebaseAuth.instance.currentUser;
      if (_currentUser != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .get();
        if (userDoc.exists) {
          Map<String, dynamic>? data = userDoc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('contas')) {
            if (mounted) {
              setState(() {
                _contas =
                    List<Map<String, dynamic>>.from(data['contas'].map((conta) {
                  return {
                    'descricao': conta['descricao'],
                    'diretorio': conta['diretorio'],
                    'dataInicio': conta['dataInicio'] != null
                        ? (conta['dataInicio'] as Timestamp).toDate()
                        : null,
                    'dataTermino': conta['dataTermino'] != null
                        ? (conta['dataTermino'] as Timestamp).toDate()
                        : null,
                    'comprovante': conta['comprovante'] ?? false,
                    'comprovanteUrl': conta['comprovanteUrl'] ?? '',
                  };
                }));
              });
            }
          }
        }
      }
    } catch (e) {
      print('Erro ao carregar contas: $e');
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _showSnackBar('Erro ao carregar contas: $e');
        });
      }
    }
  }

  Future<void> _loadDirectories() async {
    try {
      _currentUser = FirebaseAuth.instance.currentUser;
      if (_currentUser != null) {
        QuerySnapshot directoriesSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('directories')
            .get();
        if (mounted) {
          setState(() {
            _diretorios =
                directoriesSnapshot.docs.map((doc) => doc.id).toList();
            _diretoriosMap = {
              for (var doc in directoriesSnapshot.docs)
                doc.id: (doc.data() as Map<String, dynamic>)['name'] ?? doc.id
            };
          });
        }
      }
    } catch (e) {
      print('Erro ao carregar diretórios: $e');
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _showSnackBar('Erro ao carregar diretórios: $e');
        });
      }
    }
  }

  Future<void> _saveContas() async {
    try {
      if (_currentUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .update({
          'contas': _contas.map((conta) {
            return {
              'descricao': conta['descricao'],
              'diretorio': conta['diretorio'],
              'dataInicio': conta['dataInicio'] != null
                  ? Timestamp.fromDate(conta['dataInicio'])
                  : null,
              'dataTermino': conta['dataTermino'] != null
                  ? Timestamp.fromDate(conta['dataTermino'])
                  : null,
              'comprovante': conta['comprovante'],
              'comprovanteUrl': conta['comprovanteUrl'],
            };
          }).toList(),
        });
      }
    } catch (e) {
      print('Erro ao salvar contas: $e');
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _showSnackBar('Erro ao salvar contas: $e');
        });
      }
    }
  }

  Future<void> _pickFiles(BuildContext context, String description,
      DateTime date, String directoryId) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result != null) {
        File pickedFile = File(result.files.single.path!);
        await _uploadFile(context, pickedFile, description, date, directoryId);
      }
    } catch (e) {
      print('Erro ao selecionar arquivo: $e');
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _showSnackBar('Erro ao selecionar arquivo: $e');
        });
      }
    }
  }

  Future<void> _pickImage(BuildContext context, String description,
      DateTime date, String directoryId) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);

      if (pickedFile != null) {
        File imageFile = File(pickedFile.path);
        await _uploadFile(context, imageFile, description, date, directoryId);
      }
    } catch (e) {
      print('Erro ao capturar imagem: $e');
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _showSnackBar('Erro ao capturar imagem: $e');
        });
      }
    }
  }

  Future<void> _uploadFile(BuildContext context, File file, String description,
      DateTime date, String directoryId) async {
    try {
      String sanitizedDescription =
          description.replaceAll(RegExp(r'[\/:*?"<>|]'), '');
      final fileName =
          '${sanitizedDescription}_${DateFormat('yyyy-MM-dd').format(date)}_${file.path.split('.').last}';

      // Upload do arquivo para o Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(
          'users/${_currentUser!.uid}/directories/$directoryId/$fileName');
      await storageRef.putFile(file);
      final fileUrl = await storageRef.getDownloadURL();

      // Salvar metadados no Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('directories')
          .doc(directoryId)
          .collection('files')
          .add({
        'description': sanitizedDescription,
        'date': date,
        'type': file.path.split('.').last,
        'url': fileUrl,
      });

      // Marcar a conta como paga
      setState(() {
        for (var conta in _contas) {
          if (conta['descricao'] == description &&
              conta['diretorio'] == directoryId) {
            conta['comprovante'] = true;
            conta['comprovanteUrl'] = fileUrl;
            break;
          }
        }
      });

      await _saveContas();

      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _showSnackBar('Arquivo enviado com sucesso!');
        });
      }
    } catch (e) {
      print('Erro ao fazer upload do arquivo: $e');
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _showSnackBar('Erro ao fazer upload do arquivo: $e');
        });
      }
    }
  }

  Future<void> _mostrarDialogoUpload(
      Map<String, dynamic> conta, bool isImage) async {
    final _descricaoController = TextEditingController();
    String? _diretorioSelecionado;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Adicionar Comprovante'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(
                        labelText: 'Descrição do Arquivo'),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Diretório'),
                    value: _diretorioSelecionado,
                    items: _diretorios.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(_diretoriosMap[value] ?? value),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() {
                        _diretorioSelecionado = newValue;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_descricaoController.text.isNotEmpty &&
                        _diretorioSelecionado != null) {
                      Navigator.of(context).pop();
                      if (isImage) {
                        await _pickImage(
                          context,
                          _descricaoController.text,
                          DateTime.now(),
                          _diretorioSelecionado!,
                        );
                      } else {
                        await _pickFiles(
                          context,
                          _descricaoController.text,
                          DateTime.now(),
                          _diretorioSelecionado!,
                        );
                      }
                      await _saveContas();
                    } else {
                      if (mounted) {
                        SchedulerBinding.instance.addPostFrameCallback((_) {
                          _showSnackBar('Por favor, preencha todos os campos.');
                        });
                      }
                    }
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _desmarcarContaComoPaga(Map<String, dynamic> conta) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desmarcar como paga'),
        content: const Text(
            'Você tem certeza que deseja desmarcar esta conta como paga?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: const Text('Desmarcar'),
          ),
        ],
      ),
    );

    if (confirm) {
      setState(() {
        conta['comprovante'] = false;
        conta['comprovanteUrl'] = '';
      });
      await _saveContas();
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    List<Map<String, dynamic>> contasFiltradas = _contas.where((conta) {
      // Filtrar contas do mês atual
      DateTime? dataInicio = conta['dataInicio'];
      DateTime? dataTermino = conta['dataTermino'];
      bool isCurrentMonth = (dataInicio != null &&
              dataInicio.month == now.month &&
              dataInicio.year == now.year) ||
          (dataTermino != null &&
              dataTermino.month == now.month &&
              dataTermino.year == now.year);
      return isCurrentMonth;
    }).toList();

    // Ordenar contas
    contasFiltradas.sort((a, b) {
      DateTime? dataTerminoA = a['dataTermino'];
      DateTime? dataTerminoB = b['dataTermino'];
      DateTime? dataInicioA = a['dataInicio'];
      DateTime? dataInicioB = b['dataInicio'];

      // Contas vencidas primeiro, ordenadas pela data de término (mais antigas primeiro)
      if (dataTerminoA != null && dataTerminoA.isBefore(now)) {
        if (dataTerminoB != null && dataTerminoB.isBefore(now)) {
          return dataTerminoA.compareTo(dataTerminoB);
        }
        return -1;
      }
      if (dataTerminoB != null && dataTerminoB.isBefore(now)) {
        return 1;
      }

      // Contas não vencidas, ordenadas pela data de início
      if (dataInicioA != null && dataInicioB != null) {
        return dataInicioA.compareTo(dataInicioB);
      }
      return 0;
    });

    String dataAtual = DateFormat('dd/MM/yyyy').format(now);

    return Scaffold(
      key: _scaffoldKey,
      body: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data Atual: $dataAtual',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Card(
                elevation: 5,
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: ListView.builder(
                    itemCount: contasFiltradas.length,
                    itemBuilder: (context, index) {
                      final conta = contasFiltradas[index];
                      DateTime? dataTermino = conta['dataTermino'];
                      bool isVencido =
                          dataTermino != null && dataTermino.isBefore(now);
                      bool hasComprovante = conta['comprovante'];

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        height: 90, // Definindo a altura do container
                        decoration: BoxDecoration(
                          color: hasComprovante
                              ? Colors.green[100]
                              : isVencido
                                  ? Colors.red[100]
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasComprovante
                                ? Colors.green
                                : isVencido
                                    ? Colors.red
                                    : Colors.grey,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          title: Text(conta['descricao']),
                          subtitle: Text(
                            '${_diretoriosMap[conta['diretorio']] ?? conta['diretorio']} - Início: ${DateFormat('dd/MM/yyyy').format(conta['dataInicio'] ?? DateTime.now())} - Término: ${conta['dataTermino'] != null ? DateFormat('dd/MM/yyyy').format(conta['dataTermino']!) : 'N/A'}',
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon:
                                        const Icon(Icons.attach_file, size: 24),
                                    onPressed: () =>
                                        _mostrarDialogoUpload(conta, false),
                                  ),
                                  IconButton(
                                    icon:
                                        const Icon(Icons.camera_alt, size: 24),
                                    onPressed: () =>
                                        _mostrarDialogoUpload(conta, true),
                                  ),
                                ],
                              ),
                              // PopupMenuButton<String>(
                              //   onSelected: (String value) {
                              //     if (value == 'desmarcar') {
                              //       _desmarcarContaComoPaga(conta);
                              //     }
                              //   },
                              //   itemBuilder: (BuildContext context) {
                              //     return {'desmarcar'}.map((String choice) {
                              //       return PopupMenuItem<String>(
                              //         value: choice,
                              //         child: Text(choice),
                              //       );
                              //     }).toList();
                              //   },
                              // ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
