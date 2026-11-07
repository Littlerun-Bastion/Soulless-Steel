# Steelapedia: writing guide

Steelapedia is the encyclopedia on the NET (`steelapedia.net`). This guide tells you how to write its articles.

The code is `game/net/steelapedia/Steelapedia.gd` (the articles), `game/net/steelapedia/SteelapediaMarkup.gd` (the markup) and `game/ui/net/sites/steelapedia/SteelapediaPage.gd` (the pages).

## Where to put an article

Put each article in a text file: `database/steelapedia/<category>/<slug>.txt`.

| Folder | Use it for |
|---|---|
| `parts` | Parts. The slug is the part id, for example `MA-L127.txt`. |
| `manufacturers` | Makers. The slug is the maker id, for example `martel.txt`. |
| `entities` | Entity species. The slug is the species with `_` for spaces, for example `coyote_spitter.txt`. |
| `pilots` | Pilots. |
| `places` | Places. |
| `history` | History. |
| `misc` | Everything else. |

Make the folder if it does not exist.

The file name is the slug. Slugs are not case-sensitive. Use `_` for spaces. Do not use the same slug in two folders.

## The file format

A file has a header, a line with `---`, and the body.

```
title: Martel Shipping and SAV Manufacturing
summary: One line for search results and the Main Page.
requires: {"flags": {"met_martel": true}}
infobox.Founded: [YEAR]
infobox.Headquarters: [PLACE]
see_also: orontes, pt_gajah_teknis
categories: shipping
---
'''Martel''' is ...

== History ==
Text with a [[orontes|link to another article]] and [[pt_gajah_teknis]].
```

## The header keys

Write each header line as `key: value`.

| Key | Meaning |
|---|---|
| `title` | The title. |
| `summary` | One line. Search results and the Main Page show it. |
| `requires` | Story conditions, written as JSON. The whole article is hidden until they pass. |
| `infobox.<Label>` | One row of the infobox: the label, then the value. The rows keep the file order. A value can use links. |
| `see_also` | Slugs, with commas between them. They go under "See also". |
| `categories` | More categories, with commas between them. The folder is always a category. |

A line that starts with `#` is a note. The game ignores it.

The conditions use the `StoryDirector` shapes:

- `{"reached": "chapter_2"}`: the story reached the chapter (or `"chapter_2/beat"`).
- `{"not_reached": "chapter_2"}`: the story did not reach it.
- `{"flags": {"met_martel": true}}`: each flag has that value.

## The markup

| Markup | Result |
|---|---|
| `== Heading ==` | A section heading. It goes into the contents box. |
| `=== Subheading ===` | A subsection heading. |
| `requires: {...}` on the line after a heading | The section stays hidden until the conditions pass. |
| `'''bold'''` | **Bold.** |
| `''italic''` | *Italic.* |
| `[[slug]]` | A link to an article. It shows the article's title. |
| `[[slug\|text]]` | A link to an article, with your text. |
| `[[net:pilot.net/board/news\|text]]` | A link to another NET site. |
| `* item` | A bullet. |
| A blank line | A new paragraph. |

A link to a slug with no article shows dim and struck through. This is a "red link". The link still works. It goes to a "no article" page.

The contents box shows when an article has three or more headings.

## How section requires work

Put a `requires:` line directly after a heading:

```
== Products ==
requires: {"reached": "chapter_2"}
* A bullet.
```

The section stays hidden until the conditions pass. Its subsections (`===`) stay hidden too. The other sections show. Use this to make an article grow as the story moves.

The game checks the conditions every time the player opens the page. A change in the story shows at once.

"This page was last modified on Day n" shows the day the article first became visible. An article with no `requires` shows Day 1.

## Articles that the game makes

The game makes some articles from its data. You do not need a file for them.

| Articles | Which ones | Generated data |
|---|---|---|
| Parts | Every part that amazing.com sells. A secret part (`store_listed` off) only after the player has owned one. Never test parts. | Infobox: maker, part type, tech tier, price, weight, size and the comparison stats. A link to buy it on amazing.com. |
| Manufacturers | Every maker but the test maker. | Infobox: name, short name, website, parts in the catalogue. A list of the maker's parts under "Products". A link to the maker's stock on amazing.com. |
| Entities | Every Entity species with a scene in `game/entities/`. | Infobox: species and `[CLASSIFICATION]`. |

Their prose is Lorem Ipsum. Each article always shows the same Lorem Ipsum.

Generated parts are also in a category for their part type (for example "Heads") and for their maker (for example "Martel").

## How a file replaces generated text

Write a file with the same slug. Put it in the right folder.

- The file's body replaces the Lorem Ipsum.
- The file's `summary` replaces the generated summary.
- The file's `requires` hides the article until it passes.
- The generated data stays. The game adds the file's `infobox.` rows after the generated rows.
- The maker's list of parts stays. The game adds it under your "Products" section. If you have no "Products" section, the game adds one.
- The title stays the part's or the maker's name, unless the file gives a `title`.

Example, `database/steelapedia/parts/MA-L127.txt`:

```
summary: The rifle every new pilot starts with.
---
'''MA-L127''' is ...

== Overview ==
Your text.
```

## The sample files

The folders `pilots`, `places`, `history` and `misc` each hold one sample file. Their titles start with `[SAMPLE]`. `misc/sample_markup.txt` uses every row of the markup table. Delete the samples when you do not need them.

## How to test an article

1. Edit or add the file.
2. In the game, press **F9**. Steelapedia reads its files again. (pilot.net also does.)
3. Open the article on `steelapedia.net/wiki/<slug>`.

Run `run_tests.bat --suite=Steelapedia` after you change files. The test reports a header line it cannot read, an unknown header key, a `requires` that is not JSON, a missing `---` line and a slug that two files use.
