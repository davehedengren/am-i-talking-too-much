"""
Am I Talking Too Much?

A simple app to track your speaking percentage in conversations.
Uses voice calibration and OpenAI Whisper for analysis.
"""

import streamlit as st
import numpy as np
import time
import tempfile
import os
from pathlib import Path
from dotenv import load_dotenv

from audio_recorder import (
    record_audio, record_audio_continuous, save_audio, save_to_temp_file,
    calculate_rms, SAMPLE_RATE, get_audio_devices, get_audio_level
)
from voice_matcher import (
    create_voice_profile, match_voice, VoiceProfile,
    save_profile, load_profile
)
from whisper_client import WhisperClient, test_api_key

# Load .env file from project directory
APP_DIR = Path(__file__).parent
ENV_PATH = APP_DIR / ".env"
PROFILE_PATH = APP_DIR / "voice_profile.json"

if ENV_PATH.exists():
    load_dotenv(ENV_PATH)


# Page config
st.set_page_config(
    page_title="Am I Talking Too Much?",
    page_icon="🎤",
    layout="centered"
)

# Custom CSS for cleaner look
st.markdown("""
<style>
    .main-header {
        font-size: 2.5rem;
        font-weight: 600;
        text-align: center;
        margin-bottom: 0.5rem;
    }
    .sub-header {
        font-size: 1.1rem;
        text-align: center;
        color: #666;
        margin-bottom: 2rem;
    }
    .big-number {
        font-size: 4rem;
        font-weight: 700;
        text-align: center;
    }
    .metric-label {
        font-size: 1.2rem;
        text-align: center;
        color: #666;
    }
    .stProgress > div > div > div > div {
        height: 20px;
    }
</style>
""", unsafe_allow_html=True)


def init_session_state():
    """Initialize session state variables."""
    if 'api_key' not in st.session_state:
        # Try to load from environment first
        env_key = os.getenv("OPENAI_API_KEY")
        st.session_state.api_key = env_key if env_key else None
    if 'debug_logs' not in st.session_state:
        st.session_state.debug_logs = []
    if 'voice_profile' not in st.session_state:
        # Try to load saved profile
        if PROFILE_PATH.exists():
            try:
                st.session_state.voice_profile = load_profile(str(PROFILE_PATH))
            except:
                st.session_state.voice_profile = None
        else:
            st.session_state.voice_profile = None
    if 'calibration_audio' not in st.session_state:
        st.session_state.calibration_audio = None
    if 'is_tracking' not in st.session_state:
        st.session_state.is_tracking = False
    if 'user_speaking_time' not in st.session_state:
        st.session_state.user_speaking_time = 0.0
    if 'total_time' not in st.session_state:
        st.session_state.total_time = 0.0
    if 'transcription' not in st.session_state:
        st.session_state.transcription = []
    if 'percentage_history' not in st.session_state:
        st.session_state.percentage_history = []
    if 'selected_device' not in st.session_state:
        st.session_state.selected_device = None
    if 'audio_devices' not in st.session_state:
        st.session_state.audio_devices = get_audio_devices()
    if 'transcription_enabled' not in st.session_state:
        st.session_state.transcription_enabled = False  # Off by default for fully local operation


def render_api_setup():
    """Render API key setup screen."""
    st.markdown('<p class="main-header">Am I Talking Too Much?</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-header">Track your speaking time in conversations</p>', unsafe_allow_html=True)

    st.markdown("### Step 1: Enter your OpenAI API key")

    # Check if key exists in environment
    env_key = os.getenv("OPENAI_API_KEY")
    if env_key:
        st.success("Found API key in .env file!")
        if st.button("Use .env API Key", type="primary"):
            with st.spinner("Validating API key..."):
                is_valid, message = test_api_key(env_key)
                if is_valid:
                    st.session_state.api_key = env_key
                    st.rerun()
                else:
                    st.error(message)
        st.markdown("---")
        st.markdown("Or enter a different key:")

    st.markdown("Your API key is used for Whisper transcription. It's stored only in this session.")

    api_key = st.text_input(
        "OpenAI API Key",
        type="password",
        placeholder="sk-...",
        help="Get your API key from platform.openai.com"
    )

    if st.button("Continue", type="primary", disabled=not api_key):
        with st.spinner("Validating API key..."):
            is_valid, message = test_api_key(api_key)
            if is_valid:
                st.session_state.api_key = api_key
                st.rerun()
            else:
                st.error(message)


def render_calibration():
    """Render voice calibration screen."""
    # Sidebar for device selection
    with st.sidebar:
        st.markdown("### Audio Input")
        devices = st.session_state.audio_devices
        device_names = [d['name'] for d in devices]
        device_ids = [d['id'] for d in devices]

        if device_names:
            current_idx = 0
            if st.session_state.selected_device in device_ids:
                current_idx = device_ids.index(st.session_state.selected_device)

            selected_name = st.selectbox(
                "Microphone",
                device_names,
                index=current_idx,
                key="calib_device_selector"
            )
            selected_idx = device_names.index(selected_name)
            st.session_state.selected_device = device_ids[selected_idx]

        if st.button("🔄 Refresh Devices"):
            st.session_state.audio_devices = get_audio_devices()
            st.rerun()

    st.markdown('<p class="main-header">Voice Calibration</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-header">Record a sample of your voice so we can identify you</p>', unsafe_allow_html=True)

    # Live audio level indicator (always running)
    st.markdown("**Audio Level** - speak to verify your mic is working")
    level = get_audio_level(0.15, st.session_state.selected_device)
    st.progress(level, text=f"Level: {level:.0%}")

    st.markdown("""
    **Instructions:**
    1. Verify the level meter above responds when you speak
    2. Click "Start Recording"
    3. Speak naturally for 10 seconds (read something aloud or just talk)
    4. Review and save your voice profile
    """)

    col1, col2, col3 = st.columns([1, 2, 1])

    with col2:
        if st.session_state.calibration_audio is None:
            if st.button("🎤 Start Recording (10 seconds)", type="primary", use_container_width=True):
                with st.spinner("Recording for 10 seconds... Speak now!"):
                    # Record continuously to avoid gaps between chunks
                    st.session_state.calibration_audio = record_audio(
                        10.0, SAMPLE_RATE, st.session_state.selected_device
                    )
                    st.rerun()
            else:
                # Auto-refresh to keep level meter live
                time.sleep(0.3)
                st.rerun()
        else:
            st.success("Recording complete!")

            # Save to temp file for playback
            temp_path = save_to_temp_file(st.session_state.calibration_audio, SAMPLE_RATE)
            st.audio(temp_path, format="audio/wav")

            col_a, col_b = st.columns(2)

            with col_a:
                if st.button("🔄 Re-record", use_container_width=True):
                    st.session_state.calibration_audio = None
                    st.rerun()

            with col_b:
                if st.button("✓ Save Profile", type="primary", use_container_width=True):
                    with st.spinner("Creating voice profile..."):
                        profile = create_voice_profile(
                            st.session_state.calibration_audio,
                            SAMPLE_RATE
                        )
                        st.session_state.voice_profile = profile
                        # Save to disk
                        save_profile(profile, str(PROFILE_PATH))
                        st.session_state.calibration_audio = None
                        st.rerun()


def render_tracking():
    """Render conversation tracking screen."""
    st.markdown('<p class="main-header">Conversation Tracker</p>', unsafe_allow_html=True)

    # Calculate percentage
    if st.session_state.total_time > 0:
        percentage = (st.session_state.user_speaking_time / st.session_state.total_time) * 100
    else:
        percentage = 0

    # Color based on percentage
    if percentage <= 40:
        color = "#28a745"  # Green - great
    elif percentage <= 55:
        color = "#ffc107"  # Yellow - balanced
    else:
        color = "#dc3545"  # Red - talking too much

    # Big percentage display
    st.markdown(f"""
    <div style="text-align: center; padding: 2rem;">
        <div style="font-size: 5rem; font-weight: 700; color: {color};">
            {percentage:.0f}%
        </div>
        <div style="font-size: 1.2rem; color: #666;">
            Your speaking time
        </div>
    </div>
    """, unsafe_allow_html=True)

    # Progress bar
    st.progress(min(percentage / 100, 1.0))

    # Line chart of percentage over time
    if st.session_state.percentage_history:
        import pandas as pd
        chart_data = pd.DataFrame({
            'Your Speaking %': st.session_state.percentage_history
        })
        st.line_chart(chart_data, height=200, use_container_width=True)

    # Time stats (speaking time only, silence not counted)
    col1, col2, col3 = st.columns(3)
    with col1:
        st.metric("You spoke", f"{st.session_state.user_speaking_time:.1f}s")
    with col2:
        others_time = st.session_state.total_time - st.session_state.user_speaking_time
        st.metric("Others spoke", f"{others_time:.1f}s")
    with col3:
        st.metric("Total speech", f"{st.session_state.total_time:.1f}s")
    st.caption("Silence is not counted - only time when someone is speaking")

    st.divider()

    # Control buttons
    col_a, col_b = st.columns(2)

    with col_a:
        if not st.session_state.is_tracking:
            if st.button("▶ Start Tracking", type="primary", use_container_width=True):
                st.session_state.is_tracking = True
                st.session_state.user_speaking_time = 0.0
                st.session_state.total_time = 0.0
                st.session_state.transcription = []
                st.session_state.percentage_history = []
                st.session_state.debug_logs = []
                st.rerun()
        else:
            if st.button("⏹ Stop Tracking", type="secondary", use_container_width=True):
                st.session_state.is_tracking = False
                st.rerun()

    with col_b:
        if st.button("🔄 Reset", use_container_width=True):
            st.session_state.user_speaking_time = 0.0
            st.session_state.total_time = 0.0
            st.session_state.transcription = []
            st.session_state.percentage_history = []
            st.session_state.debug_logs = []
            st.session_state.is_tracking = False
            st.rerun()

    # Audio level when not tracking (always live)
    if not st.session_state.is_tracking:
        st.markdown("**Audio Level**")
        level = get_audio_level(0.15, st.session_state.selected_device)
        st.progress(level, text=f"Level: {level:.0%}")

    # Active tracking loop
    if st.session_state.is_tracking:
        st.info("🎤 Listening... Speak naturally!")

        # Process audio in chunks
        chunk_duration = 2.0
        SPEECH_THRESHOLD = 0.005  # Lowered threshold for speech detection

        with st.spinner(""):
            audio = record_audio(chunk_duration, SAMPLE_RATE, st.session_state.selected_device)

            # Check if there's any speech
            rms = calculate_rms(audio)
            audio_max = float(np.max(np.abs(audio)))

            # Log audio stats
            log_entry = f"RMS: {rms:.4f} | Max: {audio_max:.4f}"

            if rms > SPEECH_THRESHOLD:  # Speech detected
                # Match against profile
                is_user, confidence = match_voice(
                    audio,
                    st.session_state.voice_profile,
                    SAMPLE_RATE,
                    threshold=0.5
                )

                log_entry += f" | SPEECH | Match: {confidence:.2f} | IsYou: {is_user}"

                st.session_state.total_time += chunk_duration

                if is_user:
                    st.session_state.user_speaking_time += chunk_duration

                # Track percentage history for chart
                current_pct = (st.session_state.user_speaking_time / st.session_state.total_time) * 100
                st.session_state.percentage_history.append(current_pct)

                # Optional: transcribe (if enabled)
                if st.session_state.transcription_enabled:
                    try:
                        temp_path = save_to_temp_file(audio, SAMPLE_RATE)
                        client = WhisperClient(st.session_state.api_key)
                        result = client.transcribe(temp_path)
                        if result["success"] and result["text"].strip():
                            speaker = "You" if is_user else "Other"
                            st.session_state.transcription.append(f"**{speaker}:** {result['text']}")
                            log_entry += f" | Text: {result['text'][:30]}..."
                        os.unlink(temp_path)
                    except Exception as e:
                        log_entry += f" | Transcribe error: {str(e)[:30]}"
            else:
                log_entry += " | (silence)"

            # Keep last 20 log entries
            st.session_state.debug_logs.append(log_entry)
            st.session_state.debug_logs = st.session_state.debug_logs[-20:]

            st.rerun()

    # Transcription display
    if st.session_state.transcription:
        st.divider()
        st.markdown("### Transcription")
        for line in st.session_state.transcription[-10:]:  # Last 10 lines
            st.markdown(line)

    # Sidebar settings
    with st.sidebar:
        st.markdown("### Audio Input")
        devices = st.session_state.audio_devices
        device_names = [d['name'] for d in devices]
        device_ids = [d['id'] for d in devices]

        if device_names:
            # Find current selection index
            current_idx = 0
            if st.session_state.selected_device in device_ids:
                current_idx = device_ids.index(st.session_state.selected_device)

            selected_name = st.selectbox(
                "Microphone",
                device_names,
                index=current_idx,
                key="device_selector"
            )
            selected_idx = device_names.index(selected_name)
            st.session_state.selected_device = device_ids[selected_idx]

        if st.button("🔄 Refresh Devices"):
            st.session_state.audio_devices = get_audio_devices()
            st.rerun()

        st.divider()
        st.markdown("### Voice Profile")

        if PROFILE_PATH.exists():
            st.success("Saved profile loaded")

        if st.button("Re-calibrate Voice"):
            st.session_state.voice_profile = None
            if PROFILE_PATH.exists():
                PROFILE_PATH.unlink()  # Delete saved profile
            st.rerun()

        if st.button("Change API Key"):
            st.session_state.api_key = None
            st.rerun()

        st.divider()
        st.markdown("### Transcription")
        st.session_state.transcription_enabled = st.toggle(
            "Enable transcription",
            value=st.session_state.transcription_enabled,
            help="When enabled, sends audio to OpenAI Whisper for transcription. Disable for fully local operation."
        )
        if st.session_state.transcription_enabled:
            st.caption("Audio sent to OpenAI Whisper")
        else:
            st.caption("Fully local (no API calls)")

        st.divider()
        st.markdown("### Guide")
        st.markdown("""
        - **Green** (< 40%): Great listening!
        - **Yellow** (40-55%): Balanced
        - **Red** (> 55%): Talking a lot
        """)

        # Debug logs
        st.divider()
        st.markdown("### Debug Log")
        if st.session_state.debug_logs:
            for log in reversed(st.session_state.debug_logs[-10:]):
                st.text(log)
        else:
            st.text("No logs yet. Start tracking.")

    # Auto-refresh level meter when not tracking (after sidebar renders)
    if not st.session_state.is_tracking:
        time.sleep(0.3)
        st.rerun()


def main():
    """Main app logic."""
    init_session_state()

    # Flow: API Key -> Calibration -> Tracking
    if st.session_state.api_key is None:
        render_api_setup()
    elif st.session_state.voice_profile is None:
        render_calibration()
    else:
        render_tracking()


if __name__ == "__main__":
    main()
