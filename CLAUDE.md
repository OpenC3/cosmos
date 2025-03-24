# OpenC3 COSMOS Development Guide

## Build/Test Commands
- Ruby unit tests: `bundle exec rake build spec` (in openc3 dir)
- Ruby single test: `bundle exec rspec spec/path/to/file_spec.rb` 
- Python unit tests: `cd openc3/python && poetry run pytest ./test/`
- Python single test: `cd openc3/python && poetry run pytest ./test/path/to/test_file.py`
- Python linting: `cd openc3/python && poetry run ruff check openc3`
- Integration tests: `npm run playwright` (in playwright dir)

## Code Style

### Ruby
- Line length: No limit (rubocop disabled)
- Styling: Follow existing conventions in similar files
- Error handling: Use begin/rescue blocks appropriately

### Python
- Line length: 120 characters max (black/ruff configured)
- Formatting: Use black and ruff for formatting
- Imports: Standard library first, then third-party, then local
- Types: Python 3.10+ type hints encouraged
- Error handling: Use try/except with specific exceptions

### General Practices
- Write tests for new functionality
- Follow existing code patterns
- Document complex logic
- Commit messages: Describe what and why, not how