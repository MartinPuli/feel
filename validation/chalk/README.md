# Independent Chalk acceptance cases

`holdout.json` contains authored synthetic requests with explicit expected actions.
It is a specification dataset, not evidence that a model passed. Do not put expected
labels into the request or prompt. Use a separate development dataset when tuning.
If these cases are used to tune, relabel them development and create a new holdout.

Cases cover English/Spanish paraphrases, ambiguity, missing places, tracking loss,
map restoration, immediate Stop, unsupported hardware commands and prompt injection.
A unique destination must match its actual ID; arbitrary plausible text is not a
correct result. For ambiguous or absent names, the expected action is clarification.
For invalid tracking/restoration, motion-related action is rejected; Stop is allowed.

Evaluation reports must name model, prompt revision, input dataset hash, timestamp,
case count, errors, expected vs actual actions, and timing boundaries. Compare
identical datasets and classify errors separately from successful but wrong output.
Do not publish a fake baseline or promise improvement if the candidate loses.
