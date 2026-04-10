# Release Notes

This page is the navigation index for versioned Genestack release notes.

## Available Releases

- [Release 2026.1](release-2026.1.md)

## Maintainer Notes

Versioned release notes are generated from [reno](https://docs.openstack.org/reno/latest/) and then published as separate documentation pages.

Example generation workflow:

```shell
pip install -r doc-requirements.txt -r dev-requirements.txt
apt update && apt install -y pandoc
reno report -o /tmp/reno.rst
pandoc /tmp/reno.rst -f rst -t markdown -o docs/release-<version>.md
```
