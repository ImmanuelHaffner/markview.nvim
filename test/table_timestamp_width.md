; Timestamps in table cells — column width / right-border drift
Times, dates and full timestamps in table cells must not change the computed
column width vs. plain text of the same visible length. If the width
calculation in `renderers/markdown/tostring.lua` mis-handles any character
(most likely the `:` in `HH:mm:ss`, which collides with the `:emoji:` syntax),
the cell is treated as wider/narrower than drawn and the right border drifts.

Open this file and check that every right border lines up. Each timestamp row
is followed by (or paired with) a plain control cell of the same character
count — they must render with identical width.

NOTE: tables are deliberately surrounded by blank lines to avoid a separate
heading/border-collision bug; keep them isolated so this fixture only exercises
the width calculation.

### Times (HH:mm:ss)

| Label            | Value    |
|------------------|----------|
| Time             | 12:34:56 |
| Time (midnight)  | 00:00:00 |
| Time (end)       | 23:59:59 |
| HH:mm only       | 09:41    |
| Plain 8-char ctl | XXXXXXXX |
| Plain 5-char ctl | XXXXX    |

### Dates (YYYY-MM-DD)

| Label             | Value      |
|-------------------|------------|
| ISO date          | 2026-07-03 |
| Leap day          | 2024-02-29 |
| Slash date        | 2026/07/03 |
| Dotted date       | 03.07.2026 |
| Plain 10-char ctl | XXXXXXXXXX |

### Full timestamps (YYYY-MM-DD HH:mm:ss)

| Label              | Value                     |
|--------------------|---------------------------|
| ISO datetime       | 2026-07-03 14:35:12       |
| ISO 'T' separator  | 2026-07-03T14:35:12       |
| With timezone Z    | 2026-07-03T14:35:12Z      |
| With offset        | 2026-07-03T14:35:12+02:00 |
| RFC-ish            | Fri, 03 Jul 2026 14:35:12 |
| Plain 19-char ctl  | XXXXXXXXXXXXXXXXXXX       |

### Colon-heavy values (emoji-syntax collision suspects)

| Label                | Value        |
|----------------------|--------------|
| Bare colon pair      | 12:34        |
| Word:word            | key:value    |
| Looks-like-emoji     | :12:34:56:   |
| Real emoji (control) | :rocket:     |
| Ratio                | 16:9         |
| Duration             | 1:02:03.456  |

### Mixed timestamps in a log-style table

| When                | Level | Message                |
|---------------------|-------|------------------------|
| 2026-07-03 14:35:12 | INFO  | started up             |
| 2026-07-03 14:35:13 | WARN  | slow query 00:00:02    |
| 2026-07-03 14:35:14 | ERROR | timeout after 00:01:30 |
| 2026-07-03 14:35:15 | DEBUG | next run at 23:59:59   |

<!-- vim: set nowrap: -->
