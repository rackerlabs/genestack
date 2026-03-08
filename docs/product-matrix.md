# Product Matrix
All release notes are automatically generated using the **Python script** found in [scripts/generate_product_matrix.py](https://github.com/rackerlabs/genestack/scripts/generate_product_matrix.py).

To manually generate and update this file, run the following commands from the **root of the repository**:

```shell
poetry install --with docs,runtime --no-root
poetry run python scripts/generate_product_matrix.py
```
