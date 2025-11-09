# Quick Start: AWS Routing Setup

## What to Do in AWS Console (Current Page)

You're on the **"Create API key"** page. Here's what to do:

### Step 1: Name Your API Key
- **Name**: Enter `GraphGoRouteAPIKey` (or any name you prefer)
- **Description**: Optional - e.g., "API key for GraphGo route calculation"

### Step 2: Select Routes Actions (IMPORTANT!)

In the **"Resources and actions"** section, find the **Routes Resource ARN** column:

**Check these boxes:**
- ✅ **CalculateRoutes** - Required for point-to-point routing
- ✅ **OptimizeWaypoints** - Required for multi-stop route optimization
- ✅ **CalculateRouteMatrix** - Optional, useful for distance matrices

**Optional - Places Actions** (if you need geocoding):
- ✅ **Geocode** - Convert addresses to coordinates
- ✅ **ReverseGeocode** - Convert coordinates to addresses

### Step 3: Create the Key
- Click **"Create API key"** button
- **IMPORTANT**: Copy the API key value immediately - you won't be able to see it again!

### Step 4: Configure Your App

1. Create a `.env` file in your project root:
   ```bash
   touch .env
   ```

2. Add your credentials to `.env`:
   ```env
   AWS_API_KEY=paste_your_api_key_here
   AWS_REGION=us-east-1
   AWS_CALCULATOR_NAME=GraphGoRouteCalculator
   ```

3. Make sure you've created a Route Calculator in AWS:
   - Go to Amazon Location Service → Route calculators
   - Create one named `GraphGoRouteCalculator` (or update the name in `.env`)

### Step 5: Test It

Run your Flutter app and try calculating a route. The app will automatically use API key authentication.

## Need Help?

See `AWS_SETUP.md` for detailed instructions and troubleshooting.

