---
hide:
  - navigation
---

# Genestack Documentation Standards and Style Guide

This document is intended to help define some common documentation standards and practices for the [Genestack documentation](https://docs.rackspacecloud.com/){:target="_blank"}.

## Introduction

The Genestack documentation is built using [mkdocs-material](https://squidfunk.github.io/mkdocs-material/){:target="_blank"} with the source files located directly in the [docs subdirectory](https://github.com/rackerlabs/genestack/tree/main/docs){:target="_blank"} of the [Genestack project](https://github.com/rackerlabs/genestack){:target="_blank"}.

This page highlights some of the conventions and standards we strive to use across the Genestack documentation to hopefully provide a consistent reading experience for Genestack users.

## Page Layout

Each page should start with a top-level heading (single `#`) with the tile of the page.

Subsections start with 2nd-level headings (double `##`) and can have various levels nested underneath, 3rd-level (triple `###`), 4th-level (quad `####`), etc...

## Markdown

While easy to use, Markdown does have some "gotchas" that make writing documentation interesting.  It's easy to make some [common mistakes](https://gist.github.com/OpenStackKen/52d70ef2be6570fbd2603738e02adacc) when writing Markdown that can result in bad, illegible, or unintentionally humorous rendering issues.

This is mostly due to ambiguous information on how to implement certain edge-cases. CommonMark was one standard put in place to attempt to make this easier for authors.

Here are some notes on Markdown syntax used in mkdocs:

### Headings

The headings (defined by `#`) should follow a natural progression of the hierarchy of the page contents. You cannot have two title headings otherwise they won't show up on the table of contents on the right side of the page:

```markdown
# Title
## Main heading one
### Sub Heading one
### Sub heading two
## Main heading two
```

### Links

Links should follow this syntax:

```markdown
[Link](path to link)
```

If it is a link to another wiki page it should be a relative path:

```markdown
[Installation](Installation)
```

and not like this:

```markdown
[Installation](https://github.com/username/repo/wiki/Installation)
```

Instead, use that style for external links.  Also, for external links, please add `{:target="_blank"}` at the end to have the link open in a new window:

```markdown
[Google](https://google.com)){:target="_blank"}
```

### Code Blocks

#### Inline

Inline code blocks are indicated with single backticks: \`

```markdown
`inline`
```

This will render as: `inline`

#### Code blocks

Code blocks are _fenced_ with triple backtick fences

````markdown
```
# code block
```
````

This will render as:

```markdown
# code block
```

### Bullets

Bullets are used to denote unordered lists.  To have nested layers of bullets, you need to indent by 4 spaces for each nested layer bullet[^1].

```markdown
- Bullet
    - Sub bullet
        - Sub sub bullet
```

This will render like this:

- Bullet
  - Sub bullet
    - Sub sub bullet

**NOTE:** [Markdownlint](#markdownlint) will complain, saying that you should _indent by 2_ unless you change or ignore rule [MD007](https://github.com/DavidAnson/markdownlint/blob/main/doc/md007.md){:target="_blank"}.

### Numbering

Numbers will only order properly if in a listed sequence. If that sequence is broken by paragraphs then the numbering will restart.

Numbered lists are formatted as follows:

```markdown
1. item 1
2. item 2
3. item 3
4. item 4
```

### Symbols/Emojis

Emojis are not supported with python markdown and should be avoided. Rather important text should be bolded or italicized.

The following in github:

```markdown
:exclamation:
```

renders to :exclamation:

but in the generated docs it will show

```markdown
:exclamation:
```

### Markdownlint

Using [markdownlint](https://github.com/DavidAnson/markdownlint){:target="_blank"} on your files before you check them in can save you a lot of time and hassle. While some of mkdocs

You can use markdownlint from the CLI, or as a plugin in [Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint){:target="_blank"}.

For other editors there are also solutions:

- For Emacs, there is [markdown mode](https://jblevins.org/projects/markdown-mode){:target="_blank"}.
- For vim, there is a [markdown plugin](https://github.com/preservim/vim-markdown){:target="_blank"} as well as a [markdownlint plugin](https://github.com/fannheyward/coc-markdownlint){:target="_blank"} available.

## Admonitions

Admonitions are used to highlight certain information to make it stand-out to readers.

### Admonition Standards

It is important to have some documentation standards so that a user can understand how to process the information they read.

!!! info
    The "info" admonition type is to point out something particularly interesting.

!!! info "To Do"
    For "To Do" items, use the "info" admonition with a "To Do" title
    ...

!!! tip
    The "tip" admonition type is to show a recommended or preferred way to implement a detail or to address a concern.

!!! warning
    The "warning" admonition type should be use to show when something can have adverse consequences if incorrectly implemented or if certain precautions are not taken.

### Custom Admonition Types

!!! genestack
    The "genestack" admonition type is for Genestack-specific information or to point how _how_ something is done in Genestack.

[^1]: This is explained [here](https://python-markdown.github.io/#differences){:target="_blank"} in the python-markdown docmentation.
