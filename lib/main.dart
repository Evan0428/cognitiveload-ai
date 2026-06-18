import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'view_models/auth_view_model.dart';
import 'view_models/add_task_viewmodel.dart'; // 🟢 导入新写的添加任务 ViewModel
import 'views/login_view.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'views/dashboard_screen.dart'; // 🟢 引入我们最新版、带4个Tab管理的自洽式主大屏

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const CognitiveLoadApp());
}

class CognitiveLoadApp extends StatelessWidget {
  const CognitiveLoadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..init()),
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        // 🟢 核心修复：在这里向全局注册 AddTaskViewModel，供添加任务相关的 View 正常 Listen
        ChangeNotifierProvider(create: (_) => AddTaskViewModel()),
      ],
      child: MaterialApp(
        title: 'CognitiveLoad AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthenticationWrapper(),
      ),
    );
  }
}

class AuthenticationWrapper extends StatelessWidget {
  const AuthenticationWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 🟢 如果用户已成功登录，彻底舍弃旧的 HomeShell，直接跳转到最新的 DashboardScreen()
        if (snapshot.hasData) {
          return const DashboardScreen();
        }

        // 🔴 如果未登录，正常前往登录界面
        return const LoginView();
      },
    );
  }
}