; Timestamps in table cells — emoji-parser false positive drift
The inline emoji parser matches `:shortcode:` spans with a permissive pattern.
In a `HH:mm:ss` timestamp like `11:38:13`, the middle `:38:` was matched as an
emoji shorthand named "38". The name does not resolve to a real emoji, so the
width calculation and the renderer both ignore it — but the stray inline_emoji
span still desynced inline rendering from the table's width bookkeeping, drifting
each time cell's right border by the number of `:` delimiters (2 per HH:mm:ss).

Fix: the parser now only emits an inline_emoji span when the name resolves to a
known shorthand. Real digit-only shorthands (`:100:`, `:1234:`) still render.

Open this file with hybrid/preview mode and check every right border lines up.
The time columns must align exactly with the plain control cells of equal width.

### Time columns (HH:mm:ss) vs plain controls

| Row | Submit   | Cancel   | Plain    |
|-----|----------|----------|----------|
| a   | 11:38:13 | 14:54:27 | XXXXXXXX |
| b   | 06:34:40 | 07:51:34 | XXXXXXXX |
| c   | 08:28:44 | 08:30:15 | XXXXXXXX |
| d   | 00:00:00 | 23:59:59 | XXXXXXXX |

### Real emoji shorthands still render (must NOT regress)

| Kind             | Value    |
|------------------|----------|
| Named emoji      | :rocket: |
| Named emoji      | :tada:   |
| Digit-only (100) | :100:    |
| Digit-only(1234) | :1234:   |
| Plus-one         | :+1:     |

### True emoji embedded in a colon sequence (must render)

A real shorthand surrounded by digits and colons, e.g. `42:100:13`, still
resolves: the `:100:` renders as the 💯 emoji (concealing the `:100:`), while the
surrounding `42`/`13` stay literal. This confirms the fix is precise — it does
not blanket-reject colon-delimited digit runs, only spans whose name is not a
known shorthand.

| Kind                 | Value     |
|----------------------|-----------|
| :100: inside digits  | 42:100:13 |
| :100: between times  | 00:100:00 |
| Bare :100:           | :100:     |
| No-render control    | 42:38:13  |

### Colon values that must stay literal (no emoji)

| Kind          | Value        |
|---------------|--------------|
| Time          | 11:38:13     |
| Ratio         | 16:9         |
| key:value     | key:value    |
| Bare pair     | 12:34        |
| Looks-emoji   | :38:         |
| Plain control | XXXXXXXX     |

### Log-style table (real-world repro)

| When     | Cancel   | Note                |
|----------|----------|---------------------|
| 11:38:13 | 14:54:27 | started up          |
| 14:55:09 | 19:47:34 | slow query 00:00:02 |
| 06:34:40 | 07:51:34 | timeout 00:01:30    |
| 08:28:44 | 08:30:15 | next run 23:59:59   |



| Cmd | Date | Submit | Cancel | FS runtime | Key id |
|---|---|---|---|---|---|
| #51 | Jun 9 | 11:38:13 | 14:54:27 | 3h16m | jobGroup `…_10286eeb0d844a75b9b5d0fb0509b4f6` |
| #107 | Jun 9 | 14:55:09 | 19:47:34 | 4h52m | jobGroup `…_bc56393eb5664c91a92a12760e38377b` |
| #26 | Jun 11 | 06:34:40 | 07:51:34 | 77m | execId 386, jobGroup `…_e4766ee01df24ebda6b0ec6a7f092da8`, workloadId `bc232644-acd7-476d-9cc3-585ec07173d3` |
| #177 | Jun 11 | 08:28:44 | 08:30:15 | 91s | queryId `84294f15-df60-4b72-bf3a-68b41b064739` |
| #185 | Jun 11 | 08:30:27 | 08:35:07 | 280s | queryId `1dea36d1-7d14-4a87-8293-3bf2bdef8e72` |
| #218 | Jun 11 | 08:35:07 | 08:36:45 | 98s | queryId `220f49e1-1de5-4246-8e59-9a7f99a6e82c` |
| #277 | Jun 11 | 09:08:55 | 09:09:04 | 9s | queryId `7b0ff6f3-5687-407a-b93b-1ebb0bddc369` |
| #286 | Jun 11 | 09:33:21 | 09:52:23 | 19m | queryId `3902b95b-6a23-496c-b966-55f1fb4ad600` |


<!-- vim: set nowrap: -->
