# Onion Grading Dataset — merged, cleaned & balanced (YOLOv8 format)

Built for: detect + count onions in a single multi-onion photo, and classify
each one as **healthy / damaged / rotten / sprouted** (undersized handled
separately — see below). Count = number of detected boxes per photo, so no
separate counting model is needed.

## Important: a data-quality issue was found and fixed during the build

Your `veg1hcqsf2.v1i.yolov8.zip` (638 images) turned out to be only **29%
real onion photos**. The other **454 images (71%)** — every file with a
plain six-digit name like `300015_jpg...` — are clean studio **stock
photography** (wood-plank / marble / slate backgrounds), one still carrying
a visible **"Natura Fresh" brand watermark**. These were almost certainly
bulk-downloaded to pad out the dataset. They were **excluded** from this
build: training a real-world inspection model on branded stock photos
would both risk a licensing problem and teach the model a studio look it
will never see on your actual conveyor/tray photos.

What's left after removing them: **184 genuine images** — 77 real onion
crate photos (timestamped, matching the public "onion-disease" Roboflow
set), 31 real phone/WhatsApp photos, and 76 unbranded casual photos
(spot-checked: garden and kitchen snapshots, no watermarks). These 184 were
re-split 80/12/8 into train/valid/test ourselves, since the original
638-image split put most of the genuine photos in "valid" and most of the
stock photos in "train" — meaningless once the stock photos are gone.

## Classes
0. healthy 1. damaged (cuts, black smut, staining, split skin) 2. rotten
(spoiled) 3. sprouted. `nc: 4` in `data.yaml`.

**"Undersized" is not a trained class** — no source labels onions by size,
because size is a measurement, not a visual defect. Handle it after
detection: compare each box's real-world diameter (calibrated with a
reference object or fixed camera height/distance) against a threshold.

## Sources merged
1. **veg1-hcqsf-2** genuine subset (184 images, see above) — real
   multi-onion photos, 512×512, original 6 classes remapped to the 4 above.
2. **onion_grading SIH26031 kit** (`data_real/`): 1,800 real "bad" onion
   crops + 85 real "good" onion crops, upscaled 128→512px, added as extra
   full-frame detection examples. The 1,784 Fruits-360 studio photos in
   that kit were **excluded** for the same reason as the stock photos above.
3. **Synthetic copy-paste balancing** for the two classes that were far too
   rare to train on directly: real crops (native pixel resolution, cut from
   the genuine photos only) were composited — random flip/rotation/scale/
   brightness, soft-edge blended — onto procedural neutral tray backgrounds,
   several onions per canvas, deliberately mixing classes (multiple onions
   per frame, good and bad together).

## Final counts

| split | images | healthy | damaged | rotten | sprouted |
|---|---|---|---|---|---|
| train | 2,375 | 1,625 | 1,982 | 1,000 | 800 |
| valid | 211 | 143 | 204 | 36 | 3 |
| test | 15 | 22 | 19 | 2 | 0 |

## Known limitations — please read before trusting metrics blindly

- **"sprouted" is the one class you should not trust yet.** It rests on
  only 3 real source crops in the entire combined dataset, and — checked by
  eye during this build — those 3 crops are tiny (12×20px, 31×59px, 23×21px
  on the original photo) and too low-detail to clearly show a green shoot
  even zoomed in 6×. Every one of the 800 "sprouted" training instances is
  a copy-paste composite of those same 3 blurry crops (flipped, rotated,
  recolored, rescaled) — the model has no real chance to learn what a
  sprouted onion actually looks like from this data. **Do not ship the
  sprouted grade until this is fixed.** Two ways to fix it: (a) photograph
  15–20 real sprouted onions yourself, full-onion framing with the shoot
  clearly visible, or (b) there's a public Roboflow set ("onion-disease" by
  Anas Kadiri, 53 real crate photos with proper full-size sprouted boxes)
  that we skipped earlier for being too small — it's small, but its
  sprouted examples are real, whole-onion crops, which is exactly what's
  missing here. Say the word if you want it pulled in just to rescue this
  one class.
- **"rotten" boxes are mostly small surface spots** (avg ~36×22px on a
  512px photo), not whole discolored onions — that's how the source photos
  were originally annotated (205 of 209 real rotten instances came from
  real WhatsApp photos, which is good — but they mark blemish spots, not
  whole-onion calls). The model will learn to detect spots; keep that in
  mind when reading its output.
- **Test split is small (15 images)** — rely on `valid` (211 images) for
  meaningful per-epoch metrics, and treat `test` as a token holdout.
- The synthetic canvases use a plain procedural background, not your actual
  camera rig's real tray/conveyor. Expect some domain gap versus training
  purely on your own procurement-centre photos; this dataset is a strong
  starting point, but real photos from your target setup will help before
  deployment, especially for sprouted and rotten.

## A note on file size / resolution

To fit this dataset under the delivery size limit, images were re-encoded:
real crate photos stay at their original 512×512, synthetic composite
canvases were saved at 416×416, and the upscaled onion.zip crops at 256×256
(closer to their honest native 128×128 than the 512 they were first
inflated to — no real detail was lost by shrinking a blown-up image back
down). Mixed resolutions are not a problem for YOLO training — Ultralytics
resizes every image to its configured `imgsz` (commonly 640) regardless of
source size — but it's worth knowing before you inspect files by hand.

## Files
- `train/`, `valid/`, `test/` — `images/` + YOLO `labels/*.txt`
- `data.yaml` — Ultralytics/YOLO training config, paths already correct

## Train on Ultralytics Platform
Upload this folder (or the zip) as a new dataset, point training at
`data.yaml`, and pick a detection task — every box already carries both a
location (for counting) and a class (for grading) in one pass.
