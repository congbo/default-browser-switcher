# Clean Machine Checklist

1. Export release credentials and run `./Tools/Release/build-release.sh`.
2. Verify the exported artifact with `./Tools/Release/verify-artifact.sh build/release/exported/DefaultBrowserSwitcher.app build/release/DefaultBrowserSwitcher-macOS-Universal.zip`.
3. Unzip the final artifact and move `DefaultBrowserSwitcher.app` into `/Applications`.
4. Run `./Tools/Release/verify-installed-app.sh /Applications/DefaultBrowserSwitcher.app`.
5. Launch the installed app outside Xcode and confirm the browser list loads.
6. Switch the default browser once from the installed build and confirm macOS updates the system default browser.
7. Confirm `Refresh` keeps the browser list usable, and if you can reproduce a failed or stale switch state, confirm `Retry` helps recover.
