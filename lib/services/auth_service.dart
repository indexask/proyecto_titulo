import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/profile.dart';

class AuthService {
  Stream<AuthState> get onAuthStateChange => supabase.auth.onAuthStateChange;

  Session? get currentSession => supabase.auth.currentSession;

  Future<void> signIn({required String email, required String password}) {
    return supabase.auth
        .signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) {
    return supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<void> signOut() => supabase.auth.signOut();

  Future<Profile> fetchProfile(String userId) async {
    final data =
        await supabase.from('profiles').select().eq('id', userId).single();
    return Profile.fromMap(data);
  }
}
