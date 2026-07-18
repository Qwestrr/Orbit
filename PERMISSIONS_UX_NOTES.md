# Permission request UX

Both Apple and Google require (and review for) a clear, upfront
explanation before an app requests background/"Always" location — this
isn't optional polish, apps get rejected without it.

Recommended flow, to build into `onboarding_screen.dart` before the first
`LocationService.ensurePermissions()` call:

1. A plain-language screen: "Family Circle shares your location with your
   group continuously, including when the app is closed, so they can see
   you on the map and you can get place alerts and crash detection. You
   can turn this off anytime in Settings."
2. Request "while using the app" location first (this is what
   `Geolocator.requestPermission()` gives you initially on both
   platforms).
3. Only after that's granted, prompt for "Always"/background, with a
   second short explanation of specifically why (place alerts + crash
   detection while the phone is locked).
4. Request motion/activity permission (iOS) and notification permission
   separately, each with a one-line reason.

Skipping straight to requesting "Always" location on first launch is a
common reason background-location apps get bounced in App Store /
Play Store review.
