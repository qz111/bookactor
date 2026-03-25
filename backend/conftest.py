import sys
import os

# Add the repo root to sys.path so tests can import `backend.services.*` etc.
# This makes pytest invocations from any working directory work correctly.
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
