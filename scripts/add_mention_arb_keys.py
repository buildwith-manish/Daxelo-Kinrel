#!/usr/bin/env python3
"""
Add the 12 Phase-A mention keys to a single .arb file, preserving the
file's existing formatting. Inserts the new entries just before the
final closing `}`.

Reads the file as raw text, finds the last `}` at column 0, inserts
the 12 entries (with proper trailing commas) before it.
"""
import json
import sys
import os
import re
from pathlib import Path

# Per-language translations.
TRANSLATIONS = {
    "app_en.arb": {
        "mentionLoading": "Loading\u2026",
        "mentionErrorRetry": "Couldn\u2019t load \u2014 tap to retry",
        "mentionNoMatch": "No one matches",
        "mentionNoCandidates": "No one to mention in this chat",
        "mentionDmHeader": "Mention a relative \u00b7 they won\u2019t be notified",
        "mentionDmNoRelatives": "No other relatives to mention in this family",
        "mentionCapExceeded": "You can mention up to 5 people in one message",
        "mentionRecentlyActiveA11y": "Recently active",
        "mentionElderA11y": "Elder",
        "mentionBadgeA11y": "Mention",
        "mentionNotificationBodyOne": "{sender} mentioned you in chat",
        "mentionNotificationBodyMany": "{sender} and {count} others mentioned you in chat",
    },
    "app_hi.arb": {
        "mentionLoading": "\u0932\u094b\u0921 \u0939\u094b \u0930\u0939\u093e \u0939\u0948\u2026",
        "mentionErrorRetry": "\u0932\u094b\u0921 \u0928\u0939\u0940\u0902 \u0939\u0941\u0906 \u2014 \u092a\u0941\u0928\u0903 \u092a\u094d\u0930\u092f\u093e\u0938 \u0915\u0930\u0947\u0902",
        "mentionNoMatch": "\u0915\u094b\u0908 \u092e\u093f\u0932\u093e\u0928\u0947 \u0935\u093e\u0932\u093e \u0928\u0939\u0940\u0902",
        "mentionNoCandidates": "\u0907\u0938 \u091a\u0948\u091f \u092e\u0947\u0902 \u092e\u0947\u0902\u0936\u0928 \u0915\u0930\u0928\u0947 \u0915\u0947 \u0932\u093f\u090f \u0915\u094b\u0908 \u0928\u0939\u0940\u0902 \u0939\u0948",
        "mentionDmHeader": "\u0915\u093f\u0938\u0940 \u0930\u093f\u0936\u094d\u0924\u0947\u0926\u093e\u0930 \u0915\u093e \u092e\u0947\u0902\u0936\u0928 \u0932\u093f\u090f\u0902 \u00b7 \u0909\u0928\u094d\u0939\u0947\u0902 \u0938\u0942\u091a\u0928\u093e \u0928\u0939\u0940\u0902 \u092e\u093f\u0932\u0947\u0917\u0940",
        "mentionDmNoRelatives": "\u0907\u0938 \u092a\u0930\u093f\u0935\u093e\u0930 \u092e\u0947\u0902 \u092e\u0947\u0902\u0936\u0928 \u0915\u0930\u0928\u0947 \u0915\u0947 \u0932\u093f\u090f \u0915\u094b\u0908 \u0905\u0928\u094d\u092f \u0930\u093f\u0936\u094d\u0924\u0947\u0926\u093e\u0930 \u0928\u0939\u0940\u0902 \u0939\u0948",
        "mentionCapExceeded": "\u0906\u092a \u090f\u0915 \u0938\u0902\u0926\u0947\u0936 \u092e\u0947\u0902 \u0905\u0927\u093f\u0915\u0924\u092e 5 \u0932\u094b\u0917\u094b\u0902 \u0915\u093e \u092e\u0947\u0902\u0936\u0928 \u0915\u0930 \u0938\u0915\u0924\u0947 \u0939\u0948\u0902",
        "mentionRecentlyActiveA11y": "\u0939\u093e\u0932 \u0939\u0940 \u092e\u0947\u0902 \u0938\u0915\u094d\u0930\u093f\u092f",
        "mentionElderA11y": "\u092c\u091c\u0941\u0930\u094d\u0917",
        "mentionBadgeA11y": "\u092e\u0947\u0902\u0936\u0928",
        "mentionNotificationBodyOne": "{sender} \u0928\u0947 \u091a\u0948\u091f \u092e\u0947\u0902 \u0906\u092a\u0915\u093e \u092e\u0947\u0902\u0936\u0928 \u0915\u093f\u092f\u093e",
        "mentionNotificationBodyMany": "{sender} \u0914\u0930 {count} \u0932\u094b\u0917\u094b\u0902 \u0928\u0947 \u091a\u0948\u091f \u092e\u0947\u0902 \u0906\u092a\u0915\u093e \u092e\u0947\u0902\u0936\u0928 \u0915\u093f\u092f\u093e",
    },
    "app_bn.arb": {
        "mentionLoading": "\u09b2\u09cb\u09a1 \u09b9\u099a\u09cd\u099b\u09c7\u2026",
        "mentionErrorRetry": "\u09b2\u09cb\u09a1 \u0995\u09b0\u09be \u09af\u09be\u09af\u09bc\u09a8\u09bf \u2014 \u0986\u09ac\u09be\u09b0 \u099a\u09c7\u09b7\u09cd\u099f\u09be \u0995\u09b0\u09c1\u09a8",
        "mentionNoMatch": "\u0995\u09c7\u0989\u0987 \u09ae\u09bf\u09b2\u099b\u09c7 \u09a8\u09be",
        "mentionNoCandidates": "\u098f\u0987 \u099a\u09cd\u09af\u09be\u099f\u09c7 \u0989\u09b2\u09cd\u09b2\u09c7\u0996 \u0995\u09b0\u09b0 \u0995\u09c7\u0989 \u09a8\u09c7\u0987",
        "mentionDmHeader": "\u0986\u09a4\u09cd\u09ae\u09c0\u09af\u09bc\u09b0 \u0989\u09b2\u09cd\u09b2\u09c7\u0996 \u0995\u09b0\u09c1\u09a8 \u00b7 \u09a4\u09be\u09a6\u09c7\u09b0 \u09ac\u09be\u09b0\u09cd\u09a4\u09be \u09a6\u09c7\u0993\u09af\u09bc\u09be \u09b9\u09ac\u09c7 \u09a8\u09be",
        "mentionDmNoRelatives": "\u098f\u0987 \u09aa\u09b0\u09bf\u09ac\u09be\u09b0\u09c7 \u0989\u09b2\u09cd\u09b2\u09c7\u0996 \u0995\u09b0\u09b0 \u0995\u09cb\u09a8 \u0986\u09a4\u09cd\u09ae\u09c0\u09af\u09bc \u0986\u09a4\u09cd\u09ae\u09c0\u09af\u09bc \u09a8\u09c7\u0987",
        "mentionCapExceeded": "\u0986\u09aa\u09a8\u09bf \u098f\u0995\u099f\u09bf \u09ac\u09be\u09b0\u09cd\u09a4\u09be\u09af\u09bc \u09b8\u09b0\u09cd\u09ac\u09cb\u099a\u09cd\u099a 5 \u099c\u09a8 \u0995\u09c7 \u0989\u09b2\u09cd\u09b2\u09c7\u0996 \u0995\u09b0\u09a4\u09c7 \u09aa\u09be\u09b0\u09c7\u09a8",
        "mentionRecentlyActiveA11y": "\u09b8\u09be\u09ae\u09cd\u09aa\u09cd\u09b0\u09a4\u09bf\u0995 \u09b8\u0995\u09cd\u09b0\u09bf\u09af\u09bc",
        "mentionElderA11y": "\u09aa\u09cd\u09b0\u09ac\u09c0\u09a8",
        "mentionBadgeA11y": "\u0989\u09b2\u09cd\u09b2\u09c7\u0996",
        "mentionNotificationBodyOne": "{sender} \u099a\u09cd\u09af\u09be\u099f\u09c7 \u0986\u09aa\u09a8\u09be\u0995\u09c7 \u0989\u09b2\u09cd\u09b2\u09c7\u0996 \u0995\u09b0\u09c7\u099b\u09c7\u09a8",
        "mentionNotificationBodyMany": "{sender} \u098f\u09ac\u0982 {count} \u099c\u09a8 \u099a\u09cd\u09af\u09be\u099f\u09c7 \u0986\u09aa\u09a8\u09be\u0995\u09c7 \u0989\u09b2\u09cd\u09b2\u09c7\u0996 \u0995\u09b0\u09c7\u099b\u09c7\u09a8",
    },
    "app_ta.arb": {
        "mentionLoading": "\u0b8f\u0bb1\u0bcd\u0bb1\u0bc1\u0b95\u0bbf\u0bb1\u0ba4\u0bc1\u2026",
        "mentionErrorRetry": "\u0b8f\u0bb1\u0bcd\u0bb1 \u0bae\u0bc1\u0b9f\u0bbf\u0baf\u0bb5\u0bbf\u0bb2\u0bcd\u0bb2\u0bc8 \u2014 \u0bae\u0bc0\u0ba3\u0bcd\u0b9f\u0bc1\u0bae\u0bcd \u0bae\u0bc1\u0baf\u0bb1\u0bcd\u0b9a\u0bbf\u0b95\u0bcd\u0b95\u0bb5\u0bc1\u0bae\u0bcd",
        "mentionNoMatch": "\u0baf\u0bbe\u0bb0\u0bc1\u0bae\u0bcd \u0baa\u0bca\u0bb0\u0bc1\u0ba8\u0bcd\u0ba4\u0bb5\u0bbf\u0bb2\u0bcd\u0bb2\u0bc8",
        "mentionNoCandidates": "\u0b87\u0ba8\u0bcd\u0ba4 \u0b85\u0bb0\u0b9f\u0bc8\u0baf\u0bbf\u0bb2\u0bcd \u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bbf\u0b9f \u0baf\u0bbe\u0bb0\u0bc1\u0bae\u0bcd \u0b87\u0bb2\u0bcd\u0bb2\u0bc8",
        "mentionDmHeader": "\u0b89\u0bb1\u0bb5\u0bbf\u0ba9\u0bb0\u0bc8\u0b95\u0bcd \u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bbf\u0b9f\u0bc1\u0b99\u0bcd\u0b95\u0bb3\u0bcd \u00b7 \u0b85\u0bb5\u0bb0\u0bcd\u0b95\u0bb3\u0bc1\u0b95\u0bcd\u0b95\u0bc1 \u0b85\u0bb1\u0bbf\u0bb5\u0bbf\u0baa\u0bcd\u0baa\u0bc1 \u0b9a\u0bc6\u0bb2\u0bcd\u0bb2\u0bbe\u0ba4\u0bc1",
        "mentionDmNoRelatives": "\u0b87\u0ba8\u0bcd\u0ba4 \u0b95\u0bc1\u0b9f\u0bc1\u0bae\u0bcd\u0baa\u0ba4\u0bcd\u0ba4\u0bbf\u0bb2\u0bcd \u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bbf\u0b9f \u0bb5\u0bc7\u0bb1\u0bc1 \u0b89\u0bb1\u0bb5\u0bbf\u0ba9\u0bb0\u0bcd \u0b87\u0bb2\u0bcd\u0bb2\u0bc8",
        "mentionCapExceeded": "\u0b92\u0bb0\u0bc7 \u0b9a\u0bc6\u0baf\u0bcd\u0ba4\u0bbf\u0baf\u0bbf\u0bb2\u0bcd \u0b85\u0ba4\u0bbf\u0bb5\u0bb0\u0bae\u0bc1\u0bae\u0bcd 5 \u0baa\u0bc7\u0bb0\u0bc8\u0b95\u0bcd \u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bbf\u0b9f\u0bb2\u0bbe\u0bae\u0bcd",
        "mentionRecentlyActiveA11y": "\u0b9a\u0bae\u0bc0\u0baa\u0ba4\u0bcd\u0ba4\u0bbf\u0baf\u0bbf\u0bb2\u0bcd \u0b9a\u0bc6\u0baf\u0bb2\u0bcd",
        "mentionElderA11y": "\u0bae\u0bc2\u0ba4\u0bbe\u0ba9\u0bb5\u0bb0\u0bcd",
        "mentionBadgeA11y": "\u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bc1",
        "mentionNotificationBodyOne": "{sender} \u0b85\u0bb0\u0b9f\u0bc8\u0baf\u0bbf\u0bb2\u0bcd \u0b89\u0b99\u0bcd\u0b95\u0bb3\u0bc8\u0b95\u0bcd \u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bbf\u0b9f\u0bcd\u0b9f\u0bbe\u0bb0\u0bcd",
        "mentionNotificationBodyMany": "{sender} \u0bae\u0bb1\u0bcd\u0bb1\u0bc1\u0bae\u0bcd {count} \u0baa\u0bc7\u0bb0\u0bc1\u0bae\u0bcd \u0b85\u0bb0\u0b9f\u0bc8\u0baf\u0bbf\u0bb2\u0bcd \u0b89\u0b99\u0bcd\u0b95\u0bb3\u0bc8\u0b95\u0bcd \u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bbf\u0b9f\u0bcd\u0b9f\u0bbe\u0bb0\u0bcd\u0b95\u0bb3\u0bcd",
    },
}


def format_value(value):
    """Format an arb string value (double-quoted, JSON-escaped, no reflow)."""
    return json.dumps(value, ensure_ascii=False)


def format_metadata(key):
    """Format the @-prefixed metadata block for a key, matching the file's existing style."""
    lines = [f'    "@{key}":  {{']
    lines.append(f'        "description":  "Mention picker / notification string: {key}"')
    if "Body" in key:
        lines.append('        ,"placeholders":  {')
        lines.append('            "sender":  {')
        lines.append('                "type":  "String"')
        lines.append('            }')
        if "Many" in key:
            lines.append('            ,"count":  {')
            lines.append('                "type":  "int"')
            lines.append('            }')
        lines.append('        }')
    lines.append('    }')
    return '\n'.join(lines)


def insert_keys(arb_path):
    """Insert the 12 mention keys just before the closing } of the .arb file."""
    filename = os.path.basename(arb_path)
    translations = TRANSLATIONS.get(filename)
    if not translations:
        print(f"  (no translations for {filename}, skipping)")
        return

    with open(arb_path, 'r', encoding='utf-8') as f:
        text = f.read()

    # Skip if any of the keys already exist.
    already_present = set(re.findall(r'"(mention[A-Za-z]+)":', text))
    to_add = [(k, v) for k, v in translations.items() if k not in already_present]
    if not to_add:
        print(f"  {filename}: all 12 keys already present, skipping")
        return

    # The file's ending looks like (with arbitrary indentation on the
    # last metadata block's closing brace):
    #   ...metadata block of the last entry...
    #       ...metadata fields...
    #   <whitespace>}        <-- last entry's metadata close (any indent)
    # }                       <-- file's closing brace (column 0)
    #
    # We need to insert a `,` after the last entry's `}` and then add
    # the new entries before the file's closing `}`. Find the file's
    # closing `\n}` (column 0) and the previous `\n<whitespace>}`
    # (the last entry's metadata close, any indent), then insert
    # `,\n<new_entries>` after that previous `}`.

    import re as _re
    # Find the file's closing brace at column 0 (must be the LAST
    # newline-then-brace at column 0).
    last_close = text.rfind('\n}')
    if last_close < 0:
        print(f"  {filename}: could not find file-closing brace, skipping")
        return

    # Search backwards from `last_close` for the previous `\n<ws>}`
    # (any closing brace preceded by whitespace-only line).
    prev_close_match = None
    for m in _re.finditer(r'\n[ \t]*\}', text[:last_close]):
        prev_close_match = m  # keep the LAST one before `last_close`
    if prev_close_match is None:
        print(f"  {filename}: could not find last entry's metadata close, skipping")
        return
    insert_at = prev_close_match.end()  # after the matched `}`

    lines = []
    for key, value in to_add:
        formatted_val = format_value(value)
        lines.append(f'    "{key}":  {formatted_val},')
        lines.append(format_metadata(key) + ',')
    # The last entry must NOT have a trailing comma (JSON). Strip the
    # trailing `,` from the final line.
    if lines and lines[-1].endswith(','):
        lines[-1] = lines[-1][:-1]
    new_block = ',\n' + '\n'.join(lines) + '\n'

    new_text = text[:insert_at] + new_block + text[insert_at:]
    with open(arb_path, 'w', encoding='utf-8') as f:
        f.write(new_text)
    print(f"  {filename}: added {len(to_add)} keys")


if __name__ == '__main__':
    arb_dir = '/home/z/my-project/Daxelo-Kinrel/Daxelo-Kinrel-App/lib/l10n'
    for fname in ['app_en.arb', 'app_hi.arb', 'app_bn.arb', 'app_ta.arb']:
        path = os.path.join(arb_dir, fname)
        insert_keys(path)
