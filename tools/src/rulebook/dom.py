from __future__ import annotations

from dataclasses import dataclass, field
from html.parser import HTMLParser

VOID_TAGS = frozenset(
    {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "wbr"},
)


@dataclass
class Element:
    tag: str
    attrs: dict[str, str | None] = field(default_factory=dict)
    children: list[Element | str] = field(default_factory=list)
    parent: Element | None = field(default=None, repr=False)

    def has_attr(self, name: str) -> bool:
        return name in self.attrs

    def attr(self, name: str) -> str | None:
        return self.attrs.get(name)

    def elements(self) -> list[Element]:
        return [child for child in self.children if isinstance(child, Element)]

    def iter(self) -> list[Element]:
        found: list[Element] = []
        stack: list[Element] = [self]
        while stack:
            node = stack.pop()
            found.append(node)
            stack.extend(reversed(node.elements()))
        return found

    def text(self) -> str:
        parts: list[str] = []
        for child in self.children:
            parts.append(child if isinstance(child, str) else child.text())
        return "".join(parts)


class _TreeBuilder(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.root = Element("document")
        self._current = self.root

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        element = Element(tag, dict(attrs), parent=self._current)
        self._current.children.append(element)
        if tag not in VOID_TAGS:
            self._current = element

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._current.children.append(Element(tag, dict(attrs), parent=self._current))

    def handle_endtag(self, tag: str) -> None:
        if tag in VOID_TAGS:
            return
        node: Element | None = self._current
        while node is not None and node.tag != tag:
            node = node.parent
        if node is not None and node.parent is not None:
            self._current = node.parent

    def handle_data(self, data: str) -> None:
        self._current.children.append(data)


def parse_html(html: str) -> Element:
    builder = _TreeBuilder()
    builder.feed(html)
    builder.close()
    return builder.root
