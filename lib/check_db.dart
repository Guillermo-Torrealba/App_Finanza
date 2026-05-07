import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_secrets.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: AppSecrets.supabaseUrl,
    anonKey: AppSecrets.supabaseAnonKey,
  );
  
  final supabase = Supabase.instance.client;
  
  // Get all accounts from the user
  final response = await supabase
      .from('gastos')
      .select('cuenta, item, monto, tipo, categoria, fecha')
      .order('fecha', ascending: false)
      .limit(50);
      
  print('Last 50 movements:');
  for (var r in response) {
    print('${r['fecha']} | ${r['cuenta']} | ${r['item']} | ${r['categoria']} | ${r['tipo']} | ${r['monto']}');
  }
  exit(0);
}
