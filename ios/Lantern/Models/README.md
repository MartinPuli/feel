# Optional CoreML detector

Run `python3 scripts/fetch_model.py` from the repository root before generating the Xcode project. It downloads Apple's published quantized YOLOv3 model at a pinned revision, verifies SHA-256, and writes `ios/Lantern/Models/FEELDetector.mlmodel`. Xcode compiles it to `FEELDetector.mlmodelc`; the generic `MLModel`/`VNCoreMLModel` adapter loads that name. Large pretrained weights are not committed.

Model provenance/license and the exact URL/hash are in the repository model manifest and fetch script. This is a pretrained third-party model, not a model trained during the event. Include it in the hackathon disclosure. Download verification is not model inference validation.

The adapter requires `VNRecognizedObjectObservation` outputs with normalized bounding boxes and labels. Its selected labels are `chair` and `person`. It uses `.scaleFill` and native landscape-left capture orientation (`.up`) so Vision boxes map to the matching native depth map. Wrong output type or model-load errors become an explicit unavailable message.

Without weights, chair finding is unavailable. Person finding uses Vision's built-in human rectangle detector; EXIT uses text recognition; **Door candidate** is a rectangle/aspect heuristic and cannot establish that a door exists or is traversable. No trained door model is claimed.

On a real device, verify actual inference latency, confidence, matching depth coordinates, detection disappearance, and thermal behavior. The app keeps at most one Vision request in flight and discards stale generations/results beyond 500 ms. Raw images are not saved or uploaded.
