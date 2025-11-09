# AWS Route Calculation Integration

This document explains how to set up and use AWS Location Service for route calculation in GraphGo.

## Setup Instructions

### 1. Create AWS Location Service Calculator

1. Log in to AWS Console
2. Navigate to Amazon Location Service
3. Create a new Route Calculator:
   - Name: `GraphGoRouteCalculator` (or your preferred name)
   - Data Source: Choose Esri or HERE
   - Click "Create calculator"

### 2. Choose Authentication Method

The app supports two authentication methods. **API keys are recommended** for mobile apps.

#### Option A: API Key Authentication (Recommended)

1. In AWS Console, navigate to **Amazon Location Service** → **API keys**
2. Click **"Create API key"**
3. Fill in the form:
   - **Name**: `GraphGoRouteAPIKey` (or your preferred name)
   - **Description**: Optional description
   - **Resources and Actions** - Select these:
     - **Routes Resource ARN** (`arn:aws:geo-routes:us-east-1::provider/default`):
       - ✅ `CalculateRoutes` (required for point-to-point routing)
       - ✅ `OptimizeWaypoints` (required for multi-stop optimization)
       - ✅ `CalculateRouteMatrix` (optional, for distance matrix)
     - **Places Resource ARN** (optional, if you need geocoding):
       - ✅ `Geocode` (to convert addresses to coordinates)
       - ✅ `ReverseGeocode` (to convert coordinates to addresses)
4. Click **"Create API key"**
5. **Save the API key value** - you'll only see it once!

#### Option B: IAM Credentials (Alternative)

1. Go to IAM Console → Users → Create User
2. Attach Policy with these permissions:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "geo:CalculateRoute",
           "geo:CalculateRouteMatrix",
           "geo:OptimizeWaypoints"
         ],
         "Resource": "arn:aws:geo:*:*:route-calculator/*"
       }
     ]
   }
   ```
3. Create Access Keys for the user
4. Save the Access Key ID and Secret Access Key securely

### 3. Configure Environment Variables

1. Create a `.env` file in the project root (copy from `.env.example` if it exists)

2. **For API Key Authentication** (Recommended):
   ```env
   AWS_API_KEY=your_api_key_here
   AWS_REGION=us-east-1
   AWS_CALCULATOR_NAME=GraphGoRouteCalculator
   ```

3. **For IAM Credentials** (Alternative):
   ```env
   AWS_ACCESS_KEY_ID=your_access_key_id_here
   AWS_SECRET_ACCESS_KEY=your_secret_access_key_here
   AWS_REGION=us-east-1
   AWS_CALCULATOR_NAME=GraphGoRouteCalculator
   ```

4. **Important**: Never commit `.env` to version control (it's already in `.gitignore`)

**Note**: The app will automatically detect which authentication method you're using based on the environment variables provided. If `AWS_API_KEY` is present, it uses API key authentication. Otherwise, it falls back to IAM credentials.

### 4. Install Dependencies

Run:
```bash
flutter pub get
```

## Usage

### Using AWS Routing in Code

```dart
import 'package:graph_go/providers/delivery_provider.dart';
import 'package:graph_go/models/route_optimization.dart';

// In your widget/service
final deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);

// Calculate route using AWS
final route = await deliveryProvider.optimizeRoute(
  name: 'My AWS Route',
  algorithm: RouteAlgorithm.aws,
  travelMode: 'Truck', // Options: 'Car', 'Truck', 'Walking'
  optimizationMode: 'FastestRoute', // Options: 'FastestRoute', 'ShortestRoute'
  departureTime: DateTime.now(), // Optional: for traffic-aware routing
);
```

### Route Visualization

Routes calculated with AWS will automatically appear on the map in `HomeScreen`:
- AWS routes are displayed with **purple dashed lines**
- Local algorithm routes are displayed with **solid green lines**
- Markers show start (green), waypoints (blue), and end (red)

## Error Handling

The implementation includes automatic fallback:
- If AWS credentials are missing or invalid, the service falls back to the nearest neighbor algorithm
- Errors are logged and displayed to the user
- The app continues to function even if AWS is unavailable

## API Parameters

### Travel Modes
- `Car`: Standard car routing
- `Truck`: Truck-specific routing (recommended for delivery)
- `Walking`: Pedestrian routing

### Optimization Modes
- `FastestRoute`: Minimizes travel time (default)
- `ShortestRoute`: Minimizes distance

### Optional Parameters
- `departureTime`: DateTime for traffic-aware routing
- `startAddress`: Custom starting point (defaults to first address)

## Cost Considerations

- AWS Location Service charges per request
- Consider caching route results for repeated calculations
- Monitor usage in AWS CloudWatch
- Set up billing alerts to avoid unexpected charges

## Testing

Run tests with:
```bash
flutter test test/services/aws_route_service_test.dart
```

## Troubleshooting

### "AWS Route Service not initialized"
- Ensure `.env` file exists and contains all required variables
- Check that `flutter_dotenv` is loading the file correctly
- Verify credentials are correct
- For API keys: Ensure `AWS_API_KEY` is set correctly
- For IAM: Ensure both `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set

### "AWS API error"
- **For API keys**: Verify the API key has the correct actions enabled (CalculateRoutes, OptimizeWaypoints)
- **For IAM**: Check IAM permissions match the required actions
- Verify calculator name matches exactly (case-sensitive)
- Ensure region is correct (must match where calculator was created)
- Check AWS service status
- Verify API key hasn't expired or been deleted

### Routes not displaying on map
- Ensure addresses have coordinates (latitude/longitude)
- Check that `RouteOptimization.optimizedRoute` is not null
- Verify Google Maps API key is configured

## Security Best Practices

1. **Never commit `.env` files** - Already in `.gitignore`
2. **Use API keys for mobile apps** - More secure than embedding IAM credentials
3. **Restrict API key permissions** - Only enable actions you actually need
4. **Rotate credentials regularly** - Both API keys and IAM access keys
5. **Monitor API usage** in AWS CloudWatch
6. **Set up billing alerts** to avoid unexpected charges
7. **Use IAM roles** instead of access keys when possible (for server-side applications)

## Support

For AWS-specific issues:
- AWS Location Service Documentation: https://docs.aws.amazon.com/location/
- AWS Support: https://aws.amazon.com/support/

For app-specific issues:
- Check the error logs in console
- Verify all dependencies are installed
- Ensure Firebase is properly configured

