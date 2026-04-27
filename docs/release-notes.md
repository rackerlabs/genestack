# Release Notes

This page is the navigation index for versioned Genestack release notes.

## Available Releases

- [Release 2026.1.0](release-2026.1.0.md)

## Maintainer Notes

Versioned release notes are generated from [reno](https://docs.openstack.org/reno/latest/) and then published as separate documentation pages.

Example generation workflow:

```shell
pip install -r doc-requirements.txt -r dev-requirements.txt
python scripts/generate_release_docs.py --release release-2026.1.0
```
