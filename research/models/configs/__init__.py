import yaml
from pathlib import Path


def load_config(config_path: str) -> dict:
    """Load a YAML config file, merging with base.yaml defaults."""
    config_dir = Path(__file__).parent

    # Load base config
    with open(config_dir / "base.yaml") as f:
        base = yaml.safe_load(f)

    # Load experiment config
    with open(config_path) as f:
        experiment = yaml.safe_load(f)

    # Deep merge: experiment overrides base
    config = _deep_merge(base, experiment)
    return config


def _deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override into base."""
    result = base.copy()
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result
