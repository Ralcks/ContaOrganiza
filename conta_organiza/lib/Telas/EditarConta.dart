import 'package:flutter/material.dart';

class Configuracoes extends StatefulWidget {
  @override
  _ConfiguracoesState createState() => _ConfiguracoesState();
}

class _ConfiguracoesState extends State<Configuracoes> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          ListTile(
            leading: Icon(
                Icons.notifications), // Adiciona o ícone na frente do texto
            title: Text('Alterar senha'),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              // Navegue para a tela de configurações de notificações
            },
          ),
          ListTile(
            title: Text('Contas vinculadas'),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              // Navegue para a tela de informações sobre o aplicativo
            },
          ),
        ],
      ),
    );
  }
}
