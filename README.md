# GraphGo

A Flutter application for graph visualization and analysis.

## Features

- Interactive graph visualization
- Add and remove nodes
- Create connections between nodes
- Customizable appearance settings
- Modern Material Design 3 UI

## Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK
- Android Studio or VS Code with Flutter extensions

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Run `flutter pub get` to install dependencies
4. Run `flutter run` to start the app

### Project Structure

```
lib/
├── main.dart                 # App entry point
├── screens/                  # UI screens
│   ├── home_screen.dart     # Main home screen
│   ├── graph_screen.dart    # Graph visualization screen
│   └── settings_screen.dart # Settings and preferences
└── providers/               # State management
    └── graph_provider.dart  # Graph data management
```

## Usage

1. Launch the app to see the welcome screen
2. Tap "Start Graphing" to begin creating your graph
3. Use the "+" button to add nodes
4. Configure appearance in the Settings screen

## Dependencies

- `go_router`: Navigation and routing
- `provider`: State management
- `flutter_svg`: SVG support
- `cupertino_icons`: iOS-style icons

## License

This project is licensed under the MIT License.
