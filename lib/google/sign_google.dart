import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SignGoogle extends ConsumerStatefulWidget {
  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SignGoogle();
}

class _SignGoogle extends ConsumerState<SignGoogle> {
  GoogleSignInAccount? signInAccount;
  bool _isAuthorized = false;
  String _errorText = '';
  String _serverAuthCode = '';

  @override
  void initState() {
    super.initState();
    final GoogleSignIn signIn = GoogleSignIn.instance;
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
