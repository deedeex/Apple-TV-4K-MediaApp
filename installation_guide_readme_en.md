# How to Install the App on Apple TV Using Xcode

Since this application is not distributed via the App Store or TestFlight, building and installing it requires using **Xcode** and your own (free) Apple ID account.

The installation process takes about 5 minutes and involves a few simple configuration steps.

## Prerequisites

* A Mac computer with **Xcode** installed (available for free in the Mac App Store).

* An **Apple TV** connected to the same Wi-Fi network as your Mac.

* A personal Apple ID account.

## Step-by-Step Instructions

### 1. Download the Project

Download the source code from this repository (or clone it using Git) and open the `.xcodeproj` or `.xcworkspace` file in Xcode.

### 2. Add Your Apple ID in Xcode

1. In Xcode, navigate to the top menu: **Xcode > Settings** (or *Preferences*).

2. Click on the **Accounts** tab.

3. Click the **`+`** button in the bottom-left corner and add your Apple ID.

### 3. Change Team and Bundle Identifier

Since Apple identifiers are bound to specific developer accounts, you need to update two settings in the project:

1. In the left navigator pane, select the main project file (the top item).

2. Select the main app target under the **Targets** section.

3. Go to the **Signing & Capabilities** tab.

4. Make sure **Automatically manage signing** is checked.

5. Under **Team**, select your account from the dropdown list (typically listed as `Your Name (Personal Team)`).

6. In the **Bundle Identifier** field, change the default string (e.g., from `com.creator.MyApp`) to your own unique string (e.g., `com.yourname.MyApp`).

   *(Without this change, Xcode will throw an error regarding missing permissions for the original creator's identifier).*

### 4. Pair Apple TV with Xcode

1. Ensure both your Mac and Apple TV are connected to the same Wi-Fi network.

2. On your Apple TV, go to: **Settings > Remotes and Devices > Xcode** (or *Remote app and devices*).

3. In Xcode on your Mac, go to the top menu: **Window > Devices and Simulators** (shortcut: `Shift + Cmd + 2`).

4. Select your Apple TV from the list on the left and click **Connect**.

5. Enter the PIN code shown on your TV screen to complete the pairing.

### 5. Build and Run the App

1. In the top bar of Xcode (next to the *Play/Build* button), select your paired **Apple TV** as the destination device.

2. Click the **Play (Run)** button or press `Cmd + R` to compile and install the app on your Apple TV.

## Troubleshooting & Important Notes

### "Untrusted Developer" Error

If you encounter an "Untrusted Developer" prompt when launching the app on Apple TV:

1. On your Apple TV, go to: **Settings > General > Profiles & Device Management**.

2. Select your Apple ID / developer profile from the list.

3. Click **Trust \[Your Apple ID\]** and confirm.

### Installation Validity (7 Days)

If you are using a free Apple ID account, the free provisioning profile expires after **7 days**. After this period, the app will no longer open on your Apple TV. To use it again, simply connect your Mac, open the project in Xcode, and click **Run** (`Cmd + R`) again.