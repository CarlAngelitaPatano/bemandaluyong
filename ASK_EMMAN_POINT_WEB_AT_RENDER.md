# For Emmanuel — point the website at the Render backend

Copy everything under **PROMPT** and give it to the web system's Claude.

---

> **PROMPT**
>
> ## Diagnosis is confirmed — this is a config issue, not a bug
>
> The mobile app's feedback **is** reaching the shared backend. Verified in the
> TiDB SQL Editor:
>
> ```
> place                          reviewer      rating  sentiment  comment          created_at
> San Felipe Neri Parish Church  Patano Carl   4       Positive   New data sets    2026-09-01 12:34:46
> St. Francis of Assisi          Anonymous     5       Positive   New system       2026-09-01 12:33:20
> ```
>
> Two notes on that:
> - `reviewer: "Patano Carl"` is the tester's Firebase display name, and
>   `"Anonymous"` is the app's "send anonymously" checkbox — neither can come
>   from the web form. These are definitely app submissions.
> - **`created_at` is stored in UTC.** `12:34 UTC` = `8:34 PM` Manila, which is
>   when they were submitted. Earlier confusion about the timestamps was a
>   timezone issue, not stale data.
>
> Meanwhile the admin dashboard at `localhost:5173/admin/sentiment` shows
> **nothing newer than Aug 27** (`user1`, `user77`). TiDB has entries from
> Sept 1.
>
> **Conclusion: the website being run locally is reading the local XAMPP
> database, not the Render/TiDB one.** Two different databases.
>
> ## What to change
>
> Point the React app's API base URL at the deployed backend:
>
> ```
> VITE_API_BASE_URL=https://tourism-cultural-information-management-kof5.onrender.com/my-app-backend
> ```
>
> (in `.env` / `.env.local`, or whatever the project uses for the API host),
> then restart `npm run dev` and reload `/admin/sentiment`.
>
> Expected result: the two September reviews appear in Review Management, and
> the older `user1` / `user77` rows disappear — those exist only in local
> XAMPP. That is correct; TiDB is the shared database now.
>
> ## Please also confirm
>
> 1. **CORS** — a browser page on `http://localhost:5173` calling the Render
>    API is cross-origin. Confirm the API sends CORS headers allowing that
>    origin and answers `OPTIONS` preflight. Symptom if not: the table renders
>    empty while the browser console shows "blocked by CORS policy", even
>    though the API works.
>
> 2. **Is there anywhere else still hardcoded to localhost?** Any other service
>    file, fetch call, or config that would keep part of the site pointed at
>    XAMPP while the rest uses Render.
>
> 3. **For the defense** — is the plan to deploy the React frontend (Render
>    hosts static sites free), or to demo from `localhost`? A deployed frontend
>    makes the "phone and web share one database" story much cleaner, and
>    avoids the question of whether the system is actually online.
>
> ## Two follow-ups from earlier, still open
>
> - **Rotate the TiDB password.** The database user and password were shared in
>   plain text while debugging. Please reset the credential in the TiDB Cloud
>   console and keep it only in Render's environment variables.
>
> - **Disable directory listing.** `/my-app-backend/` currently returns a
>   browsable index exposing every `.sql` file (`add_admin_pin.sql`,
>   `add_login_security.sql`, `add_password_reset.sql`, …) to anyone with the
>   URL. Add `Options -Indexes` and move `.sql` / config files out of the web
>   root.

---

## Notes for the humans (do not paste)

- Nothing needs to change in the Flutter app. Feedback, the Firebase→TCIMS
  token exchange, and server-side sentiment classification are all verified
  working against the live Render backend.
- Once the env variable is changed, the "check in on the phone, see it on the
  web" demo works for the first time.
