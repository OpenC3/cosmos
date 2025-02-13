## Python support for OpenC3 COSMOS v5

---

This project allows accessing the COSMOS v5 API from the python programming language.
Additional functionality and support will be added over time.

---

[![Code style: black](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/psf/black)

## Installation:

```
cosmos/openc3/python % pip install openc3
cosmos/openc3/python % pip install poetry
cosmos/openc3/python % poetry install
```

### Development

Every command should be prefixed with poetry to ensure the correct environment. To run the unit tests and generate a report:

```
cosmos/openc3/python % poetry run coverage run -m pytest
cosmos/openc3/python % poetry run coverage html
```
