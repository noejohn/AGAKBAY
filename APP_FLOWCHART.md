# Agakbay App Flowchart

This flowchart summarizes the current Flutter app flow from startup through authentication, dashboard navigation, hiking, offline maps, and offline activity sync.

## Main User Flow

```mermaid
flowchart TD
    A([Launch Agakbay]) --> B[Splash Screen]
    B --> C{Firebase initialized?}
    C -- No --> D[Show Firebase configuration error]
    C -- Yes --> E[Start auto sync service]
    E --> F{Authenticated user?}

    F -- No --> G[Welcome Screen]
    G --> H[Login Screen]
    H --> I{User action}
    I -- Login --> J{Valid credentials?}
    J -- No --> K[Show login error]
    K --> H
    J -- Yes --> L[Dashboard]

    I -- Forgot password --> M[Forgot Password Screen]
    M --> N[Send reset email]
    N --> H

    I -- Create account --> O[Sign Up Screen]
    O --> P[Create Firebase Auth user]
    P --> Q[Save user profile in Firestore]
    Q --> R[Email Verification Screen]
    R --> S{Email verified?}
    S -- No --> R
    S -- Yes --> G

    F -- Yes --> L

    L --> T{Bottom navigation}
    T -- Explore --> U[Explore Map]
    T -- My Hikes --> V[Completed Hikes List]
    T -- Community --> W[Community Placeholder]
    T -- Profile --> X[Profile Screen]

    U --> Y[Search or select mountain marker]
    Y --> Z[Mountain Details Sheet]
    Z --> AA[Select route, view trail info, weather, and details]
    AA --> AB[Start Hiking]
    AB --> AC[Hiking Mode Screen]
    AC --> AD[Track GPS, distance, duration, elevation, checkpoints]
    AD --> AE{End hike?}
    AE -- No --> AC
    AE -- Yes --> AF[Return hike result]
    AF --> AG[Save completed hike]
    AG --> V

    X --> AH[Offline Maps]
    AH --> AI[Cache sample trail]
    AH --> AJ[Display cached trail]
    AJ --> AK[Trail Display Screen]
    AH --> AL[Download map tiles]
    AH --> AM[Show cache statistics]

    X --> AN[Offline GPS Tracker]
    AN --> AO[Start local activity]
    AO --> AP[Pause or resume activity]
    AP --> AQ[Stop activity]
    AQ --> AR[Activity Summary Screen]
    AQ --> AS[Sync pending activities]

    X --> AT[Sign Out]
    AT --> G
```

## Offline And Data Flow

```mermaid
flowchart LR
    A[Flutter UI] --> B[Firebase Auth]
    A --> C[Cloud Firestore]
    A --> D[Google Maps]
    A --> E[Geolocator GPS]

    B --> F[AuthGate]
    F --> G[Dashboard]

    G --> H[Explore Map]
    H --> I[Mountain Details]
    I --> J[Hiking Mode]
    J --> E
    J --> K[Offline Activity Database]
    J --> L[Completed hike result]
    L --> M[My Hikes tab]
    L --> C

    G --> N[Profile]
    N --> O[Offline Maps Screen]
    O --> P[Offline Map Service]
    O --> Q[Offline Trail Service]
    P --> R[Cached map tiles on device]
    Q --> S[Cached GPX trails on device]
    R --> T[Offline Map Widget]
    S --> T

    N --> U[Offline GPS Tracker]
    U --> V[Activity Tracking Service]
    V --> E
    V --> K
    K --> W[Unsynced finished activities]
    W --> X[Activity Sync Service]
    X --> Y{Network available and user signed in?}
    Y -- No --> K
    Y -- Yes --> C
    C --> Z[Mark activity synced locally]
    Z --> K
```

## Key App Areas

- Startup: `SplashScreen` initializes Firebase and starts `ActivitySyncService`.
- Auth: `AuthGate`, `WelcomeScreen`, `LoginScreen`, `SignUpScreen`, `ForgotPasswordScreen`, and `EmailVerificationScreen`.
- Dashboard: `Explore`, `My Hikes`, `Community`, and `Profile` tabs.
- Hiking: mountain details open `_HikingModeScreen`, which returns a completed hike result to the dashboard.
- Offline maps: `OfflineMapExampleScreen`, `OfflineMapService`, `OfflineTrailService`, and `OfflineMapWidget`.
- Offline tracking: `OfflineActivityTrackerScreen`, `ActivityTrackingService`, `OfflineActivityDatabase`, and `ActivitySyncService`.
