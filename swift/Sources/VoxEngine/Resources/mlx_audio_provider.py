#!/usr/bin/env python3

import argparse
import base64
import inspect
import io
import json
import os
import sys
import time
import wave
from typing import Any, Dict, Iterable, List, Optional


BACKEND = "mlx-audio"
DEFAULT_ASR_MODELS = [
    "mlx-community/parakeet-tdt-0.6b-v3",
    "mlx-community/whisper-large-v3-turbo-asr-fp16",
    "mlx-community/Qwen3-ASR-0.6B-8bit",
]
DEFAULT_TTS_MODELS = [
    "mlx-community/Kokoro-82M-bf16",
    "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
    "mlx-community/Voxtral-4B-TTS-2603-mlx-bf16",
    "mlx-community/csm-1b",
]
DEFAULT_TTS_VOICES = {
    "mlx-community/Kokoro-82M-bf16": [
        "af_heart",
        "af_bella",
        "af_nova",
        "af_sky",
        "am_adam",
        "am_echo",
        "bf_alice",
        "bf_emma",
        "bm_daniel",
        "bm_george",
        "jf_alpha",
        "jm_kumo",
        "zf_xiaobei",
        "zm_yunxi",
    ],
    "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit": [
        "Chelsie",
        "Ethan",
        "Vivian",
        "Ryan",
        "Aiden",
        "Serena",
    ],
    "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit": [
        "Chelsie",
        "Ethan",
        "Vivian",
        "Ryan",
        "Aiden",
        "Serena",
    ],
    "mlx-community/Voxtral-4B-TTS-2603-mlx-bf16": [
        "casual_female",
        "casual_male",
        "cheerful_female",
        "neutral_female",
        "neutral_male",
        "pt_male",
        "pt_female",
        "nl_male",
        "nl_female",
        "it_male",
        "it_female",
        "fr_male",
        "fr_female",
        "es_male",
        "es_female",
        "de_male",
        "de_female",
        "ar_male",
        "hi_male",
        "hi_female",
    ],
    "mlx-community/csm-1b": [
        "conversational_a",
        "conversational_b",
    ],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Vox mlx-audio provider bridge")
    parser.add_argument("--kind", choices=["asr", "tts"], required=True)
    return parser.parse_args()


def read_json_env(name: str) -> Dict[str, Any]:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return {}
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else {}
    except json.JSONDecodeError:
        return {}


def parse_csv_env(name: str, fallback: List[str]) -> List[str]:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return fallback
    values = [value.strip() for value in raw.split(",")]
    return [value for value in values if value]


def parse_positive_int_env(name: str) -> Optional[int]:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return None
    try:
        value = int(raw)
    except ValueError:
        return None
    return value if value > 0 else None


def model_name(model_id: str) -> str:
    return model_id.split("/")[-1]


def json_dump(payload: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def respond(request_id: int, result: Dict[str, Any]) -> None:
    json_dump({"jsonrpc": "2.0", "id": request_id, "result": result})


def respond_error(request_id: int, message: str) -> None:
    json_dump({"jsonrpc": "2.0", "id": request_id, "error": {"code": -32000, "message": message}})


def notify_progress(model_id: str, progress: float, status: str) -> None:
    json_dump({
        "jsonrpc": "2.0",
        "method": "progress",
        "params": {
            "modelId": model_id,
            "progress": progress,
            "status": status,
        },
    })


def safe_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def now_ms(start: float) -> int:
    return max(0, int((time.perf_counter() - start) * 1000))


def normalize_word_text(value: Any) -> str:
    text = str(value or "").strip()
    return text


def duration_ms_from_time_string(value: Any) -> int:
    text = str(value or "").strip()
    if not text:
        return 0
    try:
        hours, minutes, seconds = text.split(":")
        total = int(hours) * 3600 + int(minutes) * 60 + float(seconds)
        return int(total * 1000)
    except (TypeError, ValueError):
        return 0


def audio_bytes_from_chunks(chunks: Iterable[Any], sample_rate: int) -> bytes:
    try:
        import numpy as np
    except Exception as exc:  # pragma: no cover - optional dependency is bundled with mlx-audio
        raise RuntimeError("numpy is required to encode mlx-audio waveform output.") from exc

    arrays: List[Any] = []
    for chunk in chunks:
        array = np.asarray(chunk, dtype=np.float32)
        if array.ndim == 0:
            continue
        if array.ndim > 1:
            array = array.reshape(-1)
        arrays.append(array)

    if not arrays:
        raise RuntimeError("mlx-audio did not return any synthesized audio.")

    waveform = np.concatenate(arrays, axis=0)
    waveform = np.clip(waveform, -1.0, 1.0)
    pcm = (waveform * 32767.0).astype(np.int16)

    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm.tobytes())
    return buffer.getvalue()


class ProviderRuntime:
    def __init__(self, kind: str):
        self.kind = kind
        self.loaded_models: Dict[str, Any] = {}
        self.available_error: Optional[str] = None
        self._asr_loader = None
        self._tts_loader = None
        self._voice_overrides = self._parse_voice_overrides()

    def available(self) -> bool:
        if self.kind == "asr":
            return self._ensure_asr_loader() is not None
        return self._ensure_tts_loader() is not None

    def models(self) -> List[Dict[str, Any]]:
        model_ids = parse_csv_env(
            "VOX_MLX_AUDIO_ASR_MODELS" if self.kind == "asr" else "VOX_MLX_AUDIO_TTS_MODELS",
            DEFAULT_ASR_MODELS if self.kind == "asr" else DEFAULT_TTS_MODELS,
        )
        is_available = self.available()
        return [
            {
                "id": model_id,
                "name": model_name(model_id),
                "backend": BACKEND,
                "installed": is_available,
                "preloaded": model_id in self.loaded_models,
                "available": is_available,
            }
            for model_id in model_ids
        ]

    def preload(self, model_id: str) -> Dict[str, Any]:
        self._load_model(model_id)
        return self._model_info(model_id)

    def install(self, model_id: str) -> Dict[str, Any]:
        self._load_model(model_id)
        return self._model_info(model_id)

    def voices(self, model_id: Optional[str]) -> List[Dict[str, Any]]:
        if self.kind != "tts":
            return []

        model_ids = [model_id] if model_id else [model["id"] for model in self.models()]
        voices: List[Dict[str, Any]] = []
        for current_model_id in model_ids:
            discovered = self._discover_tts_voices(current_model_id)
            if not discovered:
                default_voice = self._default_tts_voice(current_model_id)
                if default_voice:
                    discovered = [default_voice]

            for index, voice_id in enumerate(discovered):
                voices.append({
                    "id": voice_id,
                    "name": voice_id,
                    "language": self._voice_language(current_model_id, voice_id),
                    "backend": BACKEND,
                    "modelId": current_model_id,
                    "available": self.available(),
                    "default": index == 0,
                })

        return voices

    def transcribe(self, model_id: str, path: str) -> Dict[str, Any]:
        total_start = time.perf_counter()

        file_check_start = time.perf_counter()
        if not os.path.exists(path):
            raise FileNotFoundError(path)
        input_bytes = os.path.getsize(path)
        file_check_ms = now_ms(file_check_start)

        model_check_start = time.perf_counter()
        was_preloaded = model_id in self.loaded_models
        model_check_ms = now_ms(model_check_start)

        model_load_ms = 0
        if not was_preloaded:
            model_load_start = time.perf_counter()
            self._load_model(model_id)
            model_load_ms = now_ms(model_load_start)

        model = self.loaded_models[model_id]
        inference_start = time.perf_counter()
        kwargs: Dict[str, Any] = {"verbose": False}
        language = (
            os.environ.get("VOX_MLX_AUDIO_STT_LANGUAGE")
            or os.environ.get("VOX_MLX_AUDIO_LANGUAGE")
            or ""
        ).strip()
        if language:
            kwargs["language"] = language

        result = model.generate(path, **supported_kwargs(model.generate, kwargs))
        inference_ms = now_ms(inference_start)
        words = extract_words(result)
        audio_duration_ms = infer_audio_duration_ms(result, words)
        total_ms = now_ms(total_start)

        return {
            "modelId": model_id,
            "text": str(getattr(result, "text", "") or ""),
            "elapsedMs": total_ms,
            "metrics": {
                "traceId": make_trace_id(),
                "audioDurationMs": audio_duration_ms,
                "inputBytes": input_bytes,
                "wasPreloaded": was_preloaded,
                "fileCheckMs": file_check_ms,
                "modelCheckMs": model_check_ms,
                "modelLoadMs": model_load_ms,
                "audioLoadMs": 0,
                "audioPrepareMs": 0,
                "inferenceMs": inference_ms,
                "totalMs": total_ms,
            },
            "words": words,
        }

    def synthesize(self, model_id: str, text: str, voice_id: Optional[str], speed: Optional[float], instructions: Optional[str]) -> Dict[str, Any]:
        total_start = time.perf_counter()
        if not text.strip():
            raise ValueError("Missing text")

        model_check_start = time.perf_counter()
        was_preloaded = model_id in self.loaded_models
        model_check_ms = now_ms(model_check_start)

        model_load_ms = 0
        if not was_preloaded:
            model_load_start = time.perf_counter()
            self._load_model(model_id)
            model_load_ms = now_ms(model_load_start)

        model = self.loaded_models[model_id]
        resolved_voice = voice_id or self._default_tts_voice(model_id)

        voice_resolve_start = time.perf_counter()
        voice_resolve_ms = now_ms(voice_resolve_start)

        inference_start = time.perf_counter()
        kwargs: Dict[str, Any] = {
            "text": text,
            "verbose": False,
        }
        if speed is not None:
            kwargs["speed"] = speed
        if resolved_voice:
            kwargs["voice"] = resolved_voice

        lang_code = self._tts_lang_code(model_id, resolved_voice)
        if lang_code:
            kwargs["lang_code"] = lang_code

        max_tokens = self._tts_max_tokens(model_id, text)
        if max_tokens is not None:
            kwargs["max_tokens"] = max_tokens

        if instructions:
            kwargs["instruct"] = instructions

        results = list(model.generate(**supported_kwargs(model.generate, kwargs)))
        synthesis_ms = now_ms(inference_start)

        sample_rate = safe_int(getattr(model, "sample_rate", 0), 0)
        if sample_rate <= 0 and results:
            sample_rate = safe_int(getattr(results[0], "sample_rate", 0), 0)
        if sample_rate <= 0:
            sample_rate = 24000

        audio_chunks = [getattr(result, "audio", None) for result in results if getattr(result, "audio", None) is not None]
        wav_bytes = audio_bytes_from_chunks(audio_chunks, sample_rate)

        audio_duration_ms = 0
        for result in results:
            duration_ms = duration_ms_from_time_string(getattr(result, "audio_duration", None))
            if duration_ms > 0:
                audio_duration_ms += duration_ms

        if audio_duration_ms <= 0 and sample_rate > 0:
            audio_duration_ms = int((len(wav_bytes) - 44) / 2 / sample_rate * 1000)

        total_ms = now_ms(total_start)
        resolved_voice_id = resolved_voice or ""
        return {
            "modelId": model_id,
            "voiceId": resolved_voice_id,
            "format": "wav",
            "contentType": "audio/wav",
            "audioBase64": base64.b64encode(wav_bytes).decode("ascii"),
            "elapsedMs": total_ms,
            "metrics": {
                "traceId": make_trace_id(),
                "characterCount": len(text),
                "audioDurationMs": audio_duration_ms,
                "outputBytes": len(wav_bytes),
                "wasPreloaded": was_preloaded,
                "modelCheckMs": model_check_ms,
                "modelLoadMs": model_load_ms,
                "voiceResolveMs": voice_resolve_ms,
                "synthesisMs": synthesis_ms,
                "totalMs": total_ms,
            },
        }

    def _load_model(self, model_id: str) -> Any:
        if model_id in self.loaded_models:
            return self.loaded_models[model_id]

        loader = self._ensure_asr_loader() if self.kind == "asr" else self._ensure_tts_loader()
        if loader is None:
            raise RuntimeError(self.available_error or "mlx-audio is unavailable.")

        model = loader(model_id)
        self.loaded_models[model_id] = model
        return model

    def _model_info(self, model_id: str) -> Dict[str, Any]:
        return {
            "id": model_id,
            "name": model_name(model_id),
            "backend": BACKEND,
            "installed": self.available(),
            "preloaded": model_id in self.loaded_models,
            "available": self.available(),
        }

    def _ensure_asr_loader(self):
        if self._asr_loader is not None:
            return self._asr_loader
        try:
            from mlx_audio.stt import load_model
        except Exception as exc:
            self.available_error = missing_mlx_audio_message(exc)
            return None
        self._asr_loader = load_model
        self.available_error = None
        return self._asr_loader

    def _ensure_tts_loader(self):
        if self._tts_loader is not None:
            return self._tts_loader
        try:
            from mlx_audio.tts import load_model
        except Exception as exc:
            self.available_error = missing_mlx_audio_message(exc)
            return None
        self._tts_loader = load_model
        self.available_error = None
        return self._tts_loader

    def _parse_voice_overrides(self) -> Dict[str, List[str]]:
        raw = read_json_env("VOX_MLX_AUDIO_TTS_VOICES_JSON")
        overrides: Dict[str, List[str]] = {}
        for key, value in raw.items():
            if isinstance(value, list):
                overrides[key] = [str(entry) for entry in value if str(entry).strip()]
        return overrides

    def _discover_tts_voices(self, model_id: str) -> List[str]:
        if model_id in self._voice_overrides:
            return self._voice_overrides[model_id]

        for configured_model_id, voices in DEFAULT_TTS_VOICES.items():
            if configured_model_id.lower() == model_id.lower():
                return voices

        lowered = model_id.lower()
        if "qwen3-tts" in lowered:
            return [
                "Chelsie",
                "Ethan",
                "Vivian",
                "Ryan",
                "Aiden",
                "Serena",
            ]
        if "kokoro" in lowered:
            return DEFAULT_TTS_VOICES["mlx-community/Kokoro-82M-bf16"]
        if "voxtral" in lowered and "tts" in lowered:
            return DEFAULT_TTS_VOICES["mlx-community/Voxtral-4B-TTS-2603-mlx-bf16"]
        if "csm" in lowered or "sesame" in lowered:
            return DEFAULT_TTS_VOICES["mlx-community/csm-1b"]
        return []

    def _default_tts_voice(self, model_id: str) -> Optional[str]:
        override = os.environ.get("VOX_MLX_AUDIO_TTS_DEFAULT_VOICE", "").strip()
        if override:
            return override

        voices = self._discover_tts_voices(model_id)
        return voices[0] if voices else None

    def _tts_lang_code(self, model_id: str, voice_id: Optional[str]) -> Optional[str]:
        override = (
            os.environ.get("VOX_MLX_AUDIO_TTS_LANG_CODE")
            or os.environ.get("VOX_MLX_AUDIO_LANG_CODE")
            or ""
        ).strip()
        if override:
            return override

        lowered = model_id.lower()
        if "kokoro" in lowered and voice_id:
            if voice_id.startswith(("af_", "am_")):
                return "a"
            if voice_id.startswith(("bf_", "bm_")):
                return "b"
            if voice_id.startswith(("jf_", "jm_")):
                return "j"
            if voice_id.startswith(("zf_", "zm_")):
                return "z"
            return "a"

        if "qwen3-tts" in lowered:
            return "English"
        return None

    def _tts_max_tokens(self, model_id: str, text: str) -> Optional[int]:
        override = parse_positive_int_env("VOX_MLX_AUDIO_TTS_MAX_TOKENS")
        if override is not None:
            return override

        lowered = model_id.lower()
        if "soprano" not in lowered:
            return None

        trimmed = text.strip()
        if not trimmed:
            return 32

        word_count = len([word for word in trimmed.split() if word])
        character_count = len(trimmed)

        # Soprano's default max_tokens (512) can turn short prompts like
        # "hi" into ~33s of audio when generation does not stop early.
        # Apply conservative caps for short prompts, while leaving longer
        # inputs on the model default unless explicitly overridden.
        if word_count <= 2 and character_count <= 12:
            return 32
        if word_count <= 6 and character_count <= 48:
            return 64
        if word_count <= 12 and character_count <= 120:
            return 128
        return None

    def _voice_language(self, model_id: str, voice_id: str) -> Optional[str]:
        lowered = model_id.lower()
        if "kokoro" in lowered:
            if voice_id.startswith(("af_", "am_")):
                return "en-US"
            if voice_id.startswith(("bf_", "bm_")):
                return "en-GB"
            if voice_id.startswith(("jf_", "jm_")):
                return "ja-JP"
            if voice_id.startswith(("zf_", "zm_")):
                return "zh-CN"
        return None


def extract_words(result: Any) -> List[Dict[str, Any]]:
    words: List[Dict[str, Any]] = []

    sentences = getattr(result, "sentences", None)
    if sentences:
        for sentence in sentences:
            tokens = getattr(sentence, "tokens", None) or []
            for token in tokens:
                word = normalize_word_text(getattr(token, "text", ""))
                if not word:
                    continue
                words.append({
                    "word": word,
                    "start": safe_float(getattr(token, "start", 0.0)),
                    "end": safe_float(getattr(token, "end", 0.0)),
                    "confidence": safe_float(getattr(token, "confidence", 1.0), 1.0),
                })

    segments = getattr(result, "segments", None)
    if segments:
        for segment in segments:
            segment_words = []
            if isinstance(segment, dict):
                segment_words = segment.get("words") or []
            for entry in segment_words:
                if not isinstance(entry, dict):
                    continue
                word = normalize_word_text(entry.get("word") or entry.get("text"))
                if not word:
                    continue
                words.append({
                    "word": word,
                    "start": safe_float(entry.get("start") or entry.get("start_time")),
                    "end": safe_float(entry.get("end") or entry.get("end_time")),
                    "confidence": safe_float(entry.get("confidence") or entry.get("probability"), 1.0),
                })

    unique_words: List[Dict[str, Any]] = []
    seen = set()
    for word in words:
        key = (word["word"], word["start"], word["end"])
        if key in seen:
            continue
        seen.add(key)
        unique_words.append(word)
    return unique_words


def infer_audio_duration_ms(result: Any, words: List[Dict[str, Any]]) -> int:
    if words:
        return int(max(word["end"] for word in words) * 1000)

    sentences = getattr(result, "sentences", None)
    if sentences:
        ends = [safe_float(getattr(sentence, "end", 0.0)) for sentence in sentences]
        ends = [value for value in ends if value > 0]
        if ends:
            return int(max(ends) * 1000)

    segments = getattr(result, "segments", None)
    if segments:
        ends = []
        for segment in segments:
            if isinstance(segment, dict):
                end_value = segment.get("end") or segment.get("end_time")
                ends.append(safe_float(end_value))
        ends = [value for value in ends if value > 0]
        if ends:
            return int(max(ends) * 1000)

    total_time = safe_float(getattr(result, "total_time", 0.0))
    return int(total_time * 1000) if total_time > 0 else 0


def missing_mlx_audio_message(exc: Exception) -> str:
    interpreter = sys.executable or "python3"
    return (
        "mlx-audio is not installed for the configured provider interpreter "
        f"({interpreter}). Set VOX_MLX_AUDIO_PYTHON to a Python with mlx-audio "
        "installed, or install it with `pip install mlx-audio`. "
        f"Import error: {exc}"
    )


def make_trace_id() -> str:
    return f"{int(time.time() * 1000):x}"[-8:]


def supported_kwargs(function: Any, kwargs: Dict[str, Any]) -> Dict[str, Any]:
    try:
        parameters = inspect.signature(function).parameters
    except (TypeError, ValueError):
        return kwargs

    if any(parameter.kind == inspect.Parameter.VAR_KEYWORD for parameter in parameters.values()):
        return kwargs

    return {key: value for key, value in kwargs.items() if key in parameters}


def handle_request(runtime: ProviderRuntime, request: Dict[str, Any]) -> None:
    request_id = request.get("id")
    method = request.get("method")
    params = request.get("params") or {}

    if not isinstance(request_id, int):
        return

    try:
        if method == "models":
            respond(request_id, {"models": runtime.models()})
            return

        if method == "install":
            model_id = str(params.get("modelId") or "")
            notify_progress(model_id, 0.25, "loading")
            model = runtime.install(model_id)
            notify_progress(model_id, 1.0, "ready")
            respond(request_id, {"model": model})
            return

        if method == "preload":
            model_id = str(params.get("modelId") or "")
            notify_progress(model_id, 0.25, "loading")
            model = runtime.preload(model_id)
            notify_progress(model_id, 1.0, "ready")
            respond(request_id, {"model": model})
            return

        if method == "transcribe":
            if runtime.kind != "asr":
                raise RuntimeError("transcribe is only available for ASR providers")
            path = str(params.get("path") or "")
            model_id = str(params.get("modelId") or "")
            respond(request_id, runtime.transcribe(model_id, path))
            return

        if method == "voices":
            if runtime.kind != "tts":
                raise RuntimeError("voices is only available for TTS providers")
            model_id = params.get("modelId")
            respond(request_id, {"voices": runtime.voices(str(model_id) if model_id else None)})
            return

        if method == "synthesize":
            if runtime.kind != "tts":
                raise RuntimeError("synthesize is only available for TTS providers")
            model_id = str(params.get("modelId") or "")
            text = str(params.get("input") or "")
            voice_id = params.get("voiceId")
            speed = params.get("speed")
            instructions = params.get("instructions")
            respond(
                request_id,
                runtime.synthesize(
                    model_id=model_id,
                    text=text,
                    voice_id=str(voice_id) if voice_id else None,
                    speed=safe_float(speed) if speed is not None else None,
                    instructions=str(instructions) if instructions else None,
                ),
            )
            return

        respond_error(request_id, f"Unknown method: {method}")
    except Exception as exc:  # pragma: no cover - exercised via runtime integration
        respond_error(request_id, str(exc))


def main() -> None:
    args = parse_args()
    runtime = ProviderRuntime(args.kind)

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(request, dict):
            continue
        handle_request(runtime, request)


if __name__ == "__main__":
    main()
