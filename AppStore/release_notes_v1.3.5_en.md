# v1.3.5 Release Notes (for App Store submission)

```
• Fixed an issue where the source video's frame rate could be detected incorrectly, causing a 30 FPS video to be treated as 60 FPS. The video list and the exported video now both match the original frame rate

• When you add a scoreboard to video shot at 120 FPS or 240 FPS, such as slow motion, it is now exported at 60 FPS. This keeps export times and file sizes from becoming impractically large. Exporting without a scoreboard keeps the original frame rate

• Fixed an issue where temporary files could stay on your device after importing video from the photo library, so free space would not come back even after deleting the video in the app. Files left behind by earlier versions are now removed automatically when the app starts
```
