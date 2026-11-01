# On-device privacy notes

The app caches wellness days, pending offline outbox entries, the selected theme, and the onboarding completion flag in unencrypted `SharedPreferences` on the device. Android cloud backup and device transfer are disabled for all app data. Signing out does not remove cached preferences; deleting health data clears account health records and the app's wellness cache.

Do not include report photos or health details in support email.
