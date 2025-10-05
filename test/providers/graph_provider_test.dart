import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:graph_go/providers/graph_provider.dart';
import 'package:graph_go/models/delivery_address.dart';
import 'google_api_service_test.mocks.dart'; // import the generated mock
import 'package:graph_go/services/google_api_service.dart';

void main() {
  late GraphProvider graphProvider;
  late MockGoogleApiService mockApi;

  setUp(() {
    mockApi = MockGoogleApiService();
    // Make sure GraphProvider accepts GoogleApiService via constructor
    graphProvider = GraphProvider(apiService: mockApi);
  });

  test('buildGraphFromAddresses populates graph correctly', () async {
    // Step 1: Create test addresses
    final testAddresses = [
      DeliveryAddress(
        streetAddress: '1600 Amphitheatre Parkway',
        city: 'Mountain View',
        state: 'CA',
        zipCode: '94043',
      ),
      DeliveryAddress(
        streetAddress: '1 Infinite Loop',
        city: 'Cupertino',
        state: 'CA',
        zipCode: '95014',
      ),
      DeliveryAddress(
        streetAddress: '500 Terry A Francois Blvd',
        city: 'San Francisco',
        state: 'CA',
        zipCode: '94158',
      ),
    ];

    // Step 2: Mock GoogleApiService responses
    when(mockApi.geocodeAddresses(any)).thenAnswer((_) async => {
      testAddresses[0].fullAddress: LatLng(37.422, -122.084),
      testAddresses[1].fullAddress: LatLng(37.331, -122.030),
      testAddresses[2].fullAddress: LatLng(37.770, -122.387),
    });

    when(mockApi.getDistanceMatrix(any)).thenAnswer((_) async => [
      [0, 1000, 2000],
      [1000, 0, 1500],
      [2000, 1500, 0],
    ]);

    // Step 3: Run the method under test
    await graphProvider.buildGraphFromAddresses(testAddresses);

    // Step 4: Verify coordinates were populated
    for (var addr in testAddresses) {
      expect(addr.hasCoordinates, true);
    }

    // Step 5: Verify distance matrix
    expect(graphProvider.matrix!.length, 3);
    expect(graphProvider.matrix![0][1], 1000);

    // Step 6: Verify digraph adjacency
    expect(graphProvider.graph!.adj[0].length, 2); // edges to node 1 & 2

    // Step 7: Test shortest path computation
    final result = graphProvider.shortestRoute(0, 2);
    expect(result['path'], isNotEmpty);
    expect(result['distanceSeconds'], 2000);
  });
}

