# Release Notes

All release notes are generated using [reno](https://docs.openstack.org/reno/latest/).

To manaually generate your release notes and see this file populated, run the following commands

``` shell
pip install -r doc-requirements.txt -r dev-requirements.txt
apt update && apt install -y pandoc
reno report -o /tmp/reno.rst
pandoc /tmp/reno.rst -f rst -t markdown -o docs/release-notes.md
```
