# ChatGPT

## PROMPT 1

looking for a cli tool that will transform json into "pretty json5":

- strings with embedded \n get multi-lined for readability
- strings with embedded " but no embedded ' get quoted with ' so " doesn't need escaping

I think that's about it :P

## RESPONSE 1

Closest “off-the-shelf CLI” I’ve found that matches your **quote rule** is the **Python `json5` package (pyjson5)**:

*   It has a `--quote-style` option, including `prefer_single`, which **switches between `'` and `"` to avoid unnecessary escaping** (exactly your “if it has `"` but no `'`, use `'`” vibe). [GitHub+1](https://github.com/dpranke/pyjson5)
    

Example:

```bash
pip install json5
cat input.json | python -m json5 --indent 2 --quote-style prefer_single > output.json5
```

It also supports other JSON5-ish output controls (indent, quote-keys, trailing-commas, as-json) via its CLI tooling. [GitHub+1](https://github.com/dpranke/pyjson5)

___________

### About the “turn `\n` into multiline for readability” part

This is the snag: **JSON5 allows string literals to _span_ multiple lines only by escaping the newline** (a JavaScript-style line continuation), but that _does not_ represent an actual newline character in the string value. [Jordan Tucker+1](https://jordanbtucker.github.io/json5/?utm_source=chatgpt.com)

So if your JSON contains a real newline character (represented as `\n` in JSON source), a formatter generally **can’t** turn that into a visually multiline literal _while preserving the same value_, because JSON5 doesn’t have a “block string” syntax like YAML.

If you’re willing to change representation (e.g., store arrays-of-lines), that’s doable — but that’s no longer a pure “pretty-printer”.

___________

### If you mostly want “pretty JSON5 formatting” (indent / trailing commas / etc.)

Check out Google’s **`json5format`** repo; it includes an example CLI called `formatjson5` that formats JSON5 with a few options. [GitHub](https://github.com/google/json5format)

___________

### What _not_ to reach for (common footgun)

The Node/Debian/Ubuntu `json5` CLI (`node-json5`) typically **outputs standard JSON**, not JSON5 (the manpage literally says “do not output JSON” for validate mode, implying normal mode outputs JSON). [Debian Manpages+1](https://manpages.debian.org/testing/node-json5/json5.1.en.html)

___________

If you tell me whether you _must_ preserve the exact string values (i.e., `\n` means real newline, not two characters `\` and `n`), I can suggest the least-bad workaround (usually: keep `\n`, but make the _display_ nicer in your tooling/editor rather than in the serialized format).

## PROMPT 2

I don't think the newline thing will be that bad given how I want it to work:

json:

"key": "the quick\nbrown fox jumps\nover the lazy dog"

json5 conversion:

"key": "the quick\n\
brown fox jumps\n\
over the lazy dog"

but I guess maybe none of the mainstream tools do this, so maybe I roll my own?

## RESPONSE 2

Yep — your conversion is **valid JSON5**. JSON5 allows **line continuations inside string literals** with a trailing `\` at end of line (the json5.org “kitchen sink” example shows this). [JSON5](https://json5.org/)

And your specific pattern works the way you want:

```js
"the quick\n\
brown fox\n\
over the lazy dog"
```

*   `\n` still produces a real newline in the value
    
*   the trailing `\` just means “keep reading the same string on the next source line”
    

### Why most formatters don’t do this

Because **indentation becomes part of the string**. Any spaces you put at the start of the continuation line are literal characters in the value. So if you want to preserve the exact value, continuation lines basically have to start at column 0 (like your example). That’s also why a “normal pretty printer” won’t eagerly insert these breaks.

### What you can reuse today

For the quoting rule (“use `'` when it avoids escaping `"`”), the Python `json5` (dpranke/pyjson5) CLI already supports `--quote-style prefer_single`. [PyPI+1](https://pypi.org/project/json5/)

But I’m not aware of any mainstream CLI that also does your `\n\` folding out of the box.

___________

Roll-your-own: tiny CLI that does _exactly_ your two rules
----------------------------------------------------------

Here’s a self-contained Python script that:

*   reads JSON from stdin (or a file),
    
*   prints JSON5-ish output,
    
*   uses `'` only when it avoids escaping `"` (your rule),
    
*   folds newline-containing strings into `\n\` + newline (your rule),
    
*   keeps everything else straightforward and deterministic.
    

```python
#!/usr/bin/env python3
import argparse
import json
import re
from typing import Any

_IDENTIFIER = re.compile(r"^[A-Za-z_$][A-Za-z0-9_$]*$")

def encode_string(s: str, *, fold_newlines: bool) -> str:
    # Your quote rule: default to ", switch to ' only when it avoids escaping "
    use_single = ('"' in s) and ("'" not in s)
    quote = "'" if use_single else '"'

    def esc_fragment(fragment: str) -> str:
        out = []
        for ch in fragment:
            if ch == "\\":
                out.append("\\\\")
            elif ch == quote:
                out.append("\\" + ch)
            elif ch == "\b":
                out.append("\\b")
            elif ch == "\f":
                out.append("\\f")
            elif ch == "\r":
                out.append("\\r")
            elif ch == "\t":
                out.append("\\t")
            else:
                # Leave most unicode alone; JSON5 allows it.
                out.append(ch)
        return "".join(out)

    if fold_newlines and "\n" in s:
        parts = s.split("\n")
        # Each actual newline becomes the escape sequence "\n" plus a line continuation "\".
        # NOTE: Continuation lines must not be indented if you want to preserve the exact value.
        rendered = ("\\n\\\n").join(esc_fragment(p) for p in parts)
        return f"{quote}{rendered}{quote}"

    # No folding: encode newline as \n like normal JSON-ish escaping.
    rendered = esc_fragment(s).replace("\n", "\\n")
    return f"{quote}{rendered}{quote}"

def to_json5(v: Any, *, indent: int, level: int) -> str:
    pad = " " * (indent * level)
    pad_in = " " * (indent * (level + 1))

    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        # JSON input won’t contain NaN/Infinity; keep it simple.
        return repr(v)
    if isinstance(v, str):
        return encode_string(v, fold_newlines=True)
    if isinstance(v, list):
        if not v:
            return "[]"
        items = [to_json5(x, indent=indent, level=level + 1) for x in v]
        return "[\n" + ",\n".join(pad_in + it for it in items) + "\n" + pad + "]"
    if isinstance(v, dict):
        if not v:
            return "{}"
        lines = []
        for k, val in v.items():
            if _IDENTIFIER.match(k):
                key = k  # JSON5 allows unquoted identifiers
            else:
                key = encode_string(k, fold_newlines=False)
            lines.append(f"{pad_in}{key}: {to_json5(val, indent=indent, level=level + 1)}")
        return "{\n" + ",\n".join(lines) + "\n" + pad + "}"
    raise TypeError(f"Unsupported type: {type(v)}")

def main() -> None:
    ap = argparse.ArgumentParser(description="JSON -> 'pretty JSON5' with newline folding + smart quotes.")
    ap.add_argument("file", nargs="?", help="Input JSON file (defaults to stdin).")
    ap.add_argument("-i", "--indent", type=int, default=2)
    args = ap.parse_args()

    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = json.load(sys.stdin)

    print(to_json5(data, indent=args.indent, level=0))

if __name__ == "__main__":
    import sys
    main()
```

Usage:

```bash
chmod +x json2json5.py
./json2json5.py input.json > output.json5
# or:
cat input.json | ./json2json5.py > output.json5
```

### One important gotcha (so you don’t get surprised)

If a string folds, the continuation lines won’t be indented (or you’d inject spaces into the value). That’s inherent to the `\`\-newline mechanism shown in the JSON5 examples. [JSON5](https://json5.org/)

If you want, I can tweak the script to _only_ apply folding above some length threshold (so short multiline strings stay on one line as `"a\nb"`), which makes the output less “ragged-left” in practice.

