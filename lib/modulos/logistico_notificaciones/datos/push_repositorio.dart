import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/env.dart';
import '../../../core/supabase_client.dart';

/// Notificaciones push (RF-19). Firebase Cloud Messaging se usa ÚNICAMENTE
/// como canal de envío; las alertas las genera y despacha Supabase.
/// Solo en la app móvil (Android/iOS).
class PushRepositorio {
  static bool _inicializado = false;

  static bool get disponible =>
      _inicializado &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static String get _plataforma => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Inicializa Firebase si está configurado. Se llama una vez en `main`.
  static Future<void> inicializar() async {
    if (kIsWeb || !Env.firebaseConfigurado) return;
    final esIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (!esIos && defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: Env.firebaseApiKey,
          appId: esIos ? Env.firebaseAppIdIos : Env.firebaseAppIdAndroid,
          messagingSenderId: Env.firebaseMessagingSenderId,
          projectId: Env.firebaseProjectId,
        ),
      );
      _inicializado = true;
    } catch (e) {
      debugPrint('Push deshabilitado: no se pudo inicializar Firebase ($e)');
    }
  }

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  /// Pide permiso, obtiene el token del dispositivo y lo registra para el
  /// usuario con sesión. Devuelve `false` si el usuario negó el permiso.
  Future<bool> registrar() async {
    if (!disponible) return false;
    final permiso = await _fcm.requestPermission();
    if (permiso.authorizationStatus == AuthorizationStatus.denied) return false;
    final token = await _fcm.getToken();
    if (token != null) await _guardarToken(token);
    return true;
  }

  Stream<String> get cambiosDeToken => disponible ? _fcm.onTokenRefresh : const Stream.empty();

  Future<void> guardarTokenRenovado(String token) => _guardarToken(token);

  Future<void> _guardarToken(String token) => supabase.rpc('registrar_dispositivo_push',
      params: {'p_token': token, 'p_plataforma': _plataforma});

  /// Al cerrar sesión: el dispositivo deja de recibir alertas de ese usuario.
  Future<void> desregistrar() async {
    if (!disponible) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) await supabase.from('dispositivo_push').delete().eq('token', token);
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('No se pudo desregistrar el dispositivo: $e');
    }
  }

  Stream<RemoteMessage> get mensajesEnPrimerPlano =>
      disponible ? FirebaseMessaging.onMessage : const Stream.empty();

  Stream<RemoteMessage> get notificacionesAbiertas =>
      disponible ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();

  Future<RemoteMessage?> notificacionInicial() async =>
      disponible ? _fcm.getInitialMessage() : null;
}
