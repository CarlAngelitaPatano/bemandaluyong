# Website Integration — Pending Decision

**Status:** PINNED / not yet done
**Owner:** Emmanuel (website), Carl (app)

---

## The issue

The mobile app and the website currently have **two separate account systems**:

| | Mobile app | Website (TCIMS) |
|---|---|---|
| Hosting | Android | InfinityFree (PHP/MySQL) |
| Login | Firebase Authentication | Own MySQL user table (Username field) |
| Admin check | Firestore `staff/{uid}` | Its own admin flag |
| Data | Firestore | MySQL (assumed) |

A CCAT officer would need **two different accounts**. This contradicts the
paper's claim of one centralized cross-platform system, and a panelist will
likely ask about it.

## The fix (recommended)

Emmanuel switches the website's login to the **Firebase JS SDK (client-side)**.
This also sidesteps InfinityFree's block on server-side outbound calls, because
all Firebase traffic happens in the browser, not on his server.

Then:

1. Website login uses Firebase Auth (same accounts as the app)
2. After login, check whether `staff/{uid}` exists → if yes, show the admin dashboard
3. Read/write the same Firestore collections the app uses

Result — the defensible answer:

> "A single CCAT officer account manages the system from both the mobile app
> and the web dashboard, with permissions controlled by one shared staff
> registry."

---

## Firebase project

```
projectId          be-mandaluyong-4sight
authDomain         be-mandaluyong-4sight.firebaseapp.com
storageBucket      be-mandaluyong-4sight.firebasestorage.app
messagingSenderId  350180192875
web apiKey         AIzaSyCZ-jZJt0c7e3fD3D0BYvGBdpA1Gj5Spao
web appId          1:350180192875:web:5e0b98e888aa14a25cf72e
measurementId      G-VTRW5BNQ14
```

(These client keys are not secrets — they are safe in web/app code. Only a
service-account private key must never be committed.)

---

## Shared Firestore collections

### `users/{uid}` — trail progress (written by the app)
```
displayName      string
email            string
userType         string    'Tourist' | 'Mandaleño'
visitedChurches  array<string>
visitedCount     number
trailCompleted   bool
completedAt      timestamp
lastSyncedAt     timestamp
platform         string    last client that wrote ('mobile')
```

### `feedback/{id}` — visitor feedback + sentiment
```
message         string    the text analysed by NLP
rating          number    1-5
category        string
name, email, userId
userType        string
source          string    'mobile' | 'web'
sentiment       string    'positive' | 'neutral' | 'negative'
sentimentScore  number
createdAt       timestamp
```

### `accreditations/{id}` — policy management
```
businessName, businessType, ownerName, address, contact,
permitNumber, email, userId
status          string    'pending' | 'under_review' | 'approved' | 'rejected'
requirements    map<string, bool>
submittedAt, updatedAt   timestamp
reviewedBy      string    staff email (set on review)
source          string
```

### `announcements/{id}` — official city announcements
```
title        string
body         string
category     string    'General' | 'Advisory' | 'Event' | 'Emergency'
author       string
pinned       bool
publishedAt  timestamp
postedBy     string
```

### `staff/{uid}` — who is a CCAT officer
```
role  string   e.g. 'officer'
```

---

## Staff check (website JS)

```js
import { doc, getDoc } from "firebase/firestore";

async function isStaff(uid) {
  const snap = await getDoc(doc(db, "staff", uid));
  return snap.exists();
}
```

---

## Security rules currently published

Only staff can approve accreditations or publish announcements; users can only
read/write their own progress. See Firebase Console → Firestore → Rules.
