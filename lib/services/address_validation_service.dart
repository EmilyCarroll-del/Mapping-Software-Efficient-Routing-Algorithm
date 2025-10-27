import 'dart:convert';
import 'package:http/http.dart' as http;
import '../main.dart'; // To get the API key

class AddressValidationService {
  static const String _apiEndpoint =
      "https://addressvalidation.googleapis.com/v1:validateAddress?key=$googleApiKey";

  static Future<Map<String, dynamic>> validateAddress(String address) async {
    final response = await http.post(
      Uri.parse(_apiEndpoint),
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
