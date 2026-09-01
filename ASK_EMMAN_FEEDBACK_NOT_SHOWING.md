# Questions for Emmanuel — mobile feedback isn't showing in the admin dashboard

Copy everything under **PROMPT** and give it to the web system's Claude.

---

> **PROMPT**
>
> The Flutter mobile app now posts feedback to the shared backend at
> `https://tourism-cultural-information-management-kof5.onrender.com/my-app-backend/api/feedback.php`
> with `Authorization: Bearer <api_token>` and a JSON body of
> `{"place": "...", "rating": 1-5, "comment": "...", "reviewer": "..."}`.
>
> A review was submitted successfully from the phone, but it does not appear in
> the website's admin dashboard. Please investigate and answer these
> specifically — the answers determine whether the problem is on the app side
> or the web side.
>
> ### 1. Which database is the website actually reading?
>
> This is the most likely cause. The mobile app writes to the **Render/TiDB**
> database. If the website being viewed is running on localhost and connecting
> to a **local XAMPP MySQL**, it is a different database entirely and the
> mobile review will never appear there.
>
> - What is the website's configured DB host in the environment it is being
>   viewed in?
> - Is the local React app's API base URL pointing at the Render backend, or at
>   `localhost/my-app-backend`?
>
> ### 2. Is the review actually in the Render database?
>
> Query the **TiDB/Render** database directly (not local XAMPP):
> ```sql
> SELECT id, place, rating, comment, reviewer, sentiment, created_at
> FROM reviews ORDER BY id DESC LIMIT 10;
> ```
> - Is the mobile review there?
> - If yes → the app is working and this is purely a web-side display issue.
> - If no → `feedback.php` did not persist it; check its error log.
>
> ### 3. What does the admin dashboard query?
>
> - Which table and which exact query feeds the reviews list?
> - Does it filter by anything the mobile insert might not satisfy — a
>   `status`, `approved`, `is_published`, `source`, `establishment_id`,
>   `place_id`, or date range?
> - Does a review need to be linked to an existing `places` / establishment row
>   to appear? The app sends `place` as a **free-text church or attraction
>   name** (e.g. `"San Felipe Neri Parish Church"`), not an ID. If the
>   dashboard joins on a places table, an unmatched name would be hidden.
>
> ### 4. What does feedback.php require and write?
>
> - What are the required fields, and what does it do if `reviewer` is absent
>   or the place name is unknown?
> - Which columns does it populate, and are any dashboard-required columns left
>   NULL for mobile-submitted rows?
> - Does it return `{"success": true, "id": .., "sentiment": ".."}` exactly?
>
> ### 5. CORS for local development
>
> If the site is being run on localhost against the Render API, confirm the API
> sends CORS headers permitting the localhost origin and answers `OPTIONS`
> preflight. A CORS block shows as an empty list in the UI with a red error in
> the browser console, even though the API itself is fine.
>
> ### 6. Confirm the auth bridge works in production
>
> `POST /api/firebase_login.php` with a real Firebase ID token — does it return
> an `api_token` on the **Render host** (not just locally)? This proves Render
> can reach Google's public keys to verify the token. It also powers the
> website's Google sign-in, so a failure breaks both platforms.
>
> ### 7. Security issue to fix (separate from the bug)
>
> Directory listing is enabled on the deployed backend —
> `/my-app-backend/` returns a browsable index, exposing every `.sql` file
> (`add_admin_pin.sql`, `add_login_security.sql`, `add_password_reset.sql`,
> etc.) to anyone with the URL. Please:
> - add `Options -Indexes` (Apache config or `.htaccess`), and
> - move `.sql` files and any config containing credentials out of the web root
>
> ### What to send back
>
> 1. Whether the mobile review exists in the Render database (§2)
> 2. The dashboard's query and any filters (§3)
> 3. Confirmation of which DB the viewed website connects to (§1)
> 4. Whether `firebase_login.php` works on the live host (§6)

---

## Notes for the humans (do not paste)

- The app's side is already verified: `api/visits.php` returns
  `{"error":"Unauthorized. Please log in again."}` in a browser, so the API
  layer and auth guard are working on Render.
- If §2 shows the review IS in the Render database, no app changes are needed —
  it is entirely a web display/config issue.
