from __future__ import annotations

import json
import re
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

from rulebook.dom import Element, parse_html
from rulebook.markdown import render_blocks

GUIDELINES_URL = "https://developer.apple.com/app-store/review/guidelines/"
APPLE_ORIGIN = "https://developer.apple.com"
SECTION_NUMBER = re.compile(r"^\d+(\.\d+)*$")
LEADING_NUMBER = re.compile(r"^\s*\d+(\.\d+)*\.?\s*")
EXCERPT_WORDS = 10
OMITTED = "Intentionally omitted."
PSEUDO_HEADING = re.compile(r"^\*\*([^*]+)\*\*$", re.MULTILINE)
LAST_UPDATED = re.compile(r"Last Updated:\s*<a[^>]*>\s*([A-Z][a-z]+ \d{1,2}, \d{4})")


@dataclass(frozen=True)
class Section:
    slug: str
    number: str | None
    title: str
    parent: str | None
    notarization: bool
    children: tuple[str, ...]
    body: str


@dataclass(frozen=True)
class Snapshot:
    last_updated: str
    sections: tuple[Section, ...]


def fetch(url: str = GUIDELINES_URL) -> str:
    if not url.startswith("https://"):
        raise ValueError(f"Refusing non-HTTPS guidelines URL: {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "app-store-review-kit"})  # noqa: S310
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
        body: bytes = response.read()
    return body.decode("utf-8")


def parse(html: str) -> Snapshot:
    match = LAST_UPDATED.search(html)
    if match is None:
        raise ValueError("No 'Last Updated' date found; Apple changed the page layout.")
    last_updated = datetime.strptime(match.group(1), "%B %d, %Y").date().isoformat()

    root = parse_html(html)
    headings = [e for e in root.iter() if e.tag == "h3" and e.has_attr("data-sidenav")]
    if not headings or headings[0].parent is None:
        raise ValueError("No guideline headings found; Apple changed the page layout.")

    sections: list[Section] = []
    for heading, nodes in _group_by_heading(headings[0].parent, headings):
        sections.extend(_top_section(heading, nodes))
    return Snapshot(last_updated, tuple(sections))


def write(snapshot: Snapshot, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    expected = {f"{section.slug}.md" for section in snapshot.sections} | {"README.md"}
    for stale in out.glob("*.md"):
        if stale.name not in expected:
            stale.unlink()
    for section in snapshot.sections:
        (out / f"{section.slug}.md").write_text(_section_markdown(section, snapshot))
    (out / "README.md").write_text(_index_markdown(snapshot))
    index = {
        "source": GUIDELINES_URL,
        "last_updated": snapshot.last_updated,
        "sections": [
            {key: value for key, value in asdict(section).items() if key != "body"}
            | {"omitted": section.body == OMITTED}
            for section in snapshot.sections
        ],
    }
    (out / "index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n")


def _group_by_heading(
    container: Element,
    headings: list[Element],
) -> list[tuple[Element, list[Element | str]]]:
    groups: list[tuple[Element, list[Element | str]]] = []
    for child in container.children:
        if isinstance(child, Element) and any(child is heading for heading in headings):
            groups.append((child, []))
        elif groups:
            groups[-1][1].append(child)
    return groups


def _top_section(heading: Element, nodes: list[Element | str]) -> list[Section]:
    number = _section_number(heading)
    slug = number or heading.attr("id") or "untitled"
    nested = [
        element
        for node in nodes
        if isinstance(node, Element)
        for element in node.iter()
        if _section_number(element) is not None and element is not heading
    ]
    direct = [element for element in nested if _parent_section(element) is None]
    top = Section(
        slug=slug,
        number=number,
        title=_title(heading),
        parent=None,
        notarization=heading.has_attr("data-nr"),
        children=tuple(_slug(element) for element in direct),
        body=_render(nodes, owner=heading, nested=nested),
    )
    subsections = [
        Section(
            slug=_slug(element),
            number=_section_number(element),
            title=_title(element),
            parent=_parent_number(element) or number,
            notarization=element.has_attr("data-nr"),
            children=tuple(_slug(other) for other in nested if _parent_section(other) is element),
            body=_render(element.children, owner=element, nested=nested),
        )
        for element in nested
    ]
    return [top, *subsections]


def _render(nodes: list[Element | str], owner: Element, nested: list[Element]) -> str:
    title_strong = next((e for e in owner.elements() if e.tag == "strong"), None)

    def skip(element: Element) -> bool:
        if element is owner:
            return False
        if any(element is section for section in nested):
            return True
        if element is title_strong:
            return True
        if element.tag == "p" and element.text().strip().startswith("Last Updated"):
            return True
        return element.tag == "span" and SECTION_NUMBER.match(element.attr("id") or "") is not None

    return render_blocks(nodes, skip, _resolve_link)


def _section_number(element: Element) -> str | None:
    own = element.attr("id") or ""
    if element.tag == "li" and SECTION_NUMBER.match(own):
        return own
    for child in element.elements():
        if child.tag == "span":
            anchor = child.attr("id") or ""
            if SECTION_NUMBER.match(anchor):
                return anchor
    return None


def _slug(element: Element) -> str:
    return _section_number(element) or element.attr("id") or "untitled"


def _parent_section(element: Element) -> Element | None:
    node = element.parent
    while node is not None:
        if node.tag == "li" and _section_number(node) is not None:
            return node
        node = node.parent
    return None


def _parent_number(element: Element) -> str | None:
    parent = _parent_section(element)
    return _section_number(parent) if parent is not None else None


def _title(element: Element) -> str:
    label = element.attr("data-sidenav") or ""
    if not label:
        strong = next((e for e in element.elements() if e.tag == "strong"), None)
        label = (strong or element).text()
    label = " ".join(label.replace("\xa0", " ").split())
    return LEADING_NUMBER.sub("", label).rstrip(":") if _section_number(element) else label


def _resolve_link(href: str) -> str:
    if href.startswith("#"):
        anchor = href[1:]
        return f"{anchor}.md" if SECTION_NUMBER.match(anchor) else f"{GUIDELINES_URL}{href}"
    if href.startswith("/"):
        return f"{APPLE_ORIGIN}{href}"
    return href


def _heading(section: Section) -> str:
    if section.number is None:
        return section.title
    separator = ". " if "." not in section.number else " "
    return f"{section.number}{separator}{section.title}".rstrip()


def _label(section: Section) -> str:
    if section.title or not section.body:
        return _heading(section)
    stripped = re.sub(r"[*\[\]]|\([^)]*\.md\)", "", section.body)
    words = [word for word in stripped.split() if word not in {"-", "1."}]
    excerpt = " ".join(words[:EXCERPT_WORDS])
    return (
        f"{section.number}: {excerpt}…"
        if len(words) > EXCERPT_WORDS
        else f"{section.number}: {excerpt}"
    )


def _section_markdown(section: Section, snapshot: Snapshot) -> str:
    by_slug = {s.slug: s for s in snapshot.sections}
    parts = [f"# {_heading(section)}"]
    source = f"{GUIDELINES_URL}#{section.slug}"
    parts.append(
        f"Source: [App Review Guidelines]({source}), last updated {snapshot.last_updated}."
    )
    if section.body:
        parts.append(PSEUDO_HEADING.sub(r"## \1", section.body))
    if section.children:
        links = "\n".join(f"- [{_label(by_slug[child])}]({child}.md)" for child in section.children)
        parts.append(f"## Subsections\n\n{links}")
    return "\n\n".join(parts) + "\n"


def _index_markdown(snapshot: Snapshot) -> str:
    by_slug = {s.slug: s for s in snapshot.sections}
    lines: list[str] = []

    def walk(slug: str, depth: int) -> None:
        section = by_slug[slug]
        lines.append(f"{'  ' * depth}- [{_label(section)}]({slug}.md)")
        for child in section.children:
            walk(child, depth + 1)

    for section in snapshot.sections:
        if section.parent is None:
            walk(section.slug, 0)
    return (
        "# App Review Guidelines mirror\n\n"
        f"Apple's [App Review Guidelines]({GUIDELINES_URL}), one file per section, "
        f"as last updated by Apple on {snapshot.last_updated}. "
        "Regenerate with `uv run rulebook mirror`; "
        "the git history of this folder is the changelog.\n\n" + "\n".join(lines) + "\n"
    )
