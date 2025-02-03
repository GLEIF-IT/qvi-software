.PHONY: all build

all: test

setup:
	@curl -LsSf https://astral.sh/uv/install.sh | sh
	@uv venv
	@uv lock

test:
	@uv run behave

fmt:
	@uv tool run ruff check --select I --fix
	@uv tool run ruff format

check:
	uv tool run ruff check --select I
	uv tool run ruff format --check
