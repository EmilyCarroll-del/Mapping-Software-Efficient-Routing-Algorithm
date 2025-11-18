# Server Setup for Address Autocomplete

This server acts as a proxy for Google Places API to avoid CORS issues and keep your API key secure.

## Setup Instructions

1. **Install dependencies** (if not already installed):
   ```bash
   cd server
   npm install
   ```

2. **Create a `.env` file** in the `server` directory:
   ```bash
   PLACES_API_KEY=your_google_places_api_key_here
   PORT=3000
   ```

3. **Get a Google Places API Key**:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select an existing one
   - Enable the "Places API" (not "Places API (New)")
   - Create credentials (API Key)
   - **IMPORTANT**: When restricting the API key:
     - ✅ **DO**: Restrict by "API restrictions" → Select "Places API"
     - ✅ **DO**: Use "IP address restrictions" if you want to restrict by server IP
     - ❌ **DON'T**: Use "HTTP referrer restrictions" - these don't work with server-side calls
     - If you see "REQUEST_DENIED: API keys with referer restrictions cannot be used with this API", remove the referrer restrictions from your API key

4. **Start the server**:
   ```bash
   node index.cjs
   ```
   
   Or use npm:
   ```bash
   npm start
   ```

   You should see: `Notifier + Places proxy on http://localhost:3000`

5. **Keep the server running** while using the Flutter web app.

## Troubleshooting

- **"Server not running" error**: Make sure the server is started on port 3000
- **"API key not configured" error**: Check that `PLACES_API_KEY` is set in the `.env` file
- **"REQUEST_DENIED: API keys with referer restrictions cannot be used with this API"**:
  - Go to [Google Cloud Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials)
  - Click on your API key
  - Under "Application restrictions", change from "HTTP referrers" to either:
    - "None" (for development - less secure)
    - "IP addresses" (for production - add your server's IP address)
  - Save the changes and wait 1-2 minutes for changes to propagate
- **CORS errors**: The server should handle CORS automatically with the `cors` package
- **Port already in use**: Change the `PORT` in `.env` or stop the process using port 3000

## Note

The `.env` file should NOT be committed to version control. Add it to `.gitignore`.


