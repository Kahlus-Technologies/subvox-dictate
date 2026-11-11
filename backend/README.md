# Subvox Dictate backend (Convex)

Opt-in research uploads. No accounts: each install sends a random UUID.

- Prod: `https://honorable-manatee-356.convex.cloud` (the app's default)
- Dev: `https://insightful-orca-743.convex.cloud` (set `SUBVOX_BACKEND` to use it)
- Dashboard: Convex team `aayu22809`, project `subvox-dictate`

Flow: `uploads:consent` once, then per dictation `uploads:uploadUrl` -> POST zip -> `uploads:finishUpload`.
The server refuses uploads without current consent, audio the user didn't agree to share, files over 20 MB,
more than 500 sessions a day per install, and bad names. `uploads:deleteMyData` erases an install's files and
withdraws consent. A daily cron deletes files that were uploaded but never registered.

Get the data: `npx convex run admin:sessionFiles '{"installId":"..."}'` returns download URLs.

    npm install
    npx convex dev --once      # push to dev
    npx convex deploy -y       # push to prod
    python3 test_backend.py <deployment url>   # 11 end-to-end checks; cleans up after itself

When the consent text in `Hex/Clients/SubvoxSharing.swift` changes, bump `CONSENT_VERSION` in
`convex/uploads.ts` and `consentVersion` in the app together.
