import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class AddressValidationService {

  static Future<Map<String, dynamic>> validateAddress(String address) async {
    // Load the key from environment variables
    final googleApiKey = dotenv.env['GOOGLE_API_KEY'];

    if (googleApiKey == null || googleApiKey.isEmpty) {
      throw Exception('GOOGLE_API_KEY not found in .env file. Please add it.');
    }

    final String apiEndpoint =
      "https://addressvalidation.googleapis.com/v1:validateAddress?key=$googleApiKey";

    final response = await http.post(
      Uri.parse(apiEndpoint),
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
