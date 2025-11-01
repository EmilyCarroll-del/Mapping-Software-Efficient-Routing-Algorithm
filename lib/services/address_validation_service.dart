import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart'; // central config for API keys and constants

class AddressValidationService {
  static const String _baseEndpoint =
      "https://addressvalidation.googleapis.com/v1:validateAddress";

  static Future<Map<String, dynamic>> validateAddress(String address) async {
    final uri = Uri.parse('$_baseEndpoint?key=$googleApiKey');
    final response = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "address": {
          "regionCode": "US", // Assuming US for now
          "addressLines": [address]
        }
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to validate address: ${response.body}');
    }
  }
}
