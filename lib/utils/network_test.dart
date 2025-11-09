import 'dart:io';
import 'package:http/http.dart' as http;

/// Network connectivity test utility
/// 
/// Tests connectivity to AWS endpoints to diagnose routing issues.
class NetworkTest {
  /// Test if AWS endpoint is reachable
  static Future<NetworkTestResult> testAwsConnectivity(String region) async {
    final endpoint = 'routes.$region.amazonaws.com';
    final url = 'https://$endpoint';
    
    print('🧪 Testing network connectivity to AWS...');
    print('Target: $endpoint');
    
    try {
      // Test 1: DNS Resolution
      print('📡 Test 1: DNS Resolution...');
      final addresses = await InternetAddress.lookup(endpoint);
      if (addresses.isEmpty) {
        return NetworkTestResult(
          success: false,
          message: 'DNS lookup returned no addresses',
          details: 'Cannot resolve $endpoint to an IP address',
        );
      }
      print('✅ DNS resolved to: ${addresses.first.address}');
      
      // Test 2: HTTP Connection
      print('📡 Test 2: HTTP Connection...');
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timed out');
        },
      );
      
      print('✅ HTTP connection successful');
      print('Response status: ${response.statusCode}');
      
      return NetworkTestResult(
        success: true,
        message: 'AWS endpoint is reachable',
        details: 'DNS: ${addresses.first.address}, HTTP: ${response.statusCode}',
      );
    } on SocketException catch (e) {
      print('❌ Socket Exception: $e');
      return NetworkTestResult(
        success: false,
        message: 'DNS resolution failed',
        details: 'Emulator cannot resolve AWS hostnames. Try:\n'
            '1. Test on real Android device\n'
            '2. Restart emulator with: -dns-server 8.8.8.8\n'
            '3. Check emulator network settings',
      );
    } catch (e) {
      print('❌ Network test failed: $e');
      return NetworkTestResult(
        success: false,
        message: 'Network test failed',
        details: e.toString(),
      );
    }
  }
}

class NetworkTestResult {
  final bool success;
  final String message;
  final String details;
  
  NetworkTestResult({
    required this.success,
    required this.message,
    required this.details,
  });
}

