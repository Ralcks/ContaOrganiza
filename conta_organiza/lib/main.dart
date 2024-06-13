import 'package:conta_organiza/Telas/TelaInicialPage.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'Telas/CadastrarUsuario.dart';
import 'Telas/Inicio.dart';
import 'Telas/ListaContas.dart';
import 'Telas/Login.dart';
import 'Telas/VerificaEmail.dart'; // Certifique-se de importar a tela de verificação de e-mail
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
  );

  // Inicializar a formatação de data para português
  await initializeDateFormatting('pt_BR', null);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Conta Organiza',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'), // English
        Locale('pt', 'BR'), // Portuguese
      ],
      initialRoute: '/',
      routes: {
        '/': (context) => AuthWrapper(),
        '/inicio': (context) => const TelaInicial(),
        '/login': (context) => Login(),
        '/cadastrar': (context) => const CadastrarUsuario(),
        '/lista-contas': (context) => const ListaContas(),
        '/verificar-email': (context) => const VerificaEmail(
            email: ''), // Adicione a rota para a tela de verificação de e-mail
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData) {
          User? user = snapshot.data;
          if (user != null && user.emailVerified) {
            return const ListaContas();
          } else {
            return VerificaEmail(email: user?.email ?? '');
          }
        }
        return const TelaInicial();
      },
    );
  }
}
