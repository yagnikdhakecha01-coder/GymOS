# Phase 28: Attendance Display Integration into GymOS Info Website & Production Deployment (gymos.tech/attendance)

## Goal
Integrate the standalone GymOS Attendance Display TV/Tablet web client (`attendance_display_website/`) directly into the production GymOS static web infrastructure (`website/`, deployed from `JigarGamer0/gym-os-info-website` to `gymos.tech`). Ensure the display is live and accessible at `https://gymos.tech/attendance` (with fallback aliases), add prominent "Attendance Display" buttons to the landing page navigation and hero sections, preserve 100% functionality of the existing landing page and Flutter Web Portal (`/portal/*`), update the Flutter app display link generator to point to production, and push to GitHub so it automatically deploys live to `gymos.tech`.

---

## Architecture & Routing Blueprint

```
+----------------------------------------------------------------------------------------------------+
|                                    GYMOS.TECH WEB ARCHITECTURE                                     |
|                                                                                                    |
|  1. ROOT LANDING PAGE:                                                                             |
|     - URL: https://gymos.tech/                                                                     |
|     - File: website/index.html + css/ + js/ + images/                                              |
|     - Updates: Add "Attendance" button to Navbar and Hero section alongside "Web Portal".          |
|                                                                                                    |
|  2. WEB PORTAL (FLUTTER SPA):                                                                      |
|     - URL: https://gymos.tech/portal/*                                                             |
|     - Directory: website/portal/ (index.html, main.dart.js, assets/, canvaskit/)                  |
|     - Status: STRICTLY PRESERVED & UNTOUCHED - No modifications to existing build.                 |
|                                                                                                    |
|  3. ATTENDANCE DISPLAY (STANDALONE WEB CLIENT):                                                    |
|     - URL: https://gymos.tech/attendance (and /attenadce typo redirect)                            |
|     - Directory: website/attendance/                                                               |
|     - Files: index.html, app.js                                                                    |
|     - Features:                                                                                    |
|       * Direct Handshake if ?display_id=xxx is present in URL.                                     |
|       * Elegant Pairing/Input screen if opened directly from website without ?display_id parameter.|
|       * LocalStorage persistence of Display ID for smart TVs & front desk tablets.                 |
|       * Realtime Supabase dynamic QR rotation & attendance sound alerts.                           |
|                                                                                                    |
|  4. CLOUDFLARE/NETLIFY ROUTING:                                                                    |
|     - website/_redirects:                                                                          |
|         /portal/*        /portal/index.html        200                                             |
|         /attendance      /attendance/index.html    200                                             |
|         /attendance/*    /attendance/index.html    200                                             |
|         /attenadce       /attendance/index.html    301                                             |
|         /attenadce/*     /attendance/index.html    301                                             |
|     - website/_headers: Security headers, CORS, and cache controls for /attendance/*               |
+----------------------------------------------------------------------------------------------------+
```

---

## Detailed Task Breakdown

### Task 1: Setup `/attendance/` Web Assets in `website/` Repo
- Copy `attendance_display_website/index.html` and `attendance_display_website/app.js` into `website/attendance/`.
- Ensure all relative script and stylesheet paths (`app.js`, CDN links for Tailwind, Lucide, Supabase JS, QRCode.js) are valid and functional.
- Enhance `app.js` and `index.html`:
  - When `?display_id=` is missing from the query string:
    - Instead of showing a static configuration error, render a sleek pairing screen with an input field: `[ Enter Display ID / Pairing Code ]` and a "Launch Display" button.
    - Provide clear guidance: *"To launch your front-desk attendance screen, copy your unique Display Link from GymOS App (Settings > Attendance Display) or enter your Display ID above."*
    - Cache the last verified `display_id` in `localStorage` so refreshing on a gym tablet/TV retains the connection without requiring re-entry.

### Task 2: Configure Server Routing & Headers (`_redirects` & `_headers`)
- Update `website/_redirects` to include:
  ```
  # Attendance Display Web App
  /attendance        /attendance/index.html    200
  /attendance/*      /attendance/index.html    200
  /attenadce         /attendance/index.html    301
  /attenadce/*       /attendance/index.html    301
  ```
- Update `website/_headers` to ensure `/attendance/*` has appropriate headers (CORS, no-cache for instant dynamic QR updates).

### Task 3: Add "Attendance" Access Buttons to `website/index.html`
- In the **Navbar** (`<div class="navbar__links">`):
  - Add an "Attendance" link / button alongside Google Play, App Store, and Web Portal:
    ```html
    <a href="attendance/" class="navbar__cta navbar__cta--attendance" style="background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.15);color:#fff;font-weight:600;display:inline-flex;align-items:center;">
      <svg ...> [QR / Monitor icon] </svg>
      Attendance Display
    </a>
    ```
- In the **Hero Actions** (`<div class="hero__actions">`):
  - Add an "Attendance Display" button:
    ```html
    <a href="attendance/" class="btn btn--outline" style="border-color:rgba(108,58,237,0.4);color:#c4b5fd;">
      <svg ...> [Screen icon] </svg>
      Attendance Display
    </a>
    ```
- Verify mobile navigation drawer (`#navLinks` responsive drawer) correctly displays the new button without breaking menu layout.

### Task 4: Update Display Link Generator in App & Portal Codebases
- Update `getOrGenerateDisplayLink()` in `lib/core/repository/gym_repository.dart` and `gymos_web/lib/core/repository/gym_repository.dart`:
  - Replace `http://localhost:8080/attendance_display_website/index.html?display_id=$publicId`
  - With `https://gymos.tech/attendance?display_id=$publicId`
- Ensure owners who copy or share the display link from mobile app or web portal receive the live `gymos.tech/attendance` URL.

### Task 5: Zero-Regression Local Verification
- Start local HTTP server serving `website/`.
- Verify:
  1. `http://localhost:[port]/` loads GymOS landing page with working buttons, styles, and zero console errors.
  2. `http://localhost:[port]/portal/` loads Flutter Web Portal login page normally without breaking.
  3. `http://localhost:[port]/attendance/` loads the Attendance Display with the new pairing UI.
  4. `http://localhost:[port]/attendance/?display_id=[test_id]` connects directly and displays live clock, QR code container, and status indicators.

### Task 6: Commit and Push to `gym-os-info-website`
- Stage and commit all changes in `website/` (`attendance/`, `index.html`, `_redirects`, `_headers`).
- Push branch `main` to `origin` (`https://github.com/JigarGamer0/gym-os-info-website.git`).
- Stage and commit the Flutter repository changes in root (`lib/`, `gymos_web/`, `.planning/`).
- Verify production deployment trigger on `gymos.tech`.

---

## Verification Criteria
1. `gymos.tech/attendance` correctly serves the attendance display client.
2. `gymos.tech/portal/` remains completely unharmed and fully functional.
3. `gymos.tech` landing page has a sleek, responsive Attendance Display button in header and hero.
4. If an owner opens the attendance display link generated from the app (`gymos.tech/attendance?display_id=...`), it immediately pairs with the gym's live dynamic QR code system.
