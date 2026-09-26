# 🏢 GymOS Biometric Sync Bridge — 1-Time Setup & Windows Background Service
### Compatible with: Windows 7, Windows 8, Windows 10, & Windows 11

Yeh software **1-Time Setup** hota hai. Ek baar install karne ke baad:
- Koi black CMD window khuli rakhne ki zaroorat nahi hai (yeh **100% Silent Background Service** me chalta hai).
- **PC restart ya switch off hoke on hoga**, to yeh apne aap background me start ho jayega.
- Internet chala jaye to machine logs PC ke SQLite WAL storage me rehte hain, jab tak cloud me na chale jayein.

---

### 📂 Root Directory Files:

| File Name | Purpose |
| :--- | :--- |
| **`INSTALL_ONE_TIME_SETUP.bat`** | **👉 Ek baar run karein!** Yeh auto-start register karta hai aur silent background service start kar deta hai. |
| **`CHECK_STATUS.bat`** | Kisi bhi waqt check karne ke liye ki bridge chalu hai ya nahi, aur live log dekhne ke liye. |
| **`STOP_BRIDGE.bat`** | Background bridge ko band karne ke liye. |
| **`UNINSTALL_AUTORUN.bat`** | Auto-start band / remove karne ke liye. |
| **`gymos_bridge_config.json`** | Gym Secret Key aur Machine local IP daalne ke liye. |
| **`GymOS_PC_Biometric_Bridge.zip`** | Kisi bhi gym ko bhejne ke liye 1-click zip file. |

---

### 🚀 2-Minute 1-Time Setup:

1. **Secret Key Paste Karein**:
   - GymOS Mobile App me jayein -> **Owner Attendance Settings** -> **Biometric & Face Recognition Card** -> **Secret Key Copy** karein.
   - PC par `gymos_bridge_config.json` Notepad me open karke `"device_secret"` me paste karein aur Save karein.

2. **1-Time Installer Run Karein**:
   - Simply **`INSTALL_ONE_TIME_SETUP.bat`** par double click karein.
   - Bas! Background service start ho gayi aur Windows Startup me register ho gayi.

3. **Verify Status**:
   - Aap kisi bhi time **`CHECK_STATUS.bat`** par double click karke live status aur attendance upload logs dekh sakte hain!
