## GraphGo Environment Setup

Create a `.env` file in the project root (alongside `pubspec.yaml`) and paste the following keys. Replace the placeholder values with your real AWS credentials.

```env
# AWS Location Service API key (preferred)
AWS_API_KEY=YOUR_AWS_LOCATION_API_KEY

# AWS region where all Location Service resources were created
AWS_REGION=us-east-1

# Resource names (case-sensitive) from your AWS Location Service console
AWS_MAP_NAME=GraphGo
AWS_PLACE_INDEX_NAME=GraphGo-Place
AWS_ROUTE_CALCULATOR_NAME=GraphGo-Route
AWS_TRACKER_NAME=GraphGo-Tracker
AWS_GEOFENCE_COLLECTION_NAME=GraphGo-Geo

# Optional: endpoint override for VPC endpoints (leave empty if not used)
# AWS_ENDPOINT_OVERRIDE=https://your-custom-endpoint.amazonaws.com

# Optional: IAM credentials if you prefer SigV4 auth instead of API key
# AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY
# AWS_SECRET_ACCESS_KEY=YOUR_SECRET_ACCESS_KEY
```

> ⚠️ **Do not commit the `.env` file** to version control. It contains secrets and is ignored by Git via `.gitignore`.


