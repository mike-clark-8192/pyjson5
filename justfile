set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

default:
    @just --list

# Create/refresh the local environment (useful for editors).
sync:
    uv sync --extra dev

# Run doctests and unit tests. Pass extra args through to `python -m unittest`,
# e.g. `just test -v` or `just test -k foo`.
test *args:
    uv run python -m doctest json5/lib.py
    uv run python -m unittest discover -p '*_test.py' {{args}}

tests *args: (test args)

format:
    uv run --extra dev ruff format

format-check:
    uv run --extra dev ruff format --check

check:
    uv run --extra dev ruff check

pylint:
    uv run --extra dev pylint run json5 tests benchmarks

mypy:
    uv run --extra dev mypy json5 tests benchmarks/run.py

coverage:
    uv run --extra dev coverage run -m unittest discover -p '*_test.py'
    uv run --extra dev coverage report --show-missing

build:
    uv build

twine-check:
    uv run --extra dev twine check dist/*

publish-test:
    uv run --extra dev twine upload --repository testpypi dist/*

publish-prod:
    uv run --extra dev twine upload dist/*

clean:
    uv run python -c 'import shutil, pathlib; paths=[".coverage","build","dist","json5.egg-info"]; [shutil.rmtree(p, ignore_errors=True) if pathlib.Path(p).is_dir() else pathlib.Path(p).unlink(missing_ok=True) for p in paths]'

regen:
    uv run python ../glop/glop/tool.py -o json5/parser.py --no-main --no-memoize -c json5/json5.g
    uv run --extra dev ruff format json5/parser.py

regen-check:
    just regen
    git diff --exit-code -- json5/parser.py

presubmit: regen-check format-check check pylint mypy coverage build twine-check
