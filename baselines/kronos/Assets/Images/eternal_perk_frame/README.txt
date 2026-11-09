Eternal perk frame packs

Create a subfolder for each style:
  eternal_perk_frame/My Frame/ui_icon_eternalperk.png

From the cod25 folder run:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Refresh-EternalPerkFrames.ps1

Fully restart the game after importing or replacing PNGs. Open Weapons > Custom Perks and click the FRAME button at the bottom to cycle styles. The choice saves automatically. Default uses Assets/Images/ui_icon_eternalperk.png. Frames are local cosmetics, so co-op players can choose different styles.

PNG width and height are read automatically and the aspect ratio is preserved. The image is centered by default. Keep the center transparent if you want to draw over an icon; this HUD draws the frame behind the icon.

Optional frame.json in the same style folder:
  {"referenceSize":256,"scale":1.1,"centerX":160,"centerY":154}

referenceSize is the pixel size of the perk icon for which the frame was designed. Default is 256. centerX/centerY are pixel coordinates in the frame PNG; omitted values use the image center. scale is an extra multiplier; omit it to follow frameScale in bo7_custom_perks_post.lua.

pack_ids.json preserves saved selection IDs. Keep it when adding folders. The generated gcp_eternal_frame_*.png files and bo7_eternal_frame_packs_post.lua are required for the imported styles to render.
