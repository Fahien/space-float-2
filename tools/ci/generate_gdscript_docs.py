#!/usr/bin/env python3
"""Generate a static website from Godot GDScript docs XML."""

from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
import html
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import quote, urljoin, urlparse
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET


GODOT_DOCS_STATIC_BASE_URL = "https://docs.godotengine.org/en/stable/_static"
GODOT_DOCS_THEME_CSS_URL = f"{GODOT_DOCS_STATIC_BASE_URL}/css/theme.css"
GODOT_DOCS_CUSTOM_CSS_URL = f"{GODOT_DOCS_STATIC_BASE_URL}/css/custom.css"
GODOT_DOCS_CLASS_BASE_URL = "https://docs.godotengine.org/en/stable/classes"
GODOT_DOCS_LOCAL_STATIC_DIR = "_static"
GODOT_DOCS_LOCAL_THEME_CSS_PATH = f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/theme.css"
GODOT_DOCS_LOCAL_CUSTOM_CSS_PATH = f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/custom.css"
GODOT_DOCS_FONT_PRELOADS = (
    f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/fonts/Inter-Regular.woff2",
    f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/fonts/Inter-Italic.woff2",
    f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/fonts/Inter-Bold.woff2",
    f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/fonts/Inter-BoldItalic.woff2",
    f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/fonts/JetBrainsMono-Regular.woff2",
    f"{GODOT_DOCS_LOCAL_STATIC_DIR}/css/fonts/JetBrainsMono-Medium.woff2",
)
TYPE_ATOM_RE = re.compile(r"^@?[A-Za-z_][A-Za-z0-9_.]*$")
CSS_URL_RE = re.compile(r"url\(\s*(['\"]?)(?P<url>[^'\"\)]+)\1\s*\)")
GODOT_BASE_TYPES = frozenset(
    {
        "AABB",
        "Array",
        "Basis",
        "bool",
        "Callable",
        "Color",
        "Dictionary",
        "float",
        "int",
        "Nil",
        "NodePath",
        "PackedByteArray",
        "PackedColorArray",
        "PackedFloat32Array",
        "PackedFloat64Array",
        "PackedInt32Array",
        "PackedInt64Array",
        "PackedStringArray",
        "PackedVector2Array",
        "PackedVector3Array",
        "PackedVector4Array",
        "Plane",
        "Projection",
        "Quaternion",
        "Rect2",
        "Rect2i",
        "RID",
        "Signal",
        "String",
        "StringName",
        "Transform2D",
        "Transform3D",
        "Variant",
        "Vector2",
        "Vector2i",
        "Vector3",
        "Vector3i",
        "Vector4",
        "Vector4i",
        "void",
    }
)


@dataclass(frozen=True)
class ArgumentDoc:
    name: str
    type_name: str
    default: str = ""


@dataclass(frozen=True)
class CallableDoc:
    name: str
    return_type: str
    description: str
    arguments: tuple[ArgumentDoc, ...] = ()


@dataclass(frozen=True)
class MemberDoc:
    name: str
    type_name: str
    default: str
    description: str


@dataclass(frozen=True)
class ClassDoc:
    name: str
    inherits: str
    brief: str
    description: str
    members: tuple[MemberDoc, ...] = ()
    methods: tuple[CallableDoc, ...] = ()
    signals: tuple[CallableDoc, ...] = ()
    file_name: str = field(default="")


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Generate a static API website from GDScript inline docs.",
    )
    parser.add_argument(
        "--godot",
        default=os.environ.get("GODOT_BIN", ""),
        help="Godot editor binary. Defaults to GODOT_BIN.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=project_root,
        help=f"Godot project root. Defaults to {project_root}.",
    )
    parser.add_argument(
        "--source",
        default="res://scene",
        help="GDScript docs source path passed to --gdscript-docs.",
    )
    parser.add_argument(
        "--xml-dir",
        type=Path,
        default=project_root / "target" / "docs" / "xml",
        help="Directory for Godot doctool XML output.",
    )
    parser.add_argument(
        "--site-dir",
        type=Path,
        default=project_root / "target" / "docs" / "site",
        help="Directory for generated static HTML.",
    )
    parser.add_argument(
        "--reports-dir",
        type=Path,
        default=project_root / "target" / "reports",
        help="Directory for Godot logs.",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


def fetch_bytes(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "space-float-2-docs-builder"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def write_download(url: str, path: Path) -> bytes:
    content = fetch_bytes(url)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return content


def is_local_css_asset(url: str) -> bool:
    stripped_url = url.strip()
    parsed_url = urlparse(stripped_url)
    return not (
        stripped_url.startswith("//")
        or parsed_url.scheme
        or parsed_url.path.startswith("/")
        or parsed_url.path.startswith("..")
    )


def iter_local_css_assets(css: str) -> tuple[str, ...]:
    assets: list[str] = []
    seen: set[str] = set()
    for match in CSS_URL_RE.finditer(css):
        asset_url = match.group("url").strip()
        if not is_local_css_asset(asset_url):
            continue
        parsed_asset = urlparse(asset_url)
        if parsed_asset.path in seen:
            continue
        seen.add(parsed_asset.path)
        assets.append(asset_url)
    return tuple(assets)


def write_godot_theme_assets(site_dir: Path) -> None:
    static_dir = site_dir / GODOT_DOCS_LOCAL_STATIC_DIR
    downloaded_assets: set[Path] = set()
    css_assets = (
        (GODOT_DOCS_THEME_CSS_URL, Path("css/theme.css")),
        (GODOT_DOCS_CUSTOM_CSS_URL, Path("css/custom.css")),
    )

    for css_url, local_css_path in css_assets:
        css_content = write_download(css_url, static_dir / local_css_path).decode("utf-8")
        for asset_url in iter_local_css_assets(css_content):
            parsed_asset = urlparse(asset_url)
            local_asset_path = local_css_path.parent / parsed_asset.path
            if local_asset_path in downloaded_assets:
                continue
            downloaded_assets.add(local_asset_path)
            write_download(urljoin(css_url, asset_url), static_dir / local_asset_path)


def clean_text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    text = "".join(element.itertext())
    lines = [line.strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line).strip()


def slug(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_") or "class"


def anchor_slug(value: str) -> str:
    return slug(value).replace("_", "-").lower()


def code_literal(value: str) -> str:
    return f'<code class="docutils literal notranslate"><span class="pre">{html.escape(value)}</span></code>'


def inline_markup(text: str) -> str:
    parts: list[str] = []
    cursor = 0
    for match in re.finditer(r"`([^`]+)`", text):
        parts.append(html.escape(text[cursor : match.start()]))
        parts.append(code_literal(match.group(1)))
        cursor = match.end()
    parts.append(html.escape(text[cursor:]))
    return "".join(parts)


def render_description(text: str, fallback: str = "No description.") -> str:
    if not text:
        return f'<p class="muted">{html.escape(fallback)}</p>'

    paragraphs = [paragraph.strip() for paragraph in re.split(r"\n\s*\n", text) if paragraph.strip()]
    if not paragraphs:
        paragraphs = [text.strip()]
    return "\n".join(f"<p>{inline_markup(paragraph)}</p>" for paragraph in paragraphs)


def parse_arguments(parent: ET.Element) -> tuple[ArgumentDoc, ...]:
    arguments: list[ArgumentDoc] = []
    for param in parent.findall("param"):
        arguments.append(
            ArgumentDoc(
                name=param.get("name", ""),
                type_name=param.get("type", ""),
                default=param.get("default", ""),
            )
        )
    return tuple(arguments)


def parse_callable(element: ET.Element) -> CallableDoc:
    return_element = element.find("return")
    return_type = return_element.get("type", "void") if return_element is not None else "void"
    return CallableDoc(
        name=element.get("name", ""),
        return_type=return_type,
        description=clean_text(element.find("description")),
        arguments=parse_arguments(element),
    )


def parse_class(path: Path) -> ClassDoc:
    root = ET.parse(path).getroot()
    name = root.get("name", path.stem)
    members: list[MemberDoc] = []
    methods: list[CallableDoc] = []
    signals: list[CallableDoc] = []

    for member in root.findall("./members/member"):
        members.append(
            MemberDoc(
                name=member.get("name", ""),
                type_name=member.get("type", ""),
                default=member.get("default", ""),
                description=clean_text(member),
            )
        )

    for method in root.findall("./methods/method"):
        methods.append(parse_callable(method))

    for signal in root.findall("./signals/signal"):
        signals.append(parse_callable(signal))

    return ClassDoc(
        name=name,
        inherits=root.get("inherits", ""),
        brief=clean_text(root.find("brief_description")),
        description=clean_text(root.find("description")),
        members=tuple(members),
        methods=tuple(methods),
        signals=tuple(signals),
        file_name=f"{slug(name)}.html",
    )


def classref_anchor(class_doc: ClassDoc, item_kind: str, item_name: str) -> str:
    return f"class-{anchor_slug(class_doc.name)}-{item_kind}-{anchor_slug(item_name)}"


def classref_self_link(anchor: str) -> str:
    return f'<a class="reference internal" href="#{anchor}"><span class="std std-ref">&#128279;</span></a>'


def class_page_map(class_docs: Sequence[ClassDoc]) -> dict[str, str]:
    return {class_doc.name: class_doc.file_name for class_doc in class_docs}


def godot_class_url(type_name: str) -> str:
    return f"{GODOT_DOCS_CLASS_BASE_URL}/class_{quote(type_name.lower(), safe='')}.html"


def type_punctuation(value: str) -> str:
    return f'<span class="classref-type-punctuation">{html.escape(value)}</span>'


def split_type_arguments(arguments: str) -> tuple[str, ...]:
    parts: list[str] = []
    depth = 0
    start = 0
    for index, char in enumerate(arguments):
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(arguments[start:index].strip())
            start = index + 1
    parts.append(arguments[start:].strip())
    return tuple(part for part in parts if part)


def find_generic_arguments(type_name: str) -> tuple[str, str] | None:
    depth = 0
    start = -1
    for index, char in enumerate(type_name):
        if char == "[":
            if depth == 0:
                start = index
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0 and index != len(type_name) - 1:
                return None
            if depth < 0:
                return None
    if start == -1 or depth != 0 or not type_name.endswith("]"):
        return None
    return type_name[:start].strip(), type_name[start + 1 : -1]


def render_type_atom(type_name: str, class_pages: Mapping[str, str]) -> str:
    if type_name == "void":
        return '<abbr class="classref-type classref-type-base classref-type-void" title="No return value.">void</abbr>'

    if type_name in class_pages:
        escaped_type = html.escape(type_name)
        return (
            f'<a class="classref-type classref-type-user" href="{html.escape(class_pages[type_name])}">'
            f"{escaped_type}</a>"
        )

    if not TYPE_ATOM_RE.match(type_name):
        return f'<span class="classref-type classref-type-unknown">{html.escape(type_name)}</span>'

    if "." in type_name:
        owner, _, member = type_name.partition(".")
        if owner in class_pages:
            return (
                render_type_atom(owner, class_pages)
                + type_punctuation(".")
                + f'<span class="classref-type classref-type-user">{html.escape(member)}</span>'
            )
        return f'<span class="classref-type classref-type-unknown">{html.escape(type_name)}</span>'

    type_kind = "base" if type_name in GODOT_BASE_TYPES else "engine"
    return (
        f'<a class="classref-type classref-type-{type_kind}" href="{html.escape(godot_class_url(type_name))}">'
        f"{html.escape(type_name)}</a>"
    )


def render_type(type_name: str, class_pages: Mapping[str, str] | None = None) -> str:
    if not type_name:
        return ""
    class_pages = class_pages or {}
    stripped_type = type_name.strip()

    if stripped_type.endswith("[]"):
        return render_type(stripped_type[:-2], class_pages) + type_punctuation("[]")

    generic = find_generic_arguments(stripped_type)
    if generic:
        base_type, argument_list = generic
        arguments = split_type_arguments(argument_list)
        rendered_arguments = (
            type_punctuation(", ").join(render_type(argument, class_pages) for argument in arguments)
            if arguments
            else ""
        )
        return (
            render_type_atom(base_type, class_pages)
            + type_punctuation("[")
            + rendered_arguments
            + type_punctuation("]")
        )

    return render_type_atom(stripped_type, class_pages)


def render_arguments(arguments: Sequence[ArgumentDoc], class_pages: Mapping[str, str]) -> str:
    rendered_arguments: list[str] = []
    for argument in arguments:
        argument_parts = [html.escape(argument.name)]
        if argument.type_name:
            argument_parts.append(f": {render_type(argument.type_name, class_pages)}")
        if argument.default:
            argument_parts.append(f" = {html.escape(argument.default)}")
        rendered_arguments.append("".join(argument_parts))
    return ", ".join(rendered_arguments)


def render_h2(title: str) -> str:
    anchor = anchor_slug(title)
    return (
        f'<h2>{html.escape(title)}'
        f'<a class="headerlink" href="#{anchor}" title="Link to this heading">#</a></h2>'
    )


def render_reference_table(section_id: str, title: str, rows: Sequence[Sequence[str]]) -> str:
    parts = [
        f'<section class="classref-reftable-group" id="{section_id}">',
        render_h2(title),
        '<div class="wy-table-responsive">',
        '<table class="docutils align-default">',
        "<tbody>",
    ]
    for index, row in enumerate(rows):
        row_class = "row-odd" if index % 2 == 0 else "row-even"
        parts.append(f'<tr class="{row_class}">')
        for cell in row:
            parts.append(f"<td><p>{cell}</p></td>" if cell else "<td></td>")
        parts.append("</tr>")
    parts.extend(["</tbody>", "</table>", "</div>", "</section>"])
    return "\n".join(parts)


def render_member_reference_table(class_doc: ClassDoc, class_pages: Mapping[str, str]) -> str:
    rows: list[tuple[str, str, str]] = []
    for member in class_doc.members:
        anchor = classref_anchor(class_doc, "property", member.name)
        name = (
            f'<a class="reference internal" href="#{anchor}">'
            f'<span class="std std-ref">{html.escape(member.name)}</span></a>'
        )
        rows.append((render_type(member.type_name, class_pages), name, code_literal(member.default) if member.default else ""))
    return render_reference_table("properties", "Properties", rows)


def render_method_reference_table(class_doc: ClassDoc, class_pages: Mapping[str, str]) -> str:
    rows: list[tuple[str, str]] = []
    for method in class_doc.methods:
        anchor = classref_anchor(class_doc, "method", method.name)
        name = (
            f'<a class="reference internal" href="#{anchor}">'
            f'<span class="std std-ref">{html.escape(method.name)}</span></a>'
            f"({render_arguments(method.arguments, class_pages)})"
        )
        rows.append((render_type(method.return_type, class_pages), name))
    return render_reference_table("methods", "Methods", rows)


def render_descriptions_group(section_id: str, title: str, entries: Sequence[str]) -> str:
    parts = [
        '<hr class="classref-section-separator docutils" />',
        f'<section class="classref-descriptions-group" id="{section_id}">',
        render_h2(title),
    ]
    for index, entry in enumerate(entries):
        if index > 0:
            parts.append('<hr class="classref-item-separator docutils" />')
        parts.append(entry)
    parts.append("</section>")
    return "\n".join(parts)


def render_signal_description(class_doc: ClassDoc, signal: CallableDoc, class_pages: Mapping[str, str]) -> str:
    anchor = classref_anchor(class_doc, "signal", signal.name)
    signature = f"<strong>{html.escape(signal.name)}</strong>({render_arguments(signal.arguments, class_pages)})"
    return "\n".join(
        [
            f'<p class="classref-signal" id="{anchor}">{signature} {classref_self_link(anchor)}</p>',
            render_description(signal.description),
        ]
    )


def render_member_description(class_doc: ClassDoc, member: MemberDoc, class_pages: Mapping[str, str]) -> str:
    anchor = classref_anchor(class_doc, "property", member.name)
    default = f" = {code_literal(member.default)}" if member.default else ""
    type_name = f"{render_type(member.type_name, class_pages)} " if member.type_name else ""
    signature = f"{type_name}<strong>{html.escape(member.name)}</strong>{default}"
    return "\n".join(
        [
            f'<p class="classref-property" id="{anchor}">{signature} {classref_self_link(anchor)}</p>',
            render_description(member.description),
        ]
    )


def render_method_description(class_doc: ClassDoc, method: CallableDoc, class_pages: Mapping[str, str]) -> str:
    anchor = classref_anchor(class_doc, "method", method.name)
    return_type = f"{render_type(method.return_type, class_pages)} " if method.return_type else ""
    signature = f"{return_type}<strong>{html.escape(method.name)}</strong>({render_arguments(method.arguments, class_pages)})"
    return "\n".join(
        [
            f'<p class="classref-method" id="{anchor}">{signature} {classref_self_link(anchor)}</p>',
            render_description(method.description),
        ]
    )


def render_navigation(class_docs: Sequence[ClassDoc], active_file: str) -> str:
    index_active = active_file == "index.html"
    items = [
        f'<li class="toctree-l1{" current" if index_active else ""}">'
        f'<a class="reference internal{" current" if index_active else ""}" href="index.html">API index</a>'
        "</li>"
    ]
    for class_doc in class_docs:
        is_active = class_doc.file_name == active_file
        items.append(
            f'<li class="toctree-l1{" current" if is_active else ""}">'
            f'<a class="reference internal{" current" if is_active else ""}" href="{html.escape(class_doc.file_name)}">'
            f"{html.escape(class_doc.name)}</a></li>"
        )

    return "\n".join(
        [
            '<nav class="wy-nav-side" aria-label="Documentation navigation">',
            '  <div class="wy-side-scroll">',
            '    <div class="wy-side-nav-search">',
            '      <a class="project" href="index.html">space-float-2</a>',
            '      <div class="version">GDScript API</div>',
            "    </div>",
            '    <div class="wy-menu wy-menu-vertical">',
            '      <p class="caption active" role="heading"><span class="caption-text">API Reference</span></p>',
            '      <ul class="active">',
            "\n".join(f"        {item}" for item in items),
            "      </ul>",
            "    </div>",
            "  </div>",
            "</nav>",
        ]
    )


def page_shell(title: str, body: str, class_docs: Sequence[ClassDoc], active_file: str) -> str:
    navigation = render_navigation(class_docs, active_file)
    font_preloads = "\n".join(
        f'  <link rel="preload" href="{font_path}" as="font" type="font/woff2" crossorigin>'
        for font_path in GODOT_DOCS_FONT_PRELOADS
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
{font_preloads}
  <link rel="stylesheet" href="{GODOT_DOCS_LOCAL_THEME_CSS_PATH}">
  <link rel="stylesheet" href="{GODOT_DOCS_LOCAL_CUSTOM_CSS_PATH}">
  <link rel="stylesheet" href="style.css">
</head>
<body class="wy-body-for-nav">
  <div class="wy-grid-for-nav">
{navigation}
    <section class="wy-nav-content-wrap">
      <main class="wy-nav-content">
        <div class="rst-content">
{body}
        </div>
      </main>
    </section>
  </div>
</body>
</html>
"""


def render_class_page(class_doc: ClassDoc, class_docs: Sequence[ClassDoc]) -> str:
    class_pages = class_page_map(class_docs)
    inherits = (
        f"<p><strong>Inherits:</strong> {render_type(class_doc.inherits, class_pages)}</p>"
        if class_doc.inherits
        else ""
    )
    parts = [
        f'<p class="breadcrumbs"><a href="index.html">API index</a> / {html.escape(class_doc.name)}</p>',
        f"<h1>{html.escape(class_doc.name)}</h1>",
        inherits,
        render_description(class_doc.brief, "No brief description."),
    ]

    if class_doc.description:
        parts.extend(
            [
                '<section class="classref-introduction-group" id="description">',
                render_h2("Description"),
                render_description(class_doc.description),
                "</section>",
            ]
        )
    elif not class_doc.brief:
        parts.append(render_description("", "No description."))

    if class_doc.members:
        parts.append(render_member_reference_table(class_doc, class_pages))

    if class_doc.methods:
        parts.append(render_method_reference_table(class_doc, class_pages))

    if class_doc.signals:
        parts.append(
            render_descriptions_group(
                "signals",
                "Signals",
                [render_signal_description(class_doc, signal, class_pages) for signal in class_doc.signals],
            )
        )

    if class_doc.members:
        parts.append(
            render_descriptions_group(
                "property-descriptions",
                "Property Descriptions",
                [render_member_description(class_doc, member, class_pages) for member in class_doc.members],
            )
        )

    if class_doc.methods:
        parts.append(
            render_descriptions_group(
                "method-descriptions",
                "Method Descriptions",
                [render_method_description(class_doc, method, class_pages) for method in class_doc.methods],
            )
        )

    return page_shell(class_doc.name, "\n".join(part for part in parts if part), class_docs, class_doc.file_name)


def render_index(class_docs: Sequence[ClassDoc], source: str) -> str:
    class_pages = class_page_map(class_docs)
    cards: list[str] = []
    for class_doc in class_docs:
        inherits = f"<span>extends {render_type(class_doc.inherits, class_pages)}</span>" if class_doc.inherits else ""
        brief = class_doc.brief or class_doc.description or "No description."
        cards.append(
            "\n".join(
                [
                    '<section class="card">',
                    f'  <h2><a href="{html.escape(class_doc.file_name)}">{html.escape(class_doc.name)}</a></h2>',
                    f"  <p class=\"inherits\">{inherits}</p>" if inherits else "",
                    f"  {render_description(brief, 'No description.')}",
                    "</section>",
                ]
            )
        )

    body = "\n".join(
        [
            "<h1>space-float-2 GDScript API</h1>",
            f'<p class="summary">{len(class_docs)} documented classes generated from {code_literal(source)}.</p>',
            '<div class="grid">',
            "\n".join(cards),
            "</div>",
        ]
    )
    return page_shell("space-float-2 GDScript API", body, class_docs, "index.html")


def write_styles(site_dir: Path) -> None:
    css = """/* Local API-documentation additions. The base layout, colors, fonts, and dark
   mode are loaded as render-blocking stylesheets in each generated page. */

.wy-side-nav-search .project {
  color: var(--navbar-current-color);
  display: block;
  font-size: 1.35rem;
  font-weight: 700;
  overflow-wrap: anywhere;
  text-decoration: none;
}

.wy-side-nav-search .project:visited {
  color: var(--navbar-current-color);
}

.rst-content .breadcrumbs {
  color: var(--footer-color);
  font-size: 0.9rem;
  margin-bottom: 18px;
}

.rst-content .summary,
.rst-content .inherits,
.rst-content .muted {
  color: var(--classref-secondary-color);
}

.rst-content .classref-type {
  font-family: var(--monospace-font-family);
  font-weight: 600;
  text-decoration: none;
}

.rst-content a.classref-type:hover {
  text-decoration: underline;
}

.rst-content a.classref-type::after {
  display: none;
}

.rst-content .classref-type-base,
.rst-content a.classref-type-base:visited {
  color: var(--highlight-base-type-color);
}

.rst-content .classref-type-engine,
.rst-content a.classref-type-engine:visited {
  color: var(--highlight-engine-type-color);
}

.rst-content .classref-type-user,
.rst-content a.classref-type-user:visited {
  color: var(--highlight-user-type-color);
}

.rst-content .classref-type-unknown,
.rst-content .classref-type-punctuation {
  color: var(--classref-secondary-color);
}

.rst-content .classref-type-void {
  border-bottom: 1px dotted currentColor;
  cursor: help;
}

.rst-content .grid {
  display: grid;
  gap: 16px;
  grid-template-columns: repeat(auto-fit, minmax(min(280px, 100%), 1fr));
}

.rst-content .card {
  background: var(--content-background-color);
  border: 1px solid var(--hr-color);
  border-radius: 4px;
  padding: 16px;
}

.rst-content .card h2 {
  border-bottom: 0;
  font-size: 1.15rem;
  margin-top: 0;
  padding-bottom: 0;
}

@media screen and (max-width: 768px) {
  .rst-content .grid {
    grid-template-columns: 1fr;
  }
}
"""
    (site_dir / "style.css").write_text(css, encoding="utf-8")


def run_doctool(godot: str, project_root: Path, xml_dir: Path, reports_dir: Path, source: str) -> None:
    if not godot:
        fail("GODOT_BIN is required, or pass --godot")

    if xml_dir.exists():
        shutil.rmtree(xml_dir)
    xml_dir.mkdir(parents=True)
    reports_dir.mkdir(parents=True, exist_ok=True)

    command = [
        godot,
        "--headless",
        "--log-file",
        str(reports_dir / "docs.log"),
        "--path",
        str(project_root),
        "--doctool",
        str(xml_dir),
        "--gdscript-docs",
        source,
        "--no-docbase",
    ]
    result = run(command, project_root)
    if result.returncode != 0:
        fail(f"Godot doctool failed with exit code {result.returncode}:\n{result.stdout}")


def write_site(xml_dir: Path, site_dir: Path, source: str = "res://scene") -> None:
    xml_files = sorted(xml_dir.glob("*.xml"))
    if not xml_files:
        fail(f"no XML docs generated in {xml_dir}")

    class_docs = sorted((parse_class(path) for path in xml_files), key=lambda class_doc: class_doc.name.lower())

    if site_dir.exists():
        shutil.rmtree(site_dir)
    site_dir.mkdir(parents=True)
    write_godot_theme_assets(site_dir)
    write_styles(site_dir)

    (site_dir / "index.html").write_text(render_index(class_docs, source), encoding="utf-8")
    for class_doc in class_docs:
        (site_dir / class_doc.file_name).write_text(render_class_page(class_doc, class_docs), encoding="utf-8")

    if not (site_dir / "index.html").is_file():
        fail(f"failed to generate {site_dir / 'index.html'}")


def main() -> None:
    args = parse_args()
    project_root = args.project_root.resolve()
    if not (project_root / "project.godot").is_file():
        fail(f"{project_root} does not contain project.godot")

    run_doctool(args.godot, project_root, args.xml_dir.resolve(), args.reports_dir.resolve(), args.source)
    write_site(args.xml_dir.resolve(), args.site_dir.resolve(), args.source)
    print(f"Generated docs at {args.site_dir.resolve()}")


if __name__ == "__main__":
    main()
