import os
import sys

# Add current dir to path
sys.path.append(os.getcwd())

try:
    print("Testing imports...")
    from whisper_client import WhisperClient
    print("Imports successful.")

    print("Initializing WhisperClient (downloading/loading model)...")
    # Use tiny.en for quick test
    client = WhisperClient(model_size="tiny.en", device="cpu")
    print("Model loaded.")

    print("Verification passed!")
except Exception as e:
    print(f"Verification FAILED: {e}")
    sys.exit(1)
