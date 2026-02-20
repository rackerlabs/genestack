# Working on docs locally

To work on documentation locally and preview it while developing, we can use `mkdocs serve`

Start by installing the requirements for documentation.

``` shell
poetry install --with docs --no-root
```

!!! tip

    Poetry creates and manages a virtual environment automatically.

Once the installation is done, run the mkdocs server locally to view your changes.

``` shell
cd genestack/
poetry run mkdocs serve
```
