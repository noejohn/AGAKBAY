# Capstone Flowchart: Agakbay Hiking Application

## General System Flowchart

```mermaid
flowchart TD
    A([Start]) --> B[Launch Agakbay Mobile Application]
    B --> C[Display Splash Screen]
    C --> D{Initialize Firebase Services}

    D -- Failed --> E[Display Configuration Error Message]
    E --> Z([End])

    D -- Successful --> F{Is User Authenticated?}

    F -- No --> G[Display Welcome Screen]
    G --> H{Select Authentication Option}

    H -- Log In --> I[Enter Email and Password]
    I --> J{Are Credentials Valid?}
    J -- No --> K[Display Login Error]
    K --> I
    J -- Yes --> L[Open Main Dashboard]

    H -- Sign Up --> M[Enter Account Details]
    M --> N[Create Firebase Account]
    N --> O[Save User Profile to Firestore]
    O --> P[Send Email Verification]
    P --> Q{Is Email Verified?}
    Q -- No --> P
    Q -- Yes --> I

    H -- Forgot Password --> R[Send Password Reset Email]
    R --> I

    F -- Yes --> L

    L --> S{Select Dashboard Feature}

    S -- Explore --> T[View Interactive Map]
    T --> U[Search or Select Mountain Trail]
    U --> V[View Trail Details and Route Information]
    V --> W{Start Hiking Activity?}
    W -- No --> L
    W -- Yes --> X[Open Hiking Mode]

    X --> Y{Location Permission Granted?}
    Y -- No --> Y1[Request Location Permission]
    Y1 --> Y
    Y -- Yes --> Y2[Track GPS Location, Distance, Duration, and Elevation]

    Y2 --> Y3{Internet Connection Available?}
    Y3 -- Yes --> Y4[Use Online Map and Sync Data]
    Y3 -- No --> Y5[Use Offline Map and Save Data Locally]

    Y4 --> Y6[Save Hiking Activity]
    Y5 --> Y6
    Y6 --> Y7{End Hiking Activity?}
    Y7 -- No --> Y2
    Y7 -- Yes --> Y8[Generate Hiking Summary]
    Y8 --> Y9[Store Completed Hike Record]
    Y9 --> L

    S -- My Hikes --> AA[View Completed Hiking Records]
    AA --> L

    S -- Offline Maps --> AB[Cache Trail and Map Data]
    AB --> AC[Display Cached Trail Using Offline Map]
    AC --> L

    S -- Offline GPS Tracker --> AD[Start Offline Activity Tracking]
    AD --> AE[Store Activity Data in Local Database]
    AE --> AF{Network Available?}
    AF -- No --> AE
    AF -- Yes --> AG[Sync Pending Activity Data to Firestore]
    AG --> L

    S -- Profile --> AH[View User Profile]
    AH --> AI{Sign Out?}
    AI -- No --> L
    AI -- Yes --> G
```

## Figure Description

The flowchart presents the general process of the Agakbay mobile hiking application. The system begins by launching the application and initializing Firebase services. If initialization succeeds, the application checks whether the user is already authenticated. New users may create an account, verify their email, or reset their password, while existing users may proceed directly to the main dashboard.

From the dashboard, users can access the major features of the application: exploring mountain trails, starting a hiking activity, viewing completed hikes, using offline maps, tracking offline GPS activities, and managing their profile. During hiking, the application requests location permission, records GPS-based activity data, and determines whether internet connectivity is available. If the device is offline, activity data is stored locally and synced to Firestore once a network connection becomes available.

## Short Caption For Paper

**Figure X. General system flowchart of the Agakbay hiking application showing user authentication, trail exploration, hiking activity tracking, offline storage, and cloud synchronization.**
