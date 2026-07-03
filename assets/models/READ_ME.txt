3D MODELS FOR THE AR / 3D VIEWER
================================

Put one .glb 3D model per church here. The app links each model
automatically by filename (same base name as the church photo), so no code
change is needed — just drop the file in and rebuild (full `flutter run`).

Expected filenames (must match EXACTLY, lowercase, ending in .glb):

  san_felipe_neri.glb      -> San Felipe Neri Parish Church
  divine_mercy.glb         -> Archdiocesan Shrine of the Divine Mercy
  san_roque_barangka.glb   -> San Roque de Barangka Parish Church
  st_francis_assisi.glb    -> St. Francis of Assisi Parish Church
  st_dominic_savio.glb     -> St. Dominic Savio Parish Church
  santuario_san_jose.glb   -> Santuario de San Jose Parish Church
  our_lady_abandoned.glb   -> Our Lady of the Abandoned Parish
  our_lady_fatima.glb      -> Our Lady of Fatima Parish Church
  sacred_heart.glb         -> Sacred Heart of Jesus Parish Church

Until a church's .glb is added, the AR page shows a sample model so you can
still test that AR works on your phone.

TIPS
----
- Format: .glb (binary glTF). Keep files small (a few MB) so they load fast.
- Free sources: Sketchfab (downloadable as glTF/.glb), Google Poly archives,
  or export from Blender (File > Export > glTF Binary .glb).
- Watch out for Windows hiding extensions: make sure the file is really
  "san_felipe_neri.glb" and not "san_felipe_neri.glb.glb".
