# Product Matrix
All release notes are automatically generated using the **Python script** found in [scripts/generate_product_matrix.py](https://github.com/rackerlabs/genestack/scripts/generate_product_matrix.py).

To manually generate and update this file, run the following commands from the **root of the repository**:

```shell
pip install -r doc-requirements.txt -r dev-requirements.txt
python scripts/generate_product_matrix.py --release release-2026.2.0
python scripts/generate_product_matrix.py --from-tag release-2026.1.0 --to-tag release-2026.2.0
```
