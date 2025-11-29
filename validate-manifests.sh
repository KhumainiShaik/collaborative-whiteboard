#!/bin/bash
# Validate all Kubernetes manifests

set -e

echo "🔍 Validating Kubernetes manifests..."
echo

MANIFEST_DIR="k8s-manifests"
ERRORS=0

for file in $MANIFEST_DIR/*.yaml; do
  echo "Checking: $file"
  
  # Check if kubectl is available
  if command -v kubectl &> /dev/null; then
    if kubectl apply -f "$file" --dry-run=client -o yaml > /dev/null 2>&1; then
      echo "  ✅ Valid"
    else
      echo "  ❌ INVALID"
      ERRORS=$((ERRORS + 1))
    fi
  else
    # Fallback: just check YAML syntax
    if command -v python3 &> /dev/null; then
      python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>&1 && echo "  ✅ Valid YAML" || {
        echo "  ❌ Invalid YAML"
        ERRORS=$((ERRORS + 1))
      }
    else
      echo "  ⚠️  Skipped (no kubectl or python3)"
    fi
  fi
done

echo
if [ $ERRORS -eq 0 ]; then
  echo "✅ All manifests are valid!"
  exit 0
else
  echo "❌ $ERRORS manifest(s) have errors"
  exit 1
fi
