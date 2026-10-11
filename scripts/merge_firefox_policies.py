#!/usr/bin/env python3
"""Merge recommended policies; preserve existing scalar choices by default."""
import argparse
import json
import sys


def merge(existing, desired, replace=False):
    result = dict(existing)
    for key, value in desired.items():
        if key not in result:
            result[key] = value
        elif isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = merge(result[key], value, replace)
        elif isinstance(result[key], list) and isinstance(value, list):
            result[key] = result[key] + [item for item in value if item not in result[key]]
        elif replace:
            result[key] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('existing')
    parser.add_argument('desired')
    parser.add_argument('--replace', action='store_true')
    args = parser.parse_args()
    docs = []
    for path in (args.existing, args.desired):
        with open(path) as stream:
            doc = json.load(stream)
        if not isinstance(doc, dict) or not isinstance(doc.get('policies'), dict):
            raise ValueError(f'{path}: expected a policies object')
        docs.append(doc)
    json.dump(merge(*docs, replace=args.replace), sys.stdout, indent=2)
    print()


if __name__ == '__main__':
    main()
