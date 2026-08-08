import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final googleSignInProvider =
    AsyncNotifierProvider<GoogleSignInNotifier, GoogleSignInAccount?>(() {
      return GoogleSignInNotifier();
    });

class GoogleSignInNotifier extends AsyncNotifier<GoogleSignInAccount?> {
  late final GoogleSignIn _googleSignIn;
  @override
  FutureOr<GoogleSignInAccount?> build() {}
}
