; Bold-wrapped tag in a table cell drifts the right border left

A tag wrapped in emphasis (`**#foo**`) inside a table cell makes the right
border of that column drift one column to the **left** — the column width is
computed one too short.

Root cause: the inline tag PARSER (`parsers/markdown_inline.lua`) only matches
`#tag` at start-of-line or after whitespace, so `#foo` inside `**#foo**` is NOT
a tag and the `#` is rendered literally (4 cols: `#foo`). But the width path
(`renderers/markdown/tostring.lua`) recurses INTO the emphasis span, strips
`**`, and re-evaluates `#foo` at the start of the stripped fragment where the
tag guard used to succeed, applying the tag transform (`#` concealed, paddings
added => 5 cols: ` foo `). tostring over-counted by +1 relative to what is
drawn, so the border drifted left by 1.

The fix prefixes a `\1` sentinel to the emphasis-inner text before re-matching
and gives the tag pattern a stricter guard (`at_tag_valid`) that does not treat
"right after the sentinel" as a valid tag position — mirroring the parser. A
tag after a real space inside emphasis (`**a #foo**`) still renders, and nested
italic / inline code inside emphasis (`**_foo_**`, ``**`code`**``) are
unaffected.

The plain-tag control (`#foo`) aligns correctly both before and after the fix;
only the emphasis-wrapped tag drifted.

## Bold-wrapped tag vs. controls

| Cell            | Note              | End  |
| --------------- | ----------------- | ---- |
| **#foo**        | bold tag          | XXXX |
| #foo            | plain tag         | XXXX |
| **foo**         | bold plain        | XXXX |
| foo             | plain             | XXXX |

## Regression guards: nesting still works

These must keep rendering with their inner markers stripped (they do NOT drift):
the sentinel only suppresses a leading tag, not nested emphasis / inline code.

| Cell            | Note              | End  |
| --------------- | ----------------- | ---- |
| **_foo_**       | bold + italic     | XXXX |
| **`code`**      | bold + code       | XXXX |
| *`code`*        | italic + code     | XXXX |
| **a #foo**      | tag after space   | XXXX |

<!-- vim: set nowrap: -->
