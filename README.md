# ghwt — GitHub Workflow Templates

ghwt is a collection of opinionated, reusable GitHub Actions workflow templates
with a generator script to select, configure, and install them into any project.

## Templates

Templates are organised by language and package manager. The following stacks
are currently supported:

- **Python / uv** — CI, GitHub Pages (Sphinx), PyPI release
- **TypeScript / npm** — CI, GitHub Pages (Astro Starlight), VS Code extension release

Two language-agnostic templates are available for any project regardless of stack:

- **Dependabot** — automated weekly dependency updates grouped by type
- **Mirror** — one-way mirror to Codeberg

## Installation

Clone the repository and make the generator executable:

```bash
git clone https://github.com/@@GITHUB_USER@@/ghwt.git
chmod +x ghwt/generate.sh
```

On first run, `generate.sh` automatically creates the `bin/ghwt` symlink. To
use `ghwt` from any directory, add `bin/` to your `PATH` in your shell config:

```bash
# ~/.bashrc or ~/.zshrc
export PATH="/path/to/ghwt/bin:$PATH"
```

## Usage

Navigate to your project directory and run:

```bash
ghwt
```

The generator walks through four steps:

1. **Language** — select your project's language
2. **Package manager** — select the package manager for that language
3. **Workflows** — select which workflows to install (press enter to select all)
4. **Project settings** — supply values for any placeholders required by the
   selected templates

To pre-select workflow categories and skip step 3:

```bash
ghwt ci release
```

### Output

Generated files are written relative to the current directory:

```text
.github/
├── workflows/
│   ├── ci.yml
│   ├── gh-pages.yml
│   ├── mirror.yml
│   └── release.yml
└── dependabot.yml
```

### Config file

A `.ghwt` file is created in the current directory after the first run. It
persists your placeholder values so subsequent runs offer them as defaults —
useful when adding workflows to an existing project.

## Placeholders

Placeholders use the `@@VAR_NAME@@` syntax and are replaced at generation time.
The generator prompts for each value found in the selected templates.
`@@PACKAGE_MANAGER@@` is resolved automatically from your package manager
selection and never prompted for.

Some placeholders are seeded with sensible defaults:

| Placeholder | Default |
|---|---|
| `@@NODE_VERSION@@` | `22` |
| `@@CODEBERG_USER@@` | value of `@@GITHUB_USER@@` |
| `@@CODEBERG_REPO@@` | value of `@@GITHUB_REPO@@` |
| `@@PYPI_PACKAGE@@` | value of `@@GITHUB_REPO@@` |

## Python CI — Makefile requirement

The Python CI workflow delegates linting and testing to `make`, which must be
present in the project root. The following targets are required:

```makefile
.PHONY: lint test

lint:
	uv run ruff format src/ --check
	uv run ruff check src/
	uv run bandit --config pyproject.toml --recursive src/ --severity-level medium --confidence-level low
	uv run yamllint -c .yamllint.yml .
	uv run rumdl check .

test:
	uv run pytest
```

Adjust the `lint` target to match your project's tooling. The `make lint` and
`make test` commands in the workflow are fixed — only the `Makefile` itself
needs to change.
