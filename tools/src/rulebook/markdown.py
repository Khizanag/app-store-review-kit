from __future__ import annotations

import re
from collections.abc import Callable, Iterable

from rulebook.dom import Element

BLOCK_TAGS = frozenset({"p", "ul", "ol", "div", "blockquote", "h4", "h5", "h6", "table"})
SKIPPED_TAGS = frozenset({"img", "script", "style", "button"})
LINE_BREAK = "\u2028"

Skip = Callable[[Element], bool]
LinkResolver = Callable[[str], str]


def render_blocks(nodes: Iterable[Element | str], skip: Skip, resolve: LinkResolver) -> str:
    return "\n\n".join(_blocks(nodes, skip, resolve))


def _blocks(nodes: Iterable[Element | str], skip: Skip, resolve: LinkResolver) -> list[str]:
    blocks: list[str] = []
    inline: list[str] = []

    def flush() -> None:
        paragraph = _tidy("".join(inline))
        if paragraph:
            blocks.append(paragraph)
        inline.clear()

    for node in nodes:
        if isinstance(node, str):
            inline.append(node)
            continue
        if skip(node) or node.tag in SKIPPED_TAGS:
            continue
        if node.tag not in BLOCK_TAGS:
            inline.append(_inline(node, skip, resolve))
            continue
        flush()
        if node.tag in {"ul", "ol"}:
            rendered = _list(node, skip, resolve)
        else:
            rendered = render_blocks(node.children, skip, resolve)
        if rendered:
            blocks.append(rendered)
    flush()
    return blocks


def _list(node: Element, skip: Skip, resolve: LinkResolver) -> str:
    marker = "1." if node.tag == "ol" else "-"
    indent = " " * (len(marker) + 1)
    items: list[str] = []
    for item in node.elements():
        if item.tag != "li" or skip(item):
            continue
        blocks = _blocks(item.children, skip, resolve)
        if not blocks:
            continue
        lines = f"\n{indent}".join("\n".join(blocks).splitlines())
        items.append(f"{marker} {lines}")
    return "\n".join(items)


def _inline(node: Element, skip: Skip, resolve: LinkResolver) -> str:
    if skip(node) or node.tag in SKIPPED_TAGS:
        return ""
    inner = "".join(
        child if isinstance(child, str) else _inline(child, skip, resolve)
        for child in node.children
    )
    match node.tag:
        case "strong" | "b":
            return _wrap(inner, "**")
        case "em" | "i":
            return _wrap(inner, "*")
        case "code":
            return _wrap(inner, "`")
        case "br":
            return LINE_BREAK
        case "a":
            href = node.attr("href")
            text = _tidy(inner)
            return f"[{text}]({resolve(href)})" if href and text else inner
        case _:
            return inner


def _wrap(inner: str, marker: str) -> str:
    stripped = _collapse(inner).strip()
    if not stripped:
        return _collapse(inner)
    leading = " " if inner[:1].isspace() else ""
    trailing = " " if inner[-1:].isspace() else ""
    return f"{leading}{marker}{stripped}{marker}{trailing}"


def _collapse(text: str) -> str:
    return re.sub(r"[^\S\u2028]+", " ", text)


def _tidy(text: str) -> str:
    lines = [_collapse(line).strip() for line in text.split(LINE_BREAK)]
    return "\\\n".join(line for line in lines if line)
