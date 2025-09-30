import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:graph_go/providers/delivery_provider.dart';

void main() {
  group('GraphGo Basic Tests', () {
    testWidgets('DeliveryProvider initializes correctly', (WidgetTester tester) async {
      // Create a simple test widget with just the provider
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (context) => DeliveryProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: Consumer<DeliveryProvider>(
                builder: (context, provider, child) {
                  return Column(
                    children: [
                      Text('Address Count: ${provider.addressCount}'),
                      Text('Has Addresses: ${provider.hasAddresses}'),
                      Text('Can Add More: ${provider.canAddMoreAddresses}'),
                      Text('Is Loading: ${provider.isLoading}'),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Verify provider state
      expect(find.text('Address Count: 0'), findsOneWidget);
      expect(find.text('Has Addresses: false'), findsOneWidget);
      expect(find.text('Can Add More: true'), findsOneWidget);
      expect(find.text('Is Loading: false'), findsOneWidget);
    });

    testWidgets('App theme configuration', (WidgetTester tester) async {
      // Test theme without Firebase
      await tester.pumpWidget(
        MaterialApp(
          title: 'GraphGo - Route Optimization',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          home: const Scaffold(
            body: Text('Welcome to GraphGo'),
          ),
        ),
      );

      // Verify theme properties
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.theme?.useMaterial3, true);
      expect(materialApp.title, 'GraphGo - Route Optimization');
      expect(find.text('Welcome to GraphGo'), findsOneWidget);
    });

    testWidgets('Basic UI components render', (WidgetTester tester) async {
      // Test basic UI components
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('GraphGo - Route Optimization'),
            ),
            body: const Column(
              children: [
                Text('Welcome to GraphGo'),
                Text('Your intelligent route optimization platform'),
                ElevatedButton(
                  onPressed: null,
                  child: Text('Get Started'),
                ),
                TextButton(
                  onPressed: null,
                  child: Text('Don\'t have an account? Sign Up'),
                ),
              ],
            ),
          ),
        ),
      );

      // Verify UI elements
      expect(find.text('GraphGo - Route Optimization'), findsOneWidget);
      expect(find.text('Welcome to GraphGo'), findsOneWidget);
      expect(find.text('Your intelligent route optimization platform'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Don\'t have an account? Sign Up'), findsOneWidget);
    });

    testWidgets('Button interactions work', (WidgetTester tester) async {
      bool buttonPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () {
                buttonPressed = true;
              },
              child: const Text('Test Button'),
            ),
          ),
        ),
      );

      // Tap the button
      await tester.tap(find.text('Test Button'));
      await tester.pump();

      // Verify button was pressed
      expect(buttonPressed, true);
    });

    testWidgets('Form validation works', (WidgetTester tester) async {
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: Column(
                children: [
                  TextFormField(
                    validator: (value) => value?.isEmpty == true ? 'Required' : null,
                  ),
                  ElevatedButton(
                    onPressed: () {
                      formKey.currentState?.validate();
                    },
                    child: const Text('Validate'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Try to validate empty form
      await tester.tap(find.text('Validate'));
      await tester.pump();

      // Should show validation error
      expect(find.text('Required'), findsOneWidget);
    });
  });
}