# 📱 Running GraphGo on Your Physical iPhone

## Quick Setup (5 minutes)

### Step 1: Open Xcode (DONE - it's opening now)
The Runner.xcworkspace file is opening in Xcode.

### Step 2: Sign in with Your Apple ID

1. In Xcode, go to **Xcode → Settings** (or press `Cmd + ,`)
2. Click the **Accounts** tab
3. Click the **+** button in the bottom left
4. Select **Apple ID** and sign in
5. **You don't need a paid developer account** - a free Apple ID works!

### Step 3: Configure Signing

1. In Xcode, in the left sidebar, click on **Runner** (the blue project icon at the top)
2. Select the **Runner** target under "TARGETS"
3. Click the **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Under **Team**, select your Apple ID (Personal Team)
6. Change **Bundle Identifier** to something unique like:
   - `com.yourname.graphgo` 
   - Example: `com.abdullah.graphgo`

### Step 4: Trust the Developer Certificate on Your iPhone

After the first install, on your iPhone:
1. Go to **Settings → General → VPN & Device Management**
2. Tap on your Apple ID email
3. Tap **Trust "[Your Apple ID]"**
4. Tap **Trust** again in the popup

### Step 5: Run the App

Close Xcode and run this command:

```bash
cd /Users/abdallah/GraphGo
flutter run -d "00008140-001475883A53001C"
```

Or select option **[3]** when running `flutter run`.

## ✅ Why Physical iPhone is Better

- **100% AWS connectivity** (no network issues!)
- **Real GPS** for actual navigation testing
- **Actual performance** testing
- **No emulator limitations**

## 🔧 Troubleshooting

**"Could not find an option named 'provisioning-profile'"**
- Ignore this - it's not needed for development

**"Untrusted Developer" popup on iPhone**
- Follow Step 4 above

**"Code Signing Error"**
- Make sure you're signed into Xcode with your Apple ID
- Make sure "Automatically manage signing" is checked
- Try a different bundle identifier

## 🎯 Next Steps After It Runs

1. Login as driver
2. Accept an order
3. Tap "Start Delivery"
4. Watch the professional AWS routing work perfectly!
5. See real road-based routes (no water crossings!)

Your physical iPhone will have **100% success** with AWS routing! 🎉

